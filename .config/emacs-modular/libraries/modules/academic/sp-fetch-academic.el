;;; sp-fetch-academic.el --- Fetch papers from the web and import them -*- lexical-binding: t; -*-

;;; Commentary:

;; Brings references and papers in from the web: `biblio' and Google Scholar
;; searches, DOI look-up through `org-ref', and a command that downloads a PDF
;; into the literature folder and attaches it to its BibTeX entry. Citation keys
;; come from the `bibtex-autokey' scheme set in `sp-bibprocess'.
;;
;; `consult-omni' (set up in `sp-browsing') searches OpenAlex, PubMed and Scopus
;; and hands the chosen result to the DOI or download command.

;;; Code:

(require 'sp-bibprocess)

;;;; Options

(defcustom sp-fetch-academic-download-dir sp-literature-dir
  "Folder where `sp-fetch-academic-download' saves PDFs."
  :group 'spcustom
  :type 'directory)

;;;; Searching with biblio

(use-package biblio
  :ensure t

  :custom
  (biblio-bibtex-use-autokey t))

(use-package biblio-gscholar
  :ensure (biblio-gscholar :host github :repo "seanfarley/biblio-gscholar.el"))

(defun sp--fetch-academic-bibfile ()
  "Return the BibTeX file a new entry should go into."
  (cond ((null sp-bibtex-files)
         (user-error "No BibTeX file(s) defined"))
        ((null (cdr sp-bibtex-files)) (car sp-bibtex-files))
        ((derived-mode-p 'bibtex-mode) (buffer-file-name))
        (t (completing-read "Select BibTeX file: " sp-bibtex-files nil t))))

(defun sp--fetch-academic-combined-lookup ()
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
(defun sp-fetch-academic-biblio-lookup ()
  "Insert Biblio search results into a BibTeX file."
  (interactive)
  (find-file (sp--fetch-academic-bibfile))
  (goto-char (point-max))
  (sp--fetch-academic-combined-lookup)
  (save-buffer))

;;;; DOI look-up

(defun sp--fetch-academic-clean-doi (doi)
  "Return DOI without whitespace or a resolver prefix."
  (replace-regexp-in-string "\\`\\(?:https?://\\(?:dx\\.\\)?doi\\.org/\\|doi:\\)" ""
                            (string-trim doi)))

;;;###autoload
(defun sp-fetch-academic-doi (doi)
  "Add the BibTeX entry for DOI to a bibliography and offer to fetch the PDF."
  (interactive
   (list (read-string "DOI: " (thing-at-point 'url t))))
  (require 'doi-utils)
  (let ((bibfile (sp--fetch-academic-bibfile)))
    (doi-utils-add-bibtex-entry-from-doi (sp--fetch-academic-clean-doi doi) bibfile)
    (when (y-or-n-p "Try to fetch the PDF too? ")
      (with-current-buffer (find-file-noselect bibfile)
        (goto-char (point-max))
        (bibtex-beginning-of-entry)
        (doi-utils-get-bibtex-entry-pdf)))))

;;;; Downloading files

(defun sp--fetch-academic-attach (file)
  "Add FILE to the `file' field of the BibTeX entry at point."
  (let ((relative (file-relative-name file sp-bibliography-dir)))
    (save-excursion
      (bibtex-beginning-of-entry)
      (let ((bounds (bibtex-search-forward-field "file" t)))
        (if bounds
            (let ((old (bibtex-text-in-field-bounds bounds t))
                  (start (bibtex-start-of-text-in-field bounds)))
              (delete-region start (bibtex-end-of-text-in-field bounds))
              (goto-char start)
              (insert "{" old "; " relative "}"))
          (bibtex-end-of-entry)
          (backward-char)
          (skip-chars-backward " \t\n")
          (unless (eq (char-before) ?,) (insert ","))
          (insert "\n  file = {" relative "}")
          (when bibtex-comma-after-last-field (insert ",")))))))

(defun sp--fetch-academic-pdf-p (file)
  "Return non-nil when FILE starts with the PDF magic number."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file nil 0 4)
    (equal (buffer-string) "%PDF")))

;;;###autoload
(defun sp-fetch-academic-download (url)
  "Download the PDF at URL into `sp-fetch-academic-download-dir'.
Inside a BibTeX entry, name the file after its key and attach it."
  (interactive
   (list (read-string "PDF URL: " (thing-at-point 'url t))))
  (let* ((in-entry (and (derived-mode-p 'bibtex-mode)
                        (ignore-errors
                          (save-excursion (bibtex-beginning-of-entry)
                                          (bibtex-key-in-head)))))
         (key (or in-entry
                  (read-string "Citation key (empty: name from the URL): ")))
         (base (if (string-empty-p key)
                   (file-name-base (url-filename (url-generic-parse-url url)))
                 key))
         (file (expand-file-name (concat base ".pdf")
                                 sp-fetch-academic-download-dir)))
    (when (file-exists-p file)
      (user-error "%s already exists" file))
    (make-directory sp-fetch-academic-download-dir t)
    (url-copy-file url file)
    (unless (sp--fetch-academic-pdf-p file)
      (delete-file file)
      (user-error "%s is not a PDF" url))
    (when in-entry
      (sp--fetch-academic-attach file))
    (message "Saved %s" file)
    file))

;;;; Searching with consult-omni

;;;###autoload
(defun sp-fetch-academic-omni ()
  "Search scholarly sources with consult-omni and add the chosen paper.
A result with a DOI goes to `sp-fetch-academic-doi'; one with only the URL of
a PDF goes to `sp-fetch-academic-download'."
  (interactive)
  (unless (require 'sp-browsing nil t)
    (user-error "The sp-browsing module (consult-omni) did not load"))
  (let* ((cand (consult-omni-scholar nil nil nil t))
         (doi (and (stringp cand) (get-text-property 0 :doi cand)))
         (pdf (and (stringp cand) (get-text-property 0 :pdf-url cand))))
    (cond ((and (stringp doi) (not (string-empty-p doi)))
           (sp-fetch-academic-doi doi))
          ((and (stringp pdf) (not (string-empty-p pdf)))
           (sp-fetch-academic-download pdf))
          (t (user-error "That result has neither a DOI nor a PDF address")))))

;;;; Keys

(global-set-key (kbd "C-c w b b") #'sp-fetch-academic-biblio-lookup)
(global-set-key (kbd "C-c w b i") #'sp-fetch-academic-doi)
(global-set-key (kbd "C-c w b u") #'sp-fetch-academic-download)
(global-set-key (kbd "C-c w b s") #'sp-fetch-academic-omni)

(use-package request :ensure t)
(use-package counsel :ensure t)

(use-package litdb
  :ensure (litdb :type git :host github :repo "jkitchin/litdb" :branch "main" :files "litdb.el")
  :after (hydra request counsel org-ref))

(provide 'sp-fetch-academic)
;;; sp-fetch-academic.el ends here
