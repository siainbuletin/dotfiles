;; -*- lexical-binding: t; -*-
;; sp-bibprocess.el

(defcustom sp-bibtex-dir
  (concat (file-name-as-directory (getenv "HOME")) "/bibliography/")
  "Location of BibTeX files and attachments."
  :group 'siapip
  :type 'directory)

(defvar sp-bibtex-files
  (when (file-exists-p sp-bibtex-dir)
    (directory-files sp-bibtex-dir t "^[A-Z|a-z|0-9].+.bib$"))
  "List of BibTeX files. Use `sia-bibtex-register' to configure.")

;;;###autoload
(defun sia-bibtex-register ()
  "Register the contents of the `sp-bibtex-dir' with `sp-bibtex-files`.
Use when adding or removing a BibTeX file from or to `sp-bibtex-dir'."
  (interactive)
  (when (file-exists-p sp-bibtex-dir)
    (let ((bib-files (directory-files sp-bibtex-dir t
				      "^[A-Z|a-z|0-9].+.bib$")))
      (setq sp-bibtex-files bib-files
  	    org-cite-global-bibliography bib-files
	    citar-bibliography bib-files)))
  (message "Registered:\n%s" (mapconcat #'identity sp-bibtex-files "\n")))

(defun sp--bibtex-combined-biblio-lookup ()
  "Combines `biblio-lookup' and `biblio-doi-insert-bibtex'."
  (require 'biblio)
  (let* ((dbs (biblio--named-backends))
         (db-list (append dbs '(("DOI" . biblio-doi-backend))))
         (db-selected (biblio-completing-read-alist
                       "Backend:"
                       db-list)))
    (if (eq db-selected 'biblio-doi-backend)
        (let ((doi (read-string "DOI: ")))
          (biblio-doi-insert-bibtex doi))
      (biblio-lookup db-selected))))

(setq bibtex-autokey-name-separator nil
      bibtex-autokey-name-year-separator nil
      bibtex-autokey-year-length 4
      bibtex-autokey-names 1
      bibtex-autokey-names-stretch 1
      bibtex-autokey-titlewords 0)

(use-package bibtex
  :ensure nil
  :custom
  (bibtex-dialect 'biblatex)
  (bibtex-user-optional-fields
   '(("keywords" "Keywords to describe the entry" "")
     ("file"     "Relative or absolute path to attachments" "" )))
  (bibtex-align-at-equal-sign t)
  :config
  (sia-bibtex-register)
  :bind
  (("C-c w b r" . sia-bibtex-register))
)

(provide 'sp-bibprocess)
;; sp-bibprocess.el ends here