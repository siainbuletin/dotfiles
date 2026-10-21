;; -*- lexical-binding: t; -*-
;; sp-vcontrol.el

;;; Commentary:

;;; Code:
;;;; Magit initial installation
(use-package magit
  :ensure t
  :defer t
  :after transient
  :bind
  (("C-M-g" . magit))
  :custom
  (magit-bury-buffer-function 'magit-restore-window-configuration))

;;;; YADM function to be able to work with dotfiles
(defun yadm ()
  (interactive)
  (magit-status "~/"))

;;; Forge settings
(use-package forge
  :after magit)

(setq auth-sources '("~/.authinfo"))

;; code review harness
(use-package code-review
  :ensure t
  
  :custom
  (code-review-fill-column 80) ;; Define line wrap in comment sections.
  (code-review-new-buffer-window-strategy #'switch-to-buffer) ;; Change how code-review splits the buffer when opening a new PR. Defaults to #'switch-to-buffer-other-window.
  (setq code-review-download-dir "/tmp/code-review/") ;; Change the destination where binary files is downloaded.
)

;;; For adding emojis
(add-hook 'code-review-mode-hook #'emojify-mode)

;;; Provide:

(provide 'sp-vcontrol)
;; sp-vcontrol.el ends here