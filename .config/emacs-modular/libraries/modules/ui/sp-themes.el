;; -*- lexical-binding: t; -*-
;;; sp-themes.el

;;; Commentary:

;; This includes the theme manager from Lambda Emacs
;;
;; 𝛌-Emacs comes with its own set of themes --
;; 𝛌-Themes. The user can of course configure things to use whatever theme they
;; like. The Modus themes are especially good and included with Emacs 28+.

;;; Code:
;;;; No-confirm themes
;; should this setting really come first?
(setq custom-safe-themes t)

;;;; Configuring the custom theme folder
(defcustom sp-custom-themes-dir (concat sp-library-dir "themes/")
  "Set a custom themes directory path."
  :group 'sia-lambda
  :type 'string)

;;;;; Make the custom themes dir.
(mkdir sp-custom-themes-dir t)
(setq-default custom-theme-directory sp-custom-themes-dir)

;;;;; find all themes recursively in custom-theme-folder
(let ((basedir custom-theme-directory))
  (dolist (f (directory-files basedir))
    (if (and (not (or (equal f ".") (equal f "..")))
             (file-directory-p (concat basedir f)))
        (add-to-list 'custom-theme-load-path (concat basedir f)))))

;;;; Disable All Custom Themes

;; why is this necessary in order to do sp-load-theme?
(defun sp-disable-all-themes ()
  "Disable all active themes & reset mode-line."
  (interactive)
  (progn
    (dolist (i custom-enabled-themes)
      (disable-theme i))
    ;; disable window-divider mode
    (window-divider-mode -1)
    ;; revert to mode line
    (setq-default header-line-format nil)
    (setq-default mode-line-format
                  '((:eval
                     (list
                      "%b "
                      "%m "
                      (cond ((and buffer-file-name (buffer-modified-p))
                             (propertize "(**)" 'face `(:foreground "#f08290")))
                            (buffer-read-only "(RO)" ))
                      " %l:%c %0"
                      " "
                      ))))
    (force-mode-line-update)))

;;;; Load Theme Wrapper
(defun sp-load-theme ()
  (interactive)
  (progn
    (sp-disable-all-themes)
    (call-interactively 'load-theme)))

;;;; Toggle Menubar
;; toggle menubar to light or dark
(defun sp-osx-toggle-menubar-theme ()
  "Toggle menubar to dark or light using shell command."
  (interactive)
  (shell-command "dark-mode"))

(defun sp-osx-menubar-theme-light ()
  "Turn dark mode off."
  (interactive)
  (shell-command "dark-mode off"))

(defun sp-osx-menubar-theme-dark ()
  "Turn dark mode on."
  (interactive)
  (shell-command "dark-mode on"))

;;; THEME OPTIONS

;;;; Modus themes

(use-package modus-themes
  :ensure t)

(setq modus-themes-mixed-fonts t)
(setq modus-themes-italic-constructs t)

;; In all of the following, WEIGHT is a symbol such as `semibold',
;; `light', `bold', or anything mentioned in `modus-themes-weights'.
(setq modus-themes-italic-constructs t
      modus-themes-bold-constructs nil
      modus-themes-mixed-fonts t
      modus-themes-variable-pitch-ui nil
      modus-themes-disable-other-themes t

      ;; Options for `modus-themes-prompts' are either nil (the
      ;; default), or a list of properties that may include any of those
      ;; symbols: `italic', `WEIGHT'
      modus-themes-prompts '(italic bold)

      ;; The `modus-themes-completions' is an alist that reads two
      ;; keys: `matches', `selection'.  Each accepts a nil value (or
      ;; empty list) or a list of properties that can include any of
      ;; the following (for WEIGHT read further below):
      ;;
      ;; `matches'   :: `underline', `italic', `WEIGHT'
      ;; `selection' :: `underline', `italic', `WEIGHT'
      modus-themes-completions
      '((matches . (extrabold))
        (selection . (semibold italic text-also))))

(setq modus-themes-org-blocks 'gray-background) ; {nil,'gray-background,'tinted-background}

;; EF THEMES
(use-package ef-themes
  :ensure t)

;; DORIC THEMES
(use-package doric-themes
  :ensure t
  :demand t)

;; MODUS THEMES
(use-package lambda-themes
  :ensure (:type git :host github :repo "lambda-emacs/lambda-themes") 

  :config
  ;; load preferred theme 
  ;; (load-theme 'lambda-light)
)

;; Lambda themes options
(setopt lambda-themes-set-italic-comments t)
(setopt lambda-themes-set-italic-keywords t)
(setopt lambda-themes-set-variable-pitch t)

;; kind-icon needs to have its cache flushed after theme change
(with-eval-after-load 'kind-icon
  (add-hook 'lambda-themes-after-load-theme-hook #'kind-icon-reset-cache))

;; For the setting which switches the MacOS theme automatically, based on the color of the system
;; see the sp-macos.el file.

;; For easier preview of themes

(use-package easy-theme-preview
  :ensure t)

;;;; Theme toggle
(defun toggle-dark-light-theme ()
  "Flip the active lambda variant between light and dark.
If neither lambda variant is currently active (the user loaded some
other theme), default to `ef-dream'. The macOS system-appearance
hook is left untouched; the next macOS Light/Dark change will resync."
  (interactive)
  (let* ((current (car custom-enabled-themes))
         (target (if (eq current 'lambda-light) 'ef-dream 'lambda-light-faded)))
    (sp-disable-all-themes)
    (load-theme target t)))

;;;; After Load Theme Hook
(defvar sp-after-load-theme-hook nil
  "Hook run after a color theme is loaded using `load-theme'.")
(define-advice load-theme (:after (&rest _) sp-run-after-load-theme-hook)
  "Run `sp-after-load-theme-hook'."
  (run-hooks 'sp-after-load-theme-hook))

;;; Provide
(provide 'sp-themes)
;;; sp-themes.el ends here
