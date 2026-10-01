;; -*- lexical-binding: t; -*-

(use-package org-mem
  :ensure (:wait t)
  :defer
  :config
  ;; At least one of these two is needed
  (setq org-mem-do-sync-with-org-id t)
  (setq org-mem-watch-dirs
        (list "~/notes/"))
  (org-mem-updater-mode))

(use-package inspector
  :ensure (:wait t)
  )

(use-package org-node
  :ensure (:wait t)
  :init
  ;; Optional key bindings
  ;; Tip: Try changing these to just "M-o"!
  (keymap-global-set "M-o n n" 'org-node-nodeify-entry)
  (keymap-global-set "M-o n i" 'org-node-insert-link)
  :config
  (org-node-cache-mode)
  )

(setq org-node-backlink-do-drawers nil)

(setq org-node-alter-candidates t)