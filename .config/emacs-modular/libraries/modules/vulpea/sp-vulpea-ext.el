;;; sp-vulpea-ext.el --- Vulpea extensions loader -*- lexical-binding: t; -*-

;;; Commentary:

;; A hub module for the Vulpea note system. It installs two small Vulpea add-on
;; packages (`vulpea-journal' and `vulpea-capf') and then requires the config's
;; own Vulpea extension modules: property conversion, grouped backlinks and a
;; smarter heading split.  The table modules (sp-collection-query-tables) are not loaded
;; from here; sp-org-ext requires them after the Vulpea modules.

;;; Code:

;;;; Recursive loading for the modules
(let ((default-directory (expand-file-name "modules/" sp-library-dir)))
  (normal-top-level-add-to-load-path '("."))
  (normal-top-level-add-subdirs-to-load-path))

;; Integration with other packages

;; JOURNALING
(use-package vulpea-journal
  :ensure t
  :after vulpea)

;; Other modules for vulpea
   
(use-package vulpea-capf
  :ensure (:host github :repo "neonmei/vulpea-capf")
  :hook (org-mode . vulpea-capf-mode)

  :custom
  (vulpea-capf-everywhere nil)  ; only complete inside [[...]]
  (vulpea-capf-in-brackets t)
  (vulpea-capf-annotate-function t))

;; Batch converting properties to plug into vulpea instead

(require 'sp-vulpea-convert-properties)

;; Grouping backlinks based on the property that it's representing

(require 'sp-vulpea-grouped-backlinks)

;;;; Making vulpea-split-heading smart (ensure backlinks)
(require 'sp-split-leave-parents)

(provide 'sp-vulpea-ext)
;; sp-vulpea-ext.el
