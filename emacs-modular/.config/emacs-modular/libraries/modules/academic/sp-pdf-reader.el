;;; sp-pdf-reader.el --- Read PDFs in Emacs with emureader -*- lexical-binding: t; -*-

;;; Commentary:

;; Installs emureader and gives one function, `sp-pdf-open', that
;; opens a PDF in it at a page.  Annotations stay in DEVONthink.
;; Literate source: docs/tangles/academic/sp-pdf-reader.org.

;;; Code:

(require 'subr-x)

(defgroup sp-pdf-reader nil
  "Reading PDFs in Emacs with emureader."
  :group 'applications
  :prefix "sp-pdf-reader-")

(defcustom sp-pdf-reader-function-open 'emureader-open-doc
  "Function that opens a document file in emureader (one argument: the file)."
  :type 'symbol)

(defcustom sp-pdf-reader-function-goto-page 'emureader-goto-page
  "Function that goes to a page of the current document (counted from 1)."
  :type 'symbol)

(defcustom sp-pdf-reader-function-build 'emureader-build
  "Command that builds the dynamic module of emureader."
  :type 'symbol)

;; Only under Elpaca: a plain batch Emacs (the tests) must not try to install.
;; The recipe is explicit: Elpaca's cached GNU ELPA menu can predate the
;; rename to emureader, and a package missing from the menu gets a recipe
;; with no repository (error in `elpaca-git--fetch').
(when (fboundp 'elpaca)
  (use-package emureader
    :ensure (:repo "https://codeberg.org/MonadicSheep/emureader.git")
    :defer t))

;;;; Opening

(defun sp-pdf-reader-ready-p ()
  "Non-nil when emureader is installed and can open a document."
  (and (require 'emureader nil t)
       (fboundp sp-pdf-reader-function-open)
       (fboundp sp-pdf-reader-function-goto-page)))

;;;###autoload
(defun sp-pdf-open (file &optional page)
  "Open the PDF FILE in emureader, at PAGE (counted from 1) if given.
Falls back to `find-file' when emureader is not ready."
  (interactive (list (read-file-name "PDF: " nil nil t nil
                                     (lambda (f) (or (file-directory-p f)
                                                     (string-suffix-p ".pdf" f t))))
                     (when current-prefix-arg (read-number "Page: " 1))))
  (let ((file (expand-file-name file)))
    (unless (file-exists-p file) (user-error "No such file: %s" file))
    (cond
     ((sp-pdf-reader-ready-p)
      (funcall sp-pdf-reader-function-open file)
      (when page (funcall sp-pdf-reader-function-goto-page page)))
     (t
      (message "emureader is not ready (install it, then M-x %s); using find-file"
               sp-pdf-reader-function-build)
      (find-file file)))))

;;; Provide

(provide 'sp-pdf-reader)
;;; sp-pdf-reader.el ends here
