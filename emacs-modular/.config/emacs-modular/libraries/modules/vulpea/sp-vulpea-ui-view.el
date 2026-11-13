;;; sp-vulpea-ui-view.el --- vulpea-ui widgets in a buffer and frame of their own -*- lexical-binding: t; -*-

;;; Commentary:

;; Shows the vulpea-ui sidebar widgets (backlinks and every other registered
;; widget) in a buffer of their own, by default in a frame of their own, so a
;; tiling window manager can place it.  The view follows the most recently used
;; vulpea note buffer of any frame.  Documented in
;; docs/tangles/vulpea/sp-vulpea.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vulpea-ui)
(require 'vui)

(defgroup sp-vulpea-ui-view nil
  "The vulpea-ui widgets in a buffer and frame of their own."
  :group 'vulpea-ui
  :prefix "sp-vulpea-ui-view-")

(defcustom sp-vulpea-ui-view-buffer-name "*vulpea-ui-view*"
  "Name of the buffer that holds the vulpea-ui view."
  :type 'string
  :group 'sp-vulpea-ui-view)

(defcustom sp-vulpea-ui-view-use-frame t
  "Non-nil means `sp-vulpea-ui-view-open' makes a frame for the view.
Nil shows the view in a window of the selected frame."
  :type 'boolean
  :group 'sp-vulpea-ui-view)

(defcustom sp-vulpea-ui-view-frame-name "vulpea-ui-view"
  "Name of the frame made for the view.
Emacs uses it as the window title, so a tiling window manager can match it."
  :type 'string
  :group 'sp-vulpea-ui-view)

(defcustom sp-vulpea-ui-view-frame-parameters
  '((width . 60) (height . 50) (unsplittable . t)
    (menu-bar-lines . 0) (tool-bar-lines . 0))
  "Frame parameters of the view frame, besides its name."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'sp-vulpea-ui-view)

(defcustom sp-vulpea-ui-view-return-focus t
  "Non-nil means the frame that opened the view keeps the input focus."
  :type 'boolean
  :group 'sp-vulpea-ui-view)

(defcustom sp-vulpea-ui-view-focus-on-visit t
  "Non-nil means opening a note from the view focuses the frame that shows it."
  :type 'boolean
  :group 'sp-vulpea-ui-view)

(defvar sp-vulpea-ui-view--note nil
  "The vulpea note the view shows, or nil before there was one.")

(defvar sp-vulpea-ui-view--instance nil
  "The vui instance mounted in the view buffer.")

(defvar sp-vulpea-ui-view--sync-timer nil
  "Timer of the sync that is waiting for the command loop, or nil.")

(defvar sp-vulpea-ui-view--idle-timer nil
  "Idle timer that refreshes the view, or nil when no view exists.")

(defvar sp-vulpea-ui-view--db-pending nil
  "Non-nil when the note database changed since the last render.")

(defvar sp-vulpea-ui-view--rendering nil
  "Non-nil while the view renders.")

(define-derived-mode sp-vulpea-ui-view-mode vulpea-ui-sidebar-mode "vulpea-ui-view"
  "Major mode of the vulpea-ui view buffer.
\\{sp-vulpea-ui-view-mode-map}"
  :group 'sp-vulpea-ui-view
  (add-hook 'kill-buffer-hook #'sp-vulpea-ui-view--teardown nil t))

(define-key sp-vulpea-ui-view-mode-map (kbd "q") #'sp-vulpea-ui-view-close)
(define-key sp-vulpea-ui-view-mode-map (kbd "g") #'sp-vulpea-ui-view-refresh)

(defun sp-vulpea-ui-view--buffer ()
  "Return the view buffer, or nil when it does not exist."
  (get-buffer sp-vulpea-ui-view-buffer-name))

(defun sp-vulpea-ui-view--buffer-p (buffer)
  "Return non-nil when BUFFER is a view buffer."
  (and (buffer-live-p buffer)
       (eq (buffer-local-value 'major-mode buffer) 'sp-vulpea-ui-view-mode)))

(defun sp-vulpea-ui-view--window ()
  "Return the window that shows the view, in any frame, or nil."
  (when-let* ((buffer (sp-vulpea-ui-view--buffer)))
    (get-buffer-window buffer t)))

(defun sp-vulpea-ui-view--buffer-note (buffer)
  "Return the note the sidebar would show for BUFFER, or nil."
  (when (and (buffer-live-p buffer)
             (not (sp-vulpea-ui-view--buffer-p buffer)))
    (with-demoted-errors "vulpea-ui view: %S"
      (vulpea-ui--get-note-from-buffer buffer))))

(defun sp-vulpea-ui-view--candidate-windows ()
  "Return the windows the view may follow, most recently used first."
  (let (windows)
    (dolist (frame (visible-frame-list))
      (dolist (window (window-list frame 'no-minibuf))
        (unless (or (window-parameter window 'window-side)
                    (sp-vulpea-ui-view--buffer-p (window-buffer window)))
          (push window windows))))
    (sort windows (lambda (a b) (> (window-use-time a) (window-use-time b))))))

(defun sp-vulpea-ui-view--find-note ()
  "Return the note of the most recently used note window, or nil."
  (seq-some (lambda (window)
              (sp-vulpea-ui-view--buffer-note (window-buffer window)))
            (sp-vulpea-ui-view--candidate-windows)))

(defun sp-vulpea-ui-view--same-note-p (a b)
  "Return non-nil when notes A and B have the same ID."
  (and a b (equal (vulpea-note-id a) (vulpea-note-id b))))

(defun sp-vulpea-ui-view--render (kind)
  "Render the view for `sp-vulpea-ui-view--note'.
KIND is `note', `soft' or `hard'."
  (when-let* ((buffer (sp-vulpea-ui-view--buffer))
              (window (sp-vulpea-ui-view--window)))
    (let ((vulpea-ui--rendering t)
          (sp-vulpea-ui-view--rendering t)
          (note sp-vulpea-ui-view--note))
      (with-selected-window window
        (with-current-buffer buffer
          (let ((instance sp-vulpea-ui-view--instance))
            (if (and instance
                     (buffer-live-p (vui-instance-buffer instance)))
                (pcase kind
                  ('hard (cl-incf vulpea-ui--refresh-generation)
                         (vui-update instance (list :note note)))
                  (_ (vui-update-props instance (list :note note))))
              (setq sp-vulpea-ui-view--instance
                    (vui-mount (vui-component 'vulpea-ui-sidebar-root :note note)
                               (buffer-name)))))
          (when (eq kind 'note)
            (goto-char (point-min))))))))

(defun sp-vulpea-ui-view--sync ()
  "Show the note of the newest note window, when it is another note."
  (when-let* ((note (sp-vulpea-ui-view--find-note)))
    (unless (sp-vulpea-ui-view--same-note-p note sp-vulpea-ui-view--note)
      (setq sp-vulpea-ui-view--note note)
      (sp-vulpea-ui-view--render 'note))))

(defun sp-vulpea-ui-view--on-window-change (&optional _frame)
  "Schedule a sync after a change of selected window or window buffer."
  (unless (or (minibufferp)
              sp-vulpea-ui-view--rendering
              sp-vulpea-ui-view--sync-timer)
    (setq sp-vulpea-ui-view--sync-timer
          (run-with-timer 0 nil #'sp-vulpea-ui-view--run-sync))))

(defun sp-vulpea-ui-view--run-sync ()
  "Timer function of `sp-vulpea-ui-view--on-window-change'."
  (setq sp-vulpea-ui-view--sync-timer nil)
  (when (sp-vulpea-ui-view--buffer)
    (sp-vulpea-ui-view--sync)))

(defun sp-vulpea-ui-view--on-db-updated (&rest _)
  "Remember that the database changed (`vulpea-db-updated-functions')."
  (setq sp-vulpea-ui-view--db-pending t))

(defun sp-vulpea-ui-view--on-idle ()
  "Refresh the view while Emacs is idle."
  (when (and (sp-vulpea-ui-view--window)
             (not sp-vulpea-ui-view--rendering))
    (when-let* ((note (sp-vulpea-ui-view--find-note)))
      (setq sp-vulpea-ui-view--note note))
    (sp-vulpea-ui-view--render (if sp-vulpea-ui-view--db-pending 'hard 'soft))
    (setq sp-vulpea-ui-view--db-pending nil)))

(defun sp-vulpea-ui-view--setup ()
  "Install the hooks and the idle timer of the view."
  (add-hook 'window-selection-change-functions #'sp-vulpea-ui-view--on-window-change)
  (add-hook 'window-buffer-change-functions #'sp-vulpea-ui-view--on-window-change)
  (when (boundp 'vulpea-db-updated-functions)
    (add-hook 'vulpea-db-updated-functions #'sp-vulpea-ui-view--on-db-updated))
  (unless sp-vulpea-ui-view--idle-timer
    (setq sp-vulpea-ui-view--idle-timer
          (run-with-idle-timer vulpea-ui-auto-refresh-delay t
                               #'sp-vulpea-ui-view--on-idle))))

(defun sp-vulpea-ui-view--teardown ()
  "Remove the hooks and timers of the view; run when its buffer is killed."
  (remove-hook 'window-selection-change-functions #'sp-vulpea-ui-view--on-window-change)
  (remove-hook 'window-buffer-change-functions #'sp-vulpea-ui-view--on-window-change)
  (when (boundp 'vulpea-db-updated-functions)
    (remove-hook 'vulpea-db-updated-functions #'sp-vulpea-ui-view--on-db-updated))
  (dolist (timer '(sp-vulpea-ui-view--sync-timer sp-vulpea-ui-view--idle-timer))
    (when (symbol-value timer)
      (cancel-timer (symbol-value timer))
      (set timer nil)))
  (setq sp-vulpea-ui-view--instance nil
        sp-vulpea-ui-view--db-pending nil))

(defun sp-vulpea-ui-view--editing-window ()
  "Return the window a note opened from the view should use, or nil."
  (let ((windows (sp-vulpea-ui-view--candidate-windows)))
    (or (seq-find (lambda (window)
                    (sp-vulpea-ui-view--buffer-note (window-buffer window)))
                  windows)
        (car windows))))

(defun sp-vulpea-ui-view--main-window (orig &optional frame)
  "Advice for `vulpea-ui--get-main-window' (ORIG, FRAME).
In a frame whose selected window shows the view, return the window of
the notes, so the view is not replaced."
  (let ((frame (or frame (selected-frame))))
    (or (and (sp-vulpea-ui-view--buffer-p
              (window-buffer (frame-selected-window frame)))
             (sp-vulpea-ui-view--editing-window))
        (funcall orig frame))))

(defun sp-vulpea-ui-view--focus-visit (orig &rest args)
  "Advice for the functions that open a note (ORIG, ARGS).
When the call comes from the view, focus the frame that shows the note."
  (let ((from-view (sp-vulpea-ui-view--buffer-p (window-buffer (selected-window)))))
    (prog1 (apply orig args)
      (when (and from-view
                 sp-vulpea-ui-view-focus-on-visit
                 (not (sp-vulpea-ui-view--buffer-p
                       (window-buffer (selected-window)))))
        (select-frame-set-input-focus (selected-frame))))))

(advice-add 'vulpea-ui--get-main-window :around #'sp-vulpea-ui-view--main-window)

(dolist (function '(vulpea-ui-visit-note
                    vulpea-ui--jump-to-position
                    vulpea-ui--jump-to-file-position
                    vulpea-ui--jump-to-file-line))
  (advice-add function :around #'sp-vulpea-ui-view--focus-visit))

(defun sp-vulpea-ui-view--frame-parameters ()
  "Return the frame parameters of the view frame, including its name."
  (cons (cons 'name sp-vulpea-ui-view-frame-name)
        (seq-remove (lambda (parameter) (eq (car parameter) 'name))
                    sp-vulpea-ui-view-frame-parameters)))

(defun sp-vulpea-ui-view--display (buffer)
  "Show BUFFER in a new frame or window, and return that window."
  (if sp-vulpea-ui-view-use-frame
      (let* ((frame (make-frame (sp-vulpea-ui-view--frame-parameters)))
             (window (frame-root-window frame)))
        (set-window-buffer window buffer)
        (set-window-dedicated-p window t)
        window)
    (display-buffer buffer '(display-buffer-pop-up-window))))

;;;###autoload
(defun sp-vulpea-ui-view-open ()
  "Show the vulpea-ui widgets in a view of their own, in a frame of their own.
The view follows the most recently used note window.  Calling it again
raises the view."
  (interactive)
  (let ((origin (selected-frame))
        (note (sp-vulpea-ui-view--find-note)))
    (when note
      (setq sp-vulpea-ui-view--note note))
    (let* ((buffer (get-buffer-create sp-vulpea-ui-view-buffer-name))
           (window (get-buffer-window buffer t)))
      (with-current-buffer buffer
        (unless (derived-mode-p 'sp-vulpea-ui-view-mode)
          (sp-vulpea-ui-view-mode)))
      (if (window-live-p window)
          (raise-frame (window-frame window))
        (setq window (sp-vulpea-ui-view--display buffer)))
      (sp-vulpea-ui-view--setup)
      (sp-vulpea-ui-view--render 'note)
      (when (and sp-vulpea-ui-view-return-focus
                 (frame-live-p origin)
                 (not (eq origin (window-frame window))))
        (select-frame-set-input-focus origin)))))

;;;###autoload
(defun sp-vulpea-ui-view-close ()
  "Close the vulpea-ui view and its frame."
  (interactive)
  (when-let* ((buffer (sp-vulpea-ui-view--buffer)))
    (when-let* ((window (get-buffer-window buffer t))
                (frame (window-frame window)))
      (cond ((and (window-dedicated-p window)
                  (null (cdr (window-list frame 'no-minibuf)))
                  (cdr (visible-frame-list)))
             (delete-frame frame))
            ((cdr (window-list frame 'no-minibuf))
             (delete-window window))))
    (kill-buffer buffer)))

;;;###autoload
(defun sp-vulpea-ui-view-toggle ()
  "Open the vulpea-ui view, or close it when it is open."
  (interactive)
  (if (sp-vulpea-ui-view--window)
      (sp-vulpea-ui-view-close)
    (sp-vulpea-ui-view-open)))

;;;###autoload
(defun sp-vulpea-ui-view-refresh ()
  "Refresh the vulpea-ui view, dropping the cached widget data."
  (interactive)
  (when-let* ((note (or (sp-vulpea-ui-view--find-note)
                        sp-vulpea-ui-view--note)))
    (setq sp-vulpea-ui-view--note note))
  (sp-vulpea-ui-view--render 'hard))

(keymap-global-set "M-o v" #'sp-vulpea-ui-view-toggle)

(provide 'sp-vulpea-ui-view)
;;; sp-vulpea-ui-view.el ends here
