;;; sp-mini-frame.el --- Centered minibuffer frame with background dimming -*- lexical-binding: t; -*-

;;; Commentary:

;; This configuration for emacs-mini-frame.el makes sure that the minibuffer is being
;; dimmed and centered when I'm looking for a particular file, or wanting to insert a
;; link. Inserting should still be placed somewhere in the bottom, so it can follow what
;; I'm writing in the current buffer without interrupting the focus on screen

;;; Code:

;;;; Create mini frame for the buffer

(require 'color)
(require 'cl-lib)

(defun sp-mini-frame--mix (fg bg amount)
  "Return FG mixed with BG, AMOUNT (0 to 1) of it being FG."
  (let ((f (and (stringp fg) (color-name-to-rgb fg)))
        (b (and (stringp bg) (color-name-to-rgb bg))))
    (when (and f b)
      (apply #'color-rgb-to-hex
             (append (cl-mapcar (lambda (x y) (+ (* x amount) (* y (- 1 amount))))
                                f b)
                     '(2))))))

(defcustom sp-mini-frame-contrast 0.08
  "How far the mini-frame background moves from the default background toward the foreground (0 to 1)."
  :type 'number
  :group 'minibuffer)

(defcustom sp-mini-frame-padding 4
  "Pixels of space around the text of the mini-frame."
  :type 'natnum
  :group 'minibuffer)

(defcustom sp-mini-frame-border-color nil
  "Colour of the border around the mini-frame, or nil for its own background."
  :type '(choice (const :tag "Background of the frame" nil) color)
  :group 'minibuffer)

(defcustom sp-mini-frame-nano-commands
  '(execute-extended-command amx counsel-M-x smex)
  "Commands whose prompt is styled like nano's M-x."
  :type '(repeat function)
  :group 'minibuffer)

(defcustom sp-mini-frame-divider-char ?┈
  "Character repeated for the dotted line under the M-x input, or nil for none."
  :type '(choice character (const :tag "No line" nil))
  :group 'minibuffer)

(defcustom sp-mini-frame-divider-priority -50
  "Priority of the overlay with the dotted line under the M-x input."
  :type 'integer
  :group 'minibuffer)

(defun sp-mini-frame--nano-p ()
  "Return non-nil when the prompt being shown is a nano-style M-x."
  (memq this-command sp-mini-frame-nano-commands))

(defun sp-mini-frame--lines ()
  "Return the lines of the mini-frame: prompt, candidates and the divider.
The minibuffer text is scaled by `sp-minibuffer' (two steps of
`text-scale-mode-step'), so its lines are taller than the frame's own."
  (let ((scale (if (fboundp 'sp-minibuffer) (expt text-scale-mode-step 2) 1)))
    (ceiling (* scale (+ 2 (if (boundp 'vertico-count) vertico-count 10))))))

(defun sp-mini-frame--colors (frame)
  "Return the foreground and background of the mini-frame, from the faces of FRAME.
The colours are those of the `default' face, not the frame parameters, which
stay at the values of the first frame when a theme is loaded later, and would
give text that blends into the background."
  (let ((fg (face-foreground 'default frame t))
        (bg (face-background 'default frame t)))
    (when (or (not (stringp fg)) (string-prefix-p "unspecified" fg))
      (setq fg (frame-parameter frame 'foreground-color)))
    (when (or (not (stringp bg)) (string-prefix-p "unspecified" bg))
      (setq bg (frame-parameter frame 'background-color)))
    (cons fg (or (sp-mini-frame--mix fg bg sp-mini-frame-contrast) bg))))

(defun sp-mini-frame-parameters ()
  "Return the frame parameters for the prompt of `this-command'."
  (let* ((pad sp-mini-frame-padding)
         (colors (sp-mini-frame--colors (selected-frame)))
         (fg (car colors))
         (bg (cdr colors)))
    (setq mini-frame-internal-border-color (or sp-mini-frame-border-color bg))
    `((left . 0.5)
      (top . 0.5)
      (width . 0.6)
      (height . ,(sp-mini-frame--lines))
      (foreground-color . ,fg)
      (background-color . ,bg)
      (child-frame-border-width . ,pad)
      (internal-border-width . ,pad))))

(defvar mini-frame-selected-frame)

(defun sp-mini-frame--fix-colors ()
  "Draw the minibuffer in the colours of the theme of the frame it was opened from."
  (when (and (bound-and-true-p mini-frame-mode)
             (frame-live-p mini-frame-frame)
             (eq (selected-frame) mini-frame-frame)
             (frame-live-p mini-frame-selected-frame))
    (let ((colors (sp-mini-frame--colors mini-frame-selected-frame)))
      (when (and (stringp (car colors)) (stringp (cdr colors)))
        (face-remap-add-relative 'default
                                 :foreground (car colors)
                                 :background (cdr colors))))))

(add-hook 'minibuffer-setup-hook #'sp-mini-frame--fix-colors)

(defun sp-mini-frame--divider-color ()
  "Return the colour of the dotted line."
  (or (and (fboundp 'sp-nano-style-divider-colour)
           (sp-nano-style-divider-colour))
      (face-foreground 'shadow nil t)))

(defun sp-mini-frame--style-nano ()
  "Give the M-x prompt nano's block and the input a dotted line below it.
An error is reported in the echo area and does not abort the prompt."
  (condition-case err
      (when (and (bound-and-true-p mini-frame-mode) (sp-mini-frame--nano-p))
        (face-remap-add-relative
         'minibuffer-prompt
         :inverse-video t :weight 'bold :box '(:line-width 1))
        (when sp-mini-frame-divider-char
          (let ((ov (make-overlay (point-max) (point-max) nil nil t))
                (width (max 10 (1- (window-body-width (minibuffer-window))))))
            (overlay-put ov 'priority sp-mini-frame-divider-priority)
            (overlay-put ov 'after-string
                         (concat "\n"
                                 (propertize (make-string width sp-mini-frame-divider-char)
                                             'face `(:foreground ,(sp-mini-frame--divider-color))))))))
    (error (message "sp-mini-frame: styling the prompt failed: %s" err))))

(add-hook 'minibuffer-setup-hook #'sp-mini-frame--style-nano)

(use-package mini-frame
  :ensure t

  :custom
  (mini-frame-show-parameters #'sp-mini-frame-parameters)
  (mini-frame-resize 'not-set) ; fixed height, no resizing

  :config
  (mini-frame-mode 1)
)

;;;; Dimming, only for selected commands

(defvar sp-mini-frame-dim-commands '(find-file vulpea-find org-node-find)
  "Commands whose minibuffer should dim the underlying frame.")

(defvar sp-mini-frame-dim-functions
  '(sp-select-note sp-insert-note sp-collec-query-select-note)
  "Functions whose minibuffer should dim the underlying frame, whoever calls them.")

(defvar sp-mini-frame--dim-requested nil
  "Non-nil while a function in `sp-mini-frame-dim-functions' is running.")

(defun sp-mini-frame--request-dim (fn &rest args)
  "Call FN with ARGS, asking for the frame behind the minibuffer to be dimmed."
  (let ((sp-mini-frame--dim-requested t))
    (apply fn args)))

(defun sp-mini-frame-advise-dim-functions ()
  "Advise the functions in `sp-mini-frame-dim-functions' that are defined."
  (dolist (fn sp-mini-frame-dim-functions)
    (when (fboundp fn)
      (advice-add fn :around #'sp-mini-frame--request-dim))))

(sp-mini-frame-advise-dim-functions)
(add-hook 'after-load-functions (lambda (_file) (sp-mini-frame-advise-dim-functions)))

(defvar sp-mini-frame-dim-amount 0.45
  "How far to blend text colors toward the background (0 = none, 1 = invisible).")

(defvar-local sp-mini-frame--dim-cookies nil)
(defvar sp-mini-frame--dimmed-buffers nil)

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
                             (sp-mini-frame--mix fg bg sp-mini-frame-dim-amount))))
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
             (or sp-mini-frame--dim-requested
                 (memq this-command sp-mini-frame-dim-commands))
             (minibuffer-selected-window))
    (sp-mini-frame-dim (window-frame (minibuffer-selected-window)))))

(add-hook 'minibuffer-setup-hook #'sp-mini-frame--maybe-dim)
(add-hook 'minibuffer-exit-hook #'sp-mini-frame-undim)


(provide 'sp-mini-frame)
;; sp-mini-frame.el ends here.
