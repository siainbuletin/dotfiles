;;; sp-nano-style.el --- Nano's header line blocks and mode line divider -*- lexical-binding: t; -*-

;;; Commentary:

;; The header line blocks (RW / RO / **) and the divider above the mode line
;; of N Λ N O's `nano-modeline.el' (Nicolas Rougier, GPLv3), shared by
;; `sp-lambda-modeline' and `sp-prot-modeline'.  Nothing changes until
;; `sp-nano-style-install' is called.

;;; Code:

(require 'subr-x)
(declare-function project-name "project" (project))
(defvar sp-after-load-theme-hook)

(defgroup sp-nano-style nil
  "Header line blocks and mode line divider after nano-modeline."
  :group 'mode-line)

(defcustom sp-nano-style-divider t
  "When non-nil, draw a thin line above the mode line."
  :type 'boolean
  :group 'sp-nano-style)

(defcustom sp-nano-style-divider-face 'shadow
  "Face whose foreground colours the divider above the mode line."
  :type 'face
  :group 'sp-nano-style)

(defface sp-nano-style-header-ro
  '((t :inherit (bold warning) :inverse-video t))
  "Block of a read-only buffer in the header line.")

(defface sp-nano-style-header-md
  '((t :inherit (bold error) :inverse-video t))
  "Block of a modified buffer in the header line.")

(defface sp-nano-style-header-rw
  '((t :inherit (bold shadow) :inverse-video t))
  "Block of a writable buffer, and of any buffer in a window that is not selected.")

(defface sp-nano-style-header-name
  '((t :inherit bold))
  "Path in the header line of the selected window.")

(defface sp-nano-style-header-faded
  '((t :inherit shadow))
  "Muted text in the header line.")

(defvar-local sp-nano-style--project-cache nil
  "Pair of the directory and the project name last found for this buffer.")

(defun sp-nano-style--project ()
  "Return the name of the project of this buffer, cached; \"\" for none."
  (if (equal (car sp-nano-style--project-cache) default-directory)
      (cdr sp-nano-style--project-cache)
    (let ((name (or (and (not (file-remote-p default-directory))
                         (when-let* ((project (project-current)))
                           (project-name project)))
                    "")))
      (setq sp-nano-style--project-cache (cons default-directory name))
      name)))

(defun sp-nano-style--path ()
  "Return the path of the file, the directory, or the buffer name."
  (abbreviate-file-name (or buffer-file-name
                            (and (derived-mode-p 'dired-mode) default-directory)
                            (buffer-name))))

(defun sp-nano-style--status ()
  "Return \"**\" for a modified file, \"RO\" for a read-only buffer, else \"RW\"."
  (cond ((and buffer-file-name (buffer-modified-p)) "**")
        (buffer-read-only "RO")
        (t "RW")))

(defun sp-nano-style--block (selected)
  "Return the status block; SELECTED non-nil for the selected window."
  (let ((status (sp-nano-style--status)))
    (propertize (if (window-dedicated-p) " -- " (format " %s " status))
                'face (cond ((not selected) 'sp-nano-style-header-rw)
                            ((equal status "RO") 'sp-nano-style-header-ro)
                            ((equal status "**") 'sp-nano-style-header-md)
                            (t 'sp-nano-style-header-rw))
                'help-echo (pcase status
                             ("RO" "Read-only buffer")
                             ("**" "Modified")
                             (_ "Writable buffer")))))

(defun sp-nano-style-header ()
  "Return the header line: status block, path, and the project at the right."
  (let* ((selected (mode-line-window-selected-p))
         (prefix (sp-nano-style--block selected))
         (right (concat (sp-nano-style--project) " "))
         (path (sp-nano-style--path))
         (room (max 8 (- (window-total-width)
                         (string-width prefix) (string-width right) 3)))
         (path (if (> (string-width path) room)
                   (concat "…" (truncate-string-to-width
                                path (string-width path)
                                (- (string-width path) (1- room))))
                 path)))
    (concat prefix
            " "
            (propertize path
                        'face (if selected 'sp-nano-style-header-name
                                'sp-nano-style-header-faded)
                        'help-echo (or buffer-file-name default-directory))
            (propertize " " 'display
                        `(space :align-to (- right ,(string-width right))))
            (propertize right 'face 'sp-nano-style-header-faded))))

(defconst sp-nano-style-header-format
  '(:eval (sp-nano-style-header))
  "The `header-line-format' of every window.")
(put 'sp-nano-style-header-format 'risky-local-variable t)

(defconst sp-nano-style--divider-faces
  '(mode-line mode-line-inactive lambda-line lambda-line-active lambda-line-inactive
    lambda-line-hspace-active lambda-line-hspace-inactive)
  "Faces that get the overline: the mode lines, and lambda-line's.")

(defun sp-nano-style-apply-divider (&rest _)
  "Draw (or remove) the divider above the mode line, from the current theme."
  (let* ((color (and sp-nano-style-divider
                     (face-attribute sp-nano-style-divider-face :foreground nil t)))
         (overline (if (stringp color) color 'unspecified)))
    (dolist (face sp-nano-style--divider-faces)
      (when (facep face)
        (set-face-attribute face nil :overline overline)))
    (force-mode-line-update t)))

(defvar sp-nano-style--saved-header nil
  "The default `header-line-format' before `sp-nano-style-install'.")

(defvar sp-nano-style--installed nil
  "Non-nil while the header line and divider are installed.")

(defun sp-nano-style-install ()
  "Install the header line blocks and the divider above the mode line."
  (interactive)
  (unless sp-nano-style--installed
    (setq sp-nano-style--saved-header (default-value 'header-line-format)))
  (setq-default header-line-format sp-nano-style-header-format)
  (sp-nano-style-apply-divider)
  (add-hook 'sp-after-load-theme-hook #'sp-nano-style-apply-divider 90)
  (setq sp-nano-style--installed t)
  (force-mode-line-update t))

(defun sp-nano-style-uninstall ()
  "Remove what `sp-nano-style-install' set."
  (interactive)
  (when sp-nano-style--installed
    (setq-default header-line-format sp-nano-style--saved-header)
    (let ((sp-nano-style-divider nil))
      (sp-nano-style-apply-divider))
    (remove-hook 'sp-after-load-theme-hook #'sp-nano-style-apply-divider)
    (setq sp-nano-style--installed nil)
    (force-mode-line-update t)))

(provide 'sp-nano-style)
