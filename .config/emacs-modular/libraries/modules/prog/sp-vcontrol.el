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

(defun yadm ()
  (interactive)
  (magit-status "/yadm::"))


(provide 'sp-vcontrol)
;; sp-vcontrol.el ends here