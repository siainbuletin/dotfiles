;;; sp-academic.el --- Academic workflow: bibliography and citations -*- lexical-binding: t; -*-

;;; Commentary:

;; This needs to be defined a little better.

;; This file should deal with bibliography management, as well as provide
;; guidance for where the files should be found. In the future, I want some
;; sort of DEVONthink integration that's genuinely useful.

;; The academic module was created with several submodules in mind.
;;
;; They can be enabled and disabled together for ease of use.
;;
;; Components:
;; - registering/processing BibTeX files
;; - citation framework (citar)
;;    - need to rework the citar integration (both with Denote and now with vulpea)
;;    - literature notes still created with citar-denote
;;    - anything pertaining to ROAM_REFS is done with vulpea-citar
;; - PDF processing and integration
;;    - waiting on emacs-reader (Canvas emacs patch)
;;    - deep linking to PDFs
;;    - integration with DEVONthink
;;    - perhaps semantic search over PDFs
;; - bibliographic search and database
;;    - fetch papers from sci-hub
;;    - integration with annas-archive
;; Citar has been plugged into Denote at first, because it helps in creating literature notes
;; But I would like to have a workflow similar to the BibTeX one that you get with org-roam.
;; This would have to be emulated with vulpea.
;; I need to test out the features provided by citar-vulpea, in this case

;; The sp-academic.el file is created with several submodules that I can refer to independently.
;; One has to create literature notes
;; The other part is just for citations
;; And handling the BibTeX backend
;; there should also be a way to handle PDFs, especially if we're doing deeplinking with DEVONthink,
;; but these details will have to be worked out later on.

;;; Code:

;;;; Requiring sub-libraries

(require 'sp-bibprocess)
(require 'sp-pdfprocess)
(require 'sp-citations)
(require 'sp-litnotes)

;;;; Setting up the proper variables

;;; Looking up academic sources 

(use-package biblio
  :ensure t

  :bind
  (("C-c w b b" . sp-bibtex-biblio-lookup))
)

(use-package biblio-gscholar
  :ensure (biblio-gscholar :host github :repo "seanfarley/biblio-gscholar.el"))

(use-package asoc
    :ensure (:type git :host github :repo "troyp/asoc.el"))

(use-package doct
  :ensure t)

;; Citation key generation

;; The length, separator and title-word counts are set once, further down.
(setq bibtex-autokey-titleword-ignore ;; I took "On" out of this
        '("A" "An" "The" "Eine?" "Der" "Die" "Das" "[^[:upper:]].*" ".*[^[:upper:][:lower:]0-9].*"))

;;; Org-ref
(use-package org-ref
  :ensure t
  :after (ox-pandoc)
)

;;; Forcing org-ref to recognize org-cite citation syntax instead of org-ref blocks
(setq org-ref-insert-cite-function
      (lambda ()
	(org-cite-insert nil)))

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

(setq org-ref-default-bibliography (list (sp-path sp-bibliography-dir "master.bib"))
      org-ref-pdf-directory sp-literature-dir)

;; (setq citar-library-paths (list sp-literature-dir))
;; this has to be a list of directories in order to work

(setq citar-library-file-extensions (list "pdf" "jpg")
      citar-file-additional-files-separator "-")

(setq bibtex-completion-bibliography
      (mapcar (lambda (bib) (sp-path sp-bibliography-dir bib))
              '("master.bib" "thesis.bib" "marx.bib" "hci.bib" "aesthetics.bib"
                "hegel-prezentare.bib" "modernitate.bib"))
        bibtex-completion-library-path (list sp-literature-dir)
        bibtex-completion-notes-path sp-notes-dir
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

;;;; Citation Variables
(defcustom sp-bibliography nil "User bibliography for citation."
  :group 'sia-lambda
  :tag "Lambda-Emacs User Bibliography")
(defcustom sp-bib-notes nil "User citation notes directory."
  :group 'sia-lambda
  :tag "Lambda-Emacs Citation Notes Directory")
(defcustom sp-citar-note nil "Template for use with citar notes."
  :group 'sia-lambda
  :tag "Lambda-Emacs Citar Notes Template")

(provide 'sp-academic)
