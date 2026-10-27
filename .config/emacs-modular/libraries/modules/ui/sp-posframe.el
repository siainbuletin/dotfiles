;;; sp-posframe.el --- Centered minibuffer in a posframe with background dimming -*- lexical-binding: t; -*-

;;; Commentary:

;; This configuration for vertico-posframe makes sure that the minibuffer is being
;; dimmed and centered when I'm looking for a particular file, or wanting to insert a
;; link. Inserting should still be placed somewhere in the bottom, so it can follow what
;; I'm writing in the current buffer without interrupting the focus on screen

;;; Code:

;;;; Show the minibuffer in a centered frame

(require 'color) ;; why is color needed? what is this package?

(use-package vertico-posframe
  :ensure t
  :after vertico

  :custom
  (vertico-posframe-poshandler #'posframe-poshandler-frame-center) ; centered both ways
  (vertico-posframe-min-width 80)    ; wide enough for notes and their tags
  (vertico-posframe-border-width 4)  ; padding around the text
  (vertico-posframe-fallback-mode 'vertico-buffer-mode) ; terminals have no child frames
  ;; `vertico-count' (13) sets the number of candidates; the frame fits them.

  :config
  (vertico-posframe-mode 1)
)

;;;; Dimming, only for selected commands

(defvar sp-posframe-dim-commands '(find-file vulpea-find org-node-find)
  "Commands whose minibuffer should dim the underlying frame.")

(defvar sp-posframe-dim-amount 0.45
  "How far to blend text colors toward the background (0 = none, 1 = invisible).")

(defvar-local sp-posframe--dim-cookies nil)
(defvar sp-posframe--dimmed-buffers nil)

(defun sp-posframe--blend (fg bg amount)
  (let ((f (and (stringp fg) (color-name-to-rgb fg)))
        (b (and (stringp bg) (color-name-to-rgb bg))))
    (when (and f b)
      (apply #'color-rgb-to-hex
             (append (color-blend f b amount) '(2))))))

(defun sp-posframe-dim (frame)
  "Dim all text in the buffers shown in FRAME."
  (let ((bg (face-background 'default frame)))
    (dolist (buf (delete-dups
                  (mapcar #'window-buffer (window-list frame 'no-minibuf))))
      (with-current-buffer buf
        (unless sp-posframe--dim-cookies
          (dolist (face (face-list))
            (let* ((fg (face-attribute face :foreground frame))
                   (dim (and (not (eq fg 'unspecified))
                             (sp-posframe--blend fg bg sp-posframe-dim-amount))))
              (when dim
                (push (face-remap-add-relative face :foreground dim)
                      sp-posframe--dim-cookies))))
          (push buf sp-posframe--dimmed-buffers))))))

(defun sp-posframe-undim ()
  (dolist (buf sp-posframe--dimmed-buffers)
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (mapc #'face-remap-remove-relative sp-posframe--dim-cookies)
        (setq sp-posframe--dim-cookies nil))))
  (setq sp-posframe--dimmed-buffers nil))

(defun sp-posframe--maybe-dim ()
  (when (and (bound-and-true-p vertico-posframe-mode)
             (memq this-command sp-posframe-dim-commands)
             (minibuffer-selected-window))
    (sp-posframe-dim (window-frame (minibuffer-selected-window)))))

(add-hook 'minibuffer-setup-hook #'sp-posframe--maybe-dim)
(add-hook 'minibuffer-exit-hook #'sp-posframe-undim)

(provide 'sp-posframe)
;; sp-posframe.el ends here.
