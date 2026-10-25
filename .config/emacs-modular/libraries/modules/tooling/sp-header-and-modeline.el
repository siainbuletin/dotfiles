;;; sp-header-and-modeline.el --- Lambda-line header line and mode line -*- lexical-binding: t; -*-

;;; Commentary:

;; This module installs and configures `lambda-line', the minimal status line
;; from the Lambda Emacs project, fetched from Codeberg, with a header line
;; next to it.  Tag emoji from `sp-tag-emoji' show in the mode line, and the
;; faces follow the theme.  It is loaded in both the default and minimal
;; module lists.  Alternative: `sp-prot-modeline'.

;;; Code:

(declare-function sp-tag-emoji-modeline-string "sp-tag-emoji" ())
(declare-function lambda-line-compose "lambda-line")
(declare-function project-name "project" (project))
(defvar lambda-line-position)
(defvar keycast-header-line-mode)

(defgroup sp-header-and-modeline nil
  "Lambda-line header line and mode line."
  :group 'mode-line)

(defcustom sp-header-and-modeline-layout 'both
  "Where lambda-line is shown.
`both' puts it in the mode line and adds a header line, `modeline'
leaves out the header line, and `header' puts everything in the
header line (lambda-line's `top') and shrinks the mode line to a
divider."
  :type '(choice (const :tag "Mode line and header line" both)
                 (const :tag "Mode line only" modeline)
                 (const :tag "Header line only" header))
  :group 'sp-header-and-modeline)

(defvar sp-header-and-modeline--composing-header nil
  "Non-nil while the header line is being composed.")

(defun sp-header-and-modeline--path ()
  "Return the path shown at the left of the header line."
  (abbreviate-file-name (or buffer-file-name
                            (and (derived-mode-p 'dired-mode) default-directory)
                            (buffer-name))))

(defun sp-header-and-modeline--project ()
  "Return the name of the current project, or an empty string."
  (or (and (not (file-remote-p default-directory))
           (when-let* ((project (project-current)))
             (project-name project)))
      ""))

(defun sp-header-and-modeline-header ()
  "Return the header line string: the path and the project name."
  (let ((sp-header-and-modeline--composing-header t))
    (lambda-line-compose nil
                         (sp-header-and-modeline--path)
                         ""
                         ""
                         (sp-header-and-modeline--project))))

(defconst sp-header-and-modeline-header-format
  '(:eval (sp-header-and-modeline-header))
  "The `header-line-format' used by the `both' layout.")
(put 'sp-header-and-modeline-header-format 'risky-local-variable t)

(defun sp-header-and-modeline--add-tag-emoji (args)
  "Append the tag emoji to the primary part in ARGS of `lambda-line-compose'."
  (let ((tags (and (not sp-header-and-modeline--composing-header)
                   (fboundp 'sp-tag-emoji-modeline-string)
                   (ignore-errors (sp-tag-emoji-modeline-string)))))
    (if (and (stringp tags) (not (string-blank-p tags)))
        (let ((args (copy-sequence args)))
          (setf (nth 2 args) (concat (or (nth 2 args) "") tags))
          args)
      args)))

(defun sp-header-and-modeline--foreground (face fallback)
  "Return the foreground of FACE in the current theme, or FALLBACK."
  (let ((color (face-foreground face nil t)))
    (if (and (stringp color) (not (string-prefix-p "unspecified" color)))
        color
      fallback)))

(defun sp-header-and-modeline-theme-faces (&rest _)
  "Set the lambda-line faces from the faces of the current theme."
  (when (facep 'lambda-line-active)
    (set-face-attribute 'lambda-line nil :inherit 'mode-line)
    (set-face-attribute 'lambda-line-inactive nil
                        :inherit 'mode-line-inactive
                        :weight 'unspecified :box 'unspecified
                        :foreground 'unspecified :background 'unspecified)
    (set-face-attribute 'lambda-line-active-name nil
                        :inherit '(mode-line-buffer-id lambda-line))
    (set-face-attribute 'lambda-line-active-secondary nil
                        :inherit '(shadow lambda-line))
    (let ((muted (sp-header-and-modeline--foreground 'shadow "gray50")))
      (dolist (status '("RO" "RW" "MD"))
        (set-face-attribute (intern (format "lambda-line-inactive-status-%s" status))
                            nil :inherit 'lambda-line-inactive :foreground muted)))
    (set-face-attribute 'lambda-line-active-status-RW nil
                        :foreground (sp-header-and-modeline--foreground 'success "green"))
    (set-face-attribute 'lambda-line-active-status-RO nil
                        :foreground (sp-header-and-modeline--foreground 'warning "yellow"))
    (set-face-attribute 'lambda-line-active-status-MD nil
                        :foreground (sp-header-and-modeline--foreground 'error "red"))
    (force-mode-line-update t)))

(defun sp-header-and-modeline-apply-layout ()
  "Set the mode line and the header line from `sp-header-and-modeline-layout'."
  (pcase sp-header-and-modeline-layout
    ('header
     (setq-default mode-line-format (list "%_"))
     (setq mode-line-format (list "%_")))
    ('both
     (setq-default header-line-format sp-header-and-modeline-header-format)
     (when (bound-and-true-p keycast-header-line-mode)
       (keycast-header-line-mode -1)
       (keycast-header-line-mode 1))))
  (force-mode-line-update t))

(use-package lambda-line
    :ensure (:type git :repo "https://codeberg.org/Lambda-Emacs/lambda-line")

    :custom
    (lambda-line-icon-time t) ;; requires ClockFace font (see below)
    (lambda-line-clockface-update-fontset "ClockFaceRect") ;; set clock icon
    (lambda-line-position (if (eq sp-header-and-modeline-layout 'header) 'top 'bottom))
    (lambda-line-abbrev t) ;; abbreviate major modes
    (lambda-line-hspace "  ")  ;; add some cushion
    (lambda-line-prefix t) ;; use a prefix symbol
    (lambda-line-prefix-padding t) ;; extra space for prefix
    (lambda-line-status-invert nil)  ;; no invert colors
    (lambda-line-gui-ro-symbol  " ⨂") ;; symbols
    (lambda-line-gui-mod-symbol " ⬤")
    (lambda-line-gui-rw-symbol  " ◯")
    (lambda-line-space-top +.70)  ;; padding on top and bottom of line
    (lambda-line-space-bottom -.70)
    (lambda-line-symbol-position 0.1) ;; adjust the vertical placement of symbol

    :config
    (advice-add 'lambda-line-compose :filter-args
                #'sp-header-and-modeline--add-tag-emoji)
    (lambda-line-mode)  ;; activate lambda-line
    (sp-header-and-modeline-theme-faces)
    (sp-header-and-modeline-apply-layout)
    (add-hook 'sp-after-load-theme-hook #'sp-header-and-modeline-theme-faces))

(provide 'sp-header-and-modeline)
