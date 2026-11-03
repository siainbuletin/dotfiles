;;; sp-terminal.el --- Terminal emulator (eat) -*- lexical-binding: t; -*-

;;; Commentary:

;; This module installs `eat', a terminal emulator written in Emacs Lisp (no
;; native module). `vterm' is deliberately not installed.

;;; Code:

;;;; EAT
(use-package eat
  :ensure t)

(provide 'sp-terminal)
;; sp-terminal.el ends here.
