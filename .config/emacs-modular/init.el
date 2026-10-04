;; -*- lexical-binding: t -*-
;; -*-no-byte-compile: t; -*-
;; -*- mode: emacs-lisp; coding:utf-8; fill-column: 80 -*-

;; SETTING UP THE LOAD PATH

(defvar siapip/load-path (file-name-directory (or load-file-name buffer-file-name))
  "Path of the siapip emacs config")
(when (not siapip/load-path)
  (error "Cannot determine configuration path of siapip emacs-config: both load-file-name and buffer-file-name are nil"))

(defun siapip/load (paths)
  "Load files relative to this emacs config."
  (when (not (listp paths))
    (setq paths (list paths)))
  (dolist (path paths)
    (condition-case err
        (load (expand-file-name path siapip/load-path))
      (error (message "Failed to load siapip-config sub-library at %S: %S" path err)))))

;;;; Startup

;;;;; Security
;; Properly verify outgoing ssl connections.
;; See https://glyph.twistedmatrix.com/2015/11/editor-malware.html
(use-package gnutls
  :ensure nil
  :defer 1
  :custom
  (gnutls-verify-error t)
  (gnutls-min-prime-bits 3072))

;;;;; Command Line Switches

;; Conditionally load parts of config depending on command line switches.
;; This allows startup with a clean emacs that still recognizes straight.
;; Helpful for testing packages.
;; Use (straight-use-package) command to selectively load packages.
;; See https://emacs.stackexchange.com/a/34909/11934
;; For function switch see https://stackoverflow.com/a/4065412/6277148

;; NOTE: The variable here doesn't really do anything. It is just useful to keep
;; for a record of switches.
(defvar sp-config-switches
  '("basic"
    "clean"
    "core"
    "test")
  "Custom switches for conditional loading from command line.
  
  - `clean' loads only the `init.el' file w/no personal config; 
  - `core'  loads the set of modules set in `lem-core-modules'; 
  - `test' loads only a `lem-setup-test.el' file for easy testing.")

