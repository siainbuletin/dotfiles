;;; sp-bibprocess.el --- BibTeX files, citation keys and attachment checks -*- lexical-binding: t; -*-

;;; Commentary:

;; This module manages the BibTeX bibliography that the academic modules build
;; on: where the .bib files are, how citation keys are generated, and the
;; commands that audit attachments.

;;; Code:

;;;; Defining variables

(defconst sp-bibtex-file-regexp "\\`[[:alnum:]].*\\.bib\\'"
  "Regexp for the names of the BibTeX files in `sp-bibliography-dir'.")

(defvar sp-bibtex-files
  (when (file-exists-p sp-bibliography-dir)
    (directory-files sp-bibliography-dir t sp-bibtex-file-regexp))
  "List of BibTeX files. Use `sp-bibtex-register' to configure.")

;;;###autoload
(defun sp-bibtex-register ()
  "Register the contents of the `sp-bibliography-dir' with `sp-bibtex-files`.
Use when adding or removing a BibTeX file from or to `sp-bibliography-dir'."
  (interactive)
  (when (file-exists-p sp-bibliography-dir)
    (let ((bib-files (directory-files sp-bibliography-dir t sp-bibtex-file-regexp)))
      (setq sp-bibtex-files bib-files
            org-cite-global-bibliography bib-files
            citar-bibliography bib-files
            org-ref-default-bibliography bib-files
            bibtex-completion-bibliography bib-files
            bibtex-files bib-files)))
  (message "Registered:\n%s" (mapconcat #'identity sp-bibtex-files "\n")))

;;;; Citation keys

(require 'ucs-normalize)

(defun sp-bibtex-ascii-key (key)
  "Return KEY as plain ASCII, or KEY itself when nothing is left."
  (let ((ascii (replace-regexp-in-string
                "[^[:ascii:]]" "" (ucs-normalize-NFKD-string key))))
    (if (string-empty-p ascii) key ascii)))

(use-package bibtex
  :ensure nil
  :demand t
  :custom
  (bibtex-dialect 'biblatex)

  ;; Keys: smith-2017-atten-all
  (bibtex-autokey-names 2)
  (bibtex-autokey-names-stretch 0)
  (bibtex-autokey-name-separator "")
  (bibtex-autokey-name-year-separator "-")
  (bibtex-autokey-year-length 4)
  (bibtex-autokey-year-title-separator "-")
  (bibtex-autokey-titlewords 2)
  (bibtex-autokey-titlewords-stretch 1)
  (bibtex-autokey-titleword-length 5)
  (bibtex-autokey-titleword-separator "-")
  (bibtex-autokey-name-case-convert-function #'downcase)
  (bibtex-autokey-titleword-case-convert-function #'downcase)
  (bibtex-autokey-before-presentation-function #'sp-bibtex-ascii-key)
  (bibtex-autokey-edit-before-use t)
  (bibtex-autokey-titleword-ignore
   '("A" "An" "The" "Is" "the" "a" "On" "on" "Eine?" "Der" "Die" "Das"
     "[^[:upper:]].*" ".*[^[:upper:][:lower:]0-9].*"))

  ;; Cleaning and duplicates
  (bibtex-entry-format
   '(opts-or-alts page-dashes whitespace realign last-comma
                  delimiters unify-case braces))
  (bibtex-search-entry-globally t)

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
  (("C-c w b r" . sp-bibtex-register)
   :map bibtex-mode-map
   ("H-b" . org-ref-bibtex-hydra/body))
)

;; Search for missing BibTeX attachments and filenames
(defun sp--bibtex-extract-attachments ()
  "Extract attachment file names from BibTeX files in `sp-bibliography-dir'."
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
                                      sp-bibliography-dir)
                    attachments))))))
    attachments))

(defun sp--bibtex-extract-files ()
  "List files recursively in `sp-bibliography-dir', excluding `.bib' and `.csl'."
  (seq-remove (lambda (file)
                (or (string-suffix-p ".bib" file)
                    (string-suffix-p ".csl" file)))
              (mapcar 'expand-file-name
                      (directory-files-recursively sp-bibliography-dir ""))))

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
