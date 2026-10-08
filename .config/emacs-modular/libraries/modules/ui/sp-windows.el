;; -*- lexical-binding: t; -*-
;; sp-windows.el --- Window setup

;;; Commentary:

;; This sub-library deals specifically with the issues of Windows in Emacs
;; (frames should be treated separately). 
;;
;; Eventually, the entire graphical environment and where information gets
;; placed should be moved to a larger file regarding window management,
;; and it should include controls for a daemonized Emacs which runs on a
;; tiling window manager under Linux.

;;; Code:

;;;; Appearance


;;;; Moving windows around
;; TODO: this has to be configured better.

;; This is a fun set of new commands for rearranging your window layout
;; without manually splitting and killing windows:

(keymap-global-set "C-x w t" #'window-layout-transpose)        ; EMACS-31
(keymap-global-set "C-x w r" #'window-layout-rotate-clockwise) ; EMACS-31
(keymap-global-set "C-x w f h" #'window-layout-flip-leftright)   ; EMACS-31
(keymap-global-set "C-x w f v" #'window-layout-flip-topdown)     ; EMACS-31

;; Transpose swaps your horizontal and vertical arrangement, rotate spins
;; the whole layout around, and the flip commands mirror it left-to-right
;; or top-to-bottom. If you've ever built a three-window layout and then 
;; wished the editor pane were on the other side, these do the job and 
;; keep every buffer in place while they're at it.

;; Window splits
(setq split-width-threshold 120
      split-height-threshold nil)

;;;; Packages for managing windows

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

;;;; Dim inactive windows
(use-package dimmer
  :when (and sp-load-extras (locate-library "dimmer"))
  :hook (after-init . dimmer-mode)
  :custom
  (dimmer-prevent-dimming-predicates '(window-minibuffer-p))
  (dimmer-fraction 0.5)
  (dimmer-adjustment-mode :foreground)
  (dimmer-use-colorspace :rgb)
  (dimmer-watch-frame-focus-events nil)
  :config
  (dimmer-configure-which-key)
  (dimmer-configure-magit)
  (dimmer-configure-posframe)
  (dimmer-configure-vertico))

(defun dimmer-configure-vertico ()
  "Convenience settings for Dimmer & Vertico users."
  (with-no-warnings
    (add-to-list
     'dimmer-buffer-exclusion-regexps "^ \\*Vertico\\*$")))

;;;; Functions for windows
;;;; Window Functions
;;;;; Toggle Dedicated Window
(defun lem-toggle-window-dedicated ()
  "Toggle whether the current active window is dedicated or not"
  (interactive)
  (message
   (if (let ((window (get-buffer-window (current-buffer))))
         (set-window-dedicated-p window (not (window-dedicated-p window))))
       "Window '%s' is dedicated"
     "Window '%s' is normal")
   (current-buffer)))

;;;;; Exchange Windows
;; Swap buffers in windows and leave the cursor in the original window. Courtesy of
;; Mike Zamansky's video.
;; http://cestlaz.github.io/posts/using-emacs-36-touch-of-elisp/#.WX5Wg0czpcx

(defun lem-window-exchange-buffer ()
  "Swap buffer in windows and leave focus in original window"
  (interactive)
  (ace-swap-window)
  (aw-flip-window))

;;;;; Rotate Windows
;; from magnars modified by ffevotte for dedicated windows support
(defun lem-rotate-windows (count)
  "Rotate your windows.
  Dedicated windows are left untouched. Giving a negative prefix
  argument takes the kindows rotate backwards."
  (interactive "p")
  (let* ((non-dedicated-windows (cl-remove-if 'window-dedicated-p (window-list)))
         (num-windows (length non-dedicated-windows))
         (i 0)
         (step (+ num-windows count)))
    (cond ((not (> num-windows 1))
           (message "You can't rotate a single window!"))
          (t
           (dotimes (counter (- num-windows 1))
             (let* ((next-i (% (+ step i) num-windows))

                    (w1 (elt non-dedicated-windows i))
                    (w2 (elt non-dedicated-windows next-i))

                    (b1 (window-buffer w1))
                    (b2 (window-buffer w2))

                    (s1 (window-start w1))
                    (s2 (window-start w2)))
               (set-window-buffer w1 b2)
               (set-window-buffer w2 b1)
               (set-window-start w1 s2)
               (set-window-start w2 s1)
               (setq i next-i)))))))

(defun lem-rotate-windows-backward (count)
  "Rotate your windows backward."
  (interactive "p")
  (lem-rotate-windows (* -1 count)))

;;;;; Focus Window Split
;; Easy split and move functions
(defun lem-split-window-right-and-focus ()
  "Split the window horizontally and focus the new window."
  (interactive)
  (require 'windmove)
  (split-window-right)
  (windmove-right))

(defun lem-split-window-below-and-focus ()
  "Split the window vertically and focus the new window."
  (interactive)
  (require 'windmove)
  (split-window-below)
  (windmove-down))

;;;;; Toggle Window Split
(defun lem-toggle-window-split ()
  "Move from a horizontal to a vertical split and vice versa."
  (interactive)
  (if (= (count-windows) 2)
      (let* ((this-win-buffer (window-buffer))
             (next-win-buffer (window-buffer (next-window)))
             (this-win-edges (window-edges (selected-window)))
             (next-win-edges (window-edges (next-window)))
             (this-win-2nd (not (and (<= (car this-win-edges)
                                         (car next-win-edges))
                                     (<= (cadr this-win-edges)
                                         (cadr next-win-edges)))))
             (splitter
              (if (= (car this-win-edges)
                     (car (window-edges (next-window))))
                  'split-window-horizontally
                'split-window-vertically)))
        (delete-other-windows)
        (let ((first-win (selected-window)))
          (funcall splitter)
          (if this-win-2nd (other-window 1))
          (set-window-buffer (selected-window) this-win-buffer)
          (set-window-buffer (next-window) next-win-buffer)
          (select-window first-win)
          (if this-win-2nd (other-window 1))))))

;;;;; Jump to Minibuffer Window
(defun sp-goto-minibuffer-window ()
  "locate point to minibuffer window if it is active."
  (interactive)
  (if (active-minibuffer-window)
      (select-window (active-minibuffer-window))
    (error "Minibuffer is not active")))

(bind-key "C-c m" #'sp-goto-minibuffer-window)

;;;; Helper functions
;; Redrawing the display when there's graphical errors
(global-set-key (kbd "<f6>") 'redraw-display)

;;; Provide:

(provide 'sp-windows)
;; sp-windows.el ends here.