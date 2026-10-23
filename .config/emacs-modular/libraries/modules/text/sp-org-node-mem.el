;;; sp-org-node-mem.el --- org-node and org-mem note indexing -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets up `org-mem', a fast in-memory index of Org files, and
;; `org-node', which builds note-taking commands (find, insert link, backlinks)
;; on top of it, for the notes in `~/notes/'. It also uses the index to compute
;; `org-agenda-files' automatically from files that contain anything
;; agenda-relevant.

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
)

(setq org-node-backlink-do-drawers nil)

(setq org-node-alter-candidates t)

(defun my-set-agenda-files (&rest _)
  (setq org-agenda-files
        (cl-loop for file in (org-mem-all-files)
                 unless (string-search "archive" file)
                 as entries = (org-mem-entries-in-file file)
                 when (seq-find (##or (org-mem-entry-active-timestamps %)
                                      (org-mem-entry-todo-state %)
                                      (org-mem-entry-scheduled %)
                                      (org-mem-entry-deadline %))
                                entries)
                 collect file)))
(add-hook 'org-mem-post-full-scan-functions #'my-set-agenda-files)

(provide 'sp-org-node-mem)
