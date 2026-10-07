;; -*- lexical-binding: t -*-
;; lem-dashboard.el

;;; Commentary:

;; This is the slightly modified version of Lambda dashboard (adapted for my
;; own readability within the code).
;;
;; In the original setup I had these elpaca hooks that I don't know what
;; to do with now, but I probably need to read more about how hooks work.
;;
;; See the ~emacs-include~ configuration for the dashboard to figure out
;; how it works.

;;; Code:

;;;; Dependencies
;; Load dependencies from Lambda-Emacs. Note these packages are usually deferred
;; but they must be loaded with dashboard since it requires icons.
(when (locate-library "nerd-icons")
  (require 'nerd-icons))

;; dashboard dependency
(use-package page-break-lines
  :if (and sp-load-extras (locate-library "page-break-lines"))
  :defer t
  :config
  (set-fontset-font "fontset-default"
                    (cons page-break-lines-char page-break-lines-char)
                    (face-attribute 'default :family)))

;;;; Dashboard

;; Collapsed from two separate :if keys (use-package silently
;; dropped the first). Adds sp-load-extras gate and
;; locate-library check on nerd-icons, which :custom
;; references via (nerd-icons-sucicon ...).

(use-package dashboard
  :ensure t
  :if (and sp-load-extras
             (locate-library "dashboard")
             (locate-library "nerd-icons")
             (display-graphic-p)
             (< (length command-line-args) 2))

  :custom
  ;; Set info & center
  (dashboard-set-init-info t)
  (dashboard-center-content t)
    
  ;; Set project backend
  (dashboard-projects-backend 'project-el) ;; Can this also be used with projectile?

  :config
  (add-hook 'elpaca-after-init-hook #'lem-dashboard)
  (add-hook 'dashboard-mode-hook #'lem-dashboard-hide-modeline)
  (add-hook 'elpaca-after-init-hook #'dashboard-insert-startupify-lists)
  (add-hook 'elpaca-after-init-hook #'dashboard-initialize)

  :bind
  ("C-c d d" . dashboard-open))

;;; Cosmetics for the bar

(setq dashboard-vertically-center-content t)

;;;; Header
(setq dashboard-startup-banner (concat sp-library-dir
                                  (if (eq (car custom-enabled-themes) 'lambda-dark)
                                      "lambda-logo-white.png"
                                   "lambda-logo-black.png")))

;; this if loop makes it easy to just choose between the different versons without
;; overcomplicating the color scheme that is being chosen

;;;;; Banner
(setq dashboard-banner-logo-title "Welcome to Emacs!")
(setq dashboard-startup-banner '3)
(setq dashboard-image-banner-max-width 200)
(setq dashboard-image-banner-max-height 200)

;;;; Footer
(setq dashboard-set-footer t)            
(setq dashboard-icon-type 'nerd-icons)   ;; Tell dashboard to use the nerd-icons backend for heading/file icons.
;; (setq dashboard-footer-icon (nerd-icons-sucicon "nf-custom-emacs"
;;                                           :height 1
;;                                           :v-adjust -0.15
;;                                           :face 'font-lock-constant-face))
;; for some reason, nerd-icons-sucicon errors out.

;;;; Add icons
(setq dashboard-set-heading-icons t)
(setq dashboard-set-file-icons t)

;;; Dashboard items
(setq dashboard-items '((recents   . 5)
                        (bookmarks . 5)
                        (agenda    . 7)
                        (registers . 5)))

;;; Shortcuts for reaching the elements
(setq dashboard-show-shortcuts t)

(setq dashboard-item-shortcuts '((recents   . "r")
                                 (bookmarks . "b")
                                 (agenda    . "a")
                                 (registers . "e")))

;;;; Dashboard Functions
;; Hide modeline
;; this makes the dashboard a little bit cleaner
;; but the important stuff that shows up in the modeline should somehow be supplemented by the dashboard
;; this can also be held up by the fact that the minibuffer shows up at the top instead of the bottom
(defun lem-dashboard-hide-modeline ()
  "Hide modeline in the dashboard buffer."
  (let* ((dash-buffer (get-buffer "*dashboard*")))
    (with-current-buffer dash-buffer
      (hl-line-mode -1)
      (setq-local mode-line-format nil)
      (setq-local header-line-format nil))))

;; Functions to call dashboard when it kas been killed or not loaded
(defun lem-dashboard ()
  "Load dashboard and swith to buffer."
  (interactive)
  (let ((buffer "*dashboard*"))
    (when (not (get-buffer buffer))
      (dashboard-insert-startupify-lists))
    (switch-to-buffer buffer))
  (delete-other-windows))

(defun sp-goto-dashboard ()
  "Goto the dashboard."
  (interactive)
  (switch-to-buffer "*dashboard*"))

;;; Provide:

(provide 'lem-dashboard)
;; lem-dashboard.el ends here.