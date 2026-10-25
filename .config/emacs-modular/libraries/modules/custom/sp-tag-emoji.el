;; -*- lexical-binding: t; -*-
;; sp-tag-emoji.el --- Org tags as emoji in the modeline and on links

;;; Commentary:

;; Rules map a tag, or a combination of tags, to an emoji and/or a face,
;; in the style of Obsidian's Supercharged Links.  `sp-tag-emoji-mode'
;; shows the tags of the heading or file at point as emoji in the
;; modeline, decorates id: links with the tags of their target note and
;; puts the emoji in front of titles in `vulpea-select'.  The selector
;; `sp-tag-emoji-select' also prints the tags in a right-hand column.
;; See `sp-tag-emoji-rules'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)

;;;; Settings
(defgroup sp-tag-emoji nil
  "Org tags shown as emoji."
  :group 'org
  :prefix "sp-tag-emoji-")

(defcustom sp-tag-emoji-rules
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

(defcustom sp-tag-emoji-combo-consumes t
  "When non-nil, a rule uses up its tags: less specific rules skip them."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-tag-emoji-source 'heading-or-file
  "Which tags the modeline segment shows."
  :type '(choice (const :tag "Heading, else file" heading-or-file)
                 (const :tag "Heading only" heading)
                 (const :tag "File only" file)
                 (const :tag "Heading and file" both))
  :group 'spcustom)

(defcustom sp-tag-emoji-inherit nil
  "When non-nil, a heading's tags include those of its parents."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-tag-emoji-placement 'mode-line
  "Where the modeline segment goes."
  :type '(choice (const :tag "In the modeline (global-mode-string)" mode-line)
                 (const :tag "In the header line of Org buffers" header-line))
  :group 'spcustom)

(defcustom sp-tag-emoji-separator " "
  "String between emoji in the modeline."
  :type 'string
  :group 'spcustom)

(defcustom sp-tag-emoji-link-types '("id")
  "Link types that are decorated with the emoji of their target's tags."
  :type '(repeat string)
  :group 'spcustom)

(defcustom sp-tag-emoji-link-position 'prefix
  "Default position of the emoji on a link."
  :type '(choice (const prefix) (const suffix))
  :group 'spcustom)

(defcustom sp-tag-emoji-link-tags-function #'sp-tag-emoji--vulpea-link-tags
  "Function of TYPE and PATH returning the tags of a link's target."
  :type 'function
  :group 'spcustom)

(defcustom sp-tag-emoji-link-cache-seconds 30
  "How long the tags of a link target are remembered."
  :type 'integer
  :group 'spcustom)

(defcustom sp-tag-emoji-select-column-fraction 0.33
  "Fraction of the frame width taken by the tag column of the selector."
  :type 'number
  :group 'spcustom)

(defcustom sp-tag-emoji-select-column-min 16
  "Fewest columns the tag column of the selector may have."
  :type 'integer
  :group 'spcustom)

(defface sp-tag-emoji-select-tags-face
  '((t :inherit shadow :height 0.85))
  "Face of the tags at the right of a note in `sp-tag-emoji-select'."
  :group 'spcustom)

;;;; Matching rules
(defun sp-tag-emoji--rule-tags (rule)
  "The list of tags RULE requires."
  (let ((key (car rule)))
    (if (listp key) key (list key))))

