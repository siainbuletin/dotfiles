;;; sp-devonthink-highlights.el --- Bring the highlights of a PDF into its litnote -*- lexical-binding: t; -*-

;;; Commentary:

;; Copies the highlights of the PDF of a litnote under a "* Highlights" heading,
;; each with a `devonthink:' link to its page.  One way: DEVONthink to Emacs.
;; macOS only.
;; Literate source: docs/tangles/devonthink/sp-devonthink-highlights.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'sp-reading)
(require 'sp-devonthink)
(require 'sp-devonthink-browse)

(defvar sp-litdb-python)

(defgroup sp-devonthink-highlights nil
  "Bring the highlights of a PDF into its litnote."
  :group 'sp-devonthink)

(defcustom sp-devonthink-highlights-script
  (expand-file-name "tools/devonthink-highlights.py" user-emacs-directory)
  "The script that prints the highlights of a PDF as JSON."
  :type 'file :group 'sp-devonthink-highlights)

(defcustom sp-devonthink-highlights-heading "Highlights"
  "Title of the top-level heading the highlights go under."
  :type 'string :group 'sp-devonthink-highlights)

(defcustom sp-devonthink-highlights-split nil
  "How `sp-devonthink-highlights-import' lays the highlights out.
nil keeps one flat list.  `headings' groups them under a `** Colour'
heading each; `quotes' puts each colour in a quote block marked with
`#+attr_dt: :color NAME'.  A prefix argument asks instead."
  :type '(choice (const :tag "One flat list" nil)
                 (const :tag "A sub-heading per colour" headings)
                 (const :tag "A quote block per colour" quotes))
  :group 'sp-devonthink-highlights)

;;;; Reading and formatting

(defun sp-devonthink-highlights--parse (json-text)
  "The pages read from JSON-TEXT: a list of (PAGE . HIGHLIGHTS)."
  (mapcar (lambda (page) (cons (alist-get 'page page) (alist-get 'highlights page)))
          (json-parse-string json-text :object-type 'alist :array-type 'list)))

(defun sp-devonthink-highlights--file (uuid)
  "The file on disk of the record UUID; signals a `user-error' when there is none."
  (let ((file (sp-reading--osascript (sp-devonthink-browse--path-script uuid))))
    (unless (and (not (string-empty-p file)) (file-exists-p file))
      (user-error "The record has no file on disk (is it indexed?)"))
    file))

