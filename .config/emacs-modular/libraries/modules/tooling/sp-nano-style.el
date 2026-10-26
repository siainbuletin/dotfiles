;;; sp-nano-style.el --- Nano's header line blocks and mode line divider -*- lexical-binding: t; -*-

;;; Commentary:

;; The header line blocks (RW / RO / **) and the divider above the mode line
;; of N Λ N O's `nano-modeline.el' (Nicolas Rougier, GPLv3), shared by
;; `sp-lambda-modeline' and `sp-prot-modeline'.  Nothing changes until
;; `sp-nano-style-install' is called.

;;; Code:

(require 'subr-x)
(require 'cl-lib)
(require 'color)
(declare-function org-collect-keywords "org" (keywords &optional unique directory))
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

(defcustom sp-nano-style-divider-color nil
  "Colour of the divider.  Nil takes the foreground of `sp-nano-style-divider-face'."
  :type '(choice (const :tag "From the face" nil) color)
  :group 'sp-nano-style)

(defcustom sp-nano-style-divider-opacity 1.0
  "How strong the divider is, from 0 (invisible) to 1.
It is the share of the divider colour that is mixed with the background of
the theme: 0.4 gives a faint line."
  :type 'float
  :group 'sp-nano-style)

(defcustom sp-nano-style-header-divider t
  "When non-nil, draw a line between the header and the text of the buffer."
  :type 'boolean
  :group 'sp-nano-style)

(defcustom sp-nano-style-clock t
  "When non-nil, show the time (hh:mm, 24 hours) at the right of the header."
  :type 'boolean
  :group 'sp-nano-style)

(defface sp-nano-style-header-title
  '((t :inherit org-document-title))
  "Title of an Org buffer in the header line (its `#+title:').")

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

(defvar-local sp-nano-style--title-cache nil
  "Pair of the modified tick and the `#+title:' last read in this buffer.")

(defun sp-nano-style--org-title ()
  "Return the `#+title:' of the Org buffer, or nil."
  (when (derived-mode-p 'org-mode)
    (let ((tick (buffer-chars-modified-tick)))
      (unless (eq (car sp-nano-style--title-cache) tick)
        (setq sp-nano-style--title-cache
              (cons tick (ignore-errors
                           (let ((title (cadr (assoc "TITLE" (org-collect-keywords '("TITLE"))))))
                             (and (stringp title) (not (string-blank-p title))
                                  (substring-no-properties title)))))))
      (cdr sp-nano-style--title-cache))))

(defun sp-nano-style--name ()
  "Return the name for the header: the Org title, or the buffer name."
  (or (sp-nano-style--org-title) (buffer-name)))

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
  "Return the header line: status block, name, and project and time at the right."
  (let* ((selected (mode-line-window-selected-p))
         (prefix (sp-nano-style--block selected))
         (right (concat (sp-nano-style--project)
                        (if sp-nano-style-clock
                            (concat "  " (format-time-string "%H:%M"))
                          "")
                        " "))
         (name (sp-nano-style--name))
         (title-p (and (sp-nano-style--org-title) selected))
         (room (max 8 (- (window-total-width)
                         (string-width prefix) (string-width right) 3)))
         (shown (if (> (string-width name) room)
                    (concat "…" (truncate-string-to-width
                                 name (string-width name)
                                 (- (string-width name) (1- room))))
                  name)))
    (concat prefix
            " "
            (propertize shown
                        'face (cond (title-p 'sp-nano-style-header-title)
                                    (selected 'sp-nano-style-header-name)
                                    (t 'sp-nano-style-header-faded))
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

(defun sp-nano-style--mix (color background opacity)
  "Return COLOR mixed with BACKGROUND, OPACITY (0 to 1) of it being COLOR."
  (let ((c (and (stringp color) (color-name-to-rgb color)))
        (b (and (stringp background) (color-name-to-rgb background))))
    (if (and c b)
        (apply #'color-rgb-to-hex
               (append (cl-mapcar (lambda (x y) (+ (* x opacity) (* y (- 1 opacity))))
                                  c b)
                       '(2)))
      color)))

(defun sp-nano-style-divider-colour ()
  "Return the colour of the divider in the current theme, or nil for none."
  (let ((color (or sp-nano-style-divider-color
                   (face-attribute sp-nano-style-divider-face :foreground nil t))))
    (when (and sp-nano-style-divider (stringp color)
               (not (string-prefix-p "unspecified" color)))
      (sp-nano-style--mix color (face-background 'default nil t)
                          sp-nano-style-divider-opacity))))

(defun sp-nano-style-apply-divider (&rest _)
  "Draw (or remove) the dividers above the mode line and below the header."
  (let ((color (sp-nano-style-divider-colour)))
    (dolist (face sp-nano-style--divider-faces)
      (when (facep face)
        (set-face-attribute face nil :overline (or color 'unspecified))))
    (set-face-attribute 'header-line nil
                        :underline (if (and color sp-nano-style-header-divider)
                                       `(:color ,color :position t)
                                     'unspecified))
    (force-mode-line-update t)))

(defvar sp-nano-style--saved-header nil
  "The default `header-line-format' before `sp-nano-style-install'.")

(defvar sp-nano-style--installed nil
  "Non-nil while the header line and divider are installed.")

(defun sp-nano-style--start-clock ()
  "Turn on `display-time-mode' as Prot does, and keep its text out of the mode line."
  (when sp-nano-style-clock
    (setq display-time-format "%H:%M"
          display-time-24hr-format t
          display-time-default-load-average nil
          display-time-mail-directory nil)
    (display-time-mode 1)
    (setq global-mode-string (delq 'display-time-string global-mode-string))))

(defun sp-nano-style-install ()
  "Install the header line blocks and the divider above the mode line."
  (interactive)
  (unless sp-nano-style--installed
    (setq sp-nano-style--saved-header (default-value 'header-line-format)))
  (setq-default header-line-format sp-nano-style-header-format)
  (sp-nano-style-apply-divider)
  (add-hook 'sp-after-load-theme-hook #'sp-nano-style-apply-divider 90)
  (sp-nano-style--start-clock)
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
