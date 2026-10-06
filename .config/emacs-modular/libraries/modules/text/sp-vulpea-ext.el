;; -*- lexical-binding: t; -*-

;; Integration with other packages

(use-package consult-vulpea
  :ensure (:wait t)
  :after vulpea
  :config
  (consult-vulpea-mode 1)
)

;; VULPEA PARA SETUP

(use-package vulpea-para
  :ensure (:host github :repo "d12frosted/vulpea-para"))

;; (vulpea-para-agenda-mode) ;; for some reason it shows up as void

(vulpea-para-setup-defaults)

;; keep a cemetery (or anything) out of the agenda file list
(setq vulpea-para-agenda-files-filter
      (lambda (note)
        (not (vulpea-note-tagged-any-p note "cemetery"))))

;; Getting the custom agenda view for vulpea-para
;; Should this be moved to the org-agenda file, since it's a special command?
(setq org-agenda-custom-commands
      `((" " "Agenda"
         (,vulpea-para-agenda-cmd-refile
          ,vulpea-para-agenda-cmd-today
          ,vulpea-para-agenda-cmd-focus
          ,vulpea-para-agenda-cmd-stuck-projects
          ,vulpea-para-agenda-cmd-waiting
          ,(vulpea-para-agenda-cmd-current-quarter)))))

;; the Area > Project prefix in the agenda
(setq org-agenda-prefix-format
      '((agenda . " %(vulpea-para-agenda-category 36) %?-12t %12s")
        (todo   . " %(vulpea-para-agenda-category 36) ")))

;; Other modules for vulpea
   
(use-package vulpea-capf
  :ensure (:host github :repo "neonmei/vulpea-capf")
  :hook (org-mode . vulpea-capf-mode)
)

(setq vulpea-capf-everywhere nil)   ; only complete inside [[...]]
(setq vulpea-capf-in-brackets t)
(setq vulpea-capf-annotate-function t)

;; Create dataview-like tables through the vulpea query system
(require 'sp-vulpea-dblock)
(require 'sp-vulpea-vui-table)
(require 'sp-vulpea-table-views)

;; Batch converting properties to plug into vulpea instead

(require 'sp-vulpea-convert-properties)

;; Grouping backlinks based on the property that it's representing

(require 'sp-vulpea-grouped-backlinks)