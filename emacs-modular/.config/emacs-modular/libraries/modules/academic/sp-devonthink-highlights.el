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

;;;; Reading and formatting

(defun sp-devonthink-highlights--parse (json-text)
  "The pages read from JSON-TEXT: a list of (PAGE . HIGHLIGHTS)."
  (mapcar (lambda (page) (cons (alist-get 'page page) (alist-get 'highlights page)))
          (json-parse-string json-text :object-type 'alist :array-type 'list)))

(defun sp-devonthink-highlights--fetch (uuid)
  "The highlights of the PDF of the record UUID, as (PAGE . HIGHLIGHTS) pairs."
  (let ((file (sp-reading--osascript (sp-devonthink-browse--path-script uuid))))
    (unless (and (not (string-empty-p file)) (file-exists-p file))
      (user-error "The record has no file on disk (is it indexed?)"))
    (require 'sp-litdb)
    (with-temp-buffer
      (let ((status (call-process sp-litdb-python nil (list (current-buffer) nil) nil
                                  (expand-file-name sp-devonthink-highlights-script) file)))
        (unless (eql status 0) (error "devonthink-highlights failed (status %s)" status))
        (sp-devonthink-highlights--parse (buffer-string))))))

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

(provide 'sp-devonthink-highlights)
;;; sp-devonthink-highlights.el ends here
