;; -*- lexical-binding: t -*-
;; sp-writedesk.el

;;; Commentary:

;; This sub-library is called 'writedesk' because it's supposed to set up the space specifically
;; for longform writing within org-mode.

;;;; Writeroom
(use-package writeroom-mode
  :when (and sp-load-extras (locate-library "writeroom-mode"))
  :commands (writeroom-mode)
  :config
  ;; (setq writeroom-fullscreen-effect 'maximized)
  (setq writeroom-width 95)
  (setq writeroom-mode-line t)
  (setq writeroom-bottom-divider-width 0)
  ;; better scrolling while writing
  (add-hook 'writeroom-mode-hook #'lem-writing-mode-scroll-settings))

(defun lem-writing-mode-scroll-settings ()
  "Center cursor for typewriter-like scrolling during writing."
  (progn
    (setq-local scroll-preserve-screen-position t
                scroll-conservatively 0
                maximum-scroll-margin 0.25
                scroll-margin 99999)))

(provide 'sp-writedesk)
;; sp-writedesk.el ends here.