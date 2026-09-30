;; -*- lexical-binding: t; -*-
(defvar siapip/vterm-counter 0
  "Counter to make unique vterm buffers.")
(defun siapip/start-vterm ()
    "Starts a new vterm buffer."
  (interactive)
  (setq siapip/vterm-counter (1+ siapip/vterm-counter))
  (let ((buffer-name (format "*vterm-%d*" siapip/vterm-counter)))
    (vterm buffer-name)))
(use-package vterm
  :ensure t
  :bind (("C-M-S-x" . siapip/start-vterm)
         :map vterm-mode-map
         ("C-c C-x" . 'vterm--self-insert)))
