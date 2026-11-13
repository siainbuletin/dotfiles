;;; sp-devonthink-highlights.el --- Bring the highlights of a PDF into its litnote -*- lexical-binding: t; -*-

;;; Commentary:

;; Copies the highlights of the PDF of a litnote under a "* Highlights" heading,
;; each with a `devonthink:' link to its page.  One way: DEVONthink to Emacs.
;; macOS only.
;; Literate source: docs/tangles/academic/sp-devonthink-highlights.org.

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

(defun sp-devonthink-highlights--fetch (uuid)
  "The highlights of the PDF of the record UUID, as (PAGE . HIGHLIGHTS) pairs."
  (sp-devonthink-highlights--parse (sp-devonthink-highlights--run uuid)))

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

(defun sp-devonthink-highlights--missing (pages uuid key)
  "The items for the highlights in PAGES that are not in the section yet.
PAGES is ((PAGE . HIGHLIGHTS) ...); UUID and KEY name the record."
  (let* ((bounds (sp-devonthink-highlights--bounds))
         (body (if bounds
                   (sp-devonthink-highlights--norm
                    (buffer-substring-no-properties (car bounds) (cdr bounds)))
                 ""))
         items)
    (dolist (page pages)
      (dolist (text (cdr page))
        (unless (string-search (sp-devonthink-highlights--norm text) body)
          (push (sp-devonthink-highlights--item uuid key (car page) text) items))))
    (nreverse items)))

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

;;;; The command

;;;###autoload
(defun sp-devonthink-highlights-import ()
  "Add the highlights of this litnote's PDF under its Highlights heading.
Only highlights that are not in the section yet are added; the note is not saved."
  (interactive)
  (let* ((key (sp-devonthink-note-citekey))
         (uuid (or (sp-devonthink-note-record-uuid "import highlights from")
                   (user-error "No DEVONthink record for this note (nor for its crossref)")))
         (pages (sp-devonthink-highlights--fetch uuid))
         (items (sp-devonthink-highlights--missing pages uuid (or key uuid))))
    (cond ((null pages) (message "No highlights in the PDF"))
          ((null items) (message "No new highlights"))
          (t (sp-devonthink-highlights--insert items)
             (message "Added %d highlight%s under %s (not saved)"
                      (length items) (if (cdr items) "s" "") sp-devonthink-highlights-heading)))))

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

(defun sp-devonthink-annotations--link (key annotation uuid)
  "The Org link for ANNOTATION of the record UUID, named after the citekey KEY."
  (let ((page (plist-get annotation :page)))
    (org-link-make-string (concat "devonthink:" (sp-devonthink-link-path uuid page))
                          (sp-devonthink--description key page))))

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

(provide 'sp-devonthink-highlights)
;;; sp-devonthink-highlights.el ends here
