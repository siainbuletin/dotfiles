;; -*- lexical-binding: t; -*-

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

(elpaca-wait)

;; Configuring the load-path

(let* ((base-dir (file-name-parent-directory (file-name-directory (or load-file-name buffer-file-name))))
       (packages-dir (expand-file-name "packages" base-dir)))
  (when (file-directory-p packages-dir)
    (add-to-list 'load-path packages-dir)))

;; Personal attempts from 30 september

;; (add-to-list 'load-path (expand-file-name "site-lisp" user-emacs-directory))

;; (let ((site-lisp (expand-file-name "site-lisp/" user-lisp-directory)))
;;  (when (file-directory-p site-lisp)
;;     (add-to-list 'load-path site-lisp)
;;     (dolist (dir (directory-files-recursively site-lisp ".*" t))
;;       (when (file-directory-p dir)
;;        (add-to-list 'load-path dir)))))

;; Set up the load-path
;; (let (base "~/.config/emacs-include/site-lisp/"))
;; (add-to-list 'load-path base)
;;   (dolist (f (directory-files base))
;;   (let ((name (concat base "/" f)))
;;    (when (and (file-directory-p name)
;;      (not (equal f ".."))
;;      (not (equal f ".")))
;;      (add-to-list 'load-path name))))

;; (let ((dir "~/.config/emacs-include/site-lisp/"))
;;  (dolist (file (directory-files-recursively dir "\\.el\\'"))
;;    (add-to-list 'load-path (file-name-directory file))
;;    (load (file-name-sans-extension file))))
