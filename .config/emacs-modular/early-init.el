;; -*- lexical-binding: t; no-byte-compile: t; mode: emacs-lisp; coding:utf-8; fill-column: 80 -*-
;;; early-init.el --- summary
;;: Commentary:

;; This setup file is following a lot from Lambda Emacs, but it diverges
;; by not making use of the built-in package manager (although it might
;; be an option to later come back to it).
;;
;; This setup is concerned with speeding up the initialisation process.
;;
;; There should be a better way to separate the setup part from initialisation.

;;; Code:

;; Prepare for triggering elpaca instead
;; (this is where we diverge from Lambda Emacs - I prefer using the
;; declarative 'elpaca' instead (although it might be cool to have more
;; functions that are written for the native package manager, as I think
;; elpaca was actually developed for this use-case))
(setq package-enable-at-startup nil)

;; Mirror debugging output to the terminal
(when init-file-debug               ; true only with --debug-init
  ;; Echo every message to the terminal
  (advice-add 'message :after
              (lambda (fmt &rest args)
                (when fmt
                  (princ (concat (apply #'format-message fmt args) "\n")
                         #'external-debugging-output))))
  ;; Print backtraces to the terminal instead of opening the debugger
  (setq debug-on-error t
        debugger (lambda (&rest _)
                   (let ((standard-output #'external-debugging-output))
                     (backtrace)))))

;; This should be written as an if statement so that if you're not using the
;; terminal to launch Emacs you can still get a *Backtrace* buffer if you get
;; something wrong.

;;;; Speed up startup
;; Help speed up emacs initialization See
;; https://blog.d46.us/advanced-emacs-startup/ and
;; http://tvraman.github.io/emacspeak/blog/emacs-start-speed-up.html and
;; https://www.reddit.com/r/emacs/comments/3kqt6e/2_easy_little_known_steps_to_speed_up_emacs_start/
;; This will be set back to normal at the end of the init file

(defvar sp-file-name-handler-alist file-name-handler-alist)
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
        
        ;; Don't let scratch buffer message
        initial-scratch-message nil)

;; And set these to nil so users don't have to toggle the modes twice to
;; reactivate them. Guarded so `--without-x' builds (no toolkit)
;; don't error on unbound minor-mode functions.
(when (fboundp 'tool-bar-mode)   (setopt tool-bar-mode nil))
(when (fboundp 'scroll-bar-mode) (setopt scroll-bar-mode nil))
(when (fboundp 'horizontal-scroll-bar-mode) (setopt horizontal-scroll-bar-mode nil))

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

;; Customize must never write to `init.el'. Every setting that used to live in
;; its `custom-set-variables'/`custom-set-faces' blocks is now hard-coded in the
;; module that owns it, so this file is deliberately never loaded: it is only
;; where Customize saves experiments to, until they are moved into a module.
(setq custom-file (expand-file-name "custom.el" sp-etc-dir))

;; The default config from Lambda Emacs (lem-default-config) and the 
;; Makefile that would generate it hav been deprecated

;;;; User Configuration Variables

;; Define customization group for Lambda Emacs.
(defgroup sia-lambda '()
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

;; These next two variables are both optional, but may be convenient.
;; They are used with the functions `sp-goto-projects' and `sp-goto-elisp-library'.

;; Set user project directory
(defcustom sp-project-dir nil "Set the directory for user projects."
  :group 'sia-lambda
  :type 'string)

;; Set user elisp project dir
(defcustom sp-user-elisp-dir t
  "Directory for personal elisp projects.
Any customized libraries not available via standard package repos like elpa or melpa should go here."
  :group 'sia-lambda
  :type 'string)

;; Elpaca bootstrapping has been moved to init.el, since that's where it's supposed to actually live
;; see also the result of the convo with Claude 2026.10.07

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

;; Recurse into the library dir. This must run AFTER the directories are
;; created above, and is guarded because listing a missing directory errors.
(when (file-directory-p sp-library-dir)
  (let ((default-directory sp-library-dir))
    (normal-top-level-add-to-load-path '("."))
    (normal-top-level-add-subdirs-to-load-path)))

;; Restoring the variables so the switch in ~init.el~ is actually able to load 
;; the different kinds of Emacs configurations.
(defcustom sp-headless-host nil "Skip GUI-only modules." :type 'boolean :group 'sia-lambda)
(defcustom sp-load-extras t "Load external-package configuration." :type 'boolean :group 'sia-lambda)

(defconst sp-gui-only-set '(sp-gui sp-macos sp-splash lem-dashboard)
  "Modules that are meaningless without a graphic display.")  ; adjust to your real names
(defun lem-gui-only-modules () sp-gui-only-set)

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

;; If you want to do serious debugging, you can leave this line commented, to get to see everything in the
;; terminal outout, as needed
(setq warning-minimum-level :error) 

;;;; Check Errors
;; Don't produce backtraces when errors occur.
;; This can be set to `t' interactively when debugging.
(setopt debug-on-error init-file-debug) ;; don't set it to `t`, otherwise it 
;; interefers with the init process from Elpaca later on, in the init.el. Read, 
;; also, the explanation from Claude for this problem.
;; Debugging on error would mostly be turned off when launching Emacs normally, 
;; because the window behavior is insufferable. I need to find a better way to 
;; make the debug window pop up when it's actually needed.

;; Keep Elpaca's repos and builds under var/ (replaces `package-user-dir').
;; The installer in init.el uses `defvar', so this value is respected.
(defvar elpaca-directory (expand-file-name "elpaca/" sp-var-dir))

;; Making it possible to load Emacs with a switch on or off from the CLI
(defun sp-cli-profile-switch (name)
  "Return non-nil if switch NAME was given; register it so Emacs ignores it."
  (when (member name command-line-args)
    (push (cons name #'ignore) command-switch-alist)
    t))

(when (sp-cli-profile-switch "--headless-host") (setq sp-headless-host t))
(when (sp-cli-profile-switch "--no-extras")     (setq sp-load-extras nil))

;; early-init.el ends here.