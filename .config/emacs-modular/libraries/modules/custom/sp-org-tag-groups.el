;; -*- lexical-binding: t; -*-
;; sp-org-tag-groups.el --- Org tags as emoji in the modeline and on links

;;; Commentary:

;; Rules map a tag, or a combination of tags, to an emoji and/or a face,
;; in the style of Obsidian's Supercharged Links.  `sp-org-tag-groups-mode'
;; shows the tags of the heading or file at point as emoji in the
;; modeline, decorates id: links with the tags of their target note and
;; puts the emoji in front of titles in `vulpea-select'.  The selector
;; `sp-select-note' also prints the tags in a right-hand column.
;; See `sp-org-tag-groups-rules'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)

;;;; Settings
(defgroup sp-org-tag-groups nil
  "Org tags shown as emoji."
  :group 'org
  :prefix "sp-org-tag-groups-")

(defcustom sp-org-tag-groups-rules
  '(("project"            :emoji "🚀")
    ("@home"              :emoji "🏠")
    ("@uni"               :emoji "🎓")
    ("@computer"          :emoji "💻")
    ("@phone"             :emoji "📱")
    ("@planning"          :emoji "🗺️")
    ("@configuration"     :emoji "⚙️")
    ("@writing"           :emoji "✍️")
    ("@reading"           :emoji "📖")
    ("@music"             :emoji "🎵")
    ("@research"          :emoji "🔬")
    ("@errands"           :emoji "🛒")
    ("@waiting"           :emoji "⏳")
    ("deep"               :emoji "🧠")
    ("shallow"            :emoji "🪶")
    (("@writing" "deep")  :emoji "🖋️" :face (:foreground "orchid")))
  "Rules that decorate tags.
Each rule is (KEY . PLIST).  KEY is a tag, or a list of tags that must
all be present.  PLIST may have :emoji, :face, :position (`prefix' or
`suffix', links only), :modeline and :links (nil keeps the rule out)."
  :type '(repeat (cons (choice (string :tag "Tag")
                               (repeat :tag "All of these tags" string))
                       (plist :key-type symbol :value-type sexp)))
  :group 'spcustom)

(defcustom sp-org-tag-groups-combo-consumes t
  "When non-nil, a rule uses up its tags: less specific rules skip them."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-org-tag-groups-source 'heading-or-file
  "Which tags the modeline segment shows."
  :type '(choice (const :tag "Heading, else file" heading-or-file)
                 (const :tag "Heading only" heading)
                 (const :tag "File only" file)
                 (const :tag "Heading and file" both))
  :group 'spcustom)

(defcustom sp-org-tag-groups-inherit nil
  "When non-nil, a heading's tags include those of its parents."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-org-tag-groups-placement 'mode-line
  "Where the modeline segment goes."
  :type '(choice (const :tag "In the modeline (global-mode-string)" mode-line)
                 (const :tag "In the header line of Org buffers" header-line))
  :group 'spcustom)

(defcustom sp-org-tag-groups-separator " "
  "String between emoji in the modeline."
  :type 'string
  :group 'spcustom)

(defcustom sp-org-tag-groups-link-types '("id")
  "Link types that are decorated with the emoji of their target's tags."
  :type '(repeat string)
  :group 'spcustom)

(defcustom sp-org-tag-groups-link-position 'prefix
  "Default position of the emoji on a link."
  :type '(choice (const prefix) (const suffix))
  :group 'spcustom)

(defcustom sp-org-tag-groups-link-tags-function #'sp-org-tag-groups--vulpea-link-tags
  "Function of TYPE and PATH returning the tags of a link's target."
  :type 'function
  :group 'spcustom)

(defcustom sp-org-tag-groups-link-cache-seconds 30
  "How long the tags of a link target are remembered."
  :type 'integer
  :group 'spcustom)

(defcustom sp-org-tag-groups-select-column-fraction 0.33
  "Fraction of the frame width taken by the tag column of the selector."
  :type 'number
  :group 'spcustom)

(defcustom sp-org-tag-groups-select-column-min 16
  "Fewest columns the tag column of the selector may have."
  :type 'integer
  :group 'spcustom)

(defface sp-org-tag-groups-select-tags-face
  '((t :inherit shadow :height 0.85))
  "Face of the tags at the right of a note in `sp-select-note'."
  :group 'spcustom)

;;;; Matching rules
(defun sp-org-tag-groups--rule-tags (rule)
  "The list of tags RULE requires."
  (let ((key (car rule)))
    (if (listp key) key (list key))))

