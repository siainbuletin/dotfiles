;;; sp-relationship-annotator.el --- Typed relationships between vulpea notes, as graphs and outlines -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (vulpea "2.7.0") (vui "1.4.0"))

;;; Commentary:

;; Reads relationships between vulpea notes (the `parent' relation builds
;; a hierarchy; others such as `supports' are links) and shows part of
;; them, starting from a note you choose:
;;
;;   M-x relationship-annotator-graph          interactive graph in the browser (default)
;;   M-x relationship-annotator-outline-native buttons in an Emacs buffer
;;   M-x relationship-annotator-outline-vui    the same outline built with vui (trial)
;;   M-x relationship-annotator-svg            static Graphviz SVG (needs `dot')
;;
;; Each command first asks for a starting note and a depth.  The depth
;; counts levels below the starting note.  Notes at the last level show
;; how many children they hide.  The browser graph can't load more, so
;; run the command again with a bigger depth.  The outline expands any
;; node on demand.
;;
;; Other relations between notes (`supports', `opposes', ...) are drawn
;; as labelled links.  See `relationship-annotator-relations' for how to
;; declare them and where each one is read from.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'vulpea)
(require 'vulpea-select)
(require 'vui)

(defgroup relationship-annotator nil
  "Typed relationships between vulpea notes, as graphs and outlines."
  :group 'vulpea)

(defcustom relationship-annotator-relations
  '((parent :label "parent" :color "#888888"
            :sources ((meta "parents") (meta-inverse "children")))
    (supports :label "supports" :color "#2e8b57" :direction right
              :sources ((meta "supports") (property "DG_SUPPORTS")))
    (opposes :label "opposes" :color "#c0392b" :direction left
             :sources ((meta "opposes") (property "DG_OPPOSES")))
    (informs :label "informs" :color "#2874a6" :direction 45
             :sources ((meta "informs") (property "DG_INFORMS")))
    (answers :label "answers" :color "#8e44ad" :direction up
             :sources ((meta "answers") (property "DG_ANSWERS"))))
  "Relations between notes, as (NAME :label LABEL :color COLOR :direction DIRECTION :sources SOURCES).
The relation `parent' is the one that builds the tree: its edges run
from a parent down to its children.  Every other relation is drawn as a
labelled link between two notes that are both in view.

An edge reads \"SUBJECT NAME OBJECT\", for example \"claim supports
question\".  Each of SOURCES says where to look for edges, and a
relation may have several:

  (meta KEY)           the note is the subject; the links in its
                       metadata KEY (\"- KEY :: [[id:..][..]]\") are objects.
  (meta-inverse KEY)   the note is the object; the links in its metadata
                       KEY are subjects.  \"- children :: ..\" on a note
                       gives the parent edge of each child.
  (property KEY)       the note is the subject; the links, or bare ids,
                       in its file property KEY are objects.
  (property-inverse KEY)
                       like `meta-inverse', but read from a file property.

COLOR is used for the links in the browser page and the SVG export.

DIRECTION says where the object of the relation is drawn, as seen from
its subject, in the browser page: `up', `down', `left' or `right', or an
angle in degrees, where 0 is right and 90 is up, so 45 is up and to the
right.  An angle leans on both axes at once.  The relation `parent' has
no direction, because it always puts parents above their children.  A
relation with no DIRECTION is drawn to the right.  The page treats a
direction as a request: when two requests contradict each other, the
later one is dropped."
  :type '(alist :key-type symbol :value-type plist))

(defcustom relationship-annotator-tag-colors
  '(("root" . "#4e79a7")
    ("idea" . "#f28e2b")
    ("question" . "#b07aa1")
    ("claim" . "#59a14f")
    ("evidence" . "#76b7b2")
    ("source" . "#edc948"))
  "Colours for boxes, as (FILE-TAG . COLOR).
A note takes the colour of the first of its file tags that is listed
here, in the order the tags are stored.  Notes with no listed tag keep
the default box colour.  COLOR must be in hex form, such as
\"#4e79a7\"; the views draw it as a tint, so text stays readable in
light and dark themes."
  :type '(alist :key-type string :value-type string))

(defcustom relationship-annotator-default-depth 2
  "Depth offered by default when choosing how far to show the hierarchy."
  :type 'integer)

(defcustom relationship-annotator-html-file
  (expand-file-name "relationship-annotator.html" sp-cache-dir)
  "Where `relationship-annotator-graph' writes its HTML page."
  :type 'file)

(defcustom relationship-annotator-svg-directory
  (expand-file-name "relationship-annotator/" sp-cache-dir)
  "Directory where `relationship-annotator-svg' writes its SVG files."
  :type 'directory)

(defcustom relationship-annotator-rankdir "TB"
  "Graphviz layout direction: \"TB\" (parents on top) or \"LR\" (parents on the left)."
  :type '(choice (const "LR") (const "TB")))

(defcustom relationship-annotator-wrap-width 28
  "Number of characters after which node labels wrap in the SVG export."
  :type 'integer)

;;;; Tree and scope

(defun relationship-annotator--note (id notes)
  "Return the note with ID from NOTES, loading it from the database if needed."
  (or (gethash id notes)
      (when-let ((note (vulpea-db-get-by-id id)))
        (puthash id note notes)
        note)))

(defun relationship-annotator--title (id notes)
  "Title of note ID from NOTES, or a marker for a dangling link."
  (if-let ((note (relationship-annotator--note id notes)))
      (vulpea-note-title note)
    (format "<missing %s>" id)))

(defun relationship-annotator--value-ids (values)
  "Return the ids named in VALUES, a list of strings.
A value may hold several links, separated by commas or not.  Every link
counts, not only the first one in a value.  A value with no link is
read as bare ids separated by commas or spaces."
  (let (ids)
    (dolist (value values)
      (let ((pos 0) (found nil))
        (while (string-match org-link-bracket-re value pos)
          (setq found t)
          (let ((link (match-string 1 value)))
            (when (string-prefix-p "id:" link)
              (push (string-remove-prefix "id:" link) ids)))
          (setq pos (match-end 0)))
        (unless found
          (dolist (word (split-string value "[ ,]+" t))
            (push word ids)))))
    (delete-dups (seq-remove #'string-empty-p (nreverse ids)))))

(defun relationship-annotator--source-values (note source)
  "Return the strings that SOURCE finds in NOTE."
  (pcase source
    ((or `(meta ,key) `(meta-inverse ,key))
     (cdr (assoc key (vulpea-note-meta note))))
    ((or `(property ,key) `(property-inverse ,key))
     (when-let ((value (cdr (assoc key (vulpea-note-properties note)))))
       (list value)))))

(defun relationship-annotator--source-notes (source)
  "Return the notes that may hold SOURCE."
  (pcase source
    ((or `(meta ,key) `(meta-inverse ,key))
     (vulpea-db-query-by-meta-key key))
    ((or `(property ,key) `(property-inverse ,key))
     (vulpea-db-query
      (lambda (note) (assoc key (vulpea-note-properties note)))))))

(defun relationship-annotator--edges ()
  "Return every edge as (SUBJECT RELATION OBJECT), and the notes read.
The second value is a hash table from id to note."
  (let ((notes (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        edges)
    (pcase-dolist (`(,relation . ,plist) relationship-annotator-relations)
      (dolist (source (plist-get plist :sources))
        (dolist (note (relationship-annotator--source-notes source))
          (puthash (vulpea-note-id note) note notes)
          (dolist (id (relationship-annotator--value-ids
                       (relationship-annotator--source-values note source)))
            (let* ((inverse (memq (car source) '(meta-inverse property-inverse)))
                   (edge (if inverse
                             (list id relation (vulpea-note-id note))
                           (list (vulpea-note-id note) relation id))))
              (unless (gethash edge seen)
                (puthash edge t seen)
                (push edge edges)))))))
    (cons (nreverse edges) notes)))

(defun relationship-annotator--build ()
  "Return a plist describing the whole hierarchy.
:notes maps id to note, :children maps parent id to child ids,
:roots lists ids that are parents but have no parent themselves, and
:links lists the edges (SUBJECT RELATION OBJECT) of every other relation."
  (pcase-let* ((`(,edges . ,notes) (relationship-annotator--edges))
               (children (make-hash-table :test #'equal))
               (has-parent (make-hash-table :test #'equal))
               (parent-ids nil)
               (links nil)
               (ids nil))
    (pcase-dolist (`(,subject ,relation ,object) edges)
      (push subject ids)
      (push object ids)
      (if (eq relation 'parent)
          (progn (puthash subject t has-parent)
                 (push subject (gethash object children))
                 (push object parent-ids))
        (push (list subject relation object) links)))
    ;; Notes that only appear as the object of an edge are not loaded yet.
    (dolist (note (vulpea-db-query-by-ids
                   (seq-remove (lambda (id) (gethash id notes))
                               (delete-dups ids))))
      (puthash (vulpea-note-id note) note notes))
    (list :notes notes
          :children children
          :links (nreverse links)
          :roots (sort (seq-remove (lambda (id) (gethash id has-parent))
                                   (delete-dups (copy-sequence parent-ids)))
                       (lambda (a b)
                         (string< (relationship-annotator--title a notes)
                                  (relationship-annotator--title b notes)))))))

(defun relationship-annotator--sorted-children (id tree)
  "Child ids of ID in TREE, sorted by title."
  (let ((notes (plist-get tree :notes)))
    (sort (copy-sequence (gethash id (plist-get tree :children)))
          (lambda (a b)
            (string< (relationship-annotator--title a notes)
                     (relationship-annotator--title b notes))))))

(defun relationship-annotator--scope (tree start depth)
  "Return the part of TREE reached from START within DEPTH levels.
The result has the same keys as the tree, plus :more, which maps an
id at the last level to how many children it hides, and :nodes, the
ids in scope.  :roots is just (START).  :links keeps the other
relations between two notes that are both in scope."
  (let ((notes (plist-get tree :notes))
        (children (make-hash-table :test #'equal))
        (more (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        (nodes (list start))
        (queue (list (cons start 0))))
    (puthash start t seen)
    (while queue
      (pcase-let ((`(,id . ,level) (pop queue)))
        (let ((kids (relationship-annotator--sorted-children id tree)))
          (if (< level depth)
              (dolist (kid kids)
                (puthash id (append (gethash id children) (list kid)) children)
                (unless (gethash kid seen)
                  (puthash kid t seen)
                  (push kid nodes)
                  (setq queue (append queue (list (cons kid (1+ level)))))))
            (when kids
              (puthash id (length kids) more))))))
    (setq nodes (nreverse nodes))
    (list :notes notes
          :children children
          :more more
          :roots (list start)
          :nodes nodes
          :links (seq-filter (pcase-lambda (`(,subject ,_ ,object))
                               (and (gethash subject seen) (gethash object seen)))
                             (plist-get tree :links)))))

(defun relationship-annotator--read-scope ()
  "Ask for a starting note and a depth.  Return (START-ID . DEPTH)."
  (let* ((note (vulpea-select "Start note: " :require-match t))
         (depth (read-number "Depth: " relationship-annotator-default-depth)))
    (unless (and note (vulpea-note-id note) (>= depth 1))
      (user-error "Need a starting note and a depth of at least 1"))
    (cons (vulpea-note-id note) (truncate depth))))

;;;; Browser view

(defconst relationship-annotator--html-template-file
  (expand-file-name "sp-relationship-annotator.html"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "File holding the HTML template for `relationship-annotator-graph'.
The placeholder `__DATA__' is replaced with the JSON data.")

(defun relationship-annotator--html-template ()
  "Return the text of `relationship-annotator--html-template-file'."
  (with-temp-buffer
    (insert-file-contents relationship-annotator--html-template-file)
    (buffer-string)))

(defconst relationship-annotator--vendor-directory
  (expand-file-name "vendor/relationship-annotator/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding the scripts that the browser page includes.")

(defconst relationship-annotator--vendor-scripts
  '("layout-base.min.js" "cose-base.min.js" "cytoscape.min.js"
    "cytoscape-fcose.min.js")
  "Scripts of `relationship-annotator--vendor-directory', in the order the page loads them.")

(defun relationship-annotator--libraries ()
  "Return the text of the vendored scripts, one after the other."
  (with-temp-buffer
    (dolist (file relationship-annotator--vendor-scripts)
      (insert-file-contents (expand-file-name file relationship-annotator--vendor-directory))
      (goto-char (point-max))
      (insert "\n"))
    (buffer-string)))

(defun relationship-annotator--json-for-html (object)
  "Encode OBJECT as JSON that is safe inside a <script> element."
  (let ((json-encoding-pretty-print nil))
    (thread-last (json-encode object)
                 (string-replace "<" "\\u003c")
                 (string-replace ">" "\\u003e")
                 (string-replace "&" "\\u0026"))))

(defun relationship-annotator--relation-style (relation key &optional default)
  "Return KEY of RELATION from `relationship-annotator-relations', or DEFAULT."
  (or (plist-get (cdr (assq relation relationship-annotator-relations)) key) default))

(defun relationship-annotator--direction-vector (direction)
  "Return DIRECTION as a unit vector [DX DY] on a screen, where DY grows downward."
  (let ((degrees (pcase direction
                   ('right 0) ('up 90) ('left 180) ('down 270)
                   ((pred numberp) direction)
                   (_ 0))))
    (vector (/ (round (* 1000 (cos (degrees-to-radians degrees)))) 1000.0)
            (/ (round (* -1000 (sin (degrees-to-radians degrees)))) 1000.0))))

(defun relationship-annotator--relations-json (links)
  "Return the name, label and colour of each relation used by LINKS."
  (vconcat
   (mapcar (lambda (relation)
             `((name . ,(symbol-name relation))
               (label . ,(relationship-annotator--relation-style
                          relation :label (symbol-name relation)))
               (color . ,(relationship-annotator--relation-style
                          relation :color "#888888"))
               (direction . ,(relationship-annotator--direction-vector
                              (relationship-annotator--relation-style
                               relation :direction 'right)))))
           (delete-dups (mapcar #'cadr links)))))

(defun relationship-annotator--tag-color (note)
  "Return (TAG . COLOR) for the first tag of NOTE in `relationship-annotator-tag-colors'."
  (when note
    (seq-some (lambda (tag) (assoc tag relationship-annotator-tag-colors))
              (vulpea-note-tags note))))

(defun relationship-annotator--html (tree start depth)
  "Return a self-contained HTML page showing TREE from START to DEPTH.
The page holds the whole tree, so it can recentre on any note and cut
the part to show by itself."
  (let* ((notes (plist-get tree :notes))
         (ids (let ((acc (make-hash-table :test #'equal)))
                (puthash start t acc)
                (maphash (lambda (k v)
                           (puthash k t acc)
                           (dolist (kid v) (puthash kid t acc)))
                         (plist-get tree :children))
                (pcase-dolist (`(,subject ,_ ,object) (plist-get tree :links))
                  (puthash subject t acc)
                  (puthash object t acc))
                (sort (hash-table-keys acc) #'string<)))
         (nodes
          (vconcat
           (mapcar
            (lambda (id)
              (let* ((note (relationship-annotator--note id notes))
                     (color (relationship-annotator--tag-color note)))
                `((id . ,id)
                  (title . ,(relationship-annotator--title id notes))
                  (path . ,(and note (vulpea-note-path note)))
                  (tags . ,(vconcat (and note (vulpea-note-tags note))))
                  (colorTag . ,(car color))
                  (color . ,(cdr color)))))
            ids)))
         (edges
          (vconcat
           (cl-loop for (parent . kids) in
                    (let (acc)
                      (maphash (lambda (k v) (push (cons k v) acc))
                               (plist-get tree :children))
                      acc)
                    append (mapcar (lambda (kid) (vector parent kid)) kids))))
         (links
          (vconcat
           (mapcar (pcase-lambda (`(,subject ,relation ,object))
                     `((from . ,subject) (to . ,object)
                       (rel . ,(symbol-name relation))))
                   (plist-get tree :links))))
         (data `((root . ,start)
                 (depth . ,depth)
                 (nodes . ,nodes)
                 (edges . ,edges)
                 (links . ,links)
                 (relations . ,(relationship-annotator--relations-json
                                (plist-get tree :links))))))
    (string-replace "__DATA__" (relationship-annotator--json-for-html data)
                    (string-replace "__LIBS__" (relationship-annotator--libraries)
                                    (relationship-annotator--html-template)))))

;;;###autoload
(defun relationship-annotator-graph ()
  "Ask for a starting note and depth, then open the hierarchy in the browser.
The page holds the whole tree.  Clicking a box recentres the graph on it."
  (interactive)
  (pcase-let* ((`(,start . ,depth) (relationship-annotator--read-scope))
               (tree (relationship-annotator--build)))
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file relationship-annotator-html-file
        (insert (relationship-annotator--html tree start depth))))
    (browse-url-of-file relationship-annotator-html-file)))

;;;; Native outline view

(defvar-local relationship-annotator--tree nil
  "Full hierarchy shown in this buffer.")

(defvar-local relationship-annotator--expanded nil
  "Hash table of ids whose children are shown.")

(defvar-local relationship-annotator--start nil
  "Id of the note the outline starts from.")

(defvar-local relationship-annotator--depth 2
  "Depth shown when the outline was opened.")

(defvar relationship-annotator-view-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "TAB") #'relationship-annotator-view-toggle)
    (define-key map (kbd "c") #'relationship-annotator-view-recenter)
    (define-key map (kbd "g") #'relationship-annotator-view-redraw)
    map)
  "Keymap for `relationship-annotator-view-mode'.")

(define-derived-mode relationship-annotator-view-mode special-mode "Hierarchy"
  "Major mode for the native relationship outline.
TAB or a [+]/[-] button expands or collapses a note.  RET on a
title visits the note.  c re-scopes, g rebuilds the view.")

(defun relationship-annotator-view--expand-to-depth ()
  "Expand every node in the view above the starting depth."
  (let ((queue (list (cons relationship-annotator--start 0))))
    (while queue
      (pcase-let ((`(,id . ,level) (pop queue)))
        (when (and (< level relationship-annotator--depth)
                   (relationship-annotator--sorted-children id relationship-annotator--tree))
          (puthash id t relationship-annotator--expanded)
          (dolist (kid (relationship-annotator--sorted-children id relationship-annotator--tree))
            (push (cons kid (1+ level)) queue)))))))

(defun relationship-annotator-view--insert (id level path)
  "Insert the line for ID at indent LEVEL, then its children if expanded.
PATH holds the ancestors, so a cycle stops the recursion."
  (let* ((tree relationship-annotator--tree)
         (notes (plist-get tree :notes))
         (kids (relationship-annotator--sorted-children id tree))
         (open (and kids (gethash id relationship-annotator--expanded)))
         (note (relationship-annotator--note id notes)))
    (let ((start (point)))
      (insert (make-string (* 2 level) ?\s))
      (relationship-annotator-view--insert-line-body id kids open note)
      (put-text-property start (point) 'relationship-annotator-id id))
    (insert "\n")
    (when (and open (not (member id path)))
      (dolist (kid kids)
        (relationship-annotator-view--insert kid (1+ level) (cons id path))))))

(defun relationship-annotator-view--insert-line-body (id kids open note)
  "Insert the toggle and title buttons of ID's line, then its child count."
  (let ((notes (plist-get relationship-annotator--tree :notes)))
    (if kids
        (insert-button (if open "[-]" "[+]")
                       'action #'relationship-annotator-view--button-action
                       'follow-link t
                       'help-echo "Expand or collapse"
                       'relationship-annotator-id id
                       'relationship-annotator-kind 'toggle)
      (insert "   "))
    (insert " ")
    (insert-button (relationship-annotator--title id notes)
                   'action #'relationship-annotator-view--button-action
                   'follow-link t
                   'help-echo (or (and note (vulpea-note-path note)) "")
                   'relationship-annotator-id id
                   'relationship-annotator-kind 'visit)
    (when kids (insert (format "  (%d)" (length kids))))))

(defun relationship-annotator-view--redraw ()
  "Erase the buffer and draw the view from its current state."
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (insert (propertize (format "%s  ·  depth %d  ·  TAB expand  RET visit  c re-scope  g rebuild\n\n"
                                (relationship-annotator--title
                                 relationship-annotator--start
                                 (plist-get relationship-annotator--tree :notes))
                                relationship-annotator--depth)
                        'face 'shadow))
    (relationship-annotator-view--insert relationship-annotator--start 0 nil)
    (goto-char (point-min))
    (forward-line (max 0 (1- line)))))

(defun relationship-annotator-view--button-action (button)
  "Expand or visit the note of BUTTON, depending on its kind."
  (let ((id (button-get button 'relationship-annotator-id)))
    (pcase (button-get button 'relationship-annotator-kind)
      ('toggle
       (if (gethash id relationship-annotator--expanded)
           (remhash id relationship-annotator--expanded)
         (puthash id t relationship-annotator--expanded))
       (relationship-annotator-view--redraw))
      ('visit
       (let ((note (relationship-annotator--note id (plist-get relationship-annotator--tree :notes))))
         (unless note (user-error "Note %s is not in the database" id))
         (find-file (vulpea-note-path note))
         (when (vulpea-note-pos note)
           (goto-char (vulpea-note-pos note))))))))

(defun relationship-annotator-view-toggle ()
  "Expand or collapse the note at point."
  (interactive)
  (when-let ((id (get-text-property (point) 'relationship-annotator-id)))
    (when (relationship-annotator--sorted-children id relationship-annotator--tree)
      (if (gethash id relationship-annotator--expanded)
          (remhash id relationship-annotator--expanded)
        (puthash id t relationship-annotator--expanded))
      (relationship-annotator-view--redraw))))

(defun relationship-annotator-view-redraw ()
  "Rebuild the tree from the database and redraw."
  (interactive)
  (setq relationship-annotator--tree (relationship-annotator--build))
  (relationship-annotator-view--expand-to-depth)
  (relationship-annotator-view--redraw))

(defun relationship-annotator-view-recenter ()
  "Ask for a new starting note and depth, then redraw."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (setq relationship-annotator--start start
          relationship-annotator--depth depth
          relationship-annotator--expanded (make-hash-table :test #'equal))
    (relationship-annotator-view--expand-to-depth)
    (relationship-annotator-view--redraw)))

;;;###autoload
(defun relationship-annotator-outline-native ()
  "Ask for a starting note and depth, then show the hierarchy as buttons."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (let ((buf (get-buffer-create "*relationship annotator*")))
      (with-current-buffer buf
        (relationship-annotator-view-mode)
        (setq relationship-annotator--tree (relationship-annotator--build)
              relationship-annotator--start start
              relationship-annotator--depth depth
              relationship-annotator--expanded (make-hash-table :test #'equal))
        (relationship-annotator-view--expand-to-depth)
        (relationship-annotator-view--redraw))
      (pop-to-buffer buf))))

;;;; Outline built with vui (trial)

(defun relationship-annotator--visit (id tree)
  "Visit the note ID from TREE in its file."
  (let ((note (relationship-annotator--note id (plist-get tree :notes))))
    (unless note (user-error "Note %s is not in the database" id))
    (find-file (vulpea-note-path note))
    (when (vulpea-note-pos note)
      (goto-char (vulpea-note-pos note)))))

(vui-defcomponent relationship-annotator-node (id level path tree depth initially-open)
  "One note in the vui outline, with its children below when open."
  :state ((toggled nil))
  :render
  (let* ((kids (relationship-annotator--sorted-children id tree))
         (open (if toggled (not initially-open) initially-open))
         (notes (plist-get tree :notes))
         (note (relationship-annotator--note id notes)))
    (vui-vstack
     (vui-hstack
      (vui-space (* 2 level))
      (if kids
          (vui-button (if open "-" "+")
                      :on-click (lambda () (vui-set-state :toggled (not toggled))))
        (vui-text "   "))
      (vui-button (relationship-annotator--title id notes)
                  :no-decoration t
                  :help-echo (and note (vulpea-note-path note))
                  :on-click (lambda () (relationship-annotator--visit id tree)))
      (if kids
          (vui-text (format "(%d)" (length kids)) :face 'shadow)
        (vui-fragment)))
     (if (and open kids (not (member id path)))
         (vui-list kids
                   (lambda (kid)
                     (vui-component 'relationship-annotator-node
                       :id kid :level (1+ level) :path (cons id path)
                       :tree tree :depth depth
                       :initially-open (< (1+ level) depth))))
       (vui-fragment)))))

(vui-defcomponent relationship-annotator-root (start depth tree)
  "The vui outline: a header line, then the starting note."
  :render
  (vui-vstack
   (vui-text (format "%s  ·  depth %d  ·  [+]/[-] expands  ·  title visits  ·  run the command again to re-scope"
                     (relationship-annotator--title start (plist-get tree :notes))
                     depth)
             :face 'shadow)
   (vui-newline)
   (vui-component 'relationship-annotator-node
     :id start :level 0 :path nil :tree tree :depth depth
     :initially-open (> depth 0))))

;;;###autoload
(defun relationship-annotator-outline-vui ()
  "Ask for a starting note and depth, then show the hierarchy with vui."
  (interactive)
  (pcase-let ((`(,start . ,depth) (relationship-annotator--read-scope)))
    (vui-mount (vui-component 'relationship-annotator-root
                 :start start :depth depth :tree (relationship-annotator--build))
               "*relationship annotator (vui)*")))

;;;; Static SVG export (Graphviz)

(defun relationship-annotator--wrap (text width)
  "Return TEXT as a list of lines no longer than WIDTH, breaking long words."
  (let (lines (line ""))
    (dolist (word (split-string text))
      (while (> (length word) width)
        (when (> (length line) 0) (push line lines) (setq line ""))
        (push (substring word 0 width) lines)
        (setq word (substring word width)))
      (cond ((string-empty-p line) (setq line word))
            ((<= (+ (length line) 1 (length word)) width)
             (setq line (concat line " " word)))
            (t (push line lines) (setq line word))))
    (unless (string-empty-p line) (push line lines))
    (nreverse (or lines (list "")))))

(defun relationship-annotator--label (id notes)
  "Return the title of ID from NOTES followed by its file tags, like :a:b:."
  (let* ((note (relationship-annotator--note id notes))
         (tags (and note (vulpea-note-tags note))))
    (concat (relationship-annotator--title id notes)
            (and tags (format " :%s:" (string-join tags ":"))))))

(defun relationship-annotator--dot-label (id notes)
  "Return the wrapped, escaped Graphviz label text for ID."
  (mapconcat (lambda (line) (replace-regexp-in-string "[\"\\\\]" "\\\\\\&" line))
             (relationship-annotator--wrap (relationship-annotator--label id notes)
                                     relationship-annotator-wrap-width)
             "\\n"))

(defun relationship-annotator--dot-fill (note rootp)
  "Return the Graphviz attributes for the fill of NOTE.
A note with a coloured tag gets that colour as a tint.  The root gets a
thick border, and a blue fill when it has no coloured tag."
  (let ((color (cdr (relationship-annotator--tag-color note))))
    (concat (cond (color (format ", fillcolor=\"%s66\"" color))
                  (rootp ", fillcolor=\"#d8e6f5\""))
            (and rootp ", penwidth=2"))))

(defun relationship-annotator--dot (tree)
  "Return Graphviz source for TREE, one cluster per root."
  (let ((notes (plist-get tree :notes))
        (children (plist-get tree :children))
        (drawn (make-hash-table :test #'equal)))
    (with-temp-buffer
      (insert "digraph vulpea {\n"
              (format "  rankdir=%s;\n" relationship-annotator-rankdir)
              "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#f4f4f4\","
              " fontname=\"Helvetica\"];\n"
              "  edge [color=\"#888888\"];\n")
      (let ((n 0))
        (dolist (root (plist-get tree :roots))
          (insert (format "  subgraph cluster_%d {\n    style=invis;\n" (cl-incf n)))
          (let ((queue (list root)))
            (while queue
              (let ((id (pop queue)))
                (unless (gethash id drawn)
                  (puthash id t drawn)
                  (insert (format "    %S [label=\"%s\"%s];\n"
                                  id (relationship-annotator--dot-label id notes)
                                  (relationship-annotator--dot-fill
                                   (relationship-annotator--note id notes)
                                   (equal id root))))
                  (setq queue (append queue (gethash id children)))))))
          (insert "  }\n")))
      (maphash (lambda (pid kids)
                 (dolist (kid kids)
                   (insert (format "  %S -> %S;\n" pid kid))))
               children)
      (pcase-dolist (`(,subject ,relation ,object) (plist-get tree :links))
        (insert (format "  %S -> %S [constraint=false, style=dashed, label=%S, fontsize=10, color=%S, fontcolor=%S];\n"
                        subject object
                        (relationship-annotator--relation-style
                         relation :label (symbol-name relation))
                        (relationship-annotator--relation-style relation :color "#888888")
                        (relationship-annotator--relation-style relation :color "#888888"))))
      (insert "}\n")
      (buffer-string))))

(defun relationship-annotator--slug (title)
  "Return TITLE as a file-name slug, such as \"value-form\"."
  (string-trim (downcase (replace-regexp-in-string "[^[:alnum:]]+" "-" title))
               "-+" "-+"))

(defun relationship-annotator--svg-file (start depth notes)
  "Return a new SVG file name for the scope from START to DEPTH.
The name is <creation date and time>-<note name>-<depth>.svg, so
exports of the same note never overwrite each other."
  (make-directory relationship-annotator-svg-directory t)
  (expand-file-name
   (format "%s-%s-%d.svg"
           (format-time-string "%Y%m%dT%H%M%S")
           (relationship-annotator--slug (relationship-annotator--title start notes))
           depth)
   relationship-annotator-svg-directory))

;;;###autoload
(defun relationship-annotator-svg ()
  "Ask for a starting note and depth, then write and show a Graphviz SVG."
  (interactive)
  (unless (executable-find "dot")
    (user-error "Graphviz `dot' not found on PATH"))
  (pcase-let* ((`(,start . ,depth) (relationship-annotator--read-scope))
               (tree (relationship-annotator--build))
               (scope (relationship-annotator--scope tree start depth))
               (dot (relationship-annotator--dot scope))
               (file (relationship-annotator--svg-file start depth (plist-get tree :notes))))
    (with-temp-buffer
      (insert dot)
      (unless (zerop (call-process-region (point-min) (point-max) "dot" nil t nil
                                          "-Tsvg" "-o" file))
        (error "Graphviz failed: %s" (buffer-string))))
    (pop-to-buffer (find-file-noselect file))))

;;;; Old names

;; The module used to be `sp-vulpea-hierarchy'.  The old names keep
;; working, which also keeps `sp-dg-positions' reading the same rankdir.

(dolist (name '(relations tag-colors default-depth html-file svg-directory
                          rankdir wrap-width))
  (define-obsolete-variable-alias
    (intern (format "vulpea-hierarchy-%s" name))
    (intern (format "relationship-annotator-%s" name))
    "2026-10-20"))

(dolist (name '(graph outline-native outline-vui svg))
  (define-obsolete-function-alias
    (intern (format "vulpea-hierarchy-%s" name))
    (intern (format "relationship-annotator-%s" name))
    "2026-10-20"))

(provide 'sp-relationship-annotator)
;;; sp-relationship-annotator.el ends here
