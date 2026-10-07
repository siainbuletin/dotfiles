;;; config.el --- summary -*- lexical-binding: t -*-

;; Maintainer: Colin Mclear
;; This file is not part of GNU Emacs

;;; Commentary:

;; Personal config file
;; This file contains all user-specific settings

;;; Code:
;;;; Personal Information

;; Give Emacs some personal info
(setq user-full-name "Sia Piperea"
      user-mail-address "siapiperea@gmail.com")

;;;; User Vars

;;;;; Set Fonts

;;;;; Org Directories
;; Set these if you're using org
(setq org-directory "~/notes/"
      org-default-notes-file (concat org-directory "inbox.org"))

;;;;; Set Splash Footer
;; Set a footer for the splash screen
(setq sp-splash-footer  "")

;;;; Load Modules
;; Load modules in stages for a shorter init time. We load core modules first,
;; then more expensive modules after init, with the rest loaded after startup
;; has fully completed.

;;;;; Load base modules
(message "
;; ======================================================
;; *Loading 𝛌-Emacs Base Modules*
;; ======================================================")
(measure-time
 (cl-dolist (mod (list
                  ;; Base modules
                  'sp-libraries
                  'sp-settings
                  'sp-functions
                  'sp-macros
                  'sp-scratch
                  'sp-theme

                  ;; Basic UI modules
                  'sp-windows
                  'sp-buffers
                  'sp-frames
                  'sp-fonts
                  'sp-faces))
   (require mod nil t)))

;;;;; Load After-Init Modules
(defun lem-user-config-after-init ()
  "Modules loaded after init."
  (message "
  ;; ======================================================
  ;; *Loading 𝛌-Emacs after-init Modules*
  ;; ======================================================")
  (measure-time (cl-dolist (mod (list
                                 ;; Splash/Dashboard
                                 'sp-splash
                                 'sp-dashboard

                                 ;; Completion & Keybinds
                                 'sp-completion
                                 'sp-keybindings

                                 ;; Navigation & Search modules
                                 'sp-dired
                                 'sp-dired
                                 'sp-search

                                 ;; Project & Tab/Workspace modules
                                 'sp-vc
                                 'sp-projects
                                 'sp-tabs
                                 'sp-workspaces))
                  (require mod nil t))))
(add-hook 'after-init-hook #'lem-user-config-after-init)

;;;;; Load After-Startup Modules
(defun lem-user-config-after-startup ()
  "Modules loaded after Emacs startup."
  (message "
  ;; ======================================================
  ;; *Loading 𝛌-Emacs after-startup Modules*
  ;; ======================================================")
  (measure-time (cl-dolist (mod (list

                                 ;; Writing modules
                                 'sp-writing
                                 'sp-notes
                                 'sp-citation

                                 ;; Programming modules
                                 'sp-programming
                                 'sp-debug
                                 'sp-skeleton

                                 ;; Shell & Terminal
                                 'sp-shell
                                 'sp-eshell

                                 ;; Org modules
                                 'sp-org-base
                                 'sp-org-settings
                                 'sp-org-extensions

                                 ;; Productivity
                                 'sp-elfeed

                                 ;; OS settings
                                 ;; load only if on macos
                                 (when sys-mac
                                   'sp-macos)

                                 ;; Other UI/UX
                                 'sp-help
                                 'sp-colors
                                 'sp-modeline

                                 ;; Server
                                 'sp-server))
                  (require mod nil t))))
(add-hook 'emacs-startup-hook #'lem-user-config-after-startup)

;;;;; Scratch Directory
(customize-set-variable 'sp-scratch-default-dir sp-scratch-save-dir)

;;;; User Keybindings
;; Set this to whatever you wish. All Lambda-Emacs keybinds will be available through this prefix.
(customize-set-variable 'sp-prefix "C-c C-SPC")

;;;; User Functions
;; Put any custom user functions here.

;;; Provide
(provide 'config)
;;; config.el ends here
