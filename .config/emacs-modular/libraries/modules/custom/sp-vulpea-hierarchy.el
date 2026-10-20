;;; sp-vulpea-hierarchy.el --- Parent/child views of vulpea notes -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (vulpea "2.7.0") (vui "1.4.0"))

;;; Commentary:

;; Builds a hierarchy from a parent link in each note's metadata and
;; shows part of it, starting from a note you choose:
;;
;;   M-x vulpea-hierarchy-graph          interactive graph in the browser (default)
;;   M-x vulpea-hierarchy-outline-native buttons in an Emacs buffer
;;   M-x vulpea-hierarchy-outline-vui    the same outline built with vui (trial)
;;   M-x vulpea-hierarchy-svg            static Graphviz SVG (needs `dot')
;;
;; Each command first asks for a starting note and a depth.  The depth
;; counts levels below the starting note.  Notes at the last level show
;; how many children they hide.  The browser graph holds
;; `vulpea-hierarchy-embed-depth' levels (4) and can't load more, so run
;; the command again from another note, or with a bigger depth.  The
;; outline expands any node on demand.
;;
;; Other relations between notes (`supports', `opposes', ...) are drawn
;; as labelled links.  See `vulpea-hierarchy-relations' for how to
;; declare them and where each one is read from.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'vulpea)
(require 'vulpea-select)
(require 'vui)

(defgroup vulpea-hierarchy nil
  "Parent/child views of vulpea notes."
  :group 'vulpea)

(defcustom vulpea-hierarchy-relations
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

(defcustom vulpea-hierarchy-tag-colors
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

(defcustom vulpea-hierarchy-default-depth 2
  "Depth offered by default when choosing how far to show the hierarchy."
  :type 'integer)

(defcustom vulpea-hierarchy-embed-depth 4
  "Levels below the starting note that the browser page holds.
The page recentres and changes depth only within them.  Notes at the
last level show how many children they hide; run the command again from
another note to go further.  A larger depth, when you ask for one, wins."
  :type 'integer)

(defcustom vulpea-hierarchy-html-file
  (expand-file-name "vulpea-hierarchy.html" sp-cache-dir)
  "Where `vulpea-hierarchy-graph' writes its HTML page."
  :type 'file)

(defcustom vulpea-hierarchy-svg-directory
  (expand-file-name "vulpea-hierarchy/" sp-cache-dir)
  "Directory where `vulpea-hierarchy-svg' writes its SVG files."
  :type 'directory)

(defcustom vulpea-hierarchy-rankdir "TB"
  "Graphviz layout direction: \"TB\" (parents on top) or \"LR\" (parents on the left)."
  :type '(choice (const "LR") (const "TB")))

(defcustom vulpea-hierarchy-wrap-width 28
  "Number of characters after which node labels wrap in the SVG export."
  :type 'integer)

;;;; Tree and scope

(defun vulpea-hierarchy--note (id notes)
  "Return the note with ID from NOTES, loading it from the database if needed."
  (or (gethash id notes)
      (when-let ((note (vulpea-db-get-by-id id)))
        (puthash id note notes)
        note)))

(defun vulpea-hierarchy--title (id notes)
  "Title of note ID from NOTES, or a marker for a dangling link."
  (if-let ((note (vulpea-hierarchy--note id notes)))
      (vulpea-note-title note)
    (format "<missing %s>" id)))

(defun vulpea-hierarchy--value-ids (values)
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

(defun vulpea-hierarchy--source-values (note source)
  "Return the strings that SOURCE finds in NOTE."
  (pcase source
    ((or `(meta ,key) `(meta-inverse ,key))
     (cdr (assoc key (vulpea-note-meta note))))
    ((or `(property ,key) `(property-inverse ,key))
     (when-let ((value (cdr (assoc key (vulpea-note-properties note)))))
       (list value)))))

(defun vulpea-hierarchy--source-notes (source)
  "Return the notes that may hold SOURCE."
  (pcase source
    ((or `(meta ,key) `(meta-inverse ,key))
     (vulpea-db-query-by-meta-key key))
    ((or `(property ,key) `(property-inverse ,key))
     (vulpea-db-query
      (lambda (note) (assoc key (vulpea-note-properties note)))))))

(defun vulpea-hierarchy--edges ()
  "Return every edge as (SUBJECT RELATION OBJECT), and the notes read.
The second value is a hash table from id to note."
  (let ((notes (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        edges)
    (pcase-dolist (`(,relation . ,plist) vulpea-hierarchy-relations)
      (dolist (source (plist-get plist :sources))
        (dolist (note (vulpea-hierarchy--source-notes source))
          (puthash (vulpea-note-id note) note notes)
          (dolist (id (vulpea-hierarchy--value-ids
                       (vulpea-hierarchy--source-values note source)))
            (let* ((inverse (memq (car source) '(meta-inverse property-inverse)))
                   (edge (if inverse
                             (list id relation (vulpea-note-id note))
                           (list (vulpea-note-id note) relation id))))
              (unless (gethash edge seen)
                (puthash edge t seen)
                (push edge edges)))))))
    (cons (nreverse edges) notes)))

(defun vulpea-hierarchy--build ()
  "Return a plist describing the whole hierarchy.
:notes maps id to note, :children maps parent id to child ids,
:roots lists ids that are parents but have no parent themselves, and
:links lists the edges (SUBJECT RELATION OBJECT) of every other relation."
  (pcase-let* ((`(,edges . ,notes) (vulpea-hierarchy--edges))
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
                         (string< (vulpea-hierarchy--title a notes)
                                  (vulpea-hierarchy--title b notes)))))))

(defun vulpea-hierarchy--sorted-children (id tree)
  "Child ids of ID in TREE, sorted by title."
  (let ((notes (plist-get tree :notes)))
    (sort (copy-sequence (gethash id (plist-get tree :children)))
          (lambda (a b)
            (string< (vulpea-hierarchy--title a notes)
                     (vulpea-hierarchy--title b notes))))))

(defun vulpea-hierarchy--scope (tree start depth)
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
        (let ((kids (vulpea-hierarchy--sorted-children id tree)))
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

(defun vulpea-hierarchy--read-scope ()
  "Ask for a starting note and a depth.  Return (START-ID . DEPTH)."
  (let* ((note (vulpea-select "Start note: " :require-match t))
         (depth (read-number "Depth: " vulpea-hierarchy-default-depth)))
    (unless (and note (vulpea-note-id note) (>= depth 1))
      (user-error "Need a starting note and a depth of at least 1"))
    (cons (vulpea-note-id note) (truncate depth))))

;;;; Browser view

(defconst vulpea-hierarchy--html-template-file
  (expand-file-name "sp-vulpea-hierarchy.html"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "File holding the HTML template for `vulpea-hierarchy-graph'.
The placeholder `__DATA__' is replaced with the JSON data.")

(defun vulpea-hierarchy--html-template ()
  "Return the text of `vulpea-hierarchy--html-template-file'."
  (with-temp-buffer
    (insert-file-contents vulpea-hierarchy--html-template-file)
    (buffer-string)))

(defconst vulpea-hierarchy--vendor-directory
  (expand-file-name "vendor/vulpea-hierarchy/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding the scripts that the browser page includes.")

(defconst vulpea-hierarchy--vendor-scripts
  '("layout-base.min.js" "cose-base.min.js" "cytoscape.min.js"
    "cytoscape-fcose.min.js")
  "Scripts of `vulpea-hierarchy--vendor-directory', in the order the page loads them.")

(defun vulpea-hierarchy--libraries ()
  "Return the text of the vendored scripts, one after the other."
  (with-temp-buffer
    (dolist (file vulpea-hierarchy--vendor-scripts)
      (insert-file-contents (expand-file-name file vulpea-hierarchy--vendor-directory))
      (goto-char (point-max))
      (insert "\n"))
    (buffer-string)))

(defun vulpea-hierarchy--json-for-html (object)
  "Encode OBJECT as JSON that is safe inside a <script> element."
  (let ((json-encoding-pretty-print nil))
    (thread-last (json-encode object)
                 (string-replace "<" "\\u003c")
                 (string-replace ">" "\\u003e")
                 (string-replace "&" "\\u0026"))))

(defun vulpea-hierarchy--relation-style (relation key &optional default)
  "Return KEY of RELATION from `vulpea-hierarchy-relations', or DEFAULT."
  (or (plist-get (cdr (assq relation vulpea-hierarchy-relations)) key) default))

(defun vulpea-hierarchy--direction-vector (direction)
  "Return DIRECTION as a unit vector [DX DY] on a screen, where DY grows downward."
  (let ((degrees (pcase direction
                   ('right 0) ('up 90) ('left 180) ('down 270)
                   ((pred numberp) direction)
                   (_ 0))))
    (vector (/ (round (* 1000 (cos (degrees-to-radians degrees)))) 1000.0)
            (/ (round (* -1000 (sin (degrees-to-radians degrees)))) 1000.0))))

(defun vulpea-hierarchy--relations-json (links)
  "Return the name, label and colour of each relation used by LINKS."
  (vconcat
   (mapcar (lambda (relation)
             `((name . ,(symbol-name relation))
               (label . ,(vulpea-hierarchy--relation-style
                          relation :label (symbol-name relation)))
               (color . ,(vulpea-hierarchy--relation-style
                          relation :color "#888888"))
               (direction . ,(vulpea-hierarchy--direction-vector
                              (vulpea-hierarchy--relation-style
                               relation :direction 'right)))))
           (delete-dups (mapcar #'cadr links)))))

(defun vulpea-hierarchy--tag-color (note)
  "Return (TAG . COLOR) for the first tag of NOTE in `vulpea-hierarchy-tag-colors'."
  (when note
    (seq-some (lambda (tag) (assoc tag vulpea-hierarchy-tag-colors))
              (vulpea-note-tags note))))

(defun vulpea-hierarchy--html (tree start depth)
  "Return a self-contained HTML page showing TREE from START to DEPTH.
TREE is already cut to the levels the page holds, see
`vulpea-hierarchy--scope'.  The page can recentre on any note in it and
cut the part to show by itself."
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
              (let* ((note (vulpea-hierarchy--note id notes))
                     (color (vulpea-hierarchy--tag-color note)))
                `((id . ,id)
                  (title . ,(vulpea-hierarchy--title id notes))
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
                 (hidden . ,(let (acc)
                              (maphash (lambda (id count) (push (cons id count) acc))
                                       (plist-get tree :more))
                              acc))
                 (relations . ,(vulpea-hierarchy--relations-json
                                (plist-get tree :links))))))
    (string-replace "__DATA__" (vulpea-hierarchy--json-for-html data)
                    (string-replace "__LIBS__" (vulpea-hierarchy--libraries)
                                    (vulpea-hierarchy--html-template)))))

;;;###autoload
(defun vulpea-hierarchy-graph ()
  "Ask for a starting note and depth, then open the hierarchy in the browser.
The page holds `vulpea-hierarchy-embed-depth' levels below the starting
note.  Clicking a box recentres the graph on it, within those levels."
  (interactive)
  (pcase-let* ((`(,start . ,depth) (vulpea-hierarchy--read-scope))
               (tree (vulpea-hierarchy--scope
                      (vulpea-hierarchy--build) start
                      (max depth vulpea-hierarchy-embed-depth))))
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file vulpea-hierarchy-html-file
        (insert (vulpea-hierarchy--html tree start depth))))
    (browse-url-of-file vulpea-hierarchy-html-file)))

;;;; Native outline view

(defvar-local vulpea-hierarchy--tree nil
  "Full hierarchy shown in this buffer.")

(defvar-local vulpea-hierarchy--expanded nil
  "Hash table of ids whose children are shown.")

(defvar-local vulpea-hierarchy--start nil
  "Id of the note the outline starts from.")

(defvar-local vulpea-hierarchy--depth 2
  "Depth shown when the outline was opened.")

(defvar vulpea-hierarchy-view-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "TAB") #'vulpea-hierarchy-view-toggle)
    (define-key map (kbd "c") #'vulpea-hierarchy-view-recenter)
    (define-key map (kbd "g") #'vulpea-hierarchy-view-redraw)
    map)
  "Keymap for `vulpea-hierarchy-view-mode'.")

(define-derived-mode vulpea-hierarchy-view-mode special-mode "Hierarchy"
  "Major mode for the native vulpea hierarchy outline.
TAB or a [+]/[-] button expands or collapses a note.  RET on a
title visits the note.  c re-scopes, g rebuilds the view.")

(defun vulpea-hierarchy-view--expand-to-depth ()
  "Expand every node in the view above the starting depth."
  (let ((queue (list (cons vulpea-hierarchy--start 0))))
    (while queue
      (pcase-let ((`(,id . ,level) (pop queue)))
        (when (and (< level vulpea-hierarchy--depth)
                   (vulpea-hierarchy--sorted-children id vulpea-hierarchy--tree))
          (puthash id t vulpea-hierarchy--expanded)
          (dolist (kid (vulpea-hierarchy--sorted-children id vulpea-hierarchy--tree))
            (push (cons kid (1+ level)) queue)))))))

(defun vulpea-hierarchy-view--insert (id level path)
  "Insert the line for ID at indent LEVEL, then its children if expanded.
PATH holds the ancestors, so a cycle stops the recursion."
  (let* ((tree vulpea-hierarchy--tree)
         (notes (plist-get tree :notes))
         (kids (vulpea-hierarchy--sorted-children id tree))
         (open (and kids (gethash id vulpea-hierarchy--expanded)))
         (note (vulpea-hierarchy--note id notes)))
    (let ((start (point)))
      (insert (make-string (* 2 level) ?\s))
      (vulpea-hierarchy-view--insert-line-body id kids open note)
      (put-text-property start (point) 'vulpea-hierarchy-id id))
    (insert "\n")
    (when (and open (not (member id path)))
      (dolist (kid kids)
        (vulpea-hierarchy-view--insert kid (1+ level) (cons id path))))))

(defun vulpea-hierarchy-view--insert-line-body (id kids open note)
  "Insert the toggle and title buttons of ID's line, then its child count."
  (let ((notes (plist-get vulpea-hierarchy--tree :notes)))
    (if kids
        (insert-button (if open "[-]" "[+]")
                       'action #'vulpea-hierarchy-view--button-action
                       'follow-link t
                       'help-echo "Expand or collapse"
                       'vulpea-hierarchy-id id
                       'vulpea-hierarchy-kind 'toggle)
      (insert "   "))
    (insert " ")
    (insert-button (vulpea-hierarchy--title id notes)
                   'action #'vulpea-hierarchy-view--button-action
                   'follow-link t
                   'help-echo (or (and note (vulpea-note-path note)) "")
                   'vulpea-hierarchy-id id
                   'vulpea-hierarchy-kind 'visit)
    (when kids (insert (format "  (%d)" (length kids))))))

(defun vulpea-hierarchy-view--redraw ()
  "Erase the buffer and draw the view from its current state."
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (insert (propertize (format "%s  ·  depth %d  ·  TAB expand  RET visit  c re-scope  g rebuild\n\n"
                                (vulpea-hierarchy--title
                                 vulpea-hierarchy--start
                                 (plist-get vulpea-hierarchy--tree :notes))
                                vulpea-hierarchy--depth)
                        'face 'shadow))
    (vulpea-hierarchy-view--insert vulpea-hierarchy--start 0 nil)
    (goto-char (point-min))
    (forward-line (max 0 (1- line)))))

(defun vulpea-hierarchy-view--button-action (button)
  "Expand or visit the note of BUTTON, depending on its kind."
  (let ((id (button-get button 'vulpea-hierarchy-id)))
    (pcase (button-get button 'vulpea-hierarchy-kind)
      ('toggle
       (if (gethash id vulpea-hierarchy--expanded)
           (remhash id vulpea-hierarchy--expanded)
         (puthash id t vulpea-hierarchy--expanded))
       (vulpea-hierarchy-view--redraw))
      ('visit
       (let ((note (vulpea-hierarchy--note id (plist-get vulpea-hierarchy--tree :notes))))
         (unless note (user-error "Note %s is not in the database" id))
         (find-file (vulpea-note-path note))
         (when (vulpea-note-pos note)
           (goto-char (vulpea-note-pos note))))))))

(defun vulpea-hierarchy-view-toggle ()
  "Expand or collapse the note at point."
  (interactive)
  (when-let ((id (get-text-property (point) 'vulpea-hierarchy-id)))
    (when (vulpea-hierarchy--sorted-children id vulpea-hierarchy--tree)
      (if (gethash id vulpea-hierarchy--expanded)
          (remhash id vulpea-hierarchy--expanded)
        (puthash id t vulpea-hierarchy--expanded))
      (vulpea-hierarchy-view--redraw))))

(defun vulpea-hierarchy-view-redraw ()
  "Rebuild the tree from the database and redraw."
  (interactive)
  (setq vulpea-hierarchy--tree (vulpea-hierarchy--build))
  (vulpea-hierarchy-view--expand-to-depth)
  (vulpea-hierarchy-view--redraw))

(defun vulpea-hierarchy-view-recenter ()
  "Ask for a new starting note and depth, then redraw."
  (interactive)
  (pcase-let ((`(,start . ,depth) (vulpea-hierarchy--read-scope)))
    (setq vulpea-hierarchy--start start
          vulpea-hierarchy--depth depth
          vulpea-hierarchy--expanded (make-hash-table :test #'equal))
    (vulpea-hierarchy-view--expand-to-depth)
    (vulpea-hierarchy-view--redraw)))

;;;###autoload
(defun vulpea-hierarchy-outline-native ()
  "Ask for a starting note and depth, then show the hierarchy as buttons."
  (interactive)
  (pcase-let ((`(,start . ,depth) (vulpea-hierarchy--read-scope)))
    (let ((buf (get-buffer-create "*vulpea hierarchy*")))
      (with-current-buffer buf
        (vulpea-hierarchy-view-mode)
        (setq vulpea-hierarchy--tree (vulpea-hierarchy--build)
              vulpea-hierarchy--start start
              vulpea-hierarchy--depth depth
              vulpea-hierarchy--expanded (make-hash-table :test #'equal))
        (vulpea-hierarchy-view--expand-to-depth)
        (vulpea-hierarchy-view--redraw))
      (pop-to-buffer buf))))

;;;; Outline built with vui (trial)

(defun vulpea-hierarchy--visit (id tree)
  "Visit the note ID from TREE in its file."
  (let ((note (vulpea-hierarchy--note id (plist-get tree :notes))))
    (unless note (user-error "Note %s is not in the database" id))
    (find-file (vulpea-note-path note))
    (when (vulpea-note-pos note)
      (goto-char (vulpea-note-pos note)))))

(vui-defcomponent vulpea-hierarchy-node (id level path tree depth initially-open)
  "One note in the vui outline, with its children below when open."
  :state ((toggled nil))
  :render
  (let* ((kids (vulpea-hierarchy--sorted-children id tree))
         (open (if toggled (not initially-open) initially-open))
         (notes (plist-get tree :notes))
         (note (vulpea-hierarchy--note id notes)))
    (vui-vstack
     (vui-hstack
      (vui-space (* 2 level))
      (if kids
          (vui-button (if open "-" "+")
                      :on-click (lambda () (vui-set-state :toggled (not toggled))))
        (vui-text "   "))
      (vui-button (vulpea-hierarchy--title id notes)
                  :no-decoration t
                  :help-echo (and note (vulpea-note-path note))
                  :on-click (lambda () (vulpea-hierarchy--visit id tree)))
      (if kids
          (vui-text (format "(%d)" (length kids)) :face 'shadow)
        (vui-fragment)))
     (if (and open kids (not (member id path)))
         (vui-list kids
                   (lambda (kid)
                     (vui-component 'vulpea-hierarchy-node
                       :id kid :level (1+ level) :path (cons id path)
                       :tree tree :depth depth
                       :initially-open (< (1+ level) depth))))
       (vui-fragment)))))

(vui-defcomponent vulpea-hierarchy-root (start depth tree)
  "The vui outline: a header line, then the starting note."
  :render
  (vui-vstack
   (vui-text (format "%s  ·  depth %d  ·  [+]/[-] expands  ·  title visits  ·  run the command again to re-scope"
                     (vulpea-hierarchy--title start (plist-get tree :notes))
                     depth)
             :face 'shadow)
   (vui-newline)
   (vui-component 'vulpea-hierarchy-node
     :id start :level 0 :path nil :tree tree :depth depth
     :initially-open (> depth 0))))

;;;###autoload
(defun vulpea-hierarchy-outline-vui ()
  "Ask for a starting note and depth, then show the hierarchy with vui."
  (interactive)
  (pcase-let ((`(,start . ,depth) (vulpea-hierarchy--read-scope)))
    (vui-mount (vui-component 'vulpea-hierarchy-root
                 :start start :depth depth :tree (vulpea-hierarchy--build))
               "*vulpea hierarchy (vui)*")))

;;;; Static SVG export (Graphviz)

(defun vulpea-hierarchy--wrap (text width)
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

(defun vulpea-hierarchy--label (id notes)
  "Return the title of ID from NOTES followed by its file tags, like :a:b:."
  (let* ((note (vulpea-hierarchy--note id notes))
         (tags (and note (vulpea-note-tags note))))
    (concat (vulpea-hierarchy--title id notes)
            (and tags (format " :%s:" (string-join tags ":"))))))

(defun vulpea-hierarchy--dot-label (id notes)
  "Return the wrapped, escaped Graphviz label text for ID."
  (mapconcat (lambda (line) (replace-regexp-in-string "[\"\\\\]" "\\\\\\&" line))
             (vulpea-hierarchy--wrap (vulpea-hierarchy--label id notes)
                                     vulpea-hierarchy-wrap-width)
             "\\n"))

(defun vulpea-hierarchy--dot-fill (note rootp)
  "Return the Graphviz attributes for the fill of NOTE.
A note with a coloured tag gets that colour as a tint.  The root gets a
thick border, and a blue fill when it has no coloured tag."
  (let ((color (cdr (vulpea-hierarchy--tag-color note))))
    (concat (cond (color (format ", fillcolor=\"%s66\"" color))
                  (rootp ", fillcolor=\"#d8e6f5\""))
            (and rootp ", penwidth=2"))))

(defun vulpea-hierarchy--dot (tree)
  "Return Graphviz source for TREE, one cluster per root."
  (let ((notes (plist-get tree :notes))
        (children (plist-get tree :children))
        (drawn (make-hash-table :test #'equal)))
    (with-temp-buffer
      (insert "digraph vulpea {\n"
              (format "  rankdir=%s;\n" vulpea-hierarchy-rankdir)
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
                                  id (vulpea-hierarchy--dot-label id notes)
                                  (vulpea-hierarchy--dot-fill
                                   (vulpea-hierarchy--note id notes)
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
                        (vulpea-hierarchy--relation-style
                         relation :label (symbol-name relation))
                        (vulpea-hierarchy--relation-style relation :color "#888888")
                        (vulpea-hierarchy--relation-style relation :color "#888888"))))
      (insert "}\n")
      (buffer-string))))

(defun vulpea-hierarchy--slug (title)
  "Return TITLE as a file-name slug, such as \"value-form\"."
  (string-trim (downcase (replace-regexp-in-string "[^[:alnum:]]+" "-" title))
               "-+" "-+"))

(defun vulpea-hierarchy--svg-file (start depth notes)
  "Return a new SVG file name for the scope from START to DEPTH.
The name is <creation date and time>-<note name>-<depth>.svg, so
exports of the same note never overwrite each other."
  (make-directory vulpea-hierarchy-svg-directory t)
  (expand-file-name
   (format "%s-%s-%d.svg"
           (format-time-string "%Y%m%dT%H%M%S")
           (vulpea-hierarchy--slug (vulpea-hierarchy--title start notes))
           depth)
   vulpea-hierarchy-svg-directory))

;;;###autoload
(defun vulpea-hierarchy-svg ()
  "Ask for a starting note and depth, then write and show a Graphviz SVG."
  (interactive)
  (unless (executable-find "dot")
    (user-error "Graphviz `dot' not found on PATH"))
  (pcase-let* ((`(,start . ,depth) (vulpea-hierarchy--read-scope))
               (tree (vulpea-hierarchy--build))
               (scope (vulpea-hierarchy--scope tree start depth))
               (dot (vulpea-hierarchy--dot scope))
               (file (vulpea-hierarchy--svg-file start depth (plist-get tree :notes))))
    (with-temp-buffer
      (insert dot)
      (unless (zerop (call-process-region (point-min) (point-max) "dot" nil t nil
                                          "-Tsvg" "-o" file))
        (error "Graphviz failed: %s" (buffer-string))))
    (pop-to-buffer (find-file-noselect file))))

(provide 'sp-vulpea-hierarchy)
;;; sp-vulpea-hierarchy.el ends here
