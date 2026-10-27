;;; sp-lambda-modeline.el --- Lambda-line header line and mode line -*- lexical-binding: t; -*-

;;; Commentary:

;; This module installs and configures `lambda-line', the minimal status line
;; from the Lambda Emacs project, fetched from Codeberg, with a header line
;; next to it.  Tag emoji from `sp-org-tag-groups' show in the mode line, and the
;; faces follow the theme.  It is loaded in both the default and minimal
;; module lists.  Alternative: `sp-prot-modeline'.
;;
;; The old `sp-choose-modeline' (lambda-line or doom-modeline) was removed; see
;; commit cfc047b for its code and doc.

;;; Code:

(declare-function sp-org-tag-groups-modeline-string "sp-org-tag-groups" ())
(declare-function lambda-line-compose "lambda-line")
(require 'sp-nano-style)
(require 'sp-modeline-parts)
(defvar lambda-line-position)

(defgroup sp-lambda-modeline nil
  "Lambda-line header line and mode line."
  :group 'mode-line)

(declare-function nerd-icons-icon-for-mode "nerd-icons")

(defcustom sp-lambda-modeline-mode-icon t
  "When non-nil, show the major mode as a `nerd-icons' icon, not as text."
  :type 'boolean
  :group 'sp-lambda-modeline)

(defun sp-lambda-modeline--mode-icon (orig-fun)
  "Return the icon of the major mode, or the text from ORIG-FUN."
  (let ((icon (and sp-lambda-modeline-mode-icon
                   (require 'nerd-icons nil t)
                   (nerd-icons-icon-for-mode major-mode))))
    (if (and (stringp icon) (not (string-empty-p icon)))
        (propertize icon 'help-echo (funcall orig-fun))
      (funcall orig-fun))))

(defun sp-lambda-modeline--add-tag-emoji (args)
  "Append the tag emoji to the primary part in ARGS of `lambda-line-compose'."
  (let ((tags (and (fboundp 'sp-org-tag-groups-modeline-string)
                   (ignore-errors (sp-org-tag-groups-modeline-string)))))
    (if (and (stringp tags) (not (string-blank-p tags)))
        (let ((args (copy-sequence args)))
          (setf (nth 2 args) (concat (or (nth 2 args) "") tags))
          args)
      args)))

(defun sp-lambda-modeline--foreground (face fallback)
  "Return the foreground of FACE in the current theme, or FALLBACK."
  (let ((color (face-foreground face nil t)))
    (if (and (stringp color) (not (string-prefix-p "unspecified" color)))
        color
      fallback)))

(defun sp-lambda-modeline-theme-faces (&rest _)
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
    (let ((muted (sp-lambda-modeline--foreground 'shadow "gray50")))
      (dolist (status '("RO" "RW" "MD"))
        (set-face-attribute (intern (format "lambda-line-inactive-status-%s" status))
                            nil :inherit 'lambda-line-inactive :foreground muted)))
    (set-face-attribute 'lambda-line-active-status-RW nil
                        :foreground (sp-lambda-modeline--foreground 'success "green"))
    (set-face-attribute 'lambda-line-active-status-RO nil
                        :foreground (sp-lambda-modeline--foreground 'warning "yellow"))
    (set-face-attribute 'lambda-line-active-status-MD nil
                        :foreground (sp-lambda-modeline--foreground 'error "red"))
    (force-mode-line-update t)))

(defcustom sp-lambda-modeline-new-layout t
  "When non-nil, text and programming buffers get the line of `sp-modeline-parts'."
  :type 'boolean
  :group 'sp-lambda-modeline)

(defun sp-lambda-modeline--compose (orig-fun &rest args)
  "Return the line of `sp-modeline-parts' in text and programming buffers.
Otherwise call ORIG-FUN, `lambda-line-compose', with ARGS."
  (if (and sp-lambda-modeline-new-layout
           (not (minibufferp))
           (derived-mode-p 'text-mode 'prog-mode))
      (sp-modeline-parts-compose)
    (apply orig-fun args)))

(defun sp-lambda-modeline-apply-layout ()
  "Show the name of the buffer in the header line and the new line at the bottom."
  (sp-nano-style-install)
  (sp-modeline-parts-install)
  (force-mode-line-update t))

(use-package lambda-line
    :ensure (:type git :repo "https://codeberg.org/Lambda-Emacs/lambda-line")

    :custom
    (lambda-line-icon-time t) ;; requires ClockFace font (see below)
    (lambda-line-clockface-update-fontset "ClockFaceRect") ;; set clock icon
    (lambda-line-position 'bottom) ;; the status line is the mode line
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
    (advice-add 'lambda-line-compose :around #'sp-lambda-modeline--compose)
    (advice-add 'lambda-line-compose :filter-args
                #'sp-lambda-modeline--add-tag-emoji)
    (advice-add 'lambda-line-mode-name :around #'sp-lambda-modeline--mode-icon)
    (lambda-line-mode)  ;; activate lambda-line
    (sp-lambda-modeline-theme-faces)
    (sp-lambda-modeline-apply-layout)
    (add-hook 'sp-after-load-theme-hook #'sp-lambda-modeline-theme-faces))

(provide 'sp-lambda-modeline)
