;; -*- lexical-binding: t -*-
;; sp-writedesk.el

;;; Commentary:

;; This sub-library is called 'writedesk' because it's supposed to set up the space specifically
;; for longform writing within org-mode.

;; Olivetti makes sure that every org buffer is being wrapped properly.
(use-package olivetti
  :ensure t
  
  :custom
  (olivetti-minimum-body 100)
  (olivetti-body-width 80)
  
  :bind
  (("C-c w o" . sp-olivetti))
  
  :hook
  (org-mode . olivetti-mode))

;; Distraction-free writing
(defvar sp-olivetti-point nil
  "Stores the point position before enabling Olivetti mode.")

;;;###autoload
(defun sp-olivetti ()
  "Distraction-free writing environment enhancing Olivetti mode.

Stores the window configuration when enabling Olivetti mode.
Restores the previous configuration when existing Olivetti mode
and moves point to the last location."
  (interactive)
  (if olivetti-mode
      (progn
        (if (eq (length (window-list)) 1)
            (progn
              (jump-to-register 1)
              (goto-char sp-olivetti-point)))
        (olivetti-mode 0)
        (text-scale-set 0))
    (progn
      (setq sp-olivetti-point (point))
      (window-configuration-to-register 1)
      (delete-other-windows)
      (text-scale-set 1)
      (olivetti-mode t))))

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