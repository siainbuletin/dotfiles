;; -*- lexical-binding: t; -*-
;; sia-set-bibprocess.el

(defcustom sia-bibtex-directory
  (concat (file-name-as-directory (getenv "HOME")) "/bibliography/")
  "Location of BibTeX files and attachments."
  :group 'siapip
  :type 'directory)

(defvar sia-bibtex-files
  (when (file-exists-p sia-bibtex-directory)
    (directory-files sia-bibtex-directory t "^[A-Z|a-z|0-9].+.bib$"))
  "List of BibTeX files. Use `sia-bibtex-register' to configure.")

;;;###autoload
(defun sia-bibtex-register ()
  "Register the contents of the `sia-bibtex-directory' with `sia-bibtex-files`.
Use when adding or removing a BibTeX file from or to `sia-bibtex-directory'."
  (interactive)
  (when (file-exists-p sia-bibtex-directory)
    (let ((bib-files (directory-files sia-bibtex-directory t
				      "^[A-Z|a-z|0-9].+.bib$")))
      (setq sia-bibtex-files bib-files
  	    org-cite-global-bibliography bib-files
	    citar-bibliography bib-files)))
  (message "Registered:\n%s" (mapconcat #'identity sia-bibtex-files "\n")))

(defun sia--bibtex-combined-biblio-lookup ()
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

(provide 'sia-set-bibprocess)
;; sia-set-bibprocess.el ends here