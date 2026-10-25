;;; sp-bibprocess.el --- BibTeX files, lookup and attachment checks -*- lexical-binding: t; -*-

;;; Commentary:

;; This module manages the BibTeX bibliography that the academic modules build
;; on.

;;; Code:

;;;; Defining variables

;; Moved to `sp-globals': `sp-bibtex-dir', the folder of the BibTeX files and
;; their attachments.

(defvar sp-bibtex-files
  (when (file-exists-p sp-bibtex-dir)
    (directory-files sp-bibtex-dir t "^[A-Z|a-z|0-9].+.bib$"))
  "List of BibTeX files. Use `sp-bibtex-register' to configure.")

;;;###autoload
(defun sp-bibtex-register ()
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
  (bibtex-aux-opt-alist
   '(("keywords" "Keywords to describe the entry" "")
     ("file" "Relative or absolute path to attachments" "")))
  :config
  (sp-bibtex-register)
  :bind
  (("C-c w b r" . sp-bibtex-register))
)

;;;; Other:

;;;; BIBLIOGRAPHY
(defvar sp-bibtex-files
  (when (file-exists-p sp-bibtex-dir)
    (directory-files sp-bibtex-dir t "^[A-Z|a-z|0-9].+.bib$"))
  "List of BibTeX files. Use `sp-bibtex-register' to configure.")

;;;###autoload
(defun sp-bibtex-register ()
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

;;;###autoload
(defun sp-bibtex-biblio-lookup ()
  "Insert Biblio search results into current buffer or select BibTeX file."
  (interactive)
  (if-let* ((current-mode major-mode)
	   sp-bibtex-files
	   (bibfiles (length sp-bibtex-files))
	   (bibfile (cond ((eq bibfiles 1) (car sp-bibtex-files))
			  ((equal major-mode 'bibtex-mode)
			   (buffer-file-name))
			  (t (completing-read
			      "Select BibTeX file:" sp-bibtex-files)))))
      (progn (find-file bibfile)
	     (goto-char (point-max))
	     (sp--bibtex-combined-biblio-lookup)
	     (save-buffer))
    (message "No BibTeX file(s) defined.")))

;; Search for missing BibTeX attachments and filenames
(defun sp--bibtex-extract-attachments ()
  "Extract attachment file names from BibTeX files in `sp-bibtex-dir'."
  (sp-bibtex-register)
  (let ((attachments '()))
    (dolist (bibtex-file sp-bibtex-files)
      (with-temp-buffer
        (insert-file-contents bibtex-file)
        (goto-char (point-min))
        (while (re-search-forward "file.*=.*{\\([^}]+\\)}" nil t)
          (let ((file-paths (split-string (match-string 1)
                                          "[[:space:]]*;[[:space:]]*")))
            (dolist (file-path file-paths)
              (push (expand-file-name (string-trim file-path)
                                      sp-bibtex-dir)
                    attachments))))))
    attachments))

(defun sp--bibtex-extract-files ()
  "List files recursively in `sp-bibtex-dir', excluding `.bib' and `.csl'."
  (seq-remove (lambda (file)
                (or (string-suffix-p ".bib" file)
                    (string-suffix-p ".csl" file)))
              (mapcar 'expand-file-name
                      (directory-files-recursively sp-bibtex-dir ""))))

;;;###autoload
(defun sp-bibtex-missing-files ()
  "List BibTeX attachments not listed in a BibTeX file entry."
  (interactive)
  (let* ((files (sp--bibtex-extract-files))
         (attachments (sp--bibtex-extract-attachments))
         (missing (cl-remove-if
                   (lambda (f) (member f attachments)) files)))
    (message "%s files not registered in bibliography" (length missing))
    (dolist (file missing)
      (message file))))

;;;###autoload
(defun sp-bibtex-missing-attachments ()
  "List BibTeX file entries with missing attachment(s)."
  (interactive)
  (let* ((files (sp--bibtex-extract-files))
         (attachments (sp--bibtex-extract-attachments))
         (missing (cl-remove-if
                   (lambda (f) (member f files)) attachments)))
    (message "%s BibTeX files without matching attachment." (length missing))
    (dolist (file missing)
      (message file))))

(provide 'sp-bibprocess)
;; sp-bibprocess.el ends here
