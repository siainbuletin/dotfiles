;;; sp-batch-report.el --- Report buffer of the batch commands, files as links -*- lexical-binding: t; -*-

;;; Commentary:

;; The reports of the batch conversions and dry runs are Org text in a read-only
;; buffer.  `sp-batch-report-file-link' turns a file into an Org link, so you can
;; visit the files that have issues; `sp-batch-report-show' shows the text.
;; See docs/tangles/funct/sp-batch-report.org.

;;; Code:

(require 'org)
(require 'subr-x)

(defun sp-batch-report-file-link (file &optional label line)
  "Return an Org link that visits FILE.
LABEL is the text of the link; it defaults to the name of FILE without its
folder.  LINE, when given, makes the link land on that line."
  (let ((path (expand-file-name file)))
    (org-link-make-string
     (concat "file:" path (and line (format "::%d" line)))
     (or label (file-name-nondirectory (directory-file-name path))))))

(defun sp-batch-report-file-links (files &optional separator)
  "Return the links of FILES, joined with SEPARATOR (default \", \")."
  (mapconcat #'sp-batch-report-file-link files (or separator ", ")))

(defun sp-batch-report-note-link (id title)
  "Return an Org link to the note ID, shown as TITLE."
  (org-link-make-string (concat "id:" id) title))

(defvar-local sp-batch-report-refresh-function nil
  "The function that \\<sp-batch-report-mode-map>\\[sp-batch-report-refresh] calls to make the report again, or nil.")

(defun sp-batch-report-refresh ()
  "Make this report again."
  (interactive)
  (if sp-batch-report-refresh-function
      (funcall sp-batch-report-refresh-function)
    (user-error "This report cannot be refreshed")))

(defvar sp-batch-report-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'org-open-at-point)
    (define-key map (kbd "n") #'org-next-link)
    (define-key map (kbd "p") #'org-previous-link)
    (define-key map (kbd "g") #'sp-batch-report-refresh)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap of `sp-batch-report-mode'.")

(define-derived-mode sp-batch-report-mode org-mode "Report"
  "Read-only Org buffer holding the report of a batch command.
Files are links: \\<sp-batch-report-mode-map>\\[org-open-at-point] visits the one at point,
\\[org-next-link] and \\[org-previous-link] move between them, \\[sp-batch-report-refresh] makes the report again,
\\[quit-window] closes it."
  (setq buffer-read-only t))

(defun sp-batch-report-show (name text &optional refresh mode)
  "Show the Org TEXT in the read-only report buffer NAME and return it.
REFRESH is the function \\`g' calls.  MODE is the major mode to use, a mode
derived from `sp-batch-report-mode'; the default is that mode."
  (with-current-buffer (get-buffer-create name)
    (funcall (or mode #'sp-batch-report-mode))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert text)
      (goto-char (point-min)))
    (outline-show-all)
    (setq sp-batch-report-refresh-function refresh)
    (pop-to-buffer (current-buffer))
    (current-buffer)))

(provide 'sp-batch-report)
;;; sp-batch-report.el ends here