(defvar sp--emacs-switches-found nil
  "Custom command-line switches found in `command-line-args' at startup.
Populated by a single scan at load time: each known switch
(\"-minimal\", \"-test\", \"-vanilla\", \"-default\") present in
`command-line-args' is recorded here and deleted from
`command-line-args' exactly once, so Emacs's own option processing
does not signal \"Unknown option\" after init.")

(dolist (switch '("-minimal" "-test" "-vanilla" "-default"))
  (when (member switch command-line-args)
    (push switch sp--emacs-switches-found)
    (setq command-line-args (delete switch command-line-args))))

(defun sp--emacs-switches (switch)
  "Non-nil if command line argument SWITCH was passed.
Consults `sp--emacs-switches-found', the snapshot recorded when the
switch was removed from `command-line-args' at load time, so it is
safe to call any number of times per switch."
  (member switch sp--emacs-switches-found))

;;;;; Emacs Build Version
;; When built with https://codeberg.org/mclearc/build-emacs-macos, Emacs has
;; git-version patch to include git sha1 in emacs-version string.
;; Load it only when the running build actually provides it on its load-path.
;; Checking a hardcoded Emacs.app path with `file-exists-p' breaks other builds
;; (e.g. a homebrew daemon) whose load-path omits that site-lisp: the file
;; exists on disk so the guard passes, but `require' cannot find it.
;;
;;
;; this should be worked on later!!

(when (locate-library "emacs-git-version")
  (require 'emacs-git-version))

(defun lem-emacs-version ()
  "A convenience function to print the emacs-version in the echo-area/*messages* buffer and put
emacs-version string on the kill ring."
  (interactive)
  (let ((emacs (emacs-version)))
    (message (emacs-version))
    (kill-new emacs)))

;;;;; Outline Navigation

;; this navigation could be moved to a different module !!

;; Navigate elisp files easily. Outline is a built-in library and we can easily
;; configure it to treat elisp comments as headings.
(use-package outline
  :ensure nil
  :hook (prog-mode . outline-minor-mode)
  :bind (:map outline-minor-mode-map
         ("<tab>"   . outline-cycle)
         ("S-<tab>" . outline-cycle-buffer)
         ("M-j"     . outline-move-subtree-down)
         ("M-k"     . outline-move-subtree-up)
         ("M-h"     . outline-promote)
         ("M-l"     . outline-demote))
  :config
  (add-hook 'emacs-lisp-mode-hook
            (lambda ()
              ;; prevent `outline-level' from being overwritten by `lispy'
              (setq-local outline-level #'outline-level)
              ;; setup heading regexp specific to `emacs-lisp-mode'
              (setq-local outline-regexp ";;;\\(;* \\)")
              ;; heading alist allows for subtree-like folding
              (setq-local outline-heading-alist
                          '((";;; " . 1)
                            (";;;; " . 2)
                            (";;;;; " . 3)
                            (";;;;;; " . 4)
                            (";;;;;;; " . 5))))))

;; LOADING MODULES FOR PACKAGES (with groups)

;; init modules (the most important files that I have to be loading up)

(siapip/load
 '("./libraries/init/speedup"              ;; stuff that should probably be in early-init.el
   "./libraries/init/set-elpaca"           ;; this is the basic setup for elpaca
   "./libraries/init/set-encoding"         ;; text encoding
   "./libraries/init/set-essential"        ;; this represents essential functions
   "./libraries/init/set-env"              ;; Making exec-path work.
   "./libraries/init/custom"               ;; this is for the ~customize~ buffer (currently, this doesn't manage to be found - TO FIX)
   "./libraries/init/set-gui"              ;; currently handled by early-init from Lambda Emacs
   "./libraries/init/set-macos.el"         ;; MacOS specific settings
   "./libraries/init/set-exwm"             ;; see whether you're going to combine this with regular window management
   "./libraries/init/set-snippets"         ;; snippet management
   "./libraries/init/set-base-libraries"   ;; the very basic processing libraries
   "./libraries/init/set-interaction"
   ))

;; misc modules (utility)

(siapip/load
 '("./libraries/utils/set-minibuffer"
   "./libraries/utils/exec-path-from-shell"
   "./libraries/utils/set-indention"
   "./libraries/utils/replace-with-shell"
   "./libraries/utils/misc"
   "./libraries/utils/set-choose-modeline"
   ;; "./libraries/utils/lambda-line"
   ;; "./libraries/utils/extended-command"
   "./libraries/utils/set-debug"
   "./libraries/utils/set-backups"
   ))

;; package loading

(siapip/load
  '(;; essential emacs functions
    "./libraries/packages/sia-set-search" ;; this represents full-text search packages
    "./libraries/packages/sia-set-embark"
    "./libraries/packages/sia-set-keys"
    "./libraries/packages/sia-set-dired"
    "./libraries/packages/sia-set-help"
    "./libraries/packages/sia-set-bookmarks"

    ;; computer works
    "./libraries/packages/sia-set-terminal"
    "./libraries/packages/sia-set-http"
    "./libraries/packages/sia-set-vcontrol"
    "./libraries/packages/sia-set-ai"

    ;; graphical display
    "./libraries/packages/sia-set-windows"
    "./libraries/packages/sia-set-buffers"

    ;; appearance
    "./libraries/packages/sia-set-fonts"
    "./libraries/packages/sia-set-themes"
    "./libraries/packages/sia-set-icons"
    
    ;; text modes
    "./package/sia-set-md"
    "./libraries/packages/sia-set-org-base"
    "./libraries/packages/sia-set-taskman"

    ;; setup for multimedia work
    "./libraries/packages/sia-set-multimedia"
    "./libraries/packages/sia-set-beets"
    
    ;; advanced object-based notes
    "./libraries/packages/sia-set-vulpea-base" ;; (this module) will pull its necessary add-on functions on its own (recursion)
    "./libraries/packages/sia-set-denote"
    "./libraries/packages/sia-set-dgraphs"
    "./libraries/packages/sia-set-org-node-mem"

    ;; academic modules + writing
    "./libraries/packages/sia-set-academic"
    "./libraries/packages/sia-set-reading"
    "./libraries/packages/sia-set-spelling"

    ;; extra reading    
    "./libraries/packages/sia-set-browsing"
    "./libraries/packages/sia-set-rss"

    ;; large management
    "./libraries/packages/sia-set-dashboard"
    "./libraries/packages/sia-set-projects"

    ;; other
    "./libraries/packages/sia-set-counsel-recoll" 
    "./libraries/packages/sia-set-consult-snapfile"
  ))

;; functions I wrote

(siapip/load
  '("./libraries/functions/sp-move-region-to-heading.el"
    "./libraries/functions/sp-vulpea-convert-properties.el"
    "./libraries/functions/sp-vulpea-dblock.el"
    "./libraries/functions/sp-vulpea-grouped-backlinks.el"
    "./libraries/functions/sp-vulpea-table-views.el"
    "./libraries/functions/sp-vulpea-vui-table.el"))

;; Calling functions later on

(siapip/load
  '("./libraries/packages/set-sia-vulpea-ext" ;; needs the functions that I called earlier
  ))

;; language modules

(siapip/load
 '("./libraries/langs/sp-base-code"
   ;; "./libraries/langs/sp-plantuml"
   ;; "./libraries/langs/sp-lisp"
   ;; "./libraries/langs/sp-go"
   ;; "./libraries/langs/sp-c"
   ;; "./libraries/langs/sp-python"
   ;; "./libraries/langs/sp-rust"
   ;; "./libraries/langs/sp-xml"
   ;; "./libraries/langs/sp-nix"
   ;; "./libraries/langs/sp-misc" currently disabled, as there's several packages that conflict with something else that I have on the system
   "./libraries/langs/sp-latex"
   ))

(siapip/load
 '("./ext/tex-switch-quotes/tex-switch-quotes"
   "./ext/misc/hl-line+"))

;; Cloned modules (can't install with use-package otherwise)
(siapip/load
 '("./cloned/imenu"
   ))

;;; Endnotes:
;; INFO: Your custom config can be either here or inside /path/to/siapip-emacs-config/custom.el

;; Other configurations will be found in the libraries folder.

;;;;; Load Configuration Modules
;; Lambda-Emacs loads a series of lisp-libraries or 'modules'. Which modules are
;; loaded is left to the user to set in `config.el', though if there is no
;; `config.el' file a default set of modules will be loaded.

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
                    'sp-fonts
                    'sp-faces
                    'sp-colors
                    'sp-completion
                    'sp-keys
                    'sp-help
                    'sp-modeline
                    'sp-theme
                    'sp-splash

                    ;; Navigation & Search modules
                    'sp-navigation
                    'sp-dired
                    'sp-search

                    ;; Project & Tab/Workspace modules
                    'sp-vc
                    'sp-projects
                    'sp-tabs

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
                     'sp-navigation
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
(defun lem--warn-gui-frame-on-headless ()
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
(add-hook 'server-after-make-frame-hook #'lem--warn-gui-frame-on-headless)

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
        (insert-file lem-default-config-file))
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

;;;; After Startup
;; reset file-name-handler-alist
(add-hook 'emacs-startup-hook (lambda ()
                                (setq file-name-handler-alist lem-file-name-handler-alist)
                                ;; reset garbage collection
                                (setq gc-cons-threshold 800000)
                                ;; Startup time
                                (message (format ";; ======================================================\n;; Emacs ready in %.2f seconds with %d garbage collections.\n;; ======================================================"
                                                 (float-time
                                                  (time-subtract after-init-time before-init-time)) gcs-done))
                                (put 'narrow-to-page 'disabled nil)))

;; CUSTOM VARIABLES

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(bibtex-aux-opt-alist
   '(("keywords" "Keywords to describe the entry" "")
     ("file" "Relative or absolute path to attachments" "")) nil nil "Customized with use-package bibtex")
 '(custom-safe-themes
   '("acd363510d3e4b638db178783bde3d4492574c0f5c889f845251949f43567d16"
     "f2f42f0b7c53736840fc3ff5751235e3b87cc535b04ddaf3423e2926548bfbb4"
     default))
 '(sia/modeline 'doom-modeline)
 '(package-vc-selected-packages
   '((claudemacs :url "https://github.com/cpoile/claudemacs" :branch "main")
     (org-modern-indent :url "https://github.com/jdtsmith/org-modern-indent")
     (org-devonthink :url "https://github.com/lasvice/org-devonthink" :branch
		     "master")
     (pulsing-cursor :url "https://github.com/jasonjckn/pulsing-cursor" :branch
		     "main")
     (bibtex-capf :url "https://codeberg.org/mclear-tools/bibtex-capf.git" :branch
		  "main")
     (zotxt-emacs :url "https://github.com/egh/zotxt-emacs.git" :branch "master"))))
    
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-default ((t (:background "#F0B609" :inherit default))))
 '(org-extra-emphasis ((t (:background "#F0B609" :height 1.0 :inherit default :weight bold :width normal))) t)
 '(org-extra-emphasis-01 ((t (:foreground "#003F66" :inherit org-extra-emphasis :underline t))))
 '(org-extra-emphasis-02 ((t (:foreground "#003F66" :inherit org-extra-emphasis :underline t)))))

