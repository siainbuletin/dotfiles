;; -*- lexical-binding: t -*-
;; sia-base-libraries.el 

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

(provide 'sia-base-libraries)