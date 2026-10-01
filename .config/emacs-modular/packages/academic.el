;; -*- lexical-binding: t; -*-

(defgroup ews ()
  "Emacs Writing Studio."
  :group 'files
  :link '(url-link :tag "Homepage" "https://lucidmanager.org/tags/emacs/"))

(defcustom sia-bibtex-directory
  (concat (file-name-as-directory (getenv "HOME")) "/bibliography/")
  "Location of BibTeX files and attachments."
  :group 'ews
  :type 'directory)

(defcustom sia-hunspell-dictionaries "en_US"
  "Comma-separated list of Hunspell dictionaries."
  :group 'ews
  :type 'list)

;;; BIBLIOGRAPHY
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

(use-package biblio
  :ensure t
  :bind
  (("C-c w b b" . sia-bibtex-biblio-lookup)))

(use-package biblio-gscholar
  :ensure (biblio-gscholar :host github :repo "seanfarley/biblio-gscholar.el"))

(use-package asoc
    :ensure (:type git :host github :repo "troyp/asoc.el"))

(use-package doct
  :ensure t)



(defun yant/elfeed-capture-entry ()
  "Capture selected entries into inbox."
  (interactive)
  (elfeed-search-tag-all 'opened)
  (previous-logical-line)
  (let ((entries (elfeed-search-selected)))
    (cl-loop for entry in entries
             do (elfeed-untag entry 'unread)
             when (elfeed-entry-link entry)
             do (flet ((raise-frame nil nil))
                  (org-protocol-capture (list :template "B"
                                              :url it
                                              :title (format "%s: %s"
                                                             (elfeed-feed-title (elfeed-entry-feed entry))
                                                             (elfeed-entry-title entry))
                                              :elfeed-data entry))))
    (mapc #'elfeed-search-update-entry entries)
    (unless (use-region-p) (forward-line))))

(defvar do.refs/db-dirs nil
  "A list of paths to directories containing all my bibtex databases")

(defvar do.refs/pdf-dir nil
  "The path to the directory containing the PDF files. The file
  for the entry with key <key> is stored as <key>.pdf.")

(defvar do.refs/notes-dir nil
  "The path to the directory containing my notes for the
  references. The note for the item with key <key> is stored in
  this folder as <key>.org")

(defvar do.refs/pdf-download-dir nil
  "The path to the temporary directory to which we download PDF
  files.")

(defvar do.refs/file-assoc `(("pdf" . "open")
                           ("docx" . "open")
                           ("doc" . "open")
                           ("pptx" . "open")
                           ("ppt" . "open"))
  "The executables used to open related files from the reference database.")

(defun do.refs/get-db-file-list ()
  "Get the list of all the bib files containing my bib database."
  (mapcan (lambda (dir) (directory-files dir t "\\.bib\\'"))
          do.refs/db-dirs))

(defun do.refs/update-db-file-list ()
  "Update the list of bib files."
  (interactive)
  (let ((db-list (do.refs/get-db-file-list)))
    (setq reftex-default-bibliography db-list)
    (setq bibtex-completion-bibliography db-list)
    (setq ebib-preload-bib-files db-list)))

(setq bibtex-autokey-year-length 4)
  (setq bibtex-autokey-titleword-separator "-")
  (setq bibtex-autokey-name-year-separator "-")
  (setq bibtex-autokey-year-title-separator "-")
  (setq bibtex-autokey-titleword-length 8)
  (setq bibtex-autokey-titlewords 3)
  (setq bibtex-autokey-titleword-ignore ;; I took "On" out of this
        '("A" "An" "The" "Eine?" "Der" "Die" "Das" "[^[:upper:]].*" ".*[^[:upper:][:lower:]0-9].*"))

(defun do.refs/ebib-import-from-clipboard ()
    "Attempt to import the contents in the kill ring/clipboard into `ebib'."
    (interactive)
    (with-temp-buffer
      (yank)
      (ebib-import)
      (call-interactively #'ebib)))

(defun do.refs/ebib-add-newest-from-downloads (&optional file-extension)
    "Add the most recent file from `do.refs/pdf-download-dir' to the ebib entry at point."
    (interactive)
    ;; pull out the most recent file from ~/Downloads with the .pdf extension.
    (let ((newest-file (let ((dir-files (directory-files-and-attributes do.refs/pdf-download-dir)))
                         (caar (sort
                                (if (not file-extension)
                                    ;; the newest file from the download directory
                                    (mapcan (lambda (x)
                                              (let ((file-name (concat (file-name-as-directory do.refs/pdf-download-dir) (car x))))
                                                (when (file-regular-p file-name) (cons x nil))))
                                            dir-files)
                                  ;; all files with a certain extension
                                  (mapcan (lambda (x) (when (string-equal (file-name-extension (nth 0 x)) file-extension) (cons x nil)))
                                          dir-files))
                                ;; sort by date
                                (lambda (x y) (not (time-less-p (nth 6 x) (nth 6 y)))))))))
      (if newest-file
          ;; https://nullprogram.com/blog/2017/10/27/
          ;; need to override `read-file-name' because ebib normally prompts us for the file to import
          (let ((fpath (concat (file-name-as-directory do.refs/pdf-download-dir) newest-file))
                (bibkey (ebib--get-key-at-point)))
            (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) fpath)))
              (let ((current-prefix-arg '(4))) ;; C-u (to keep from removing original file)
                (call-interactively #'ebib-import-file)))
            (message "[Ebib] [Dennis] Imported %s for %s" fpath bibkey))
        (message "[Ebib] [Dennis] No files from %s imported." do.refs/pdf-download-dir))))

(use-package citar
         :ensure t
         :defer t ; what's the point of defering in this case?
         :custom
         (org-cite-global-bibliography sia-bibtex-files)
         (org-cite-insert-processor 'citar)
         (org-cite-follow-processor 'citar)
         (org-cite-activate-processor 'citar)
         (citar-bibliography sia-bibtex-files)

         (citar-templates
'((main . "${author editor:30}   ${date year issued:4}    ${title:110}")
  (suffix . "     ${=type=:20}    ${tags keywords keywords:*}")
  (preview . "${author editor} (${year issued date}) ${title}, ${journal journaltitle publisher container-title collection-title}.\n")
  (note . "#+title: Notes on ${author editor}, ${title}") ; For new notes
  ))
;;      (citar-symbols
;;       `((file ,(all-the-icons-faicon "file-o" :face 'all-the-icons-green :v-adjust -0.1) .
;;               ,(all-the-icons-faicon "file-o" :face 'kb/citar-icon-dim :v-adjust -0.1) )
;;         (note ,(all-the-icons-material "speaker_notes" :face 'all-the-icons-blue :v-adjust -0.3) .
;;               ,(all-the-icons-material "speaker_notes" :face 'kb/citar-icon-dim :v-adjust -0.3))
;;         (link ,(all-the-icons-octicon "link" :face 'all-the-icons-orange :v-adjust 0.01) .
;;               ,(all-the-icons-octicon "link" :face 'kb/citar-icon-dim :v-adjust 0.01))))
      (citar-symbol-separator "  ")

         :bind
         (("C-c w b o" . citar-open))
         (:map org-mode-map :package org ("C-c b" . #'org-cite-insert))
         :hook
         (LaTeX-mode . citar-capf-setup)
         (org-mode . citar-capf-setup)
         (markdown-mode . citar-capf-setup))

(setq citar-library-file-extensions nil)

(use-package citar-embark
  :ensure t
  :after (citar embark)
  :no-require
  :config (citar-embark-mode)
  )

(setq citar-at-point-function 'embark-act)



(use-package citar-denote
  :ensure (:wait t)
  :custom
  (citar-open-always-create-notes t)
  :init
  (citar-denote-mode)
  :bind
  (("C-c w b c" . citar-create-note)
   ("C-c w b n" . citar-denote-open-note)
   ("C-c w b x" . citar-denote-nocite)
   :map org-mode-map
   ("C-c w b k" . citar-denote-add-citekey)
   ("C-c w b K" . citar-denote-remove-citekey)
   ("C-c w b d" . citar-denote-dwim)
   ("C-c w b e" . citar-denote-open-reference-entry)))

(setq citar-denote-title-format 'author-year-title)

(setq citar-denote-title-format-authors '2)

(setq citar-denote-keyword "litnote")

(setq citar-denote-subdir "litnotes")

(setq denote-templates
      '((report . "* Some heading\n\n* Another heading")
      (biblio . ,(concat "Creator: %^{author-or-editor}"
                         "\n\n"
                         "* Basics"
                         "\n\n" ; this will add a new line
                         "* Related bibliography"
                         "insert an org dynamic block here"))))

(defvar sia-citar-library-backup-path "~/Documents/literature/backup")

(defun sia-citar-update-pdf-metadata (citekey)
  (interactive (list (citar-select-ref)))
  (citar--check-configuration 'citar-library-paths)
  (unless citar-library-paths
    (user-error "Make sure `citar-library-paths' is non-nil"))
  (let* ((files (gethash cite-key (citar-get-files cite-key))))
    (unless files
      (user-error (format "There are no PDF files associated with %s" citekey)))
    (let ((file (or (unless (cdr files) (car files)) (completing-read "Please select a PDF file: " files)))
          (title (citar-get-value 'title citekey))
          (author (cond ((citar-get-value 'author citekey)
                         (citar-get-value 'author citekey))
                        ((citar-get-value 'editor citekey)
                         (concat (citar-get-value 'editor citekey) " (ed.)")))))
      (progn
        (copy-file file sia-citar-library-backup-path 1)
        (call-process-shell-command
         (concat "exiftool -overwrite_original_in_place -Title='" title "' -Author='" author "' " file))))))

(require 'oc-natbib)
(require 'oc-csl)

(setq org-cite-global-bibliography sia-bibtex-files
      org-cite-insert-processor 'citar
      org-cite-follow-processor 'citar
      org-cite-activate-processor 'citar)

(use-package org-ref
  :ensure t
  :after (ox-pandoc)
)

(defun org-ref-make-org-link-cite-key-visible (&rest _)
  "Make the org-ref cite link visible in descriptive links."

  (save-match-data
    (let ((s (match-string 1))
      (beg (match-beginning 0))
      (end (match-end 0))
      (cite-re (format "^\\(%s:\\)"
               (regexp-opt (-sort
                    (lambda (a b)
                      (> (length a) (length b)))
                    org-ref-cite-types))))
      cite-type)

      (when (and s (string-match cite-re s))
    (setq cite-type (match-string 1 s))
    (remove-text-properties beg end
                '(invisible))
    (add-text-properties
     beg end
     `(face (:foreground ,org-ref-cite-color)))))))

(advice-add 'org-activate-bracket-links :after #'org-ref-make-org-link-cite-key-visible)

(use-package helm-bibtex
  :ensure (:wait t))

(setq org-ref-default-bibliography '("~/bibliography/master.bib")
      org-ref-pdf-directory "~/Documents/literature/")

;; (setq citar-library-paths "~/Documents/literature")
;; this has to be a list of directories in order to work

(setq citar-library-file-extensions (list "pdf" "jpg")
      citar-file-additional-files-separator "-")

(setq bibtex-completion-bibliography
      '("~/bibliography/master.bib"
        "~/bibliography/thesis.bib"
        "~/bibliography/marx.bib"
        "~/bibliography/hci.bib"
        "~/bibliography/aesthetics.bib"
        "~/bibliography/hegel-prezentare.bib"
        "~/bibliography/modernitate.bib")
        bibtex-completion-library-path '("~/Documents/literature/")
        bibtex-completion-notes-path "~/notes/"
        bibtex-completion-notes-template-multiple-files "* ${author-or-editor}, ${title}, ${journal}, (${year}) :${=type=}: \n\nSee [[cite:&${=key=}]]\n")

;; Automatically generating BibTeX keys
(require 'bibtex)

(setq bibtex-autokey-year-length 4
      bibtex-autokey-name-year-separator "-"
      bibtex-autokey-year-title-separator "-"
      bibtex-autokey-titleword-separator "-"
      bibtex-autokey-titlewords 2
      bibtex-autokey-titlewords-stretch 1
      bibtex-autokey-titleword-length 5)

(define-key bibtex-mode-map (kbd "H-b") 'org-ref-bibtex-hydra/body)

(use-package citar-org-node
  :vc ( :url "https://github.com/krisbalintona/citar-org-node.git"
        :rev :newest))

(use-package binder ;; for stuff that looks like scrivener
  :ensure t)