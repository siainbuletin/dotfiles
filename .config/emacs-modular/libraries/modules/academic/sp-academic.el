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

;;;; Citation variables
;; Moved to `sp-globals': `sp-bib-notes' and `sp-citar-note'.
;; That module loads first, so the `use-package' forms below read them even when
;; Elpaca runs those forms while this file is still being loaded.

;;;; Requiring sub-libraries

(require 'sp-bibprocess)
(require 'sp-pdfprocess)
(require 'sp-citations)
(require 'sp-litnotes)
(require 'sp-fetch-academic)

(use-package asoc
    :ensure (:type git :host github :repo "troyp/asoc.el"))

(use-package doct
  :ensure t)

;;;; Org-ref
(use-package org-ref
  :ensure t
  :after (ox-pandoc)
)

;;;; Forcing org-ref to recognize org-cite citation syntax instead of org-ref blocks
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

(setq org-ref-pdf-directory sp-literature-dir)

(setq bibtex-completion-library-path (list sp-literature-dir)
      bibtex-completion-notes-path sp-notes-dir
      bibtex-completion-notes-template-multiple-files "* ${author-or-editor}, ${title}, ${journal}, (${year}) :${=type=}: \n\nSee [[cite:&${=key=}]]\n")

(use-package citar-org-node
  :ensure (citar-org-node :host github :repo "krisbalintona/citar-org-node"))

(use-package binder ;; for stuff that looks like scrivener
  :ensure t)

(provide 'sp-academic)
