;; -*- lexical-binding: t -*-
;; -*-no-byte-compile: t; -*-
;; -*- mode: emacs-lisp; coding:utf-8; fill-column: 80 -*-

;; Use-Package Settings
(use-package use-package
  :custom
  (use-package-always-defer nil)        ;; Don't automatically defer
  (use-package-verbose t)               ;; Report loading details
  (use-package-minimum-reported-time 0) ;; This is really helpful for profiling
  (use-package-expand-minimally nil)    ;; Expand normally

  ;; Unconditional: lambda-emacs handles installation via
  ;; `sp-install-extras' driven by `sp-packages-alist', not via
  ;; use-package's :ensure machinery. Setting this to nil lets
  ;; modules omit :ensure entirely without accidentally triggering
  ;; an install on any form that says nothing about :ensure.
  ;; (use-package-always-ensure nil)
  ;; I don't know what to do with this setting

  ;; Navigate use-package declarations w/imenu
  (use-package-enable-imenu-support t))

;; SETTING UP THE LOAD PATH

(defvar sp-load-path (file-name-directory (or load-file-name buffer-file-name))
  "Path of the siapip emacs config")
(when (not sp-load-path)
  (error "Cannot determine configuration path of siapip emacs-config: both load-file-name and buffer-file-name are nil"))

(defun sp-load (paths)
  "Load files relative to this emacs config."
  (when (not (listp paths))
    (setq paths (list paths)))
  (dolist (path paths)
    (condition-case err
        (load (expand-file-name path sp-load-path))
      (error (message "Failed to load Sia's sub-library at %S: %S" path err)))))

;;;; Startup

