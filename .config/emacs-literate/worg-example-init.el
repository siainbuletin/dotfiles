;; Load up Org Mode and (now included) Org Babel for elisp embedded in Org Mode files
(setq dotfiles-dir (file-name-directory (or (buffer-file-name) load-file-name)))

;; load up Org and Org-babel
(require 'org)
(require 'ob-tangle)

;; load up all literate org-mode files in this directory
(mapc #'org-babel-load-file (directory-files dotfiles-dir t "\\.org$"))

(let* ((dotfile-dir (file-name-directory (or (buffer-file-name)
  				     load-file-name)))
     ;; disabled
     ;; (etc-dir   (expand-file-name "etc" dotfile-dir))
     ;; (etc-files (directory-files etc-dir t "\\.org$"))
     (config-org  (expand-file-name "README.org" dotfile-dir))
     (config-el   (expand-file-name "README.el"  dotfile-dir)))
(require 'org)
(require 'ob-tangle)

;;tangle and load if newer than compiled
(if (or (not (file-exists-p config-el))
        (file-newer-than-file-p config-org config-el))
    (org-babel-load-file config-org t)
  (load-file config-el)))

;; This file has been generated from an org-mode file (=dotemacs.org=), DO NOT EDIT DIRECTLY, IT WILL BE OVERWRITTEN

;;; PACKAGE MANAGEMENT

;; Bootstrapping straight.el
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name
        "straight/repos/straight.el/bootstrap.el"
        (or (bound-and-true-p straight-base-dir)
            user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; Declaring use-package
(straight-use-package 'use-package)

(use-package straight
  :custom
  (straight-use-package-by-default t))
