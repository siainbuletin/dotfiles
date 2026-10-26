;;; sp-mini-frame.el --- Centered minibuffer frame with background dimming -*- lexical-binding: t; -*-

;;; Commentary:

;; This configuration for emacs-mini-frame.el makes sure that the minibuffer is being
;; dimmed and centered when I'm looking for a particular file, or wanting to insert a
;; link. Inserting should still be placed somewhere in the bottom, so it can follow what
;; I'm writing in the current buffer without interrupting the focus on screen

;;; Code:

;;;; Create mini frame for the buffer

(require 'color) ;; why is color needed? what is this package?

(use-package mini-frame
  :ensure t
  
  :custom
  (mini-frame-show-parameters
   '((left . 0.5)    ; float = fraction of the free space, so 0.5 centers horizontally
     (top . 0.5)     ; ... and vertically
     (width . 0.6)   ; keeps the frame from taking the full width for vertical completion
     (height . 17)   ; the prompt and `vertico-count' (13) candidates, in lines made taller by
                     ; the larger minibuffer text (`sp-minibuffer'); fixed, never resized
     (child-frame-border-width . 4) ; padding around the text
     (internal-border-width . 4)))
  (mini-frame-resize 'not-set) ; keep the fixed height above; resizing hung Emacs on macOS

  :config
  (mini-frame-mode 1)
)

;;;; Dimming, only for selected commands

(defvar sp-mini-frame-dim-commands '(find-file vulpea-find org-node-find)
  "Commands whose minibuffer should dim the underlying frame.")

(defvar sp-mini-frame-dim-amount 0.45
  "How far to blend text colors toward the background (0 = none, 1 = invisible).")

(defvar-local sp-mini-frame--dim-cookies nil)
(defvar sp-mini-frame--dimmed-buffers nil)

(defun sp-mini-frame--blend (fg bg amount)
  (let ((f (and (stringp fg) (color-name-to-rgb fg)))
        (b (and (stringp bg) (color-name-to-rgb bg))))
    (when (and f b)
      (apply #'color-rgb-to-hex
             (append (color-blend f b amount) '(2))))))

(defun sp-mini-frame-dim (frame)
  "Dim all text in the buffers shown in FRAME."
  (let ((bg (face-background 'default frame)))
    (dolist (buf (delete-dups
                  (mapcar #'window-buffer (window-list frame 'no-minibuf))))
      (with-current-buffer buf
        (unless sp-mini-frame--dim-cookies
          (dolist (face (face-list))
            (let* ((fg (face-attribute face :foreground frame))
                   (dim (and (not (eq fg 'unspecified))
                             (sp-mini-frame--blend fg bg sp-mini-frame-dim-amount))))
              (when dim
                (push (face-remap-add-relative face :foreground dim)
                      sp-mini-frame--dim-cookies))))
          (push buf sp-mini-frame--dimmed-buffers))))))

(defun sp-mini-frame-undim ()
  (dolist (buf sp-mini-frame--dimmed-buffers)
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (mapc #'face-remap-remove-relative sp-mini-frame--dim-cookies)
        (setq sp-mini-frame--dim-cookies nil))))
  (setq sp-mini-frame--dimmed-buffers nil))

(defun sp-mini-frame--maybe-dim ()
  (when (and (bound-and-true-p mini-frame-mode)
             (memq this-command sp-mini-frame-dim-commands)
             (minibuffer-selected-window))
    (sp-mini-frame-dim (window-frame (minibuffer-selected-window)))))

(add-hook 'minibuffer-setup-hook #'sp-mini-frame--maybe-dim)
(add-hook 'minibuffer-exit-hook #'sp-mini-frame-undim)

(provide 'sp-mini-frame)
;; sp-mini-frame.el ends here.