;;;;; Bootstrapping elpaca
(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" sp-var-dir))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;;; Configure elpaca use-package support
(elpaca elpaca-use-package
        ;; Enable use-package :ensure support for Elpaca.
        (elpaca-use-package-mode)
        ;; Assume :elpaca t unless otherwise specified.
        (setq elpaca-use-package-by-default t))

;;When installing a package used in the init file itself,
;;e.g. a package which adds a use-package key word,
;;use the :wait recipe keyword to block until that package is installed/configured.
;;For example:
;;(use-package general :ensure (:wait t) :demand t)

;; Elpaca wait needs to be fired, otherwise it's not going to be able to pick up the
;; actions you're sending it via use-package, later on, when you're going to call gnutls
(elpaca-wait)

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
  - `test' loads only a `sp-test.el' file for easy testing.")

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

;;; Recursive load path for Emacs lisp files

(let ((default-directory (expand-file-name "modules/" sp-library-dir)))
  (normal-top-level-add-to-load-path '("."))
  (normal-top-level-add-subdirs-to-load-path))

;; Reporting whether the modules have loaded properly
(defun sp-require-module (feature)
  "Require FEATURE and log the outcome to *Messages*.
Return non-nil if FEATURE is loaded afterwards."
  (if (featurep feature)
      (progn (message "[skip]   %-24s already loaded" feature) t)
    (let ((start (float-time)))
      (condition-case err
          (progn
            (require feature)
            (message "[ok]     %-24s %.3fs" feature (- (float-time) start))
            t)
        (error
         (message "[FAILED] %-24s %S" feature err)
         nil)))))

;;;;; Module loading helpers
(defun lem--require-modules (modules)
  "Require each feature in MODULES, logging every result to *Messages*.
Skips modules in `(lem-gui-only-modules)' when `sp-headless-host' is
non-nil. A failing module is reported and the rest still load."
  (let (loaded failed skipped)
    (dolist (mod modules)
      (cond
       ((and (bound-and-true-p sp-headless-host)
             (memq mod (lem-gui-only-modules)))
        (push mod skipped)
        (message "[headless] %-22s skipped (GUI-only)" mod))
       ((sp-require-module mod)
        (push mod loaded))
       (t
        (push mod failed))))
    (message "Modules: %d loaded, %d failed, %d skipped%s"
             (length loaded) (length failed) (length skipped)
             (if failed
                 (format " (failed: %s)"
                         (mapconcat #'symbol-name (reverse failed) ", "))
               ""))))

;;; Modular loading without a config.el
;;;;; Load order
;; The order of `lem--default-modules' follows the dependencies between the
;; Elpaca recipes in the modules; docs/load-order.org draws them and says why.
;; Two rules matter to Elpaca. A package that another package requires has to be
;; declared *before* that package, otherwise Elpaca has already queued it as a
;; dependency and warns "X previously queued as dependency of: (Y)". And a
;; `:wait t' recipe stops init until the queue so far is installed, so the
;; packages the rest of init needs go first.

(defcustom sp-defer-late-modules t
  "When non-nil, load the modules in `lem--late-modules' after startup.
They are required from an idle timer once Elpaca has finished its
initial queues, so they no longer add to the time Emacs takes to
become usable. Set to nil to load them with the other modules, in
the order of `lem--late-modules', for example when debugging."
  :type 'boolean
  :group 'sia-lambda)

(defconst lem--late-modules
  '(;; Academic: bibliography, graphs and notes tooling, not needed to edit
    ;; the first file.
    sp-academic
    sp-notes
    sp-trails ;; For gathering links from browser sessions
    sp-semantic
    ;; several graphing functionality
    sp-dgraphs
    sp-relationship-annotator
    sp-dyn-graph
    sp-relationship-annotator-live ;; live localhost view of the graph
    ;; Sandboxed Emacs for pull requests
    sp-sandbox
    ;; Version control. `sp-keys' autoloads the magit commands it binds, so
    ;; the keys work before this loads. `sp-vcontrol' installs magit and
    ;; `sp-magit-style' styles it, so it comes second.
    sp-vcontrol
    sp-magit-style
    sp-merge-pick ;; graph log: mark two commits, preview or start a merge
    ;; Terminals and shells
    sp-terminal
    sp-eshell
    ;; AI tooling: the most packages of any module
    sp-ai
    sp-tag-emoji ;; tags as emoji in the modeline and on links
    sp-thesis-dump
    )
  "Modules that can wait until after startup, in dependency order.
Nothing else requires these features, and their packages are not
needed to open the first buffer.")

(defun lem--load-late-modules ()
  "Require `lem--late-modules', then let Elpaca process what they queued."
  (lem--require-modules lem--late-modules)
  ;; Orders declared after init are only processed on their own when a
  ;; command is running interactively.
  (when (fboundp 'elpaca-process-queues)
    (elpaca-process-queues)))

(defun lem--schedule-late-modules ()
  "Load `lem--late-modules' now, or once Emacs is idle after Elpaca's init."
  (if sp-defer-late-modules
      (add-hook 'elpaca-after-init-hook
                (lambda () (run-with-idle-timer 0.5 nil #'lem--load-late-modules)))
    (lem--load-late-modules)))

;;;;; Load Configuration Modules
;; Lambda-Emacs loads a series of lisp-libraries or 'modules'. Which modules are
;; loaded is left to the user to set in `config.el', though if there is no
;; `config.el' file a default set of modules will be loaded.
(defun lem--default-modules ()
  "Load a default configuration for 𝛌-Emacs.
Skips modules listed in `(lem-gui-only-modules)' when
`sp-headless-host' is non-nil."
  (message "
;; ======================================================
;; *Loading default setup of 𝛌-Emacs Modules*
;; ======================================================")
  (measure-time
   (lem--require-modules
                    (list
                    ;; Core
                    'sp-paths
                    'sp-encoding
                    'sp-base-libraries
                    ;; 'sp-snippets ;; I don't really make use of snippets yet.
                    'sp-interaction
                    'sp-keys
                    'sp-navi ;; Navigation & search

                    ;; UI modules (loaded in order of need)
                    'sp-icons

                    'sp-colors
                    'sp-faces
                    'sp-fonts
                    'sp-emoji-font ;; colour emoji font (after sp-fonts)

                    'sp-textui
                    'sp-themes

                    ;;;; Window management
                    'sp-frame
                    'sp-buffers
                    'sp-windows
                    'sp-tabs
                    'sp-mini-frame
                    'sp-treemacs ;; File tree on <f9>

                    'sp-writedesk
                    'lem-dashboard

                    ;;;; Modern settings
                    'sp-canvas

                    ;; Environment settings (have to come after the UI because of dependencies)
                    'sp-env
                    'sp-macos
                    ;; 'sp-syswin ;; will be adding the relevant modules later
                    ;; 'sp-exwm

                    ;; Utility misc modules
                    'sp-backups
                    'sp-bookmarks
                    ;; 'sp-choose-modeline
                    'sp-debug
                    'sp-embark
                    ;; 'sp-evil
                    'sp-help
                    'sp-indention
                    'sp-lambda-line
                    'sp-md
                    'sp-minibuffer
                    'sp-network
                    'sp-scratch
                    'sp-server
                    'sp-splash
                    'sp-spelling
                    'sp-templating
                    'sp-text-manipulation
                    'sp-workspaces

                    ;; Org related settings
                    ;; `sp-org-base' and `sp-org-agenda' come before the other
                    ;; Org modules: `sp-org-agenda' declares org-super-agenda
                    ;; and then org-ql, which requires it.
                    'sp-org-base
                    'sp-denote
                    'sp-org-appearance
                    'sp-org-capture
                    'sp-org-export
                    ;; 'sp-org-fn
                    'sp-org-narrow
                    'sp-org-id-link
                    ;; 'sp-org-refile
                    'sp-org-tables
                    'sp-org-agenda
                    'sp-org-taskman-extra
                    'sp-org-ext
                    'sp-org-issues ;; issue tracker area (after sp-org-ext)
                    'sp-csv

                    ;; Functions
                    'sp-helper-funct
                    'sp-open-externally
                    'sp-move-region-to-heading
                    'sp-tab-inbox
                    'sp-org-link-conversion
                    'sp-org-lint

                    ;; Programming modules
                    'sp-base-code
                    ;; `sp-lisp' installs paredit, which emr (in
                    ;; `sp-prog-misc') requires, so it comes first.
                    'sp-lisp
                    'sp-prog-misc
                    ;; 'sp-vc-ai-workbench
                    ))
   ;; The modules in `lem--late-modules' load once startup is done.
   (lem--schedule-late-modules)))

(defun lem--minimal-modules ()
  "Load 𝛌-Emacs with a minimal set of modules.
Skips modules listed in `(lem-gui-only-modules)' when
`sp-headless-host' is non-nil, matching `lem--default-modules'."
  (message "
;; ======================================================
;; *Loading 𝛌-Emacs, with minimal modules*
;; ======================================================")
  (measure-time
   (cl-dolist (mod (cl-remove-if
                    (lambda (m)
                      (and sp-headless-host
                           (memq m (lem-gui-only-modules))))
                    (list
                     ;; Core
                    'sp-paths
                    'sp-encoding
                    'sp-base-libraries
                    ;; 'sp-snippets
                    'sp-interaction
                    'sp-keys
                    'sp-navi ;; Navigation & search

                    ;; Environment settings (have to come after the UI because of dependencies)
                    'sp-env
                    'sp-macos
                    ;; sp-win ;; will be adding the relevant modules later
                    ;; sp-exwm

                    ;; Utility misc modules
                    'sp-backups
                    'sp-bookmarks
                    ;; 'sp-choose-modeline
                    'lem-dashboard
                    'sp-debug
                    'sp-embark
                    ;; 'sp-evil
                    'sp-help
                    'sp-indention
                    'sp-lambda-line
                    'sp-md
                    'sp-minibuffer
                    'sp-network
                    'sp-scratch
                    'sp-server
                    'sp-splash
                    'sp-spelling
                    'sp-templating
                    'sp-text-manipulation
                    'sp-workspaces

                    ;; Org related settings
                    'sp-org-base
                    'sp-denote
                    'sp-org-appearance
                    'sp-org-capture
                    'sp-org-export
                    ;; 'sp-org-fn
                    'sp-org-narrow
                    ;; 'sp-org-refile
                    'sp-org-tables
                    'sp-org-agenda
                    'sp-org-taskman-extra
                    'sp-org-ext
                    'sp-csv
                    )))
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
  (lem--minimal-modules))

 ;; Load test module only. This is useful for testing a specific package
 ;; against vanilla/default emacs settings.
 ((sp--emacs-switches "-test")
  (message "*Loading test module only*")
  (require 'lem-setup-test))

 ;; Load default config
 ((sp--emacs-switches "-default")
  (message "*Loading 𝛌-Emacs default modules")
  (lem--default-modules)
  ;; MacOS settings - defer load until after init. Skipped on
  ;; headless hosts: `sp-setup-macos' is in `sp-gui-only-set'
  ;; and the dispatcher's filter already excludes it, but this
  ;; deferred require fires outside the dispatcher and would
  ;; bypass the filter without the explicit guard.
  (when (and sys-mac (not sp-headless-host))
    (message "*Load MacOS settings...*")
    (measure-time
     (run-with-idle-timer 1 nil
                          (function require)
                          'sp-setup-macos nil t))))

 ;; Default: no switch given
 (t
  (message "*Loading 𝛌-Emacs default modules*")
  (lem--default-modules)
  (when (and sys-mac (not sp-headless-host))
    (run-with-idle-timer 1 nil #'require 'sp-setup-macos nil t)))
)

;;;; After Startup
;; reset file-name-handler-alist
(add-hook 'emacs-startup-hook (lambda ()
                                (setq file-name-handler-alist sp-file-name-handler-alist)
                                ;; reset garbage collection
                                (setq gc-cons-threshold 800000)
                                ;; Startup time
                                (message (format ";; ======================================================\n;; Emacs ready in %.2f seconds with %d garbage collections.\n;; ======================================================"
                                                 (float-time
                                                  (time-subtract after-init-time before-init-time)) gcs-done))
                                (put 'narrow-to-page 'disabled nil)))
