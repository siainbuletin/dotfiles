;;; sp-mini-frame.el --- Centered minibuffer frame with background dimming -*- lexical-binding: t; -*-

;;; Commentary:

;; This configuration for emacs-mini-frame.el makes sure that the minibuffer is being
;; dimmed and centered when I'm looking for a particular file, or wanting to insert a
;; link. Inserting should still be placed somewhere in the bottom, so it can follow what
;; I'm writing in the current buffer without interrupting the focus on screen

;;; Code:

;;;; Create mini frame for the buffer

(require 'color) ;; why is color needed? what is this package?

(defcustom sp-mini-frame-nano-commands
  '(execute-extended-command amx counsel-M-x smex)
  "Commands whose prompt is shown at the bottom, in nano's style."
  :type '(repeat function)
  :group 'minibuffer)

(defcustom sp-mini-frame-nano-contrast 0.08
  "How far the nano-style frame background moves from the default background toward the foreground (0 to 1)."
  :type 'number
  :group 'minibuffer)

(defun sp-mini-frame--nano-background ()
  "Return a background slightly off the default one, from the current theme."
  (let ((bg (face-background 'default nil t))
        (fg (face-foreground 'default nil t)))
    (or (and (fboundp 'color-blend)
             (sp-mini-frame--blend bg fg sp-mini-frame-nano-contrast))
        (face-background 'mode-line-inactive nil t)
        bg)))

(defun sp-mini-frame-parameters ()
  "Return the frame parameters for the prompt of `this-command'."
  (if (memq this-command sp-mini-frame-nano-commands)
      `((left . 0.5)
        (top . 1.0)
        (width . 1.0)
        (height . 5)
        (left-fringe . 12)
        (right-fringe . 12)
        (child-frame-border-width . 0)
        (internal-border-width . 0)
        (foreground-color . ,(face-foreground 'default nil t))
        (background-color . ,(sp-mini-frame--nano-background)))
    '((left . 0.5)    ; float = fraction of the parent frame, so 0.5 centers horizontally
      (top . 0.4)     ; 0.5 is dead center for a one-line frame; slightly higher leaves
                      ; room for the candidate list to grow downward
      (width . 0.6)   ;; By adjusting the width, you're making sure that the minim-frame doesn't
                      ;; occupy the full width for vertical minibuffer completion
      (child-frame-border-width . 2)
      (internal-border-width . 2))))

(defun sp-mini-frame--nano-spacer ()
  "Put a half-height blank line above the prompt of the nano-style frame."
  (when (memq this-command sp-mini-frame-nano-commands)
    (overlay-put (make-overlay (point-min) (1+ (point-min)))
                 'before-string
                 (propertize "\n" 'face '(:extend t :height 0.5)))))

(add-hook 'minibuffer-setup-hook #'sp-mini-frame--nano-spacer)

(use-package mini-frame
  :ensure t
  
  :custom
  (mini-frame-show-parameters #'sp-mini-frame-parameters)
  (mini-frame-resize 'not-set) ; this leaves resizing to Emacs to do the job

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
