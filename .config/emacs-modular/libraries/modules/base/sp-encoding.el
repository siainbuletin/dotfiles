;; -*- lexical-binding: t; -*-
;; sp-encoding.el

;;; Code:

(set-default-coding-systems 'utf-8)     ; Default to utf-8 encoding
(prefer-coding-system       'utf-8)     ; Add utf-8 at the front for automatic detection.
(set-terminal-coding-system 'utf-8)     ; Set coding system of terminal output
(set-keyboard-coding-system 'utf-8)     ; Set coding system for keyboard input on TERMINAL
(set-language-environment "English")    ; Set up multilingual environment
(setq default-buffer-file-coding-system 'utf-8)

;;; Provide:

(provide 'sp-encoding)
;; sp-encoding.el ends here.