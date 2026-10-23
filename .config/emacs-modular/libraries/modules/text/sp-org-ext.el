;;; sp-org-ext.el --- Org extensions and sub-module loader -*- lexical-binding: t; -*-

;;; Commentary:

;; NOTE: some org-extensions are set in other setup files:
;; - org citations setup is in setup-citation

;;; Code:

;;;; EXTENSION FILES
(require 'sp-org-appearance)
(require 'sp-org-babel)
(require 'sp-org-agenda)
(require 'sp-org-images)

;;;;; ID-based workflows
(require 'sp-org-node-mem)

;;;;; Vulpea
(require 'sp-vulpea-base)
(require 'sp-vulpea-ui)
(require 'sp-vulpea-para)
(require 'sp-vulpea-schemas)
(require 'sp-vulpea-ext)
(require 'sp-collection-query-tables) ;; my own table modules

;;;;; Other extensions

;;;; Org Contrib
(use-package org-contrib
  :ensure t
  :after org
  :config
  ;; ignore export of headlines marked with :ignore: tag
  (require 'ox-extra)
  (ox-extras-activate '(ignore-headlines)))

;;;; Org Autolist (Smart Lists)
;; Better list behavior
;; this package should be researched a little bit more
(use-package org-autolist
  :ensure t
  :hook (org-mode . org-autolist-mode))

(use-package org-journal
  :ensure t
  :defer t
  :bind
  (("C-M-S-j" . (lambda () (interactive) (org-journal-new-entry nil nil t)))
   ("C-M-S-i" . (lambda () (interactive) (org-journal-new-entry nil))))
  :init
  (setq org-journal-dir (sp-path sp-org-dir "journal")
        org-journal-date-format "%Y-%m-%d"
        org-journal-enable-agenda-integration t
        org-journal-carryover-items "TODO={TODO\\|WAITING\\|DOING}"))

(use-package org-ranker
  :ensure (org-ranker :type git
                    :host github
                    :repo "CSJ7701/org-ranker"))

;; (add-to-list 'load-path "~/.config/emacs-include/cloned-modules/org-dataview")
;; (require 'org-dataview)

(use-package org-special-block-extras
  :ensure t)

;;;; org-context
;; Allows saving the context of an Org-mode entry, such as when refiling, 
;; so that entries can be restored to their original location based on that context.
(require 'org-context)

;;;; Another org context library
(require 'org-context-agen)

(provide 'sp-org-ext)
;; sp-org-ext.el ends here.
