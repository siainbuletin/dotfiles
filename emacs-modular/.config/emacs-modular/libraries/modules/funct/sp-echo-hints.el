;;; sp-echo-hints.el --- Key hints in the echo area, as nano-help does -*- lexical-binding: t; -*-

;;; Commentary:

;; Lists of key hints for report and lint buffers, shown in the echo area
;; instead of the header line (which does not wrap).  A buffer turns on
;; `sp-echo-hints-mode' and says which hints it has; they appear when Emacs is
;; idle and the echo area is empty.  After nano-help.el of nano-emacs.
;; See docs/tangles/funct/sp-echo-hints.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup sp-echo-hints nil
  "Key hints in the echo area."
  :group 'convenience)

(defcustom sp-echo-hints-delay 0.4
  "Seconds of idle time before the key hints are shown."
  :type 'number
  :group 'sp-echo-hints)

(defcustom sp-echo-hints-separator "   "
  "Text between two hints."
  :type 'string
  :group 'sp-echo-hints)

(defface sp-echo-hints-key
  '((t :inherit (bold font-lock-keyword-face)))
  "Face of the key in a key hint."
  :group 'sp-echo-hints)

(defvar sp-echo-hints-mode)

(defvar-local sp-echo-hints-list nil
  "The hints of this buffer: a list of (KEY . LABEL) strings.")

(defvar-local sp-echo-hints-function nil
  "Function with no arguments returning the hints of this buffer.
It wins over `sp-echo-hints-list'.")

(defun sp-echo-hints--one (hint)
  "The text of HINT, a cons cell (KEY . LABEL)."
  (concat (propertize (car hint) 'face 'sp-echo-hints-key) " " (cdr hint)))

(defun sp-echo-hints-format (hints &optional width)
  "Turn HINTS, a list of (KEY . LABEL), into one string no wider than WIDTH.
WIDTH is the frame width by default.  Hints that do not fit are left out and
the text ends with an ellipsis."
  (let* ((width (or width (frame-width)))
         (hints (cl-remove-if-not (lambda (h) (and (consp h) (car h) (cdr h))) hints))
         (shown nil) (used 0))
    (dolist (hint hints)
      (let ((cost (+ (string-width (car hint)) 1 (string-width (cdr hint))
                     (if shown (string-width sp-echo-hints-separator) 0))))
        (when (<= (+ used cost 2) width)
          (setq used (+ used cost))
          (push hint shown))))
    (setq shown (nreverse shown))
    (concat (mapconcat #'sp-echo-hints--one shown sp-echo-hints-separator)
            (and (< (length shown) (length hints)) " …"))))

(defun sp-echo-hints-current ()
  "The hints of the current buffer."
  (if sp-echo-hints-function
      (funcall sp-echo-hints-function)
    sp-echo-hints-list))

(defun sp-echo-hints-show (&optional hints)
  "Show HINTS, or the hints of the current buffer, in the echo area."
  (interactive)
  (let ((text (sp-echo-hints-format (or hints (sp-echo-hints-current))))
        (message-log-max nil))
    (unless (string-empty-p text)
      (message "%s" text))))

(defvar sp-echo-hints--timer nil
  "The idle timer that shows the hints.")

(defun sp-echo-hints--idle ()
  "Show the hints of the selected buffer if it has any and the echo area is free."
  (when (and sp-echo-hints-mode
             (not (active-minibuffer-window))
             (not (current-message)))
    (condition-case err
        (sp-echo-hints-show)
      (error
       (sp-echo-hints-mode -1)
       (message "sp-echo-hints: turned off in this buffer: %s" (error-message-string err))))))

(defun sp-echo-hints--any-buffer-p ()
  "Non-nil when some buffer has `sp-echo-hints-mode' on."
  (cl-some (lambda (buf) (buffer-local-value 'sp-echo-hints-mode buf)) (buffer-list)))

(defun sp-echo-hints--stop-timer ()
  "Cancel the idle timer when no buffer needs it."
  (when (and sp-echo-hints--timer (not (sp-echo-hints--any-buffer-p)))
    (cancel-timer sp-echo-hints--timer)
    (setq sp-echo-hints--timer nil)))

;;;###autoload
(define-minor-mode sp-echo-hints-mode
  "Show the key hints of this buffer in the echo area when Emacs is idle."
  :lighter nil
  (if sp-echo-hints-mode
      (progn
        (unless sp-echo-hints--timer
          (setq sp-echo-hints--timer
                (run-with-idle-timer sp-echo-hints-delay t #'sp-echo-hints--idle)))
        (add-hook 'kill-buffer-hook #'sp-echo-hints--stop-timer-later nil t))
    (remove-hook 'kill-buffer-hook #'sp-echo-hints--stop-timer-later t)
    (sp-echo-hints--stop-timer)))

(defun sp-echo-hints--stop-timer-later ()
  "Called when a buffer with the mode is killed: stop the timer if it was the last."
  (let ((buf (current-buffer)))
    (run-at-time 0 nil
                 (lambda ()
                   (unless (cl-some (lambda (b) (and (not (eq b buf))
                                                     (buffer-local-value 'sp-echo-hints-mode b)))
                                    (buffer-list))
                     (when sp-echo-hints--timer
                       (cancel-timer sp-echo-hints--timer)
                       (setq sp-echo-hints--timer nil)))))))

(provide 'sp-echo-hints)
;;; sp-echo-hints.el ends here