(defun sp-org-tag-groups--rule-applies-p (rule context)
  "Non-nil when RULE is meant for CONTEXT: `modeline', `link' or `select'."
  (let ((plist (cdr rule)))
    (pcase context
      ('modeline (not (and (plist-member plist :modeline)
                           (null (plist-get plist :modeline)))))
      ('link (not (and (plist-member plist :links)
                       (null (plist-get plist :links)))))
      ('select (not (and (plist-member plist :select)
                         (null (plist-get plist :select)))))
      (_ t))))

(defun sp-org-tag-groups--matching-rules (tags &optional context)
  "The rules of `sp-org-tag-groups-rules' that match TAGS in CONTEXT.
The most specific rules (most tags) are tried first and, with
`sp-org-tag-groups-combo-consumes', use up their tags.  The result is
ordered by the position of each rule's first tag in TAGS."
  (let ((rules (sort (copy-sequence sp-org-tag-groups-rules)
                     (lambda (a b) (> (length (sp-org-tag-groups--rule-tags a))
                                      (length (sp-org-tag-groups--rule-tags b))))))
        consumed matched)
    (dolist (rule rules)
      (let ((need (sp-org-tag-groups--rule-tags rule)))
        (when (and need
                   (cl-every (lambda (tag) (member tag tags)) need)
                   (not (and sp-org-tag-groups-combo-consumes
                             (cl-every (lambda (tag) (member tag consumed)) need)))
                   (sp-org-tag-groups--rule-applies-p rule context))
          (push rule matched)
          (when sp-org-tag-groups-combo-consumes
            (setq consumed (append need consumed))))))
    (let ((specific-first (nreverse matched)))
      (cons (cl-stable-sort
             (copy-sequence specific-first)
             #'<
             :key (lambda (rule)
                    (apply #'min (mapcar (lambda (tag) (or (cl-position tag tags :test #'equal) 0))
                                         (sp-org-tag-groups--rule-tags rule)))))
            specific-first))))

(defun sp-org-tag-groups--decorate (tags context)
  "Decoration of TAGS in CONTEXT, as a plist.
Keys: :emoji, a list of (EMOJI POSITION FACE TAGS) in tag order; and
:face, the face of the most specific rule that has one."
  (let* ((pair (sp-org-tag-groups--matching-rules tags context))
         (ordered (car pair))
         (specific (cdr pair)))
    (list :emoji (cl-loop for rule in ordered
                          for plist = (cdr rule)
                          when (plist-get plist :emoji)
                          collect (list (plist-get plist :emoji)
                                        (or (plist-get plist :position)
                                            sp-org-tag-groups-link-position)
                                        (plist-get plist :face)
                                        (sp-org-tag-groups--rule-tags rule)))
          :face (cl-loop for rule in specific
                         when (plist-get (cdr rule) :face)
                         return (plist-get (cdr rule) :face)))))

;;;; Tags at point
(defun sp-org-tag-groups--file-tags ()
  "The tags of the current buffer's #+filetags:, without text properties."
  (when (derived-mode-p 'org-mode)
    (mapcar #'substring-no-properties (bound-and-true-p org-file-tags))))

(defun sp-org-tag-groups--heading-tags ()
  "The tags of the heading at point, or nil above the first heading."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (when (ignore-errors (org-back-to-heading t) t)
        (mapcar #'substring-no-properties
                (org-get-tags nil (not sp-org-tag-groups-inherit)))))))

(defun sp-org-tag-groups-tags-at-point ()
  "The tags `sp-org-tag-groups-source' selects at point."
  (pcase sp-org-tag-groups-source
    ('heading (sp-org-tag-groups--heading-tags))
    ('file (sp-org-tag-groups--file-tags))
    ('both (delete-dups (append (sp-org-tag-groups--heading-tags)
                                (sp-org-tag-groups--file-tags))))
    (_ (or (sp-org-tag-groups--heading-tags) (sp-org-tag-groups--file-tags)))))

