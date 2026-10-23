;;; sp-frame.el --- Frame appearance, margins and frame helpers -*- lexical-binding: t; -*-

;;; Commentary:

;; Setup for frames. Note that some basic settings are placed in early-init for
;; better startup.

;;; Code:

(setq-default frame-title-format '("␥ %b ␥")) ;; Make the window title to be the buffer name

;;;; Frame defaults
;; This setting will ensure that the frame is actually square, which 
;; radically changes the appearance on MacOS and brings it closer to a
;; Linux experience.

;; Make a clean & minimalist frame
;; To modify initial frame set `initial-frame-alist`

(use-package frame
  :ensure nil
  :config

  (setq-default default-frame-alist
                (append (list
                         '(frame-title-format . nil)
                         '(internal-border-width . 30)
                         '(tool-bar-lines . 0)
                         '(vertical-scroll-bars . nil)
                         '(horizontal-scroll-bars . nil)
                         '(undecorated . t))))
  ;; Resize pixel-wise to avoid gaps
  (setq-default window-resize-pixelwise t)
  (setq-default frame-resize-pixelwise t)

  ;; Don't show icon in frame
  (setq-default ns-use-proxy-icon nil))

(defun sp-frame-recenter (&optional frame)
  "Center FRAME on the screen.
FRAME can be a frame name, a terminal name, or a frame.
If FRAME is omitted or nil, use currently selected frame."
  (interactive)
  (unless (eq 'maximized (frame-parameter nil 'fullscreen))
    (modify-frame-parameters
     frame '((user-position . t) (top . 0.5) (left . 0.5)))))

;; un/comment this hook if you want frames recentered
(add-hook 'after-make-frame-functions #'sp-frame-recenter)

;;;; Enabling keycast header line mode by default
(keycast-header-line-mode 1)

;;;;; Window Margins for Text Indentation
;; Add margins to windows to maintain text indentation with smaller frame borders
(defun sp-set-window-margins ()
  "Set left and right margins for all windows to maintain text indentation."
  (walk-windows
   (lambda (window)
     (unless (window-minibuffer-p window)
       (set-window-margins window 2 2)))))

;; Apply margins when windows change
(add-hook 'window-configuration-change-hook #'sp-set-window-margins)

;; Apply margins to initial frame
(add-hook 'after-init-hook #'sp-set-window-margins)

;; Apply margins to new frames
(add-hook 'after-make-frame-functions
          (lambda (frame)
            (select-frame frame)
            (sp-set-window-margins)))

;;;;; Fix titlebar titling colors
;; see also https://github.com/d12frosted/homebrew-emacs-plus/issues/55
(use-package ns-auto-titlebar
  :ensure t
  :when (eq system-type 'darwin)
  :commands ns-auto-titlebar-mode
  :init (ns-auto-titlebar-mode))

;;;;; Frame Functions
;;;;;; Delete Frame or Quit
(defun sp-delete-frame-or-quit ()
  "Delete the selected frame & kill terminal buffers. If the last frame, kill Emacs."
  (interactive)
  (kill-matching-buffers "*vterm" nil t)
  (when (condition-case nil (delete-frame)
          (error (save-buffers-kill-emacs))))
  (select-frame-set-input-focus (selected-frame)))

(provide 'sp-frame)
;;; sp-frame.el ends here
