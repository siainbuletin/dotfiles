;;; sp-org-node-mem.el --- org-node and org-mem note indexing -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets up `org-mem', a fast in-memory index of Org files, and
;; `org-node', which builds note-taking commands (find, insert link, backlinks)
;; on top of it, for the notes in `~/notes/'. The agenda files are not
;; computed here: vulpea-para owns them (see sp-vulpea-para and adr/0009).

;;; Code:

(use-package org-mem
  :ensure (:wait t)
  :defer
  :config
  ;; At least one of these two is needed
  (setq org-mem-do-sync-with-org-id t)
  (setq org-mem-watch-dirs
        (list sp-notes-dir))
  (org-mem-updater-mode))

(use-package inspector
  :ensure (:wait t)
  )

(use-package org-node
  :ensure (:wait t)
  :hook (after-init . org-node-cache-mode)
  :init
  ;; Optional key bindings
  ;; Tip: Try changing these to just "M-o"!
  (keymap-global-set "M-o n n" 'org-node-nodeify-entry)
  (keymap-global-set "M-o n i" 'org-node-insert-link)

  :custom
  (org-node-backlink-do-drawers nil)
  (org-node-alter-candidates t))

(provide 'sp-org-node-mem)
