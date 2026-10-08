(defconst lem-emacs-dir (expand-file-name user-emacs-directory)
  "The path to the emacs.d directory.")

(defconst lem-library-dir (concat lem-emacs-dir "lambda-library/")
  "The directory for 𝛌-Emacs Lisp libraries.
This will house all setup libraries and external libraries or packages.")

(defconst lem-user-dir (concat lem-library-dir "lambda-user/")
  "Storage for personal elisp, scripts, and any other private files.")

(defconst lem-setup-dir (concat lem-library-dir "lambda-setup/")
  "The storage location of the setup-init files.")

(defconst lem-var-dir (concat lem-emacs-dir "var/")
  "The directory for non-essential file storage.
Contents are subject to change. Used for package storage (elpa or
straight) and by `lem-etc-dir' and `lem-cache-dir'.")

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

(defconst lem-default-config-file (concat lem-library-dir "lem-default-config.el")
  "A sample default configuration of the personal config file to get the user started.")

;;;; Make System Directories
;; Directory paths
(dolist (dir (list lem-library-dir lem-var-dir lem-etc-dir lem-cache-dir lem-user-dir lem-setup-dir))
  (unless (file-directory-p dir)
    (make-directory dir t)))

;;;; Load Path
;; Add all configuration files to load-path
(eval-and-compile
  (progn
    (push lem-setup-dir load-path)
    (push lem-user-dir load-path)))

;;;; Prefer Newer files
;; Prefer newer versions of files
(setopt load-prefer-newer t)

;;;; Byte Compile Warnings
;; Disable certain byte compiler warnings to cut down on the noise. This is a
;; personal choice and can be removed if you would like to see any and all byte
;; compiler warnings.
;; NOTE: Setopt won't work here
(setq byte-compile-warnings '(not free-vars unresolved noruntime lexical make-local obsolete))


;;;; Bootstrap Package System (Elpaca)
;; Elpaca is bootstrapped from init.el, not here. At the top of init.el, paste
;; the installer snippet from the Elpaca README, then add:
;;
;;   (elpaca elpaca-use-package (elpaca-use-package-mode))
;;   (elpaca-wait)
;;   (lem-install-extras)
;;
;; `elpaca-use-package-mode' makes use-package's `:ensure' go through Elpaca.
;; `elpaca-directory' (defined above) keeps repos and builds under var/.

(defun lem-install-extras ()
  "Queue external packages declared in `lem-packages-alist' with Elpaca.

Does nothing when `lem-load-extras' is nil. On headless hosts
(`sp-headless-host' non-nil) skips topics in
`(lem-gui-only-topics)' so GUI-only packages are not installed.
Each package is queued with `elpaca'; Elpaca processes its queue
asynchronously after init (via `elpaca-process-queues' on
`after-init-hook'), so no daemon-specific deferral is needed.
Call this from init.el after Elpaca has been bootstrapped."
  (cond
   ((not lem-load-extras) nil)
   ((not (fboundp 'elpaca))
    (display-warning 'lambda-emacs
                     "Elpaca is not bootstrapped; skipping `lem-install-extras'."
                     :warning))
   (t
    (let ((gui-only (lem-gui-only-topics)))
      (dolist (entry lem-packages-alist)
        (unless (and sp-headless-host (memq (car entry) gui-only))
          (dolist (pkg (cdr entry))
            ;; `elpaca' is a macro, so build the form for each package.
            (eval `(elpaca ,pkg) t))))))))

;;;; Early Config
;; Check if there is a user early-config file & load. If it doesn't exist, print
;; a message saying so.
(let ((early-config-file (expand-file-name "early-config.el" lem-user-dir)))
  (cond ((file-exists-p early-config-file)
         (measure-time
          (load early-config-file nil 'nomessage))
         (message "early-config.el loaded!"))
        (t
         (message "No user early-config file exists.")
         (message "Loading default settings."))))

;; `lem-install-extras' is called from init.el once Elpaca is bootstrapped
;; (see "Bootstrap Package System" above). It runs after the Early Config block
;; so any override of `lem-load-extras' or `sp-headless-host' set in
;; `early-config.el' is visible to the install loop.

;;; early-init.el ends here
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 ;; NOTE: with Elpaca, git-hosted packages are declared via Elpaca orders
 ;; (e.g. use-package `:ensure' with `:host'/`:repo'), not
 ;; `package-vc-selected-packages'.
 )
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )