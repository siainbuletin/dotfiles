;; Most of this configuration is taken from the Lambda Emacs repository.
;; This is published to GitHub solely for my own usage and for ease of
;; synchronisation between different machines.

;; Speeding up the stratup

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

;;;;;;;;;;;;;;;;;;;;;;;;
;; GARBAGE COLLECTION ;;
;;;;;;;;;;;;;;;;;;;;;;;;

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

;; When idle for 15sec run the garbage collection no matter what.
(defvar k-gc-timer
  (run-with-idle-timer 15 t
                       (lambda ()
                         (let ((inhibit-message t))
                           (message "Garbage Collector has run for %.06fsec"
                                    (k-time (garbage-collect)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; IMPROVING THE INITIAL VIEW ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Fundamental mode at startup.
;; This helps with load-time since no extra libraries are loaded.
(setopt initial-major-mode 'fundamental-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CHECKING WHAT SYSTEM YOU'RE USING ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst sys-linux   (eq system-type 'gnu/linux))
(defconst sys-mac     (eq system-type 'darwin))
(defconst sys-bsd     (or sys-mac (eq system-type 'berkeley-unix)))
(defconst sys-win     (memq system-type '(cygwin windows-nt ms-dos)))

;;;;;;;;;;;;;;;;;;;;;;;;;
;; DIRECTORY VARIABLES ;;
;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst lem-emacs-dir (expand-file-name user-name-directory) "The path to the default emacs.d directory.")

(defconst lem-library-dir (concat lem-emacs-dir "lambda-library/") "This is the directory where lambda-emacs lisp libraries will live. This houses all setup libraries or external libraries/packages.")
(defconst lem-user-dir (concat lem-library-dir "lambda-user/") "Storage for personal elisp, scrips and other private files for the user.")
(defconst lem-setup-dir (concat lem-library-dir "lambda-setup/") "This will be the storage location for the setup-init files.")

(defconst lem-var-dir (concat lem-emacs-dir "var/") "The directory is meant for any kind of non-essential file storage. This can be used for package storage (from ELPA or straight) and by `lem-etc-dir` and `lem-cache-dir`.")

(defconst lem-etc-dir (concat lem-var-dir "etc/")
  "The directory for non-volatile storage.
  These are not deleted or tampered with by emacs functions. Use
  this for dependencies like servers or config files that are
  stable (i.e. it should be unlikely that you need to delete them
               if something goes wrong).")

(defconst lem-cache-dir (concat lem-var-dir "cache/")
  "The directory for volatile storage.
  Use this for transient files that are generated on the fly like
  caches and ephemeral/temporary files. Anything that may need to
  be cleared if there are problems.")

;; Finding the user configuration file
(defconst lem-config-file (expand-file-name "config.el" lem-user-dir) "This user's configuration file.")

;; MAKING THE SYSTEM DIRECTORIES
;; Directory paths
(dolist
    (dir (list lem-library-dir lem-var-dir lem-etc-dir lem-cache-dir lem-user-dir lem-setup-dir))
  (unless (file-directory-p dir)
    (make-directory dir t))
  )

;; Adding all the configuration files to the load-path
(eval-and-compile
  (progn
    (push lem-setup-dir load-path)
    (push lem-user-dir load-path)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CHECKING FOR THE EXISTENCE OF AN EARLY CONFIG ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; If the file doesn't exist, print a message saying so.
(let ((early-config-file (expand-file-name "early-config.el" lem-user-dir)))
  (cond ((file-exists-p early-config-file)
         (measure-time
          (load early-config-file nil 'nomessage))
         (message "early-config.el loaded!"))
        (t
         (message "No user early-config file exists.")
         (message "Loading default settings."))))
