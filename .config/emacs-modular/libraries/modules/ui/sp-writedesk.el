;;; sp-writedesk.el --- Writing desk: Olivetti and Writeroom -*- lexical-binding: t; -*-

;;; Commentary:

;; This sub-library is called 'writedesk' because it's supposed to set up the space specifically
;; for longform writing within org-mode.

;;; Code:

;; Olivetti makes sure that every org buffer is being wrapped properly.
(use-package olivetti
  :ensure t
  
  :custom
  (olivetti-minimum-body 100)
  (olivetti-body-width 0.8)
  
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

;;; org-view-mode
(use-package org-view-mode
  :ensure t)

;;;; Writeroom
(use-package writeroom-mode
  :ensure t
  :commands (writeroom-mode)

  :config
  (setq writeroom-fullscreen-effect 'maximized)
  (setq writeroom-width 125)
  (setq writeroom-mode-line t)
  (setq writeroom-bottom-divider-width 0)

  ;; better scrolling while writing
  (add-hook 'writeroom-mode-hook #'lem-writing-mode-scroll-settings)
)

;;; Reading mode
;; Inspired by Nicolas Rougier's book-mode (https://github.com/rougier/book-mode,
;; GPL-3.0) and its article example: wide fixed margins and extra line spacing
;; with no fringes.  Only those ideas are used; the code is written for Org here.
(defgroup sp-reading nil
  "Reading mode for long prose buffers."
  :group 'convenience)

(defcustom sp-reading-left-margin 8
  "Left margin of the text, in characters (book-mode: 8)."
  :type 'integer
  :group 'sp-reading)

(defcustom sp-reading-right-margin 6
  "Right margin of the text, in characters (book-mode: 6)."
  :type 'integer
  :group 'sp-reading)

(defcustom sp-reading-line-spacing 1
  "Extra space between lines, as in `line-spacing' (book-mode: 1)."
  :type '(choice integer float)
  :group 'sp-reading)

(defvar-local sp-reading--saved nil
  "Alist of the buffer settings changed by `sp-reading-mode'.")

(defun sp-reading--apply-window (window)
  "Set the margins and fringes of WINDOW for `sp-reading-mode'."
  (set-window-margins window sp-reading-left-margin sp-reading-right-margin)
  (set-window-fringes window 0 0))

(defun sp-reading--refresh ()
  "Apply the margins to every window that shows the current buffer."
  (when sp-reading-mode
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (sp-reading--apply-window window))))

(defun sp-reading--save (var)
  "Remember the local state of VAR so that it can be restored."
  (push (list var (local-variable-p var) (and (boundp var) (symbol-value var)))
        sp-reading--saved))

;;;###autoload
(define-minor-mode sp-reading-mode
  "Toggle a reading layout for long prose in the current buffer.

Sets wide margins, extra line spacing and no fringes, wraps lines at
the window edge and turns `olivetti-mode' off while it is active
(it would fight for the same margins).  Turning the mode off puts
every setting back as it was."
  :lighter " Read"
  (if sp-reading-mode
      (progn
        (setq sp-reading--saved nil)
        (when (boundp 'olivetti-mode)
          (push (list 'olivetti-mode nil olivetti-mode) sp-reading--saved)
          (when olivetti-mode (olivetti-mode -1)))
        (dolist (var '(line-spacing left-margin-width right-margin-width
                       left-fringe-width right-fringe-width
                       word-wrap truncate-lines))
          (sp-reading--save var))
        (push (list 'visual-line-mode nil (bound-and-true-p visual-line-mode))
              sp-reading--saved)
        (setq-local line-spacing sp-reading-line-spacing
                    left-margin-width sp-reading-left-margin
                    right-margin-width sp-reading-right-margin
                    left-fringe-width 0
                    right-fringe-width 0)
        (visual-line-mode 1)
        (add-hook 'window-configuration-change-hook #'sp-reading--refresh nil t)
        (sp-reading--refresh))
    (remove-hook 'window-configuration-change-hook #'sp-reading--refresh t)
    (dolist (entry sp-reading--saved)
      (pcase-let ((`(,var ,local ,value) entry))
        (cond ((eq var 'olivetti-mode)
               (when value (olivetti-mode 1)))
              ((eq var 'visual-line-mode)
               (visual-line-mode (if value 1 -1)))
              (local (set (make-local-variable var) value))
              (t (kill-local-variable var)))))
    (setq sp-reading--saved nil)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (set-window-margins window left-margin-width right-margin-width)
      (set-window-fringes window nil nil))))

(global-set-key (kbd "C-c w r") #'sp-reading-mode)

(provide 'sp-writedesk)
;; sp-writedesk.el ends here.
