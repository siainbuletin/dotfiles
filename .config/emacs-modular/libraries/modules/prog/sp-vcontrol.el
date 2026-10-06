;; -*- lexical-binding: t; -*-
;; sp-vcontrol.el

(use-package magit
  :ensure t
  :defer t
  :after transient
  :bind
  (("C-M-g" . magit))
  :custom
  (magit-bury-buffer-function 'magit-restore-window-configuration))

;; YADM is theoretically used for dotfile management.
;; I haven't yet been able to do anything with that within Emacs.
(defun yadm ()
  (interactive)
  (magit-status "/yadm::"))

(provide 'sp-vcontrol)
;; sp-vcontrol.el ends here