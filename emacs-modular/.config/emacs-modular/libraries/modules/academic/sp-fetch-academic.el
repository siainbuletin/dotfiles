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

(require 'seq)
(require 'sp-bibprocess)

;;;; Options

(defcustom sp-fetch-academic-download-dir sp-literature-dir
  "Folder where `sp-fetch-academic-download' saves PDFs."
  :group 'spcustom
  :type 'directory)

(defcustom sp-fetch-academic-devonthink t
  "Non-nil: `sp-fetch-academic-file' also adds the PDF to DEVONthink (macOS)."
  :group 'spcustom
  :type 'boolean)

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

(defun sp--fetch-academic-follow-doi (key bibfile)
  "Run the follow-up for the PDF `org-ref' saved for KEY, if there is one."
  (let ((pdf (expand-file-name (concat key ".pdf")
                               (if (boundp 'org-ref-pdf-directory)
                                   org-ref-pdf-directory sp-literature-dir))))
    (when (file-exists-p pdf)
      (sp-fetch-academic-file key pdf bibfile))))

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
        (let ((key (bibtex-key-in-head)))
          (doi-utils-get-bibtex-entry-pdf)
          (sp--fetch-academic-follow-doi key bibfile))))))

;;;; Downloading files

(defun sp-fetch-academic-file-field-value (file &optional bibfile)
  "The text for FILE in a `file' field of an entry of BIBFILE.
Relative to `sp-literature-dir' when FILE is inside it, else to the folder of
BIBFILE (default `sp-bibliography-dir')."
  (let ((file (expand-file-name file))
        (library (file-name-as-directory (expand-file-name sp-literature-dir))))
    (if (string-prefix-p library file)
        (file-relative-name file library)
      (file-relative-name file (if bibfile
                                   (file-name-directory (expand-file-name bibfile))
                                 sp-bibliography-dir)))))

(defun sp--fetch-academic-attach (file &optional bibfile)
  "Add FILE to the `file' field of the BibTeX entry at point; non-nil when written.
BIBFILE is the .bib file of the entry, for a path outside `sp-literature-dir'."
  (let ((relative (sp-fetch-academic-file-field-value file bibfile)))
    (save-excursion
      (bibtex-beginning-of-entry)
      (let* ((bounds (bibtex-search-forward-field "file" t))
             (old (and bounds (bibtex-text-in-field-bounds bounds t))))
        (cond
         ((and old (member relative (mapcar #'string-trim (split-string old ";" t))))
          nil)
         (bounds
          (let ((start (bibtex-start-of-text-in-field bounds)))
            (delete-region start (bibtex-end-of-text-in-field bounds))
            (goto-char start)
            (insert "{" (if (string-empty-p (string-trim old)) "" (concat old "; ")) relative "}")
            t))
         (t
          (bibtex-end-of-entry)
          (backward-char)
          (skip-chars-backward " \t\n")
          (unless (eq (char-before) ?,) (insert ","))
          (insert "\n  file = {" relative "}")
          (when bibtex-comma-after-last-field (insert ","))
          t))))))

(defun sp--fetch-academic-pdf-p (file)
  "Return non-nil when FILE starts with the PDF magic number."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file nil 0 4)
    (equal (buffer-string) "%PDF")))

;;;; One follow-up for every PDF

(declare-function sp-reading-ensure-file "sp-reading")
(declare-function sp-devonthink-bibsync-keys "sp-devonthink-bibsync")

(defun sp-fetch-academic-key-bibfile (key)
  "The file of `sp-bibtex-files' that has an entry KEY, or nil."
  (let ((re (format "^[ \t]*@[A-Za-z]+[ \t]*{[ \t]*%s[ \t]*," (regexp-quote key))))
    (seq-find (lambda (f)
                (and (file-readable-p f)
                     (with-temp-buffer
                       (insert-file-contents f)
                       (re-search-forward re nil t))))
              (bound-and-true-p sp-bibtex-files))))

(defun sp--fetch-academic-dt-p ()
  "Non-nil when the DEVONthink step can run."
  (and sp-fetch-academic-devonthink (eq system-type 'darwin) (executable-find "osascript")))

(defun sp--fetch-academic-place (key pdf)
  "Move PDF to KEY.pdf in `sp-literature-dir' unless it is there; return the new path."
  (let ((dest (expand-file-name (concat key ".pdf") sp-literature-dir)))
    (cond ((and (file-exists-p dest) (file-exists-p pdf)
                (equal (file-truename dest) (file-truename pdf)))
           dest)
          ((file-exists-p dest) (user-error "%s already exists" dest))
          ((string-prefix-p (file-name-as-directory (expand-file-name sp-literature-dir))
                            (expand-file-name pdf))
           (expand-file-name pdf))
          (t (make-directory sp-literature-dir t)
             (rename-file pdf dest)
             dest))))

(defun sp--fetch-academic-devonthink (key file)
  "Add FILE to DEVONthink as KEY.pdf if it is not there, then copy the BibTeX data.
Return the status of `sp-reading-ensure-file', or nil when it did not run."
  (when (sp--fetch-academic-dt-p)
    (condition-case err
        (progn
          (require 'sp-reading)
          (let ((status (cdr (sp-reading-ensure-file key file))))
            (when (require 'sp-devonthink-bibsync nil t)
              (sp-devonthink-bibsync-keys (list key)))
            status))
      (error (message "Filed, but DEVONthink was not updated: %s" (error-message-string err))
             nil))))

;;;###autoload
(defun sp-fetch-academic-file (key pdf &optional bibfile)
  "Attach PDF to the entry KEY and add it to DEVONthink.
The entry is in BIBFILE, default the one of `sp-bibtex-files' that has KEY.
Return a plist (:file :bibfile :attached :dt)."
  (let* ((bibfile (or bibfile (sp-fetch-academic-key-bibfile key)
                      (user-error "No entry %s in the registered .bib files" key)))
         (file (sp--fetch-academic-place key pdf))
         (attached
          (with-current-buffer (find-file-noselect bibfile)
            (save-excursion
              (goto-char (point-min))
              (unless (bibtex-find-entry key) (user-error "No entry %s in %s" key bibfile))
              (prog1 (sp--fetch-academic-attach file bibfile)
                (save-buffer))))))
    (list :file file :bibfile bibfile :attached attached
          :dt (sp--fetch-academic-devonthink key file))))

;;;###autoload
(defun sp-fetch-academic-attach-pdf (pdf &optional key)
  "Attach the PDF on disk to an entry and add it to DEVONthink.
In a BibTeX entry KEY is its key; otherwise it is asked."
  (interactive
   (list (read-file-name "PDF: " sp-literature-dir nil t)))
  (let* ((key (or key
                  (and (derived-mode-p 'bibtex-mode)
                       (ignore-errors (save-excursion (bibtex-beginning-of-entry)
                                                      (bibtex-key-in-head))))
                  (read-string "Citation key: ")))
         (result (sp-fetch-academic-file key pdf)))
    (message "%s: %s%s" key (abbreviate-file-name (plist-get result :file))
             (if (plist-get result :dt) (format " (DEVONthink: %s)" (plist-get result :dt)) ""))
    result))

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
      (sp-fetch-academic-file in-entry file (buffer-file-name)))
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

;; Bound in `sp-keys' (C-; B b, i, u, s, f); nothing to bind here.

(use-package request :ensure t)
(use-package counsel :ensure t)

(use-package litdb
  :ensure (litdb :type git :host github :repo "jkitchin/litdb" :branch "main" :files "litdb.el")
  :after (hydra request counsel org-ref))

(provide 'sp-fetch-academic)
;;; sp-fetch-academic.el ends here
