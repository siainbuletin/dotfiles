;;; sp-vulpea.el --- Vulpea: the catch-all module -*- lexical-binding: t; -*-

;;; Commentary:

;; Loads everything about Vulpea except the table modules (sp-vulpea-table),
;; which are a separate custom module: the database and vui (sp-vulpea-base),
;; the sidebar (sp-vulpea-ui), the PARA agenda wiring (sp-vulpea-para), the
;; note schemas (sp-vulpea-schemas) and the extensions (sp-vulpea-ext).

;;; Code:

(require 'sp-vulpea-base)
(require 'sp-vulpea-ui)
(require 'sp-vulpea-para)
(require 'sp-vulpea-schemas)
(require 'sp-vulpea-ext)

(provide 'sp-vulpea)
;;; sp-vulpea.el ends here
