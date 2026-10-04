;; -*- lexical-binding: t; -*-

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

;; -*- lexical-binding: t; -*-
(defvar siapip/vterm-counter 0
  "Counter to make unique vterm buffers.")
(defun siapip/start-vterm ()
    "Starts a new vterm buffer."
  (interactive)
  (setq siapip/vterm-counter (1+ siapip/vterm-counter))
  (let ((buffer-name (format "*vterm-%d*" siapip/vterm-counter)))
    (vterm buffer-name)))

