;; -*- lexical-binding: t; -*-

;; site-lisp has already been set up differently
;; (add-to-list)
(require 'org-db-v3)

;; Bind the menu to a convenient key
(global-set-key (kbd "H-v") 'org-db-menu)

;; Auto-start server when Emacs starts (optional)
;; (setq org-db-v3-auto-start-server t)
;; Optional: Enable gptel integration for AI-powered search
;; (when (featurep 'gptel)
;;  (require 'org-db-v3-gptel-tools)
;;  (org-db-v3-gptel-register-tools))