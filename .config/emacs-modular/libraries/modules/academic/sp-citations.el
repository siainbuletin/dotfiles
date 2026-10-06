;; -*- lexical-binding: t; -*-
;; sp-citations.el

(require 'oc-natbib)
;; (require 'oc-csl) -- this is already declared with use-package and all the settings

;;;; Org-Cite
;; built-in package -- set up proper configuration
(use-package oc
  :ensure nil
  :after org
  :config
  ;; (setq org-cite-global-bibliography `(,sp-bibtex-dir)) ;; I don't know if this works with a file or with a directory, unclear from the syntax.
  (setq org-cite-export-processors
        '((beamer csl)
          (latex csl)
          (t csl))))

(setq org-cite-global-bibliography sp-bibtex-files
      org-cite-insert-processor 'citar
      org-cite-follow-processor 'citar
      org-cite-activate-processor 'citar)

;; Use csl
;; needs to have CSL installed on the system
(use-package oc-csl
  :ensure nil
  :defer t  ;; Defer loading until actually needed
  :commands (org-cite-csl-activate
             org-cite-csl-render-bibliography
             org-cite-csl-render-item)
  :init
  ;; Set these variables early so they're available when needed
  (with-eval-after-load 'oc
    (setq org-cite-csl-styles-dir "~/.local/share/csl/styles")
    (setq org-cite-csl-locales-dir "~/.local/share/csl/locales")))

;;;; Citeproc
(use-package citeproc
  :if (and sp-load-extras (locate-library "citeproc"))
  :defer t  ;; Defer loading until oc-csl needs it
  :after oc)

;;;; Citar
(use-package citar
  :if (and sp-load-extras (locate-library "citar"))
  :commands (citar-open-notes
             citar-insert-citation)
  :custom
  
  ;; Use with org citation
  (org-cite-global-bibliography `(,lem-bibliography))
  (citar-bibliography `(,lem-bibliography))
  (org-cite-insert-processor 'citar)
  (org-cite-follow-processor 'citar)
  (org-cite-activate-processor 'citar)
  
  :config
  
  (setq citar-at-point-function 'embark-act) ;; use embark with at-point
  (setq citar-additional-fields '("doi" "url"))   ;; add beref entry for bookends

  (setq citar-templates
        `((main . " ${=key= id:15} ${title:48}")
          (suffix . "${author editor:30}  ${=type=:12}  ${=beref=:12} ${tags keywords:*}")
          (preview . "${author editor} (${year issued date}) ${title}, ${journal journaltitle publisher container-title collection-title}.\n")
          (note . ,lem-citar-note)))
  (when (display-graphic-p)
    ;; nerd-icons has no octicon PDF/text glyph, so those two use
    ;; FontAwesome; link-external maps to the octicon directly.
    (setq citar-symbols
          `((file ,(nerd-icons-faicon  "nf-fa-file_pdf_o"     :face 'error)   . " ")
            (note ,(nerd-icons-faicon  "nf-fa-file_text_o"    :face 'warning) . " ")
            (link ,(nerd-icons-octicon "nf-oct-link_external" :face 'org-link) . " "))))
  ;; edit notes
  (setq citar-notes-paths `(,lem-bib-notes)))

(use-package citar
         :ensure t
         :defer t ; what's the point of defering in this case?
         :custom
         (org-cite-global-bibliography sp-bibtex-files)
         (org-cite-insert-processor 'citar)
         (org-cite-follow-processor 'citar)
         (org-cite-activate-processor 'citar)
         (citar-bibliography sp-bibtex-files)

      (citar-symbol-separator "  ")

         :bind
         (("C-c w b o" . citar-open))
         (:map org-mode-map :package org ("C-c b" . #'org-cite-insert))
         :hook
         (LaTeX-mode . citar-capf-setup)
         (org-mode . citar-capf-setup)
         (markdown-mode . citar-capf-setup))

(setq citar-library-file-extensions nil)

;; Acting on citations (and jumping across the files better)
(use-package citar-embark
  :ensure t
  :after (citar embark)
  :no-require
  :config (citar-embark-mode)
  )

(setq citar-at-point-function 'embark-act)

(defvar sia-citar-library-backup-path "~/Documents/literature/backup")

(provide 'sp-citations)
;; sp-citations.el ends here