(defun sp-devonthink-highlights--run (uuid &rest flags)
  "The output of the highlights script, with FLAGS, on the file of the record UUID."
  (let ((file (sp-devonthink-highlights--file uuid)))
    (require 'sp-litdb)
    (with-temp-buffer
      (let ((status (apply #'call-process sp-litdb-python nil (list (current-buffer) nil) nil
                           (expand-file-name sp-devonthink-highlights-script)
                           (append flags (list file)))))
        (unless (eql status 0) (error "devonthink-highlights failed (status %s)" status))
        (buffer-string)))))

(defun sp-devonthink-highlights--parse-colored (json-text)
  "The pages read from JSON-TEXT made with --colors: (PAGE (TEXT . HEX) ...)."
  (mapcar (lambda (page)
            (cons (alist-get 'page page)
                  (cl-mapcar #'cons (alist-get 'highlights page) (alist-get 'colors page))))
          (json-parse-string json-text :object-type 'alist :array-type 'list :null-object nil)))

(defun sp-devonthink-highlights--fetch (uuid &optional colors)
  "The highlights of the PDF of the record UUID, as (PAGE . HIGHLIGHTS) pairs.
With COLORS each highlight is (TEXT . HEX) instead of TEXT."
  (if colors
      (sp-devonthink-highlights--parse-colored (sp-devonthink-highlights--run uuid "--colors"))
    (sp-devonthink-highlights--parse (sp-devonthink-highlights--run uuid))))

(defun sp-devonthink-highlights--norm (text)
  "TEXT without extra whitespace, in lower case, for comparing."
  (downcase (string-trim (replace-regexp-in-string "[ \t\n]+" " " text))))

(defun sp-devonthink-highlights--item (uuid key page text)
  "An Org list item for the highlight TEXT on PAGE of the record UUID (citekey KEY)."
  (format "- %s %s\n"
          (replace-regexp-in-string "[ \t\n]+" " " (string-trim text))
          (org-link-make-string (concat "devonthink:" (sp-devonthink-link-path uuid page))
                                (sp-devonthink--description key page))))

;;;; The section

(defun sp-devonthink-highlights--bounds ()
  "The (START . END) of the body of the Highlights section in this buffer, or nil."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\* %s[ \t]*$" (regexp-quote sp-devonthink-highlights-heading)) nil t)
        (forward-line 1)
        (let ((start (point)))
          (cons start (if (re-search-forward "^\\* " nil t) (match-beginning 0) (point-max))))))))

(defun sp-devonthink-highlights--missing-entries (pages uuid key)
  "The highlights in PAGES that are not in the section yet, as (HEX . ITEM) pairs.
PAGES is ((PAGE . HIGHLIGHTS) ...); a highlight is TEXT or (TEXT . HEX).
UUID and KEY name the record."
  (let* ((bounds (sp-devonthink-highlights--bounds))
         (body (if bounds
                   (sp-devonthink-highlights--norm
                    (buffer-substring-no-properties (car bounds) (cdr bounds)))
                 ""))
         items)
    (dolist (page pages)
      (dolist (highlight (cdr page))
        (let ((text (if (consp highlight) (car highlight) highlight)))
          (unless (string-search (sp-devonthink-highlights--norm text) body)
            (push (cons (and (consp highlight) (cdr highlight))
                        (sp-devonthink-highlights--item uuid key (car page) text))
                  items)))))
    (nreverse items)))

(defun sp-devonthink-highlights--missing (pages uuid key)
  "The items for the highlights in PAGES that are not in the section yet.
PAGES is ((PAGE . HIGHLIGHTS) ...); UUID and KEY name the record."
  (mapcar #'cdr (sp-devonthink-highlights--missing-entries pages uuid key)))

(defun sp-devonthink-highlights--insert (items)
  "Insert the ITEMS (strings) at the end of the Highlights section."
  (save-excursion
    (let ((bounds (sp-devonthink-highlights--bounds)))
      (if bounds
          (let ((text (apply #'concat items)))
            (goto-char (cdr bounds))
            (skip-chars-backward " \t\n" (car bounds))
            (if (= (point) (car bounds))
                (insert text)
              (insert "\n" (string-remove-suffix "\n" text))))
        (goto-char (point-max))
        (unless (or (bobp) (eq (char-before) ?\n)) (insert "\n"))
        (insert (format "\n* %s\n" sp-devonthink-highlights-heading) (apply #'concat items))))))

;;;; Splitting by colour

(defconst sp-devonthink-highlights--color-order
  '(yellow orange red pink purple blue cyan green gray none)
  "The colour names, in the order their groups are written.")

(defun sp-devonthink-highlights--color-name (hex)
  "The name (a symbol) of the colour HEX (#rrggbb); `none' when HEX is not a colour."
  (if (not (and (stringp hex) (string-match-p "\\`#[[:xdigit:]]\\{6\\}\\'" hex)))
      'none
    (let* ((rgb (mapcar (lambda (i) (/ (string-to-number (substring hex i (+ i 2)) 16) 255.0))
                        '(1 3 5)))
           (high (apply #'max rgb))
           (low (apply #'min rgb))
           (delta (- high low))
           (hue (if (zerop delta)
                    0.0
                  (mod (* 60 (cond ((= high (nth 0 rgb)) (/ (- (nth 1 rgb) (nth 2 rgb)) delta))
                                   ((= high (nth 1 rgb)) (+ 2 (/ (- (nth 2 rgb) (nth 0 rgb)) delta)))
                                   (t (+ 4 (/ (- (nth 0 rgb) (nth 1 rgb)) delta)))))
                       360.0)))
           (saturation (if (zerop high) 0.0 (/ delta high))))
      (cond ((or (< saturation 0.12) (< high 0.15)) 'gray)
            ((or (< hue 15) (>= hue 345)) 'red)
            ((< hue 45) 'orange)
            ((< hue 70) 'yellow)
            ((< hue 165) 'green)
            ((< hue 200) 'cyan)
            ((< hue 255) 'blue)
            ((< hue 295) 'purple)
            (t 'pink)))))

(defun sp-devonthink-highlights--color-label (name)
  "The heading title for the colour NAME."
  (if (eq name 'none) "No colour" (capitalize (symbol-name name))))

(defun sp-devonthink-highlights--group (entries)
  "ENTRIES, (HEX . ITEM) pairs, as ((NAME ITEM ...) ...) in colour order."
  (let (groups)
    (dolist (entry entries)
      (let* ((name (sp-devonthink-highlights--color-name (car entry)))
             (group (assq name groups)))
        (if group
            (setcdr group (append (cdr group) (list (cdr entry))))
          (push (list name (cdr entry)) groups))))
    (sort groups (lambda (a b)
                   (< (seq-position sp-devonthink-highlights--color-order (car a))
                      (seq-position sp-devonthink-highlights--color-order (car b)))))))

(defun sp-devonthink-highlights--quote-block (name items)
  "A quote block of ITEMS marked with the colour NAME."
  (format "#+attr_dt: :color %s\n#+begin_quote\n%s#+end_quote\n"
          name (apply #'concat items)))

(defun sp-devonthink-highlights--insert-under-heading (label items)
  "Insert ITEMS under the sub-heading LABEL of the Highlights section; make it if missing."
  (let* ((bounds (sp-devonthink-highlights--bounds))
         (heading (and bounds
                       (save-excursion
                         (goto-char (car bounds))
                         (re-search-forward
                          (format "^\\*\\* %s[ \t]*$" (regexp-quote label)) (cdr bounds) t)))))
    (if (not heading)
        (sp-devonthink-highlights--insert (cons (format "** %s\n" label) items))
      (save-excursion
        (goto-char heading)
        (end-of-line)
        (goto-char (if (re-search-forward "^\\*\\{1,2\\} " (cdr bounds) t)
                       (match-beginning 0)
                     (cdr bounds)))
        (skip-chars-backward " \t\n" heading)
        (insert "\n" (string-remove-suffix "\n" (apply #'concat items)))))))

(defun sp-devonthink-highlights--insert-groups (groups layout)
  "Insert GROUPS (see `sp-devonthink-highlights--group') in the LAYOUT."
  (pcase layout
    ('quotes
     (sp-devonthink-highlights--insert
      (list (mapconcat (lambda (g) (sp-devonthink-highlights--quote-block (car g) (cdr g)))
                       groups "\n"))))
    (_
     (dolist (g groups)
       (sp-devonthink-highlights--insert-under-heading
        (sp-devonthink-highlights--color-label (car g)) (cdr g))))))

;;;; The command

;;;###autoload
(defun sp-devonthink-highlights--layout (arg)
  "The layout for ARG: `sp-devonthink-highlights-split' when nil, nil for `flat'."
  (cond ((null arg) sp-devonthink-highlights-split)
        ((eq arg 'flat) nil)
        (t arg)))

(defun sp-devonthink-highlights--read-layout ()
  "Ask for a layout: `flat', `headings' or `quotes'."
  (intern (completing-read "Layout: " '("flat" "headings" "quotes") nil t nil nil
                           (symbol-name (or sp-devonthink-highlights-split 'flat)))))

;;;###autoload
(defun sp-devonthink-highlights-import (&optional layout)
  "Add the highlights of this litnote's PDF under its Highlights heading.
Only highlights that are not in the section yet are added; the note is not saved.
LAYOUT is `flat', `headings' or `quotes' (see `sp-devonthink-highlights-split',
the default); with a prefix argument it is asked."
  (interactive (list (when current-prefix-arg (sp-devonthink-highlights--read-layout))))
  (let* ((layout (sp-devonthink-highlights--layout layout))
         (key (sp-devonthink-note-citekey))
         (uuid (or (sp-devonthink-note-record-uuid "import highlights from")
                   (user-error "No DEVONthink record for this note (nor for its crossref)")))
         (pages (sp-devonthink-highlights--fetch uuid (and layout t)))
         (entries (sp-devonthink-highlights--missing-entries pages uuid (or key uuid))))
    (cond ((null pages) (message "No highlights in the PDF"))
          ((null entries) (message "No new highlights"))
          (t (if layout
                 (sp-devonthink-highlights--insert-groups
                  (sp-devonthink-highlights--group entries) layout)
               (sp-devonthink-highlights--insert (mapcar #'cdr entries)))
             (message "Added %d highlight%s under %s%s (not saved)"
                      (length entries) (if (cdr entries) "s" "")
                      sp-devonthink-highlights-heading
                      (if layout (format ", split by colour (%s)" layout) ""))))))

(keymap-set sp-devonthink-map "h" #'sp-devonthink-highlights-import)

;;;; Links to single annotations

(defcustom sp-devonthink-annotation-default 'choose
  "What `sp-devonthink-insert-annotation-link' does without a prefix argument.
`latest' links the most recently created annotation; `choose' asks which one.
A prefix argument does the other."
  :type '(choice (const :tag "Choose from a list" choose)
                 (const :tag "Most recently created" latest))
  :group 'sp-devonthink-highlights)

(defun sp-devonthink-annotations--parse (json-text)
  "The annotations read from JSON-TEXT, as plists (:page :text :note :created :modified)."
  (mapcar (lambda (a)
            (list :page (alist-get 'page a)
                  :text (or (alist-get 'text a) "")
                  :note (or (alist-get 'note a) "")
                  :created (alist-get 'created a)
                  :modified (alist-get 'modified a)))
          (json-parse-string json-text :object-type 'alist :array-type 'list :null-object nil)))

(defun sp-devonthink-annotations--mode (prefix)
  "The mode to use: `sp-devonthink-annotation-default', or the other one when PREFIX is non-nil."
  (if prefix
      (if (eq sp-devonthink-annotation-default 'latest) 'choose 'latest)
    sp-devonthink-annotation-default))

(defun sp-devonthink-annotations--fetch (uuid)
  "Every highlight of the PDF of the record UUID, as plists, in file order."
  (sp-devonthink-annotations--parse (sp-devonthink-highlights--run uuid "--annotations")))

(defun sp-devonthink-annotations--date (annotation)
  "The creation date of ANNOTATION (ISO string), else its modification date, else nil."
  (or (plist-get annotation :created) (plist-get annotation :modified)))

(defun sp-devonthink-annotations--latest (annotations)
  "The most recently created of ANNOTATIONS.
Without dates, or on a tie, the one that comes last in the file wins."
  (let (best)
    (dolist (a annotations best)
      (when (or (null best)
                (not (string-lessp (or (sp-devonthink-annotations--date a) "")
                                   (or (sp-devonthink-annotations--date best) ""))))
        (setq best a)))))

(defun sp-devonthink-annotations--label (annotation)
  "The line that stands for ANNOTATION in the list: page, date, text, comment."
  (let ((date (sp-devonthink-annotations--date annotation)))
    (format "p. %-4d %s  %s%s"
            (plist-get annotation :page)
            (if date (substring date 0 (min 10 (length date))) "----------")
            (truncate-string-to-width
             (replace-regexp-in-string "[ \t\n]+" " " (plist-get annotation :text)) 100 nil nil "…")
            (if (string-empty-p (plist-get annotation :note)) ""
              (format "  [%s]" (truncate-string-to-width (plist-get annotation :note) 40 nil nil "…"))))))

(defun sp-devonthink-annotations--read (annotations prompt)
  "Ask which of ANNOTATIONS to use; the list keeps the order of the file."
  (let* ((table (mapcar (lambda (a) (cons (sp-devonthink-annotations--label a) a)) annotations))
         (collection (lambda (string pred action)
                       (if (eq action 'metadata)
                           '(metadata (display-sort-function . identity)
                                      (cycle-sort-function . identity))
                         (complete-with-action action table string pred)))))
    (cdr (assoc (completing-read prompt collection nil t) table))))

(defcustom sp-devonthink-annotation-short-description t
  "Whether a link to a highlight of this litnote's own record is named `[DT-annot]'.
Applies only when the current buffer is the litnote of the record the link
points to; links in any other buffer keep the citekey and page as description."
  :type 'boolean
  :group 'sp-devonthink-highlights)

(defconst sp-devonthink-annotation-short-text "[DT-annot]"
  "The link description used in the litnote of the record itself.")

(defun sp-devonthink-annotations--own-litnote-p (key uuid)
  "Non-nil when the current buffer is the litnote of the record UUID (citekey KEY).
Matches the note's `#+devonthink:' record, or else its citekey."
  (and (derived-mode-p 'org-mode)
       (or (and-let* ((own (sp-devonthink-note-uuid)))
             (string-equal-ignore-case own uuid))
           (and-let* ((own (sp-devonthink-note-citekey)))
             (string-equal-ignore-case own key)))))

(defun sp-devonthink-annotations--link (key annotation uuid)
  "The Org link for ANNOTATION of the record UUID, named after the citekey KEY.
In the litnote of that record the description is just `[DT-annot]' when
`sp-devonthink-annotation-short-description' is non-nil."
  (let ((page (plist-get annotation :page)))
    (org-link-make-string
     (concat "devonthink:" (sp-devonthink-link-path uuid page))
     (if (and sp-devonthink-annotation-short-description
              (sp-devonthink-annotations--own-litnote-p key uuid))
         sp-devonthink-annotation-short-text
       (sp-devonthink--description key page)))))

;;;###autoload
(defun sp-devonthink-insert-annotation-link (key &optional mode)
  "Insert a `devonthink:' link to a highlight of the record of the citekey KEY.
MODE is `latest' (the most recently created highlight) or `choose' (pick from a
list showing page, date and text).  Interactively it is
`sp-devonthink-annotation-default', and a prefix argument takes the other.
An entry without a record of its own uses its crossref parent's record, whose
highlights are those of the whole book."
  (interactive
   (list (if (fboundp 'citar-select-ref) (citar-select-ref) (read-string "Citekey: "))
         (sp-devonthink-annotations--mode current-prefix-arg)))
  (let* ((found (or (sp-devonthink-record key)
                    (user-error "No DEVONthink record named %s.pdf, and no record for its crossref" key)))
         (uuid (plist-get found :uuid))
         (annotations (or (sp-devonthink-annotations--fetch uuid)
                          (user-error "No highlights in the PDF of %s" (plist-get found :supplier))))
         (annotation (if (eq mode 'latest)
                         (sp-devonthink-annotations--latest annotations)
                       (sp-devonthink-annotations--read
                        annotations (format "Highlight of %s: " (plist-get found :supplier))))))
    (when-let* ((parent (plist-get found :via)))
      (message "%s has no record of its own: highlight of %s (the whole book)" key parent))
    (insert (sp-devonthink-annotations--link key annotation uuid))))

;;;###autoload
(defun sp-devonthink-insert-latest-annotation-link (key)
  "Insert a link to the most recently created highlight of the citekey KEY."
  (interactive (list (if (fboundp 'citar-select-ref) (citar-select-ref) (read-string "Citekey: "))))
  (sp-devonthink-insert-annotation-link key 'latest))

(keymap-set sp-devonthink-map "A" #'sp-devonthink-insert-annotation-link)
(keymap-set sp-devonthink-map "L" #'sp-devonthink-insert-latest-annotation-link)

;;;; Quote block colours

(require 'org)
(declare-function sp-theme-color "sp-theme-engine")
(declare-function sp-theme-blend "sp-theme-engine")
(defvar sp-after-load-theme-hook)

(defgroup sp-devonthink-quote-colors nil
  "Colour the quote blocks that hold highlights of one colour."
  :group 'sp-devonthink-highlights)

(defcustom sp-devonthink-quote-colors-auto t
  "Whether Org buffers turn on `sp-devonthink-quote-colors-mode'."
  :type 'boolean :group 'sp-devonthink-quote-colors)

(defcustom sp-devonthink-quote-color-sources
  '((yellow . yellow) (orange . accent-1) (red . red) (pink . magenta) (purple . accent-2)
    (blue . blue) (cyan . cyan) (green . green) (gray) (none))
  "The theme colour (a name for `sp-theme-color') behind each highlight colour.
An entry with no theme colour gets a neutral blend of the foreground."
  :type '(alist :key-type symbol :value-type (choice (const :tag "Neutral" nil) symbol))
  :group 'sp-devonthink-quote-colors)

(dolist (name sp-devonthink-highlights--color-order)
  (custom-declare-face (intern (format "sp-devonthink-quote-%s" name))
                       '((t :inherit org-quote :extend t))
                       (format "Background of a quote block of %s highlights." name)
                       :group 'sp-devonthink-quote-colors))

(defun sp-devonthink-quote-colors--hex (color)
  "COLOR (a name or #rrggbb) as #rrggbb, or nil."
  (when-let* ((rgb (and (stringp color) (ignore-errors (color-values color)))))
    (apply #'format "#%02x%02x%02x" (mapcar (lambda (c) (/ c 257)) rgb))))

(defun sp-devonthink-quote-colors-refresh (&rest _)
  "Work out the quote block faces from the theme, and fontify the buffers that use them."
  (when (and (require 'sp-theme-engine nil t) (fboundp 'sp-theme-color))
    (let* ((dark (eq (frame-parameter nil 'background-mode) 'dark))
           (bg (or (sp-devonthink-quote-colors--hex (face-attribute 'default :background nil t))
                   (if dark "#000000" "#ffffff")))
           (fg (or (sp-devonthink-quote-colors--hex (face-attribute 'default :foreground nil t))
                   (if dark "#ffffff" "#000000"))))
      (dolist (name sp-devonthink-highlights--color-order)
        (let* ((source (cdr (assq name sp-devonthink-quote-color-sources)))
               (hue (and source (ignore-errors (sp-theme-color source))))
               (tint (if hue
                         (sp-theme-blend bg hue (if dark 0.32 0.22))
                       (sp-theme-blend bg fg (if dark 0.18 0.10)))))
          (face-spec-set (intern (format "sp-devonthink-quote-%s" name))
                         `((t :inherit org-quote :background ,tint :extend t)))))
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (bound-and-true-p sp-devonthink-quote-colors-mode) (font-lock-flush)))))))

(add-hook 'sp-after-load-theme-hook #'sp-devonthink-quote-colors-refresh)

(defconst sp-devonthink-quote-colors--regexp
  (concat "^[ \t]*#\\+attr_dt:[ \t]+\\(?:.*[ \t]\\)?:color[ \t]+\\([[:alnum:]-]+\\)[ \t]*\n"
          "[ \t]*#\\+begin_quote\\_>.*\n"
          "\\(\\(?:.*\n\\)*?\\)[ \t]*#\\+end_quote")
  "Matches a marked quote block: group 1 is the colour name, group 2 the body.")

(defun sp-devonthink-quote-colors--matcher (limit)
  "Font-lock matcher: the next marked quote block before LIMIT."
  (let ((case-fold-search t))
    (re-search-forward sp-devonthink-quote-colors--regexp limit t)))

(defun sp-devonthink-quote-colors--face ()
  "The face for the colour name in group 1 of the match, or nil."
  (let ((face (intern (format "sp-devonthink-quote-%s" (downcase (match-string 1))))))
    (and (facep face) face)))

(defconst sp-devonthink-quote-colors--keywords
  '((sp-devonthink-quote-colors--matcher
     (0 (progn (put-text-property (match-beginning 0) (match-end 0) 'font-lock-multiline t) nil))
     (2 (sp-devonthink-quote-colors--face) prepend t)))
  "The font-lock keywords of `sp-devonthink-quote-colors-mode'.")

(define-minor-mode sp-devonthink-quote-colors-mode
  "Show quote blocks marked with `#+attr_dt: :color NAME' in a colour of the theme."
  :lighter nil
  (if sp-devonthink-quote-colors-mode
      (progn (sp-devonthink-quote-colors-refresh)
             (font-lock-add-keywords nil sp-devonthink-quote-colors--keywords 'append))
    (font-lock-remove-keywords nil sp-devonthink-quote-colors--keywords))
  (when font-lock-mode (font-lock-flush)))

(defun sp-devonthink-quote-colors--maybe-enable ()
  "Turn the mode on in this Org buffer when `sp-devonthink-quote-colors-auto' is set."
  (when sp-devonthink-quote-colors-auto (sp-devonthink-quote-colors-mode 1)))

(add-hook 'org-mode-hook #'sp-devonthink-quote-colors--maybe-enable)

(provide 'sp-devonthink-highlights)
;;; sp-devonthink-highlights.el ends here
