;;; sp-config-profiles.el --- Declarative module profiles  -*- lexical-binding: t; -*-

;;; Commentary:

;; Lambda Emacs originally ships with a different config loader (which helps in 
;; case of testing the configuration, but I wanted to replace the ~config.el~ file,
;; as I don't see the point of using one if the configuration is made for me and me only.
;; 
;; This new module structure was written by Claude (and adapted).
;; 
;; It may also need more refinement for perhaps lazyloading certain parts of the
;; config when actually calling that function (example: several modules from the
;; ~media/~ directory.
;; 
;; Modules (sub-libraries) are declared as plain feature symbols (e.g. `sp-base-code')
;; loaded with `require', so they are found anywhere under `sp-library-dir' and are
;; only ever loaded once.  Every module file must end with (provide 'its-own-file-name).

;; ERROR
;; this doesn't currently work well and I don't know what to tell Claude to do in order to
;; not load this. Theoretically, the vanilla Lambda Emacs thing doesn't use config.el if it
;; does not exist and it just uses the default profile, if it exists.

;;; Lambda emacs modified (Claude) modular loading
;; The recursive loading already existed in early-init.el and there's no need to
;; declare it again. The variables for loading profiles can be found in 
;; sp-config-profiles.el. Everything else that's essential is configured later.
;; 
;; I would want to change the location of sp-config-profiles.el so that it's no
;; longer in the top-level directory.

;;; Code:

;;;; Safe require
(defun sp-require-module (feature)
  "Require FEATURE, reporting a message instead of aborting on failure."
  (condition-case err
      (require feature)
    (error
     (message "Failed to load sub-library `%S': %S" feature err)
     nil)))

;; Drop-in replacement for `sp-load': accepts one symbol or a list.
(defun sp-require (features)
  "Require FEATURES (a symbol or list of symbols) with error reporting."
  (dolist (feature (ensure-list features))
    (sp-require-module feature)))

;;;; Profiles
;; Edit these lists to change what each bundle loads.  This is the
;; replacement for config.el.
(defvar sp-module-profiles
  '((default
     . (;; Core
        sp-paths
        sp-encoding
        sp-base-libraries
        sp-snippets
        sp-interaction
        sp-keys
        sp-navi ;; Navigation & search

        ;; UI
        sp-buffers
        sp-canvas
        sp-colors
        lem-dashboard
        sp-faces
        sp-frame
        sp-fonts
        sp-icons
        sp-tabs
        sp-textui
        sp-themes
        sp-windows
        sp-writedesk

        ;; Environment settings (have to come after the UI because of dependencies)
        sp-env
        sp-macos
        ;; sp-win ;; will be adding the relevant modules later
        ;; sp-exwm

        ;; Utility misc modules
        sp-backuos
        sp-bookmarks
        ;; sp-choose-modeline
        lem-dashboard
        sp-debug
        sp-embark
        ;; sp-evil
        sp-help
        sp-indention
        sp-lambda-line
        sp-md
        sp-minibuffer
        sp-network
        sp-scratch
        sp-server
        sp-splash
        sp-spelling
        sp-templating
        sp-text-manipulation
        sp-workspaces

        ;; Org related settings
        sp-org-base
        sp-denote
        sp-org-appearance
        sp-org-capture
        sp-org-export
        sp-org-narrow
        ;; sp-org-refile
        sp-org-tables
        sp-org-agenda
        sp-org-taskman-extra
        sp-org-ext

        ;; Academic
        sp-academic
        ;; sp-statistics
        sp-dgraphs
        sp-notes

        ;; Functions
        sp-helper-funct
        sp-open-externally
        sp-move-region-to-heading

        ;; Project & workspace
        sp-vcontrol
        sp-projects
        sp-tabman
        ;; Org
        sp-org-base sp-org-settings
        ;; Writing
        sp-writing sp-notes sp-citation
        ;; Shell & terminal
        sp-shell sp-eshell))
    (plus-programming
     . (;; Core
        sp-package
        sp-paths
        sp-encoding
        sp-base-libraries
        sp-snippets
        sp-interaction
        sp-keys
        sp-navi ;; Navigation & search

        ;; UI
        sp-buffers
        sp-canvas
        sp-colors
        lem-dashboard
        sp-faces
        sp-frame
        sp-fonts
        sp-icons
        sp-tabs
        sp-textui
        sp-themes
        sp-windows
        sp-writedesk

        ;; Environment settings (have to come after the UI because of dependencies)
        sp-env
        sp-macos
        ;; sp-win ;; will be adding the relevant modules later
        ;; sp-exwm

        ;; Utility misc modules
        sp-backups
        sp-bookmarks
        ;; sp-choose-modeline
        lem-dashboard
        sp-debug
        sp-embark
        ;; sp-evil
        sp-help
        sp-indention
        sp-lambda-line
        sp-md
        sp-minibuffer
        sp-network
        sp-scratch
        sp-server
        sp-splash
        sp-spelling
        sp-templating
        sp-text-manipulation
        sp-workspaces

        ;; Programming
        sp-base-code
        sp-prog-misc
        sp-terminal
        sp-vcontrol
        sp-eshell
        sp-latex))
    (minimal
     . (;; Core
        sp-package
        sp-paths
        sp-encoding
        sp-base-libraries
        sp-snippets
        sp-interaction
        sp-keys
        sp-navi ;; Navigation & search

        ;; UI
        sp-buffers
        sp-canvas
        sp-colors
        lem-dashboard
        sp-faces
        sp-frame
        sp-fonts
        sp-icons
        sp-tabs
        sp-textui
        sp-themes
        sp-windows
        sp-writedesk

        ;; Environment settings (have to come after the UI because of dependencies)
        sp-env
        sp-macos
        ;; sp-win ;; will be adding the relevant modules later
        ;; sp-exwm))
    (test
     . (;; Core
        sp-package
        sp-paths
        sp-encoding
        sp-base-libraries
        sp-snippets
        sp-interaction
        sp-keys
        sp-navi ;; Navigation & search

        ;; Needs setup for sp-test module
        )))
  "Alist mapping a profile name to the features loaded for it.")

(defun sp--active-profile ()
  "Return the profile selected by command-line switches."
  (cond ((sp--emacs-switches "-minimal") 'minimal)
        ((sp--emacs-switches "-test") 'test)
        (t 'default)))

(defun sp-load-profile (&optional profile)
  "Load every module of PROFILE (default: the one chosen by switches).
Skips modules in `(sp-gui-only-modules)' when `sp-headless-host' is non-nil."
  (let* ((profile (or profile (sp--active-profile)))
         (modules (alist-get profile sp-module-profiles)))
    (unless modules
      (user-error "No modules defined for profile `%S'" profile))
    (message "\n;; ======================================================
;; *Loading Lambda-Emacs profile: %S*
;; ======================================================" profile)
    (measure-time
     (dolist (mod modules)
       (unless (and sp-headless-host
                    (memq mod (sp-gui-only-modules)))
         (sp-require-module mod))))
    ;; MacOS settings: deferred until idle, default profile only, never headless.
    (when (and sys-mac (not sp-headless-host) (eq profile 'default))
      (run-with-idle-timer 1 nil #'require 'sp-macos nil t))))

;;;; Defensive headless-host warning (unchanged)
(require 'server)
(defun sp--warn-gui-frame-on-headless ()
  "Warn if a server client created a GUI frame on a headless host."
  (when (and sp-headless-host
             (display-graphic-p))
    (display-warning
     'lambda-emacs
     (concat "GUI client frame created on a host where "
             "sp-headless-host is t. GUI modules were not "
             "loaded; fonts, mode-line, and faces are "
             "unconfigured. Unset sp-headless-host and "
             "restart Emacs to recover.")
     :error)))
(add-hook 'server-after-make-frame-hook #'sp--warn-gui-frame-on-headless)

;; Cloned modules (can't install with use-package otherwise)
;; set up later

;;;; Go
(sp-load-profile)

;;;; Provide:
(provide 'sp-config-profiles)
;;; sp-config-profiles.el ends here