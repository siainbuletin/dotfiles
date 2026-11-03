;;; sp-org-refile.el --- Org refile targets and caching -*- lexical-binding: t; -*-

;;; Commentary:

;; This module configures Org's refile command (`C-c C-w'), which moves the
;; heading at point under another heading. It sets the list of possible targets
;; (open Org buffers, the current file, and the agenda files), makes the
;; completion show full outline paths in one step, allows creating new parent
;; headings, and caches the target list, rebuilding it in the background when
;; Emacs is idle.

;;; Code:

;;;; Org Refile

;; See https://blog.aaronbieber.com/2017/03/19/organizing-notes-with-refile.html.

;; With the below settings, you can trigger Refile with C-c C-w in any Org file
;; and get a completing read of all headings up to three levels deep in all
;; files in org-agenda-files. You can also refile to the top header in a
;; document and create new parents.

;; (this setting is comming from lambda emacs and I'm not really sure if it will
;; work as intended, because I modified what it does via use-package)

;; This would be more useful if adapted from Lambda emacs to work with vulpea.

(use-package org-refile
  :ensure nil
  :after org

  :custom
  (org-outline-path-complete-in-steps nil)
  (org-refile-allow-creating-parent-nodes 'confirm)
  ;; there is something wrong in the syntax in the way that I wrote it here
  (org-refile-targets
   '(
     (+org/opened-buffer-files :maxlevel . 9)
     (nil :maxlevel . 9)
     (org-agenda-files :maxlevel . 8)
   ))
  (org-refile-use-cache t)
  (org-refile-use-outline-path 'file)
)

(run-with-idle-timer 300 t (lambda ()
                            (org-refile-cache-clear)
                            (org-refile-get-targets)))

(provide 'sp-org-refile)
