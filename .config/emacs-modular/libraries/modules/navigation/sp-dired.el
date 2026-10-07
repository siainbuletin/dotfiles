;; -*- lexical-binding: t; -*-
;;; sp-dired.el --- summary

;;; Commentary:

;; Setup code for "navigating" Emacs, in the sense of outlines, goto functions,
;; saving place, recent files, etc.
;; this file is particularly concerned with good settings for dired.

;;; Code:

;;;;; Dired Sidebar
(use-package dired-sidebar
  :when (and sp-load-extras (locate-library "dired-sidebar"))
  :commands (dired-sidebar-toggle-sidebar)
  
  :custom
  ;; Auto-fit width to content
  (dired-sidebar-resize-on-open t)
  (dired-sidebar-width 40)
  
  ;; Set horizontal fitting to only when needed
  (fit-window-to-buffer-horizontally 'only))

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

;;;; Go To Change
;; Easily go to last change
(use-package goto-last-change
  :when (and sp-load-extras (locate-library "goto-last-change"))
  :bind (("C-\"" . #'goto-last-change)))

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


;;;; Personal function for sorting

(defun sia-dired-sort ()
  "Sort dired dir listing in different ways.
Prompt for a choice.
Works in linux, MacOS, Microsoft Windows."
  (interactive)
  (let ((xmenu '(("date" . "-Al -t")
                 ("size" . "-Al -S")
                 ("name" . "-Al ")
                 ("dir" . "-Al --group-directories-first")))
        xsortBy)
    (setq xsortBy (completing-read "Sort by (default date):" xmenu nil t nil nil (caar xmenu)))
    (dired-sort-other (cdr (assoc xsortBy xmenu)))))

;; Set Dired listing switches for more minimalist output
(setq dired-listing-switches "-aghov --group-directories-first")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Provide
(provide 'sp-dired)

;;; sp-dired.el ends here