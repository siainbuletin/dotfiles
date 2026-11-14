;;; sp-interaction.el --- Mouse and scrolling -*- lexical-binding: t; -*-

;;; Commentary:

;; This is set up for the lowest level of interaction
;; with the graphical interface in Emacs. For example,
;; the mouse support.

;;; Code:

;; Scrolling and mouse usage
;; taken from lambda emacs 2026.10.02

;; this is a built-in package
(use-package mwheel
  :ensure nil
  :config
  ;; Optimize mouse wheel scrolling for smooth-scrolling trackpad use.
  ;; Trackpads send a lot more scroll events than regular mouse wheels,
  ;; so the scroll amount and acceleration must be tuned to smooth it out.
  (setq
   ;; If the frame contains multiple windows, scroll the one under the cursor
   ;; instead of the one that currently has keyboard focus.
   mouse-wheel-follow-mouse 't
   ;; Completely disable mouse wheel acceleration to avoid speeding away.
   mouse-wheel-progressive-speed nil
   mwheel-coalesce-scroll-events t
   ;; The most important setting of all! Make each scroll-event move 1 line at a
   ;; time (instead of 5 at default). Simply hold down shift to move twice as
   ;; fast. Perfect for trackpads.
   mouse-wheel-scroll-amount '(1 ((shift) . 2))))

;; Don't use pixel-scroll by default -- it causes janky behavior on MacOS
(use-package pixel-scroll
  :ensure nil
  :disabled)

;;;; Mouse
;; Don't be afraid of the mouse!
;; For ideas see https://ruzkuku.com/texts/emacs-mouse.html
(use-package mouse
  :ensure nil
  :config
  ;; Focus follows mouse
  (setq mouse-autoselect-window t
        focus-follows-mouse t)
  (setq context-menu-functions
        '(context-menu-ffap
          occur-context-menu
          context-menu-region
          context-menu-undo
          context-menu-dictionary)))

;; This should include a link to the window management packages that I use in this case.
;; and exwm should be moved to the window management macro library.

;;;; Echo-area help hints
;; Key hints in the echo area, in the style of nano-emacs' nano-help.el.
(require 'subr-x)

(defgroup sp-interaction nil
  "Mouse, scrolling and echo-area hints."
  :group 'convenience)

(defcustom sp-echo-help-rows 2
  "Number of rows the key hints are laid out in."
  :type 'integer
  :group 'sp-interaction)

(defface sp-echo-help-face '((t :inherit shadow))
  "Face of the key hints in the echo area."
  :group 'sp-interaction)

(defface sp-echo-help-strong-face '((t :inherit bold))
  "Face of the emphasised key hints in the echo area."
  :group 'sp-interaction)

(defvar-local sp-echo-help--hints nil
  "The hints of the current buffer, see `sp-echo-help-set'.")

(defvar-local sp-echo-help--note nil
  "The line shown above the hints of the current buffer.")

(defun sp-echo-help-format (hints &optional note rows)
  "Return the echo-area text for HINTS.
HINTS is a list of (KEY DESCRIPTION [STRONG]).
The hints fill ROWS rows (default `sp-echo-help-rows'), column by column,
each column but the last padded to its widest hint.  A non-nil STRONG
shows the hint in `sp-echo-help-strong-face'.  A non-empty NOTE is put on a
line above."
  (let* ((rows (max 1 (min (or rows sp-echo-help-rows) (max 1 (length hints)))))
         (ncols (ceiling (length hints) rows))
         (texts (mapcar (lambda (h) (format "[%s] %s" (nth 0 h) (nth 1 h))) hints))
         (widths (make-vector ncols 0))
         (lines nil))
    (dotimes (i (length texts))
      (aset widths (/ i rows)
            (max (aref widths (/ i rows)) (string-width (nth i texts)))))
    (dotimes (r rows)
      (let ((cells nil))
        (dotimes (c ncols)
          (let ((i (+ (* c rows) r)))
            (when (< i (length hints))
              (push (propertize
                     (concat (nth i texts)
                             (if (< c (1- ncols))
                                 (make-string (- (aref widths c) (string-width (nth i texts))) ?\s)
                               ""))
                     'face (if (nth 2 (nth i hints))
                               'sp-echo-help-strong-face
                             'sp-echo-help-face))
                    cells))))
        (push (concat " " (string-join (nreverse cells) "   ")) lines)))
    (let ((body (string-join (nreverse lines) "\n")))
      (cond ((and note (not (string-empty-p note)) hints)
             (concat " " (propertize note 'face 'sp-echo-help-face) "\n" body))
            ((and note (not (string-empty-p note)))
             (concat " " (propertize note 'face 'sp-echo-help-face)))
            (t body)))))

(defun sp-echo-help-show (&optional force)
  "Show the hints of the current buffer in the echo area, without logging them.
Does nothing while the minibuffer is active or another message is showing,
unless FORCE is non-nil."
  (when (and sp-echo-help--hints
             (not (active-minibuffer-window))
             (or force (not (current-message))))
    (let ((message-log-max nil))
      (message "%s" (sp-echo-help-format sp-echo-help--hints sp-echo-help--note)))))

(defcustom sp-echo-help-idle-delay 1.5
  "Seconds of idle time after which the hints are shown again.
Nil never shows them again on idle."
  :type '(choice (const :tag "Never" nil) number)
  :group 'sp-interaction)

(defvar sp-echo-help-mode)

(defvar sp-echo-help--timer nil
  "The idle timer that shows the hints again, shared by all buffers.")

(defun sp-echo-help--any-buffer-p ()
  "Non-nil when a live buffer has `sp-echo-help-mode' on."
  (seq-some (lambda (b) (buffer-local-value 'sp-echo-help-mode b)) (buffer-list)))

(defcustom sp-echo-help-message-hold 5
  "Seconds a message of a command stays before idle time replaces it with the hints.
The hints never replace a younger message; `sp-echo-help-show-now' always does."
  :type 'number
  :group 'sp-interaction)

(defun sp-echo-help--idle-show ()
  "Show the hints of the selected window's buffer; stop the timer when unused.
The hints replace a message only after Emacs has been idle for
`sp-echo-help-message-hold' seconds, so the last message of a job does not
hide them for good, and a message just emitted is never replaced."
  (if (not (sp-echo-help--any-buffer-p))
      (when (timerp sp-echo-help--timer)
        (cancel-timer sp-echo-help--timer)
        (setq sp-echo-help--timer nil))
    (with-current-buffer (window-buffer (selected-window))
      (when sp-echo-help-mode
        (sp-echo-help-show (let ((idle (current-idle-time)))
                             (and idle (>= (float-time idle) sp-echo-help-message-hold))))))))

(defun sp-echo-help-show-now ()
  "Show the key hints of this buffer in the echo area now."
  (interactive)
  (if sp-echo-help--hints
      (sp-echo-help-show t)
    (user-error "No key hints for this buffer")))

(defvar-keymap sp-echo-help-mode-map
  :doc "Keys of `sp-echo-help-mode'."
  "C-c ?" #'sp-echo-help-show-now)

(define-minor-mode sp-echo-help-mode
  "Keep the key hints of this buffer in the echo area.
Set them with `sp-echo-help-set'.  \\{sp-echo-help-mode-map}"
  :lighter nil
  (if sp-echo-help-mode
      (progn
        (add-hook 'post-command-hook #'sp-echo-help-show nil t)
        (when (and sp-echo-help-idle-delay (not (timerp sp-echo-help--timer)))
          (setq sp-echo-help--timer
                (run-with-idle-timer sp-echo-help-idle-delay t #'sp-echo-help--idle-show))))
    (remove-hook 'post-command-hook #'sp-echo-help-show t)))

(defun sp-echo-help-set (hints &optional note quiet)
  "Show HINTS in the echo area whenever this buffer is current.
HINTS is a list of (KEY DESCRIPTION [STRONG]); see `sp-echo-help-format'.
NOTE is an optional line above them.  Nil HINTS turn the hints off.
A non-nil QUIET keeps a message that is in the echo area: the hints then
show after the next command or idle time, not now."
  (setq sp-echo-help--hints hints
        sp-echo-help--note note)
  (sp-echo-help-mode (if hints 1 -1))
  (when (and hints (eq (current-buffer) (window-buffer (selected-window))))
    (sp-echo-help-show (not quiet))))

(provide 'sp-interaction)
;; sp-interaction.el ends here.
