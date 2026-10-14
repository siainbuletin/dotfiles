;;; -*- lexical-binding: t -*-

;; NOTE: some org-extensions are set in other setup files:
;; - org citations setup is in setup-citation

;;;; EXTENSION FILES
(require 'sp-org-appearance)
(require 'sp-org-capture)
(require 'sp-org-babel)
(require 'sp-org-agenda)
(require 'sp-org-images)

;;;;;; ID-based workflows
(require 'sp-org-node-mem)

;;;;;; Vulpea
(require 'sp-vulpea-base)
(require 'sp-vulpea-ui)
(require 'sp-vulpea-para)
(require 'sp-vulpea-schemas)
(require 'sp-vulpea-ext) ;; these are other vulpea extension files that I didn't include elsewher

;;;;;; Other extensions

;;;; Org Contrib
(use-package org-contrib
  :when (and sp-load-extras (locate-library "org-contrib"))
  :after org
  :config
  ;; ignore export of headlines marked with :ignore: tag
  (require 'ox-extra)
  (ox-extras-activate '(ignore-headlines)))

;;; Org Autolist (Smart Lists)
;; Better list behavior
;; this package should be researched a little bit more
(use-package org-autolist
  :if (and sp-load-extras (locate-library "org-autolist"))
  :hook (org-mode . org-autolist-mode))

(use-package org-journal
  :defer t
  :bind
  (("C-M-S-j" . (lambda () (interactive) (org-journal-new-entry nil nil t)))
   ("C-M-S-i" . (lambda () (interactive) (org-journal-new-entry nil))))
  :init
  (setq org-journal-dir "~/org/journal"
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

;;; org-context
;; Allows saving the context of an Org-mode entry, such as when refiling, 
;; so that entries can be restored to their original location based on that context.
(use-package org-context
  :after org
  :demand t

  :bind (:map
         org-mode-map
         ("C-c C-x R" . org-context-undo)
         ("C-c C-x W" . org-context-show-olpath))

  :config
  (org-context-install)
)

;;; Provide:

(provide 'sp-org-ext)
;; sp-org-ext.el ends here.