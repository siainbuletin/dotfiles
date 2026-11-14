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

;;;; Keycast now lives in the mode line (sp-lambda-modeline, sp-prot-modeline)
;; (keycast-header-line-mode 1)

;;;;; Window Margins for Text Indentation
;; Add margins to windows to maintain text indentation with smaller frame borders
(defun sp-set-window-margins ()
  "Set left and right margins for all windows to maintain text indentation.
Windows showing a buffer in `olivetti-mode' are skipped: Olivetti
centres the text with these same margins."
  (walk-windows
   (lambda (window)
     (unless (or (window-minibuffer-p window)
                 (with-current-buffer (window-buffer window)
                   (bound-and-true-p olivetti-mode)))
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
  "Delete the selected frame. If the last frame, kill Emacs."
  (interactive)
  (when (condition-case nil (delete-frame)
          (error (save-buffers-kill-emacs))))
  (select-frame-set-input-focus (selected-frame)))

;;;;; Share the buffer list between frames
;; A new frame starts with an empty `buffer-list' frame parameter.  `tabspaces'
;; (sp-tabs) lists a workspace's buffers from that parameter, so `consult-buffer'
;; in a new frame showed almost nothing.

(defgroup sp-frame-share-buffers nil
  "Give new frames the buffer list of an existing frame."
  :group 'frames)

(defcustom sp-frame-share-buffers-scope 'selected
  "Which buffers a new frame gets in its buffer list.
`selected' copies the buffer list of the frame that was selected before
the new frame was made.  `all' uses every live buffer whose name does
not start with a space."
  :type '(choice (const :tag "Buffers of the previously selected frame" selected)
                 (const :tag "All live buffers" all)))

(defvar sp-frame-share-buffers--source nil
  "Frame that was selected just before the latest `make-frame'.")

(defun sp-frame-share-buffers--live (buffers)
  "Return the live buffers of BUFFERS, without duplicates."
  (delete-dups (seq-filter #'buffer-live-p buffers)))

(defun sp-frame-share-buffers--eligible-p (frame)
  "Return non-nil if FRAME should receive a shared buffer list.
Child frames (posframe and similar) and frames with the
`sp-no-share-buffers' parameter are left alone."
  (and (frame-live-p frame)
       (not (frame-parameter frame 'parent-frame))
       (not (frame-parameter frame 'sp-no-share-buffers))))

(defun sp-frame-share-buffers--remember-source ()
  "Remember the selected frame before a new frame is made."
  (setq sp-frame-share-buffers--source (selected-frame)))

(defun sp-frame-share-buffers-into (frame &optional source)
  "Set the buffer lists of FRAME from SOURCE, per `sp-frame-share-buffers-scope'.
SOURCE defaults to the frame remembered before the latest `make-frame',
or else the first other frame."
  (when-let* (((sp-frame-share-buffers--eligible-p frame))
              (source (or (and (frame-live-p source) source)
                          (and (frame-live-p sp-frame-share-buffers--source)
                               (not (eq sp-frame-share-buffers--source frame))
                               sp-frame-share-buffers--source)
                          (seq-find (lambda (f) (and (not (eq f frame))
                                                     (sp-frame-share-buffers--eligible-p f)))
                                    (frame-list)))))
    (pcase sp-frame-share-buffers-scope
      ('all
       (set-frame-parameter
        frame 'buffer-list
        (seq-remove (lambda (b) (string-prefix-p " " (buffer-name b)))
                    (sp-frame-share-buffers--live (buffer-list))))
       (set-frame-parameter frame 'buried-buffer-list nil))
      (_
       (set-frame-parameter
        frame 'buffer-list
        (sp-frame-share-buffers--live (frame-parameter source 'buffer-list)))
       (set-frame-parameter
        frame 'buried-buffer-list
        (sp-frame-share-buffers--live (frame-parameter source 'buried-buffer-list)))))))

(defun sp-frame-share-buffers--after-make (frame)
  "Share the buffer list into the new FRAME; never signal an error."
  (condition-case err
      (sp-frame-share-buffers-into frame)
    (error (message "sp-frame-share-buffers: %s" (error-message-string err)))))

(defun sp-frame-share-buffers-now ()
  "Share the buffer list of another frame into the selected frame."
  (interactive)
  (sp-frame-share-buffers-into (selected-frame)))

(define-minor-mode sp-frame-share-buffers-mode
  "Give every new frame the buffer list of an existing frame.
Frames made by code, such as the vulpea-ui view frame, count too."
  :global t
  :group 'sp-frame-share-buffers
  (if sp-frame-share-buffers-mode
      (progn
        (add-hook 'before-make-frame-hook #'sp-frame-share-buffers--remember-source)
        (add-hook 'after-make-frame-functions #'sp-frame-share-buffers--after-make))
    (remove-hook 'before-make-frame-hook #'sp-frame-share-buffers--remember-source)
    (remove-hook 'after-make-frame-functions #'sp-frame-share-buffers--after-make)))

(sp-frame-share-buffers-mode 1)

(provide 'sp-frame)
;;; sp-frame.el ends here
