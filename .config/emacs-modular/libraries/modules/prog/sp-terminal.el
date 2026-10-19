;; -*- lexical-binding: t; -*-
;; sp-terminal.el --- Terminal emulator settings

;;; Commentary:

;;; Code:

;; Does not work on Windows, but we can just avoid compiling dependencies and using it
;; (if I'm ever forced to use Windows again for work or similar)
(use-package vterm
  :ensure t
  :bind (("C-M-S-x" . siapip/start-vterm)
         :map vterm-mode-map
         ("C-c C-x" . 'vterm--self-insert))

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

;; Vterm counter
(defvar sp-vterm-counter 0
  "Counter to make unique vterm buffers.")
(defun siapip/start-vterm ()
    "Starts a new vterm buffer."
  (interactive)
  (setq sp-vterm-counter (1+ sp-vterm-counter))
  (let ((buffer-name (format "*vterm-%d*" sp-vterm-counter)))
    (vterm buffer-name)))

;;;; EAT
(use-package eat
  :ensure t)

;;; Provide:

(provide 'sp-terminal)
;; sp-terminal.el ends here.
