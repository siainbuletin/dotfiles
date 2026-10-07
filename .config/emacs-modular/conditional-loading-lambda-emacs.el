;;;;; Load Configuration Modules
;; Lambda-Emacs loads a series of lisp-libraries or 'modules'. Which modules are
;; loaded is left to the user to set in `config.el', though if there is no
;; `config.el' file a default set of modules will be loaded.

;; Different configurations available
;; - default - this will work without the `config.el' file.

(defun sp--default-modules ()
  "Load a default configuration for 𝛌-Emacs.
Skips modules listed in `(sp-gui-only-modules)' when
`sp-headless-host' is non-nil."
  (message "
;; ======================================================
;; *Loading default setup of 𝛌-Emacs Modules*
;; ======================================================")
  (measure-time
   (cl-dolist (mod (cl-remove-if
                    (lambda (m)
                      (and sp-headless-host
                           (memq m (sp-gui-only-modules))))
                    (list
                    ;; Core modules
                    'sp-libraries
                    'sp-settings
                    'sp-functions
                    'sp-server
                    'sp-scratch

                    ;; UI modules
                    'sp-frames
                    'sp-windows
                    'sp-buffers
                    'sp-fonts         ;; All font settings
                    'sp-faces
                    'sp-colors
                    'sp-completion
                    'sp-keys          ;; I don't think this should be in the UI, rather in navigation
                    'sp-help
                    'sp-modeline
                    'sp-theme
                    'sp-splash

                    ;; Navigation & Search modules (/navi/)
                    'sp-dired
                    'sp-dired
                    'sp-search

                    ;; Project & Tab/Workspace modules
                    'sp-vcontrol
                    'sp-projects
                    'sp-tabman ;; (sp-tabs)

                    ;; Org modules
                    'sp-org-base
                    'sp-org-settings

                    ;; Writing modules
                    'sp-writing
                    'sp-notes
                    'sp-citation

                    ;; Shell & Terminal
                    'sp-shell
                    'sp-eshell

                    ;; Programming modules (should be expanded with different libraries)
                    'sp-programming)))
     (require mod))))

(defun sp--minimal-modules ()
  "Load 𝛌-Emacs with a minimal set of modules.
Skips modules listed in `(sp-gui-only-modules)' when
`sp-headless-host' is non-nil, matching `sp--default-modules'."
  (message "
;; ======================================================
;; *Loading 𝛌-Emacs, with minimal modules*
;; ======================================================")
  (measure-time
   (cl-dolist (mod (cl-remove-if
                    (lambda (m)
                      (and sp-headless-host
                           (memq m (sp-gui-only-modules))))
                    (list
                     ;; Core modules
                     'sp-libraries
                     'sp-settings
                     'sp-functions
                     'sp-server
                     'sp-scratch

                     ;; UI modules
                     'sp-frames
                     'sp-windows
                     'sp-buffers
                     'sp-completion
                     'sp-keybindings
                     'sp-help
                     'sp-modeline
                     'sp-splash

                     ;; Navigation & Search modules
                     'sp-dired
                     'sp-dired
                     'sp-search)))
     (require mod))))

;;;; Defensive headless-host warning
;; Installed BEFORE the module-loading cond so the hook is in
;; place even if the cond's body errors out (e.g. an external
;; package missing in the test sandbox). The function no-ops
;; when `sp-headless-host' is nil; on a headless host it emits
;; a prominent warning if a client creates a graphical frame
;; (GUI-only modules were skipped at load time, so fonts,
;; mode-line, and faces are unconfigured in such a frame).
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

;; Conditionally load configuration files based on command-line switches,
;; presence of user-config file, or the default set of modules.
(cond
 ;; Load a subset of modules only, ignore other configuration.
 ((sp--emacs-switches "-minimal")
  (message "*Loading a subset of 𝛌-Emacs modules *only*, ignoring personal user configuration.*")
  (sp--minimal-modules))

 ;; Load test module only. This is useful for testing a specific package
 ;; against vanilla/default emacs settings.
 ((sp--emacs-switches "-test")
  (message "*Loading test module only*")
  (require 'sp-test))

 ;; Load user's personal config file (if it exists) and hasn't been bypassed
 ;; by a command-line switch to load the default libraries.
 ((and (not (sp--emacs-switches "-default"))
       (file-exists-p sp-config-file))
  (message "*Loading 𝛌-Emacs & user config*")
  (load sp-config-file 'noerror))

 ;; Load default config
 ((sp--emacs-switches "-default")
  (message "*Loading 𝛌-Emacs default modules")
  (sp--default-modules)
  ;; MacOS settings - defer load until after init. Skipped on
  ;; headless hosts: `lem-setup-macos' is in `lem-gui-only-set'
  ;; and the dispatcher's filter already excludes it, but this
  ;; deferred require fires outside the dispatcher and would
  ;; bypass the filter without the explicit guard.
  (when (and sys-mac (not sp-headless-host))
    (message "*Load MacOS settings...*")
    (measure-time
     (run-with-idle-timer 1 nil
                          (function require)
                          'sp-macos nil t))))

 ;; No user config file exists: create one from the shipped default
 ;; and load it. Historically this branch called yes-or-no-p and
 ;; discarded the answer (always proceeding), so the prompt offered
 ;; no real consent. Removed for batch-safety and honesty.
 ((when (not (file-exists-p sp-config-file))
    (progn
      (with-temp-file sp-config-file
        (insert-file sp-default-config-file))
      (load-file sp-config-file))))
 ;; Load default modules
 (t
  (message "*Loading 𝛌-Emacs default configuration files.*")
  (sp--default-modules)
  ;; MacOS settings - deferred; see the `-default' branch comment
  ;; above for why the headless guard is needed here.
  (when (and sys-mac (not sp-headless-host))
    (message "*Load MacOS settings...*")
    (measure-time
     (run-with-idle-timer 1 nil
                          (function require)
                          'sp-macos nil t)))))