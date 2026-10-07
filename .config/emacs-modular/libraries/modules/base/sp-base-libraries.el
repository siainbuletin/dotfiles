;; -*- lexical-binding: t -*-
;; sp-base-libraries.el 

;;; Commentary:

;; This is mostly taken from lem-setup-libraries.el because they're very basic libraries
;; used for asynchronous processing string
;; manipulation, list manipulation and backward compatibility respectively.

;;; Code:

;; Built in libraries; lots of packages depend on these
(use-package subr-x
  :ensure nil
  :defer 1)

(use-package cl-lib
  :ensure nil
  :defer t)

;; Include this only for compatibility purposes
(use-package cl
  :ensure nil
  :defer t)

;; Asynchronous commands. Adds the ability to call asynchronous functions and
;; process with ease. See the documentation for `async-start' and
;; `async-start-process'.

(use-package async
  :ensure t
  :after dired
  :config
  (dired-async-mode 1)
  (setq dired-async--modeline-mode nil))

;; A modern list API for Emacs. No 'cl required.

(use-package dash
  :ensure t
  :defer 2)

;; String manipulation
(use-package s
  :ensure t
  :defer 2)

;; APIs for files & directories
(use-package f
  :ensure t
  :defer 2)

;; Other base libraries (sia)

;; This is for rendering basic menus as faithfully as possible

(use-package cond-let
  :ensure (:wait t))

(use-package transient
  :ensure t
  :commands (transient-setup transient-show transient-help)
  
  :custom
  (transient-levels-file (concat sp-cache-dir "transient/levels.el"))
  (transient-values-file (concat sp-cache-dir "transient/values.el"))
  (transient-history-file (concat sp-cache-dir "transient/history.el"))
  (transient-detect-key-conflicts t)
  (transient-force-fixed-pitch t)
  (transient-show-popup t)

  ;; set transient popop to top of window
  (transient-display-buffer-action '(display-buffer-in-side-window
                                     (side . top)
                                     (dedicated . t)
                                     (inhibit-same-window . t)
                                     (window-parameters (no-other-window . t)))))


;;;; CRUX
;; This is loading the library of default functions coming from Emacs Prelude. Lots
;; of useful defaults that you can start working in Emacs with.
;;
;; Crux bundles many useful interactive commands to enhance your overall Emacs 
;; experience. 

(use-package crux
  :ensure t
  :if (and sp-load-extras (locate-library "crux"))
  :defer 1
  :bind
  ("C-k"   . crux-smart-kill-line)
  ("C-a"   . crux-move-beginning-of-line))

(use-package websocket
  :ensure (:wait t)
)

(use-package helm
    :ensure (:wait t))

(use-package taxy
  :ensure t)

;; Other settings I don't know what to do with
;; This is the configuration that I need in order to make my tangling work.
;; Also, the code should appear to be referenced elsewhere on the system.

(defun sia-execute-all-buffers ()
  (interactive)
  (let ((org-confirm-babel-evaluate nil))
    (org-babel-execute-buffer))
)

(keymap-global-set "C-c o o" 'org-org-export-to-org)
(keymap-global-set "C-c e c" 'sia-execute-all-buffers)

(setq initial-major-mode 'org-mode)

(org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (org . t)
     (R . t))
)

(setq-default cursor-type 'bar) ;; this will make the cursor similar to other text editors

(use-package undo-tree
  :ensure (:wait t)
  :config
  (add-to-list 'undo-tree-incompatible-major-modes #'nxml-mode)
  (global-undo-tree-mode)

  :custom
  (undo-tree-history-directory-alist '(("." . "~/.emacs.d/undo"))))

(use-package vundo
  :ensure (:wait t))

(keymap-global-set "C-c j j" #'join-line)

(electric-pair-mode 1)

(use-package load-dir
  :ensure (:wait t))

(use-package dwim-shell-command
  :ensure t
  :bind (([remap shell-command] . dwim-shell-command)
         :map dired-mode-map
         ([remap dired-do-async-shell-command] . dwim-shell-command)
         ([remap dired-do-shell-command] . dwim-shell-command)
         ([remap dired-smart-shell-command] . dwim-shell-command)))

(use-package try
  :ensure (:wait t))




;;; Buffer functions
(global-auto-revert-mode t) ;; If the file has changed on the disk, then update the buffer as well

;;; Avy
;; Don't remember what Avy was for, but it's a pretty important library to have.
(use-package avy
  :ensure t
  :demand t
  :bind (("C-:" . avy-goto-char)
         ("C-M-:" . avy-goto-char-timer)))

;;; Casual package
;; This is transient-based menus for working with built-in packages, like dired.
(use-package casual
  :ensure t)

(provide 'sp-base-libraries)
;; sp-base-libraries.el ends here.