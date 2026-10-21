;; -*- lexical-binding: t; -*-
;; sp-vulpea-ext.el

;;; Commentary:

;;;; Recursive loading for the modules
(let ((default-directory (expand-file-name "modules/" sp-library-dir)))
  (normal-top-level-add-to-load-path '("."))
  (normal-top-level-add-subdirs-to-load-path))

;; Integration with other packages

;;; Code:

;; JOURNALING
(use-package vulpea-journal
  :ensure t
  :after vulpea)

;; Other modules for vulpea
   
(use-package vulpea-capf
  :ensure (:host github :repo "neonmei/vulpea-capf")
  :hook (org-mode . vulpea-capf-mode)
)

(setq vulpea-capf-everywhere nil)   ; only complete inside [[...]]
(setq vulpea-capf-in-brackets t)
(setq vulpea-capf-annotate-function t)

;; Create dataview-like tables through the vulpea query system
(require 'sp-vulpea-table)

;; Batch converting properties to plug into vulpea instead

(require 'sp-vulpea-convert-properties)

;; Grouping backlinks based on the property that it's representing

(require 'sp-vulpea-grouped-backlinks)

;;; Making vulpea-split-heading smart (ensure backlinks)
(require 'sp-vulpea-split)

;;; Provide:

(provide 'sp-vulpea-ext)
;; sp-vulpea-ext.el
