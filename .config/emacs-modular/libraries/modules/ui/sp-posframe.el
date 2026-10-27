;;; sp-posframe.el --- Centered minibuffer in a posframe with background dimming -*- lexical-binding: t; -*-

;;; Commentary:

;; This configuration for vertico-posframe makes sure that the minibuffer is being
;; dimmed and centered when I'm looking for a particular file, or wanting to insert a
;; link. Inserting should still be placed somewhere in the bottom, so it can follow what
;; I'm writing in the current buffer without interrupting the focus on screen

;;; Code:

;;;; Show the minibuffer in a centered frame

(require 'color) ;; why is color needed? what is this package?

(defcustom sp-posframe-width-fraction 0.75
  "Fraction of the parent frame's width that the posframe always occupies."
  :type 'float
  :group 'minibuffer)

(defun sp-posframe-get-size (buffer)
  "Return the size of the posframe for BUFFER: a fixed share of the frame width.
Width and minimum width are both `sp-posframe-width-fraction' of the frame, so
the posframe does not follow the length of the prompt or the candidates. The
height is left to `vertico-posframe-get-size'."
  (let* ((width (round (* sp-posframe-width-fraction (frame-width))))
         (size (copy-sequence (vertico-posframe-get-size buffer))))
    (plist-put size :width width)
    (plist-put size :min-width width)
    (plist-put size :max-width width)
    size))

(use-package vertico-posframe
  :ensure t
  :after vertico

  :custom
  (vertico-posframe-poshandler #'posframe-poshandler-frame-center) ; centered both ways
  (vertico-posframe-size-function #'sp-posframe-get-size) ; fixed width, see below
  (vertico-posframe-border-width 4)  ; padding around the text
  (vertico-posframe-fallback-mode 'vertico-buffer-mode) ; terminals have no child frames
  ;; `vertico-count' (13) sets the number of candidates; the frame fits them.

  :config
  (vertico-posframe-mode 1)
)

(defun sp-posframe--match-border ()
  "Give the posframe border the background colour of the posframe itself.
The border then reads as padding. It is run again on every theme change."
  (when (facep 'vertico-posframe-border)
    (let ((bg (or (face-background 'vertico-posframe nil t)
                  (face-background 'default nil t))))
      (when (stringp bg)
        (set-face-attribute 'vertico-posframe-border nil :background bg)))))

(with-eval-after-load 'vertico-posframe
  (sp-posframe--match-border))
(add-hook 'enable-theme-functions (lambda (_theme) (sp-posframe--match-border)))

(defcustom sp-posframe-nano-commands
  '(execute-extended-command amx counsel-M-x smex)
  "Commands whose prompt is styled like nano's M-x."
  :type '(repeat function)
  :group 'minibuffer)

(defcustom sp-posframe-divider-char ?┈
  "Character repeated for the dotted line under the M-x input, or nil for none."
  :type '(choice character (const :tag "No line" nil))
  :group 'minibuffer)

(defcustom sp-posframe-divider-priority -50
  "Priority of the overlay with the dotted line under the M-x input."
  :type 'integer
  :group 'minibuffer)

(defconst sp-posframe--divider-length 300
  "Characters in the dotted line; the window cuts it at its edge.")

(defun sp-posframe--nano-p ()
  "Return non-nil when the prompt being shown is a nano-style M-x."
  (memq this-command sp-posframe-nano-commands))

(defun sp-posframe--divider-color ()
  "Return the colour of the dotted line."
  (or (and (fboundp 'sp-nano-style-divider-colour)
           (sp-nano-style-divider-colour))
      (face-foreground 'shadow nil t)))

(defun sp-posframe--style-nano ()
  "Give the M-x prompt nano's block and the input a dotted line below it.
The line is longer than any window and `truncate-lines' cuts it, so it never
wraps. An error is reported in the echo area and does not abort the prompt."
  (condition-case err
      (when (and (bound-and-true-p vertico-posframe-mode) (sp-posframe--nano-p))
        (face-remap-add-relative
         'minibuffer-prompt
         :inverse-video t :weight 'bold :box '(:line-width 1))
        (when sp-posframe-divider-char
          (setq-local truncate-lines t)
          (let ((ov (make-overlay (point-max) (point-max) nil nil t)))
            (overlay-put ov 'priority sp-posframe-divider-priority)
            (overlay-put ov 'after-string
                         (concat "\n"
                                 (propertize (make-string sp-posframe--divider-length
                                                          sp-posframe-divider-char)
                                             'face `(:foreground ,(sp-posframe--divider-color))))))))
    (error (message "sp-posframe: styling the prompt failed: %s" err))))

(add-hook 'minibuffer-setup-hook #'sp-posframe--style-nano)

;;;; Same text size for every prompt

(defun sp-posframe--reset-text-scale ()
  "Show posframe prompts at the size of the `default' face.
`sp-minibuffer' scales the text of every minibuffer up from `minibuffer-mode-hook'.
This runs later, from `minibuffer-setup-hook', and removes that scale when the
prompt is drawn in a posframe, so M-x, the file pickers and the note pickers all
have the same text size."
  (when (and (bound-and-true-p vertico-posframe-mode)
             (bound-and-true-p text-scale-mode))
    (text-scale-set 0)))

(add-hook 'minibuffer-setup-hook #'sp-posframe--reset-text-scale 90)

;;;; Dimming, only for selected commands

(defcustom sp-posframe-dim-always t
  "Non-nil means every posframe prompt dims the frame behind it.
Nil limits dimming to `sp-posframe-dim-commands' and `sp-posframe-dim-functions'."
  :type 'boolean
  :group 'minibuffer)

(defvar sp-posframe-dim-commands '(find-file vulpea-find org-node-find)
  "Commands whose minibuffer should dim the underlying frame.")

(defvar sp-posframe-dim-functions
  '(sp-select-note sp-insert-note sp-collec-query-select-note)
  "Functions whose minibuffer should dim the underlying frame, whoever calls them.")

(defvar sp-posframe--dim-requested nil
  "Non-nil while a function in `sp-posframe-dim-functions' is running.")

(defun sp-posframe--request-dim (fn &rest args)
  "Call FN with ARGS, asking for the frame behind the minibuffer to be dimmed."
  (let ((sp-posframe--dim-requested t))
    (apply fn args)))

(defun sp-posframe-advise-dim-functions ()
  "Advise the functions in `sp-posframe-dim-functions' that are defined."
  (dolist (fn sp-posframe-dim-functions)
    (when (fboundp fn)
      (advice-add fn :around #'sp-posframe--request-dim))))

(sp-posframe-advise-dim-functions)
(add-hook 'after-load-functions (lambda (_file) (sp-posframe-advise-dim-functions)))

(defvar sp-posframe-dim-amount 0.45
  "How far to blend text colors toward the background (0 = none, 1 = invisible).")

(defvar-local sp-posframe--dim-cookies nil)
(defvar sp-posframe--dimmed-buffers nil)

(defun sp-posframe--blend (fg bg amount)
  (let ((f (and (stringp fg) (color-name-to-rgb fg)))
        (b (and (stringp bg) (color-name-to-rgb bg))))
    (when (and f b)
      (apply #'color-rgb-to-hex
             (append (color-blend f b amount) '(2))))))

(defun sp-posframe-dim (frame)
  "Dim all text in the buffers shown in FRAME."
  (let ((bg (face-background 'default frame)))
    (dolist (buf (delete-dups
                  (mapcar #'window-buffer (window-list frame 'no-minibuf))))
      (with-current-buffer buf
        (unless sp-posframe--dim-cookies
          (dolist (face (face-list))
            (let* ((fg (face-attribute face :foreground frame))
                   (dim (and (not (eq fg 'unspecified))
                             (sp-posframe--blend fg bg sp-posframe-dim-amount))))
              (when dim
                (push (face-remap-add-relative face :foreground dim)
                      sp-posframe--dim-cookies))))
          (push buf sp-posframe--dimmed-buffers))))))

(defun sp-posframe-undim ()
  (dolist (buf sp-posframe--dimmed-buffers)
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (mapc #'face-remap-remove-relative sp-posframe--dim-cookies)
        (setq sp-posframe--dim-cookies nil))))
  (setq sp-posframe--dimmed-buffers nil))

(defun sp-posframe--maybe-dim ()
  (when (and (bound-and-true-p vertico-posframe-mode)
             (or sp-posframe-dim-always
                 sp-posframe--dim-requested
                 (memq this-command sp-posframe-dim-commands))
             (minibuffer-selected-window))
    (sp-posframe-dim (window-frame (minibuffer-selected-window)))))

(add-hook 'minibuffer-setup-hook #'sp-posframe--maybe-dim)
(add-hook 'minibuffer-exit-hook #'sp-posframe-undim)

(provide 'sp-posframe)
;; sp-posframe.el ends here.
