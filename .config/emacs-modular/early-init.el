;;; early-init.el --- summary -*- lexical-binding: t; no-byte-compile: t; mode: emacs-lisp; coding:utf-8; fill-column: 80 -*-

;; Prepare for triggering elpaca instead
;; (this is where we diverge from Lambda Emacs - I prefer using the
;; declarative 'elpaca' instead (although it might be cool to have more
;; functions that are written for the native package manager, as I think
;; elpaca was actually developed for this use-case))
(setq package-enable-at-startup nil)

;;;; Speed up startup
;; Help speed up emacs initialization See
;; https://blog.d46.us/advanced-emacs-startup/ and
;; http://tvraman.github.io/emacspeak/blog/emacs-start-speed-up.html and
;; https://www.reddit.com/r/emacs/comments/3kqt6e/2_easy_little_known_steps_to_speed_up_emacs_start/
;; This will be set back to normal at the end of the init file

(defvar lem-file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)

;;;; Measure Time Macro
;; Useful macro to wrap functions in for testing
;; See https://stackoverflow.com/q/23622296
(defmacro measure-time (&rest body)
  "Measure the time it takes to evaluate BODY."
  `(let ((time (current-time)))
     ,@body
     (message "
;; ======================================================
;; %s *Elapsed time: %.06f*
;; ======================================================
" (if load-file-name
      (file-name-nondirectory (format "%s |" load-file-name))
    "")
(float-time (time-since time)))))

;;;; Native Comp

;; See https://github.com/jimeh/build-emacs-for-macos#native-comp
;; https://akrl.sdf.org/gccemacs.html#org335c0de
;; https://github.com/emacscollective/no-littering/wiki/Setting-gccemacs'-eln-cache
;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=53891
;; https://emacs.stackexchange.com/a/70478/11934

;; Native compilation is enabled by default in Emacs 30+, but not every
;; build ships with libgccjit linked in. Guard on `native-compile' so
;; test harnesses and stripped Emacs builds (batch-only, no libgccjit)
;; can load this file without erroring on unbound symbols.
(when (featurep 'native-compile)
  (startup-redirect-eln-cache
   (convert-standard-filename
    (expand-file-name "var/cache/eln-cache/" user-emacs-directory)))
  (setopt native-comp-async-report-warnings-errors nil)
  (setopt native-comp-speed 2)
  (setopt native-comp-deferred-compilation t))

;; Fix native compilation on macOS
(when (and (eq system-type 'darwin)
           (featurep 'native-compile))
  ;; Set library paths for GCC/libgccjit
  (setenv "LIBRARY_PATH" 
          (string-join 
           '("/opt/homebrew/lib"
             "/opt/homebrew/lib/gcc/current"
             "/opt/homebrew/lib/gcc/current/gcc/aarch64-apple-darwin24/15"
             "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib")
           ":")))

;;;; Garbage collection
;; Defer garbage collection further back in the startup process. We'll lower
;; this to a more reasonable number at the end of the init process (i.e. at end of
;; init.el)

(setq gc-cons-threshold most-positive-fixnum)

;; Adjust garbage collection thresholds during startup, and thereafter
;; See http://akrl.sdf.org https://gitlab.com/koral/gcmh

(defmacro k-time (&rest body)
  "Measure and return the time it takes evaluating BODY."
  `(let ((time (current-time)))
     ,@body
     (float-time (time-since time))))

;; When idle for 15sec run the GC no matter what.
(defvar k-gc-timer
  (run-with-idle-timer 15 t
                       (lambda ()
                         (let ((inhibit-message t))
                           (message "Garbage Collector has run for %.06fsec"
                                    (k-time (garbage-collect)))))))

;;;; Clean View
;; UI - Disable visual cruft

;; Resizing the Emacs frame can be an expensive part of changing the
;; font. By inhibiting this, we easily halve startup times with fonts that are
;; larger than the system default.
(setopt frame-inhibit-implied-resize t
        ;; HACK: Don't show size info (or anything else) in frame title
        frame-title-format "\n"
        ;; Disable start-up screen
        inhibit-startup-screen t
        inhibit-startup-message t
        ;; We'll provide our own splash screen, thanks
        inhibit-splash-screen t
        ;; No message in initial scratch buffer
        initial-scratch-message nil)

;; And set these to nil so users don't have to toggle the modes twice to
;; reactivate them. Guarded so `--without-x' builds (no toolkit)
;; don't error on unbound minor-mode functions.
(when (fboundp 'tool-bar-mode)   (setopt tool-bar-mode nil))
(when (fboundp 'scroll-bar-mode) (setopt scroll-bar-mode nil))

;; Fundamental mode at startup.
;; This helps with load-time since no extra libraries are loaded.
(setopt initial-major-mode 'fundamental-mode)

;; Echo buffer -- don't display any message
;; https://emacs.stackexchange.com/a/437/11934
(defun display-startup-echo-area-message ()
  (message ""))

;;;; Set C Directory
;; NOTE this assumes that the C source files are included with emacs.
;; This depends on the build process used.
;; For one example see https://codeberg.org/mclearc/build-emacs-macos
(setq find-function-C-source-directory "/Applications/Emacs.app/Contents/Resources/src")

;;;; System Variables
;; Check the system used
(defconst sys-linux   (eq system-type 'gnu/linux))
(defconst sys-mac     (eq system-type 'darwin))
(defconst sys-bsd     (or sys-mac (eq system-type 'berkeley-unix)))
(defconst sys-win     (memq system-type '(cygwin windows-nt ms-dos)))

;;;; Directory Variables
;;  We're going to define a number of directories that are used throughout this
;;  configuration to store different types of files. This is a bit like the
;;  `no-littering' package, and allows us to keep `user-emacs-directory' tidy.

(defconst sp-emacs-dir (expand-file-name user-emacs-directory)
  "The path to the emacs.d directory.")

(defconst sp-library-dir (concat sp-emacs-dir "libraries/")
  "The directory for 𝛌-Emacs Lisp libraries.
This will house all setup libraries and external libraries or packages.")

(defconst sp-user-dir (concat sp-library-dir "lambda-user/")
  "Storage for personal elisp, scripts, and any other private files.")

(defconst sp-setup-dir (concat sp-library-dir "modules/")
  "The storage location of the setup-init files.")

(defconst sp-var-dir (concat sp-emacs-dir "var/")
  "The directory for non-essential file storage.
Contents are subject to change. Used for package storage (elpa or
straight) and by `sp-etc-dir' and `sp-cache-dir'.")

(defconst sp-etc-dir (concat sp-var-dir "etc/")
  "The directory for non-volatile storage.
  These are not deleted or tampered with by emacs functions. Use
  this for dependencies like servers or config files that are
  stable (i.e. it should be unlikely that you need to delete them
               if something goes wrong).")

(defconst sp-cache-dir (concat sp-var-dir "cache/")
  "The directory for volatile storage.
  Use this for transient files that are generated on the fly like
  caches and ephemeral/temporary files. Anything that may need to
  be cleared if there are problems.")

(defconst sp-default-config-file (concat sp-library-dir "lem-default-config.el")
  "A sample default configuration of the personal config file to get the user started.")

;;;; User Configuration Variables

;; Define customization group for Lambda Emacs.
(defgroup lambda-emacs '()
  "An Emacs distribution with sane defaults, pre-configured packages, and useful functions, aimed at writing and academic work in the humanities."
  :tag "Lambda-Emacs"
  :link '(url-link "https://codeberg.org/Lambda-Emacs/lambda-emacs")
  :group 'emacs)

;; Distribution version -- single source of truth. Mirror it with the
;; git release tag (e.g. v0.3.0).
(defconst lem-version "0.3.0"
  "Version of the Lambda-Emacs distribution.
Bump the minor version for new or changed modules and the major version
for breaking changes to the `lem-setup' surface a downstream config
relies on.  Keep this in sync with the git release tag.")

;; Find the user configuration file
(defconst sp-config-file (expand-file-name "config.el" user-emacs-directory)
  "The user's configuration file.")

;; These next two variables are both optional, but may be convenient.
;; They are used with the functions `lem-goto-projects' and `lem-goto-elisp-library'.

;; Set user project directory
(defcustom sp-project-dir nil "Set the directory for user projects."
  :group 'sia-lambda
  :type 'string)

;; Set user elisp project dir
(defcustom lem-user-elisp-dir nil
  "Directory for personal elisp projects.
Any customized libraries not available via standard package repos like elpa or melpa should go here."
  :group 'sia-lambda
  :type 'string)

;; External-package master switch (see `sp-install-extras')
(defcustom sp-load-extras t
  "Master switch for external-package configuration in lambda-emacs.

When non-nil (default), modules load their external-package
configuration and `sp-install-extras' installs packages listed
in `sp-packages-alist'. When nil, only built-in Emacs features
are configured -- a starter-friendly boot requiring no package
installation.

BOOT-TIME ONLY. Set via `setq' in `config.el' or `early-config.el';
changes take effect on Emacs restart.

It governs all external-package
configuration, not just the `use-package' `:ensure' behavior."
  :group 'sia-lambda
  :type 'boolean)

;; Headless host flag
(defcustom sp-headless-host nil
  "When non-nil, skip modules that are meaningless without a graphic display.

Set this in `config.el' or `early-config.el' on hosts where this
Emacs instance will never be asked to create a graphical frame --
for example, a server running `emacs --daemon' that will only
ever serve TTY clients via `emacsclient -nw'.

INVARIANT: When this is non-nil, creating a graphical frame is
unsupported. The GUI-only modules listed in `sp-gui-only-set'
are skipped at module-require time, so fonts, frames, splash,
dashboard, and macOS-specific integrations are not configured.
A defensive `server-after-make-frame-hook' installed in init.el
warns loudly if a client creates a GUI frame on a host where
this variable is set.

BOOT-TIME ONLY. Changes take effect on Emacs restart."
  :type 'boolean
  :group 'sia-lambda)

;; GUI-only skip set: single source of truth used by both the
;; install loop (skip packages whose topic is GUI-only on a
;; headless host) and the module dispatcher (skip modules whose
;; feature symbol is GUI-only on a headless host). The two views
;; are derived via helper functions so the lists cannot drift.
(defconst sp-gui-only-set
  '((fonts     . sp-setup-fonts)
    (frames    . sp-setup-frames)
    (dashboard . sp-setup-dashboard)
    (splash    . sp-setup-splash)
    (macos     . sp-setup-macos))
  "Topics and modules that are meaningless without a graphic display.
Car is a `sp-packages-alist' topic key; cdr is the feature
symbol for the corresponding `sp-setup-*' module.")

(defun sp-gui-only-topics ()
  "Return the list of topic keys from `sp-gui-only-set'."
  (mapcar #'car sp-gui-only-set))

(defun sp-gui-only-modules ()
  "Return the list of module feature symbols from `sp-gui-only-set'."
  (mapcar #'cdr sp-gui-only-set))

;; Bootstrapping elpaca
(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
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

;; (elpaca-wait)

;;;; Making sure system directories are created
;; Directory paths
(dolist (dir (list sp-library-dir sp-var-dir sp-etc-dir sp-cache-dir sp-user-dir sp-setup-dir))
  (unless (file-directory-p dir)
    (make-directory dir t)))

;;;; Load Path
;; Add all configuration files to load-path
(eval-and-compile
  (progn
    (push sp-setup-dir load-path)
    (push sp-user-dir load-path)))

;;;; Prefer Newer files
;; Prefer newer versions of files
(setopt load-prefer-newer t)

;; Warning settings
;;;; Byte Compile Warnings
;; 
;; Move other warning deferal mechanisms here
;;
;; Disable certain byte compiler warnings to cut down on the noise. This is a
;; personal choice and can be removed if you would like to see any and all byte
;; compiler warnings.
;; NOTE: Setopt won't work here
(setq byte-compile-warnings '(not free-vars unresolved noruntime lexical make-local obsolete))

;; Suppress unnecessary warnings
;; You can set minimum severity level for displaying the warning buffer to :error or :emergency:
;; https://emacs.stackexchange.com/questions/78800/how-to-disable-automatic-appearance-of-warnings-buffer-in-emacs

(setq warning-minimum-level :error)

;;;; Check Errors
;; Don't produce backtraces when errors occur.
;; This can be set to `t' interactively when debugging.
(setopt debug-on-error t)

;; Set location of package directory
(setopt package-user-dir (expand-file-name "elpa/" sp-var-dir))

;; Make sure the elpa/ folder exists after setting it above.
(unless (file-exists-p package-user-dir)
  (mkdir package-user-dir t))
(setopt package-quickstart-file (expand-file-name "package-quickstart.el" sp-cache-dir))

;; Initialize packages and load compat early
;; (package-initialize)