;; -*- lexical-binding: t; -*-

;; sp-windows.el --- Window setup

;; Appearance
;; WINDOW FUNCTIONS
(setq-default frame-title-format '("␥ %b ␥")) ;; Make the window title to be the buffer name

;; Redrawing the display when there's graphical errors
(global-set-key (kbd "<f6>") 'redraw-display)

;; Window splits
(setq split-width-threshold 120
      split-height-threshold nil)

(use-package balanced-windows
  :ensure (:wait t)
  :config
  (balanced-windows-mode)
)

(modify-all-frames-parameters
 '((right-divider-width . 10)
   (internal-border-width . 10)))

(dolist (face '(window-divider
                window-divider-first-pixel
                window-divider-last-pixel))
  (face-spec-reset-face face)
  (set-face-foreground face (face-attribute 'default :background)))

(set-face-background 'fringe (face-attribute 'default :background))

;; I don't remember what this linking thing actually does
(setq org-link-frame-setup
   '((denote . find-file)
     (vm . vm-visit-folder-other-frame)
     (vm-imap . vm-visit-imap-folder-other-frame)
     (gnus . org-gnus-no-new-news)
     (file . find-file)
     (wl . wl-other-frame)))

(use-package ace-window
  :ensure t
  :demand t

  :custom
  (aw-dispatch-always t)
  (aw-dispatch-when-more-than 0)

  :bind
  (("C-x o" . ace-window)))

(defun transpose-buffers (arg)
  "Transpose the buffers shown in two windows."
  (interactive "p")
  (let ((selector (if (>= arg 0) 'next-window 'previous-window)))
    (while (/= arg 0)
      (let ((this-win (window-buffer))
            (next-win (window-buffer (funcall selector))))
        (set-window-buffer (selected-window) next-win)
        (set-window-buffer (funcall selector) this-win)
        (select-window (funcall selector)))
      (setq arg (if (plusp arg) (1- arg) (1+ arg))))))

(use-package pulsar
  :ensure t
  :custom
  (pulsar-face 'pulsar-generic)
  (pulsar-delay 0.15)

  :bind ("<f8>" . pulsar-pulse-line)

  :config
  (dolist (built-in-function '(recenter-top-bottom move-to-window-line-top-bottom reposition-window
                               bookmark-jump other-window delete-window delete-other-windows
                               forward-page backward-page scroll-up-command scroll-down-command
                               ha-new-window tab-new tab-close tab-next org-next-visible-heading
                               org-previous-visible-heading org-forward-heading-same-level
                               org-backward-heading-same-level outline-backward-same-level
                               outline-forward-same-level outline-next-visible-heading
                               outline-previous-visible-heading outline-up-heading))
    (add-to-list 'pulsar-pulse-functions built-in-function))

  (when (fboundp 'winner-undo)
    (add-to-list 'pulsar-pulse-functions 'winner-undo)
    (add-to-list 'pulsar-pulse-functions 'winner-redo))

  (when (fboundp 'winum-select-window-1)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-1)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-2)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-3)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-4)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-5)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-6)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-7)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-8)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-9))

  (when (fboundp 'aw-delete-window)
    (add-to-list 'pulsar-pulse-functions 'aw-move-window)
    (add-to-list 'pulsar-pulse-functions 'aw-swap-window)
    (add-to-list 'pulsar-pulse-functions 'aw-copy-window)
    (add-to-list 'pulsar-pulse-functions 'aw-split-window-vert)
    (add-to-list 'pulsar-pulse-functions 'aw-split-window-horz)
    (add-to-list 'pulsar-pulse-functions 'aw-split-window-fair)
    (add-to-list 'pulsar-pulse-functions 'aw-delete-window))

  (when (fboundp 'evil-window-right)
    (add-to-list 'pulsar-pulse-functions 'evil-window-right)
    (add-to-list 'pulsar-pulse-functions 'evil-window-left)
    (add-to-list 'pulsar-pulse-functions 'evil-window-up)
    (add-to-list 'pulsar-pulse-functions 'evil-window-down))

  (pulsar-global-mode 1))

;; Function for close buffer and window

(defun close-buffer-and-window ()
  "Close the current buffer and the window it's in."
  (interactive)
  (let ((window (selected-window)))
    (kill-buffer)               ;; Kill the current buffer
    (when (window-live-p window) ;; Check if the window is still live
      (delete-window))))         ;; Delete the window if it exists

(defvar siapip/window-toggle-fullscreen:state nil)
(defun siapip/window-toggle-fullscreen ()
  (interactive)
  (if siapip/window-toggle-fullscreen:state
      (progn
        (winner-undo)
        (setq siapip/window-toggle-fullscreen:state nil))
    (progn
      (delete-other-windows)
      (setq siapip/window-toggle-fullscreen:state t))))
(when (boundp 'winner-mode)
  (winner-mode t))
(global-set-key (kbd "S-<f11>") 'siapip/window-toggle-fullscreen)

(use-package buffer-move
  :bind
  (("C-M-S-<up>"    . buf-move-up)
   ("C-M-S-<down>"  . buf-move-down)
   ("C-M-S-<left>"  . buf-move-left)
   ("C-M-S-<right>" . buf-move-right)))

;; (use-package persp-mode
;;   :ensure t
;;   :demand t
;;   :custom
;;   (wg-morph-on nil)
;;   (persp-autokill-buffer-on-remove 'kill-weak)
;;   (persp-auto-resume-time -1.0)
;;   (persp-emacsclient-init-frame-behaviour-override nil)
;;   (persp-nil-name "main")
;;   :init
;;   (persp-mode t)
;;   :config
;;   (persp-set-keymap-prefix (kbd "C-c P")))

;; (use-package perspective
;;   :ensure t
;;   :bind
;;   ("C-x k" . persp-kill-buffer*) ; this basically replaces the built-in kill buffer command
;;   :custom
;;   (persp-mode-prefix-key (kbd "C-c M-p"))  ; pick your own prefix key here
;;   :init
;;   (persp-mode))

(provide 'sp-windows)