;;;; The modeline segment
(defun sp-org-tag-groups-modeline-string ()
  "The modeline segment for the tags at point, or an empty string."
  (let* ((decoration (sp-org-tag-groups--decorate (sp-org-tag-groups-tags-at-point) 'modeline))
         (items (plist-get decoration :emoji)))
    (if (null items)
        ""
      (concat
       " "
       (mapconcat
        (pcase-lambda (`(,emoji ,_pos ,face ,tags))
          (apply #'propertize emoji
                 'help-echo (concat ":" (mapconcat #'identity tags ":") ":")
                 (when face (list 'face face))))
        items sp-org-tag-groups-separator)
       " "))))

(defvar sp-org-tag-groups-mode-line-construct
  '(:eval (sp-org-tag-groups-modeline-string))
  "The mode line construct that `sp-org-tag-groups-mode' adds.")
(put 'sp-org-tag-groups-mode-line-construct 'risky-local-variable t)

(defun sp-org-tag-groups--install-segment ()
  "Add the segment where `sp-org-tag-groups-placement' says."
  (pcase sp-org-tag-groups-placement
    ('mode-line
     (unless (listp global-mode-string)
       (setq global-mode-string (list global-mode-string)))
     (add-to-list 'global-mode-string sp-org-tag-groups-mode-line-construct t))
    ('header-line
     (add-hook 'org-mode-hook #'sp-org-tag-groups--header-line)
     (dolist (buffer (buffer-list))
       (with-current-buffer buffer
         (when (derived-mode-p 'org-mode) (sp-org-tag-groups--header-line)))))))

(defun sp-org-tag-groups--remove-segment ()
  "Remove the segment from both places."
  (setq global-mode-string
        (delete sp-org-tag-groups-mode-line-construct
                (if (listp global-mode-string) global-mode-string
                  (list global-mode-string))))
  (remove-hook 'org-mode-hook #'sp-org-tag-groups--header-line)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (local-variable-p 'header-line-format)
        (setq header-line-format
              (delete sp-org-tag-groups-mode-line-construct
                      (if (listp header-line-format) header-line-format
                        (list header-line-format))))))))

(defun sp-org-tag-groups--header-line ()
  "Put the segment at the start of this buffer's header line."
  (let ((current (if (listp header-line-format) header-line-format
                   (list header-line-format))))
    (unless (memq sp-org-tag-groups-mode-line-construct current)
      (setq-local header-line-format
                  (cons sp-org-tag-groups-mode-line-construct current)))))

;;;; Decorating links
(defvar sp-org-tag-groups--link-cache (make-hash-table :test #'equal)
  "Cache of (TYPE . PATH) to (TIME . TAGS).")

(defun sp-org-tag-groups--vulpea-link-tags (type path)
  "Tags of the vulpea note an `id' link of TYPE and PATH points to."
  (when (and (equal type "id")
             (fboundp 'vulpea-db-get-by-id)
             (fboundp 'vulpea-note-tags))
    (let* ((id (car (split-string path "::")))
           (note (ignore-errors (vulpea-db-get-by-id id))))
      (when note (vulpea-note-tags note)))))

(defun sp-org-tag-groups--link-tags (type path)
  "Cached tags of the target of a link of TYPE and PATH."
  (let* ((key (cons type path))
         (hit (gethash key sp-org-tag-groups--link-cache))
         (now (float-time)))
    (if (and hit (< (- now (car hit)) sp-org-tag-groups-link-cache-seconds))
        (cdr hit)
      (let ((tags (mapcar #'substring-no-properties
                          (funcall sp-org-tag-groups-link-tags-function type path))))
        (puthash key (cons now tags) sp-org-tag-groups--link-cache)
        tags))))

(defun sp-org-tag-groups--link-decoration (type path)
  "Decoration for a link of TYPE and PATH, or nil when no rule matches."
  (when (member type sp-org-tag-groups-link-types)
    (let ((decoration (sp-org-tag-groups--decorate (sp-org-tag-groups--link-tags type path) 'link)))
      (when (or (plist-get decoration :emoji) (plist-get decoration :face))
        decoration))))

(defun sp-org-tag-groups--link-face (type)
  "A function giving the face of a link of TYPE, for `org-link-set-parameters'."
  (lambda (path)
    (let ((face (plist-get (sp-org-tag-groups--link-decoration type path) :face)))
      (if face (list face 'org-link) 'org-link))))

(defun sp-org-tag-groups--link-label-bounds (start end)
  "Bounds of the visible label of the link between START and END."
  (save-excursion
    (goto-char start)
    (if (looking-at org-link-bracket-re)
        (if (match-beginning 2)
            (cons (match-beginning 2) (match-end 2))
          (cons (match-beginning 1) (match-end 1)))
      (cons start end))))

(defun sp-org-tag-groups--activate-link (type)
  "An activation function for links of TYPE."
  (lambda (start end path _bracketed)
    (remove-overlays start end 'sp-org-tag-groups t)
    (when-let* ((decoration (sp-org-tag-groups--link-decoration type path))
                (items (plist-get decoration :emoji)))
      (let* ((bounds (sp-org-tag-groups--link-label-bounds start end))
             (overlay (make-overlay (car bounds) (cdr bounds) nil t nil))
             (collect (lambda (position)
                        (mapconcat #'car
                                   (seq-filter (lambda (item) (eq (nth 1 item) position))
                                               items)
                                   " "))))
        (overlay-put overlay 'sp-org-tag-groups t)
        (overlay-put overlay 'evaporate t)
        (let ((before (funcall collect 'prefix))
              (after (funcall collect 'suffix)))
          (unless (string-empty-p before)
            (overlay-put overlay 'before-string (concat before " ")))
          (unless (string-empty-p after)
            (overlay-put overlay 'after-string (concat " " after))))))))

(defun sp-org-tag-groups--set-link-parameters ()
  "Attach the face and activation functions to `sp-org-tag-groups-link-types'."
  (dolist (type sp-org-tag-groups-link-types)
    (org-link-set-parameters type
                             :face (sp-org-tag-groups--link-face type)
                             :activate-func (sp-org-tag-groups--activate-link type))))

(defun sp-org-tag-groups--clear-link-parameters ()
  "Remove the face and activation functions again."
  (dolist (type sp-org-tag-groups-link-types)
    (org-link-set-parameters type :face nil :activate-func nil))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (remove-overlays (point-min) (point-max) 'sp-org-tag-groups t)))))

(defun sp-org-tag-groups-refresh ()
  "Forget remembered tags and fontify Org buffers again."
  (interactive)
  (clrhash sp-org-tag-groups--link-cache)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (font-lock-flush))))
  (force-mode-line-update t))

;;;; Tag groups and their colours
(defcustom sp-org-tag-groups-alist
  '(("structure"  "area" "project" "agenda" "archive" "cemetery")
    ("who"        "person" "musician" "group" "institution" "company")
    ("music"      "album" "genre")
    ("software"   "software" "package")
    ("literature" "text" "book" "journalarticle" "booksection"
                  "collection" "incollection")
    ("inquiry"    "question" "error" "research-q" "exploratory"))
  "Groups of note tags: a list of (GROUP TAG…).
A member may be (TAG . KEY), as in `org-tag-alist'.  See ADR 0020."
  :type '(repeat (cons (string :tag "Group") (repeat (choice string (cons string character)))))
  :group 'spcustom)

(defcustom sp-org-tag-groups-colors
  '(("structure" . gray)
    ("who" . orange)
    ("music" . pink)
    ("software" . blue)
    ("literature" . brown)
    ("inquiry" . purple))
  "Notion colour of each tag group, a name from `sp-org-tag-groups-palette'."
  :type '(alist :key-type string :value-type symbol)
  :group 'spcustom)

(defcustom sp-org-tag-groups-palette
  '((default "#E3E2E0" "#32302C" "#373737" "#D4D4D4")
    (gray    "#E3E2E0" "#32302C" "#454B4E" "#D4D4D4")
    (brown   "#EEE0DA" "#32302C" "#434040" "#D4D4D4")
    (orange  "#FADEC9" "#32302C" "#594A3A" "#D4D4D4")
    (yellow  "#FDECC8" "#32302C" "#59563B" "#D4D4D4")
    (green   "#DBEDDB" "#32302C" "#354C4B" "#D4D4D4")
    (blue    "#D3E5EF" "#32302C" "#364954" "#D4D4D4")
    (purple  "#E8DEEE" "#32302C" "#443F57" "#D4D4D4")
    (pink    "#F5E0E9" "#32302C" "#533B4C" "#D4D4D4")
    (red     "#FFE2DD" "#32302C" "#594141" "#D4D4D4"))
  "Tag colours after Notion: (NAME LIGHT-BG LIGHT-FG DARK-BG DARK-FG)."
  :type '(alist :key-type symbol :value-type (list string string string string))
  :group 'spcustom)

(defun sp-org-tag-group-of (tag)
  "The groups of TAG, as a list of names, in the order of `sp-org-tag-groups-alist'."
  (cl-loop for (group . members) in sp-org-tag-groups-alist
           when (member tag (mapcar (lambda (member) (if (consp member) (car member) member))
                                    members))
           collect group))

(defun sp-org-tag-groups--chip-face (tag)
  "Face for the chip of TAG: the colour of its first group, from the palette."
  (let* ((group (car (sp-org-tag-group-of tag)))
         (name (or (cdr (assoc group sp-org-tag-groups-colors)) 'default))
         (entry (or (assq name sp-org-tag-groups-palette) (assq 'default sp-org-tag-groups-palette)))
         (dark (eq (frame-parameter nil 'background-mode) 'dark)))
    (list :inherit 'sp-org-tag-groups-select-tags-face
          :background (nth (if dark 3 1) entry)
          :foreground (nth (if dark 4 2) entry))))

(defun sp-org-tag-groups--chips (tags columns)
  "TAGS as coloured chips, an ellipsis replacing those that exceed COLUMNS."
  (let* ((height (face-attribute 'sp-org-tag-groups-select-tags-face :height nil t))
         (height (if (numberp height) height 1.0))
         (room (max 4 (floor (/ columns height))))
         (used 0) chips)
    (catch 'full
      (dolist (tag tags)
        (let ((width (+ (string-width tag) 2 (if chips 1 0))))
          (when (> (+ used width) (1- room))
            (push (propertize "…" 'face 'sp-org-tag-groups-select-tags-face) chips)
            (throw 'full nil))
          (setq used (+ used width))
          (when chips (push " " chips))
          (push (propertize (concat " " tag " ") 'face (sp-org-tag-groups--chip-face tag)) chips))))
    (apply #'concat (nreverse chips))))

;;;; Selecting notes
(declare-function vulpea-note-title "vulpea-note")
(declare-function vulpea-note-tags "vulpea-note")
(declare-function vulpea-db-query "vulpea-db-query")
(declare-function vulpea-select-from "vulpea-select")
(declare-function vulpea-select-cache-drop "vulpea-select")
(defvar vulpea-select-describe-fn)
(defvar vulpea-select-annotate-fn)
(defvar vulpea-select-annotate-matchable)
(defvar vulpea-select-cache)
(declare-function vulpea-insert "vulpea")

(defun sp-org-tag-groups--note-emoji (note)
  "The emoji of NOTE's tags, joined by spaces, or an empty string."
  (let ((items (plist-get (sp-org-tag-groups--decorate
                           (mapcar #'substring-no-properties (vulpea-note-tags note))
                           'select)
                          :emoji)))
    (mapconcat #'car items " ")))

(defun sp-org-tag-groups-describe-note (note)
  "NOTE's title with the emoji of its tags in front."
  (let ((emoji (sp-org-tag-groups--note-emoji note))
        (title (vulpea-note-title note)))
    (if (string-empty-p emoji) title (concat emoji " " title))))

(defvar sp-org-tag-groups--select-columns nil
  "Width in columns of the tag column while `sp-select-note' runs.")

(defun sp-org-tag-groups--select-columns ()
  "Columns for the tag column, from the width of the selected frame."
  (max sp-org-tag-groups-select-column-min
       (round (* sp-org-tag-groups-select-column-fraction (frame-width)))))

(defun sp-org-tag-groups--annotate-note (note)
  "The tags of NOTE at the right edge, for `vulpea-select-annotate-fn'."
  (let ((columns (or sp-org-tag-groups--select-columns (sp-org-tag-groups--select-columns)))
        (tags (mapcar #'substring-no-properties (vulpea-note-tags note))))
    (if (null tags)
        ""
      (concat (propertize " " 'display `(space :align-to (- right ,columns)))
              (sp-org-tag-groups--chips tags columns)))))

(defmacro sp-org-tag-groups--with-tag-column (&rest body)
  "Run BODY with vulpea's selector showing emoji and a right-hand tag column.
The candidate cache is bypassed, because the column width is not a
property of the note."
  (declare (indent 0))
  `(let ((sp-org-tag-groups--select-columns (sp-org-tag-groups--select-columns))
         (vulpea-select-describe-fn #'sp-org-tag-groups-describe-note)
         (vulpea-select-annotate-fn #'sp-org-tag-groups--annotate-note)
         (vulpea-select-annotate-matchable t)
         (vulpea-select-cache nil))
     ,@body))

(cl-defun sp-select-note (prompt &key require-match initial-prompt filter-fn expand-aliases)
  "Select a note, like `vulpea-select', with its tags in a column at the right.
The title has the emoji of its tags in front.  PROMPT, REQUIRE-MATCH,
INITIAL-PROMPT, FILTER-FN and EXPAND-ALIASES are as for `vulpea-select'."
  (sp-org-tag-groups--with-tag-column
    (vulpea-select-from prompt
                        (vulpea-db-query filter-fn)
                        :require-match require-match
                        :initial-prompt initial-prompt
                        :expand-aliases expand-aliases)))

(defun sp-insert-note (&rest args)
  "Insert a link to a note chosen with the emoji and the tag column.
Like `vulpea-insert': ARGS are its keywords (:filter-fn, :candidates-fn,
:create-fn, :note-fn, :expand-aliases).  The link text is the note's
title, without the emoji."
  (interactive)
  (sp-org-tag-groups--with-tag-column
    (apply #'vulpea-insert args)))

(defvar sp-org-tag-groups--saved-describe-fn nil
  "Value of `vulpea-select-describe-fn' before `sp-org-tag-groups-mode'.")

(defun sp-org-tag-groups--install-describe-fn ()
  "Use `sp-org-tag-groups-describe-note' in `vulpea-select'."
  (unless (eq (bound-and-true-p vulpea-select-describe-fn) #'sp-org-tag-groups-describe-note)
    (setq sp-org-tag-groups--saved-describe-fn
          (or (bound-and-true-p vulpea-select-describe-fn) #'vulpea-note-title)))
  (setq vulpea-select-describe-fn #'sp-org-tag-groups-describe-note)
  (when (fboundp 'vulpea-select-cache-drop) (vulpea-select-cache-drop)))

(defun sp-org-tag-groups--remove-describe-fn ()
  "Give `vulpea-select-describe-fn' its old value back."
  (when (eq (bound-and-true-p vulpea-select-describe-fn) #'sp-org-tag-groups-describe-note)
    (setq vulpea-select-describe-fn (or sp-org-tag-groups--saved-describe-fn #'vulpea-note-title))
    (when (fboundp 'vulpea-select-cache-drop) (vulpea-select-cache-drop))))

;;;; The mode
(define-minor-mode sp-org-tag-groups-mode
  "Show Org tags as emoji in the modeline and on links."
  :global t
  :group 'sp-org-tag-groups
  (sp-org-tag-groups--remove-segment)
  (sp-org-tag-groups--clear-link-parameters)
  (sp-org-tag-groups--remove-describe-fn)
  (when sp-org-tag-groups-mode
    (sp-org-tag-groups--install-segment)
    (sp-org-tag-groups--set-link-parameters)
    (sp-org-tag-groups--install-describe-fn))
  (sp-org-tag-groups-refresh))

;;;; Commands
(defun sp-org-tag-groups-cycle-source ()
  "Cycle `sp-org-tag-groups-source' through its values."
  (interactive)
  (let ((all '(heading-or-file heading file both)))
    (setq sp-org-tag-groups-source
          (or (cadr (memq sp-org-tag-groups-source all)) (car all)))
    (message "Tag emoji source: %s" sp-org-tag-groups-source)
    (force-mode-line-update t)))

(defun sp-org-tag-groups-describe ()
  "Say which tags are at point and how the rules decorate them."
  (interactive)
  (let* ((tags (sp-org-tag-groups-tags-at-point))
         (items (plist-get (sp-org-tag-groups--decorate tags 'modeline) :emoji)))
    (message "Tags %s -> %s"
             (if tags (mapconcat (lambda (tag) (concat ":" tag ":")) tags " ") "none")
             (if items (mapconcat #'car items " ") "no rule matches"))))

(defun sp-org-tag-groups-unregistered-tags ()
  "Tags used in `sp-org-tag-groups-rules' that no tag alist knows."
  (let ((known (delq nil
                     (mapcar (lambda (entry) (and (consp entry) (stringp (car entry)) (car entry)))
                             (append org-tag-alist org-tag-persistent-alist))))
        result)
    (dolist (rule sp-org-tag-groups-rules)
      (dolist (tag (sp-org-tag-groups--rule-tags rule))
        (unless (member tag known) (cl-pushnew tag result :test #'equal))))
    (nreverse result)))

(defun sp-org-tag-groups-check-rules ()
  "Report the tags in the rules that are missing from the tag registry."
  (interactive)
  (let ((missing (sp-org-tag-groups-unregistered-tags)))
    (message (if missing "Tags not in org-tag-alist: %s" "All rule tags are registered.%s")
             (if missing (mapconcat #'identity missing ", ") ""))
    missing))

;;; Provide:

(provide 'sp-org-tag-groups)
;; sp-org-tag-groups.el ends here.
