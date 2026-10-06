;; -*- lexical-binding: t -*-
;; sp-base-libraries.el 

;; This is mostly taken from lem-setup-libraries.el because they're very basic libraries
;; used for asynchronous processing string
;; manipulation, list manipulation and backward compatibility respectively.

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
(use-package transient
  :ensure t)

;; This is loading the library of default functions coming from Emacs Prelude. Lots
;; of useful defaults that you can start working in Emacs with.
(use-package crux
  :ensure t)

(use-package websocket
  :ensure (:wait t)
)

(use-package helm
    :ensure (:wait t))

(use-package ess
  :ensure t)

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

(use-package cond-let
  :ensure (:wait t))

(use-package keycast
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

;; SOUNDS
(setq ring-bell-function 'ignore) ;; Disable the bell sound

;; BUFFER FUNCTIONS
(global-auto-revert-mode t) ;; If the file has changed on the disk, then update the buffer as well

;; Suppress unnecessary warnings

;; You can set minimum severity level for displaying the warning buffer to :error or :emergency:
;; https://emacs.stackexchange.com/questions/78800/how-to-disable-automatic-appearance-of-warnings-buffer-in-emacs

(setq warning-minimum-level :error)

(provide 'sp-base-libraries)