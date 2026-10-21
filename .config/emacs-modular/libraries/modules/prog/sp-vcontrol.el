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

;;; Provide:

(provide 'sp-vcontrol)
;; sp-vcontrol.el ends here