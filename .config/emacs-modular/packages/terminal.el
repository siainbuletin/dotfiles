;; -*- lexical-binding: t; -*-

;; Does not work on Windows, but we can just avoid compiling dependencies and using it
;; (if I'm ever forced to use Windows again for work or similar)
(use-package vterm
  :commands vterm
  :custom
  (vterm-always-compile-module t)
  :hook
  (vterm-mode . (lambda ()
                  ;; Settings to mimic dracula I use for zsh.
                  (setq-local buffer-face-mode-face '(:background "#000000" :foreground "#FFFFFF"))
                  (buffer-face-mode 1)
                  (text-scale-adjust 2)))
  :bind
  ("<f7>" . vterm))