(defun sp-tag-emoji--rule-applies-p (rule context)
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

(defun sp-tag-emoji--matching-rules (tags &optional context)
  "The rules of `sp-tag-emoji-rules' that match TAGS in CONTEXT.
The most specific rules (most tags) are tried first and, with
`sp-tag-emoji-combo-consumes', use up their tags.  The result is
ordered by the position of each rule's first tag in TAGS."
  (let ((rules (sort (copy-sequence sp-tag-emoji-rules)
                     (lambda (a b) (> (length (sp-tag-emoji--rule-tags a))
                                      (length (sp-tag-emoji--rule-tags b))))))
        consumed matched)
    (dolist (rule rules)
      (let ((need (sp-tag-emoji--rule-tags rule)))
        (when (and need
                   (cl-every (lambda (tag) (member tag tags)) need)
                   (not (and sp-tag-emoji-combo-consumes
                             (cl-every (lambda (tag) (member tag consumed)) need)))
                   (sp-tag-emoji--rule-applies-p rule context))
          (push rule matched)
          (when sp-tag-emoji-combo-consumes
            (setq consumed (append need consumed))))))
    (let ((specific-first (nreverse matched)))
      (cons (cl-stable-sort
             (copy-sequence specific-first)
             #'<
             :key (lambda (rule)
                    (apply #'min (mapcar (lambda (tag) (or (cl-position tag tags :test #'equal) 0))
                                         (sp-tag-emoji--rule-tags rule)))))
            specific-first))))

(defun sp-tag-emoji--decorate (tags context)
  "Decoration of TAGS in CONTEXT, as a plist.
Keys: :emoji, a list of (EMOJI POSITION FACE TAGS) in tag order; and
:face, the face of the most specific rule that has one."
  (let* ((pair (sp-tag-emoji--matching-rules tags context))
         (ordered (car pair))
         (specific (cdr pair)))
    (list :emoji (cl-loop for rule in ordered
                          for plist = (cdr rule)
                          when (plist-get plist :emoji)
                          collect (list (plist-get plist :emoji)
                                        (or (plist-get plist :position)
                                            sp-tag-emoji-link-position)
                                        (plist-get plist :face)
                                        (sp-tag-emoji--rule-tags rule)))
          :face (cl-loop for rule in specific
                         when (plist-get (cdr rule) :face)
                         return (plist-get (cdr rule) :face)))))

;;;; Tags at point
(defun sp-tag-emoji--file-tags ()
  "The tags of the current buffer's #+filetags:, without text properties."
  (when (derived-mode-p 'org-mode)
    (mapcar #'substring-no-properties (bound-and-true-p org-file-tags))))

(defun sp-tag-emoji--heading-tags ()
  "The tags of the heading at point, or nil above the first heading."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (when (ignore-errors (org-back-to-heading t) t)
        (mapcar #'substring-no-properties
                (org-get-tags nil (not sp-tag-emoji-inherit)))))))

(defun sp-tag-emoji-tags-at-point ()
  "The tags `sp-tag-emoji-source' selects at point."
  (pcase sp-tag-emoji-source
    ('heading (sp-tag-emoji--heading-tags))
    ('file (sp-tag-emoji--file-tags))
    ('both (delete-dups (append (sp-tag-emoji--heading-tags)
                                (sp-tag-emoji--file-tags))))
    (_ (or (sp-tag-emoji--heading-tags) (sp-tag-emoji--file-tags)))))

;;;; The modeline segment
(defun sp-tag-emoji-modeline-string ()
  "The modeline segment for the tags at point, or an empty string."
  (let* ((decoration (sp-tag-emoji--decorate (sp-tag-emoji-tags-at-point) 'modeline))
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
        items sp-tag-emoji-separator)
       " "))))

(defvar sp-tag-emoji-mode-line-construct
  '(:eval (sp-tag-emoji-modeline-string))
  "The mode line construct that `sp-tag-emoji-mode' adds.")
(put 'sp-tag-emoji-mode-line-construct 'risky-local-variable t)

(defun sp-tag-emoji--install-segment ()
  "Add the segment where `sp-tag-emoji-placement' says."
  (pcase sp-tag-emoji-placement
    ('mode-line
     (unless (listp global-mode-string)
       (setq global-mode-string (list global-mode-string)))
     (add-to-list 'global-mode-string sp-tag-emoji-mode-line-construct t))
    ('header-line
     (add-hook 'org-mode-hook #'sp-tag-emoji--header-line)
     (dolist (buffer (buffer-list))
       (with-current-buffer buffer
         (when (derived-mode-p 'org-mode) (sp-tag-emoji--header-line)))))))

(defun sp-tag-emoji--remove-segment ()
  "Remove the segment from both places."
  (setq global-mode-string
        (delete sp-tag-emoji-mode-line-construct
                (if (listp global-mode-string) global-mode-string
                  (list global-mode-string))))
  (remove-hook 'org-mode-hook #'sp-tag-emoji--header-line)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (local-variable-p 'header-line-format)
        (setq header-line-format
              (delete sp-tag-emoji-mode-line-construct
                      (if (listp header-line-format) header-line-format
                        (list header-line-format))))))))

(defun sp-tag-emoji--header-line ()
  "Put the segment at the start of this buffer's header line."
  (let ((current (if (listp header-line-format) header-line-format
                   (list header-line-format))))
    (unless (memq sp-tag-emoji-mode-line-construct current)
      (setq-local header-line-format
                  (cons sp-tag-emoji-mode-line-construct current)))))

;;;; Decorating links
(defvar sp-tag-emoji--link-cache (make-hash-table :test #'equal)
  "Cache of (TYPE . PATH) to (TIME . TAGS).")

(defun sp-tag-emoji--vulpea-link-tags (type path)
  "Tags of the vulpea note an `id' link of TYPE and PATH points to."
  (when (and (equal type "id")
             (fboundp 'vulpea-db-get-by-id)
             (fboundp 'vulpea-note-tags))
    (let* ((id (car (split-string path "::")))
           (note (ignore-errors (vulpea-db-get-by-id id))))
      (when note (vulpea-note-tags note)))))

(defun sp-tag-emoji--link-tags (type path)
  "Cached tags of the target of a link of TYPE and PATH."
  (let* ((key (cons type path))
         (hit (gethash key sp-tag-emoji--link-cache))
         (now (float-time)))
    (if (and hit (< (- now (car hit)) sp-tag-emoji-link-cache-seconds))
        (cdr hit)
      (let ((tags (mapcar #'substring-no-properties
                          (funcall sp-tag-emoji-link-tags-function type path))))
        (puthash key (cons now tags) sp-tag-emoji--link-cache)
        tags))))

(defun sp-tag-emoji--link-decoration (type path)
  "Decoration for a link of TYPE and PATH, or nil when no rule matches."
  (when (member type sp-tag-emoji-link-types)
    (let ((decoration (sp-tag-emoji--decorate (sp-tag-emoji--link-tags type path) 'link)))
      (when (or (plist-get decoration :emoji) (plist-get decoration :face))
        decoration))))

(defun sp-tag-emoji--link-face (type)
  "A function giving the face of a link of TYPE, for `org-link-set-parameters'."
  (lambda (path)
    (let ((face (plist-get (sp-tag-emoji--link-decoration type path) :face)))
      (if face (list face 'org-link) 'org-link))))

(defun sp-tag-emoji--link-label-bounds (start end)
  "Bounds of the visible label of the link between START and END."
  (save-excursion
    (goto-char start)
    (if (looking-at org-link-bracket-re)
        (if (match-beginning 2)
            (cons (match-beginning 2) (match-end 2))
          (cons (match-beginning 1) (match-end 1)))
      (cons start end))))

(defun sp-tag-emoji--activate-link (type)
  "An activation function for links of TYPE."
  (lambda (start end path _bracketed)
    (remove-overlays start end 'sp-tag-emoji t)
    (when-let* ((decoration (sp-tag-emoji--link-decoration type path))
                (items (plist-get decoration :emoji)))
      (let* ((bounds (sp-tag-emoji--link-label-bounds start end))
             (overlay (make-overlay (car bounds) (cdr bounds) nil t nil))
             (collect (lambda (position)
                        (mapconcat #'car
                                   (seq-filter (lambda (item) (eq (nth 1 item) position))
                                               items)
                                   " "))))
        (overlay-put overlay 'sp-tag-emoji t)
        (overlay-put overlay 'evaporate t)
        (let ((before (funcall collect 'prefix))
              (after (funcall collect 'suffix)))
          (unless (string-empty-p before)
            (overlay-put overlay 'before-string (concat before " ")))
          (unless (string-empty-p after)
            (overlay-put overlay 'after-string (concat " " after))))))))

(defun sp-tag-emoji--set-link-parameters ()
  "Attach the face and activation functions to `sp-tag-emoji-link-types'."
  (dolist (type sp-tag-emoji-link-types)
    (org-link-set-parameters type
                             :face (sp-tag-emoji--link-face type)
                             :activate-func (sp-tag-emoji--activate-link type))))

(defun sp-tag-emoji--clear-link-parameters ()
  "Remove the face and activation functions again."
  (dolist (type sp-tag-emoji-link-types)
    (org-link-set-parameters type :face nil :activate-func nil))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (remove-overlays (point-min) (point-max) 'sp-tag-emoji t)))))

(defun sp-tag-emoji-refresh ()
  "Forget remembered tags and fontify Org buffers again."
  (interactive)
  (clrhash sp-tag-emoji--link-cache)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (font-lock-flush))))
  (force-mode-line-update t))

;;;; Selecting notes
(declare-function vulpea-note-title "vulpea-note")
(declare-function vulpea-note-tags "vulpea-note")
(declare-function vulpea-db-query "vulpea-db-query")
(declare-function vulpea-select-from "vulpea-select")
(declare-function vulpea-visit "vulpea")
(declare-function vulpea-select-cache-drop "vulpea-select")
(defvar vulpea-select-describe-fn)
(defvar vulpea-select-annotate-fn)
(defvar vulpea-select-annotate-matchable)

(defun sp-tag-emoji--note-emoji (note)
  "The emoji of NOTE's tags, joined by spaces, or an empty string."
  (let ((items (plist-get (sp-tag-emoji--decorate
                           (mapcar #'substring-no-properties (vulpea-note-tags note))
                           'select)
                          :emoji)))
    (mapconcat #'car items " ")))

(defun sp-tag-emoji-describe-note (note)
  "NOTE's title with the emoji of its tags in front."
  (let ((emoji (sp-tag-emoji--note-emoji note))
        (title (vulpea-note-title note)))
    (if (string-empty-p emoji) title (concat emoji " " title))))

(defvar sp-tag-emoji--select-columns nil
  "Width in columns of the tag column while `sp-tag-emoji-select' runs.")

(defun sp-tag-emoji--select-columns ()
  "Columns for the tag column, from the width of the selected frame."
  (max sp-tag-emoji-select-column-min
       (round (* sp-tag-emoji-select-column-fraction (frame-width)))))

(defun sp-tag-emoji--tags-text (tags columns)
  "TAGS as \"#a #b\", cut with an ellipsis to fit COLUMNS columns."
  (let* ((height (face-attribute 'sp-tag-emoji-select-tags-face :height nil t))
         (height (if (numberp height) height 1.0))
         (room (max 4 (floor (/ columns height))))
         (text (mapconcat (lambda (tag) (concat "#" tag)) tags " ")))
    (if (> (string-width text) room)
        (concat (truncate-string-to-width text (1- room)) "…")
      text)))

(defun sp-tag-emoji--annotate-note (note)
  "The tags of NOTE at the right edge, for `vulpea-select-annotate-fn'."
  (let ((columns (or sp-tag-emoji--select-columns (sp-tag-emoji--select-columns)))
        (tags (mapcar #'substring-no-properties (vulpea-note-tags note))))
    (if (null tags)
        ""
      (concat (propertize " " 'display `(space :align-to (- right ,columns)))
              (propertize (sp-tag-emoji--tags-text tags columns)
                          'face 'sp-tag-emoji-select-tags-face)))))

(cl-defun sp-tag-emoji-select (prompt &key require-match initial-prompt filter-fn expand-aliases)
  "Select a note, like `vulpea-select', with its tags in a column at the right.
The title has the emoji of its tags in front.  PROMPT, REQUIRE-MATCH,
INITIAL-PROMPT, FILTER-FN and EXPAND-ALIASES are as for `vulpea-select'."
  (let ((sp-tag-emoji--select-columns (sp-tag-emoji--select-columns))
        (vulpea-select-describe-fn #'sp-tag-emoji-describe-note)
        (vulpea-select-annotate-fn #'sp-tag-emoji--annotate-note)
        (vulpea-select-annotate-matchable t))
    (vulpea-select-from prompt
                        (vulpea-db-query filter-fn)
                        :require-match require-match
                        :initial-prompt initial-prompt
                        :expand-aliases expand-aliases)))

(defun sp-tag-emoji-select-visit ()
  "Pick a note with `sp-tag-emoji-select' and visit it."
  (interactive)
  (vulpea-visit (sp-tag-emoji-select "Note" :require-match t)))

(defvar sp-tag-emoji--saved-describe-fn nil
  "Value of `vulpea-select-describe-fn' before `sp-tag-emoji-mode'.")

(defun sp-tag-emoji--install-describe-fn ()
  "Use `sp-tag-emoji-describe-note' in `vulpea-select'."
  (unless (eq (bound-and-true-p vulpea-select-describe-fn) #'sp-tag-emoji-describe-note)
    (setq sp-tag-emoji--saved-describe-fn
          (or (bound-and-true-p vulpea-select-describe-fn) #'vulpea-note-title)))
  (setq vulpea-select-describe-fn #'sp-tag-emoji-describe-note)
  (when (fboundp 'vulpea-select-cache-drop) (vulpea-select-cache-drop)))

(defun sp-tag-emoji--remove-describe-fn ()
  "Give `vulpea-select-describe-fn' its old value back."
  (when (eq (bound-and-true-p vulpea-select-describe-fn) #'sp-tag-emoji-describe-note)
    (setq vulpea-select-describe-fn (or sp-tag-emoji--saved-describe-fn #'vulpea-note-title))
    (when (fboundp 'vulpea-select-cache-drop) (vulpea-select-cache-drop))))

;;;; The mode
(define-minor-mode sp-tag-emoji-mode
  "Show Org tags as emoji in the modeline and on links."
  :global t
  :group 'sp-tag-emoji
  (sp-tag-emoji--remove-segment)
  (sp-tag-emoji--clear-link-parameters)
  (sp-tag-emoji--remove-describe-fn)
  (when sp-tag-emoji-mode
    (sp-tag-emoji--install-segment)
    (sp-tag-emoji--set-link-parameters)
    (sp-tag-emoji--install-describe-fn))
  (sp-tag-emoji-refresh))

;;;; Commands
(defun sp-tag-emoji-cycle-source ()
  "Cycle `sp-tag-emoji-source' through its values."
  (interactive)
  (let ((all '(heading-or-file heading file both)))
    (setq sp-tag-emoji-source
          (or (cadr (memq sp-tag-emoji-source all)) (car all)))
    (message "Tag emoji source: %s" sp-tag-emoji-source)
    (force-mode-line-update t)))

(defun sp-tag-emoji-describe ()
  "Say which tags are at point and how the rules decorate them."
  (interactive)
  (let* ((tags (sp-tag-emoji-tags-at-point))
         (items (plist-get (sp-tag-emoji--decorate tags 'modeline) :emoji)))
    (message "Tags %s -> %s"
             (if tags (mapconcat (lambda (tag) (concat ":" tag ":")) tags " ") "none")
             (if items (mapconcat #'car items " ") "no rule matches"))))

(defun sp-tag-emoji-unregistered-tags ()
  "Tags used in `sp-tag-emoji-rules' that no tag alist knows."
  (let ((known (delq nil
                     (mapcar (lambda (entry) (and (consp entry) (stringp (car entry)) (car entry)))
                             (append org-tag-alist org-tag-persistent-alist))))
        result)
    (dolist (rule sp-tag-emoji-rules)
      (dolist (tag (sp-tag-emoji--rule-tags rule))
        (unless (member tag known) (cl-pushnew tag result :test #'equal))))
    (nreverse result)))

(defun sp-tag-emoji-check-rules ()
  "Report the tags in the rules that are missing from the tag registry."
  (interactive)
  (let ((missing (sp-tag-emoji-unregistered-tags)))
    (message (if missing "Tags not in org-tag-alist: %s" "All rule tags are registered.%s")
             (if missing (mapconcat #'identity missing ", ") ""))
    missing))

;;; Provide:

(provide 'sp-tag-emoji)
;; sp-tag-emoji.el ends here.
