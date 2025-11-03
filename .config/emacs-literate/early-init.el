;; Most of this configuration is taken from the Lambda Emacs repository.
;; This is published to GitHub solely for my own usage and for ease of
;; synchronisation between different machines.

(setq package-enable-at-startup nil)

(defconst sys-linux   (eq system-type 'gnu/linux))
(defconst sys-mac     (eq system-type 'darwin))
(defconst sys-bsd     (or sys-mac (eq system-type 'berkeley-unix)))
(defconst sys-win     (memq system-type '(cygwin windows-nt ms-dos)))

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

(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.5)

(defvar sia-file-name-handler-alist file-name-handler-alist)
(defvar sia-vc-handled-backends vc-handled-backends)

(setq file-name-handler-alist nil
    vc-handled-backends nil)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 100 100 8)
                  gc-cons-percentage 0.1
                  file-name-handler-alist sia-file-name-handler-alist
                  vc-handled-backends sia-vc-handled-backends)))

(defvar k-gc-timer
(run-with-idle-timer 15 t
                     (lambda ()
                       (let ((inhibit-message t))
                         (message "Garbage Collector has run for %.06fsec"
                                  (k-time (garbage-collect)))))))

(setq frame-resize-pixelwise t
    frame-inhibit-implied-resize 'force)

;; Fundamental mode at startup.
;; This helps with load-time since no extra libraries are loaded.
(setopt initial-major-mode 'fundamental-mode)
