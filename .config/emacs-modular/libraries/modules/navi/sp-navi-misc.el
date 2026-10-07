;; -*- lexical-binding: t; -*-
;;; sp-dired.el --- summary

;;; Commentary:

;; Other useful functions for navigation.

(defun sp-open-from-home-dir ()
  "When opening a file, start searching at the user's home
directory."
  (setq default-directory "~/"))

(defun sp-auto-follow-symlinks ()
  "When opening a file, always follow symlinks."
  (setq vc-follow-symlinks t))

;;;; Go To Change
;; Easily go to last change
(use-package goto-last-change
  :when (and sp-load-extras (locate-library "goto-last-change"))
  :bind (("C-\"" . #'goto-last-change)))

;;;; Imenu list outline
;; Make a useful outline buffer
;; Binding set to toggle "o"
(use-package imenu-list
  :when (and sp-load-extras (locate-library "imenu-list"))
  :commands (imenu-list-smart-toggle imenu-list-minor-mode)
  
  :config
  (setq imenu-list-focus-after-activation t
        imenu-list-auto-resize t
        imenu-list-position 'right))

;;;; Save place
;; Everyone remember where we parked.
(use-package saveplace
  :ensure nil
  :hook (emacs-startup . save-place-mode)
  :config
  (setq save-place-file (concat sp-cache-dir "saved-places"))
  (setq save-place-forget-unreadable-files nil))
  
;;;; Recent files
;; List recent files
(use-package recentf
  :ensure nil
  :defer 2
  :custom
  (recentf-save-file (concat sp-cache-dir "recentf"))
  (recentf-max-saved-items 500)
  (recentf-max-menu-items 10)
  :config
  (recentf-mode 1))

;;;; Jump in Buffer
(defun lem-jump-in-buffer ()
  "Jump between headlines in buffer using consult"
  (interactive)
  (cond
   ((eq major-mode 'org-mode)
    (call-interactively 'consult-org-heading))
   (t
    (call-interactively 'consult-outline))))
    
(provide 'sp-navi-misc)