;; -*- lexical-binding: t; -*-

;;; sp-themes.el

;; This includes the theme manager from Lambda Emacs

;; 𝛌-Emacs comes with its own set of themes --
;; 𝛌-Themes. The user can of course configure things to use whatever theme they
;; like. The Modus themes are especially good and included with Emacs 28+.

;;;; No-confirm themes
(setq custom-safe-themes t)

;; Configuring the custom theme folder
(defcustom sp-custom-themes-dir (concat sp-libraries-dir "themes/")
  "Set a custom themes directory path."
  :group 'sia-lambda
  :type 'string)

;; Make the custom themes dir.
(mkdir sp-custom-themes-dir t)
(setq-default custom-theme-directory sp-custom-themes-dir)

;; find all themes recursively in custom-theme-folder
(let ((basedir custom-theme-directory))
  (dolist (f (directory-files basedir))
    (if (and (not (or (equal f ".") (equal f "..")))
             (file-directory-p (concat basedir f)))
        (add-to-list 'custom-theme-load-path (concat basedir f)))))

;;;; Disable All Custom Themes
(defun lem-disable-all-themes ()
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
(defun lem-load-theme ()
  (interactive)
  (progn
    (lem-disable-all-themes)
    (call-interactively 'load-theme)))

;;;; Toggle Menubar
;; toggle menubar to light or dark
(defun lem-osx-toggle-menubar-theme ()
  "Toggle menubar to dark or light using shell command."
  (interactive)
  (shell-command "dark-mode"))

(defun lem-osx-menubar-theme-light ()
  "Turn dark mode off."
  (interactive)
  (shell-command "dark-mode off"))

(defun lem-osx-menubar-theme-dark ()
  "Turn dark mode on."
  (interactive)
  (shell-command "dark-mode on"))

;;; THEME OPTIONS

;; Which themes to include?

(use-package modus-themes
  :ensure (:wait t)
  :init
  (modus-themes-include-derivatives-mode 1)
)

(use-package ef-themes
  :ensure t
  :init
  ;; This makes the Modus commands listed below consider only the Ef
  ;; themes.  For an alternative that includes Modus and all
  ;; derivative themes (like Ef), enable the
  ;; `modus-themes-include-derivatives-mode' instead.  The manual of
  ;; the Ef themes has a section that explains all the possibilities:
  ;;
  ;; - Evaluate `(info "(ef-themes) Working with other Modus themes or taking over Modus")'
  ;; - Visit <https://protesilaos.com/emacs/ef-themes#h:6585235a-5219-4f78-9dd5-6a64d87d1b6e>
  (ef-themes-take-over-modus-themes-mode 1)
  :bind
  (("M-<f5>" . modus-themes-select)
   ("C-<f5>" . modus-themes-load-random))

  :config
  ;; All customisations here.
  (setq modus-themes-mixed-fonts t)
  (setq modus-themes-italic-constructs t)

  ;; Finally, load your theme of choice (or a random one with
  ;; `modus-themes-load-random', `modus-themes-load-random-dark',
  ;; `modus-themes-load-random-light').
  (modus-themes-load-theme 'ef-melissa-light)
  )

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

;; The `modus-themes-headings' is an alist: read the manual's
;; node about it or its doc string.  Basically, it supports
;; per-level configurations for the optional use of
;; `variable-pitch' typography, a height value as a multiple of
;; the base font size (e.g. 1.5), and a `WEIGHT'.
(setq modus-themes-headings
      '((1 . (variable-pitch 1.5))
        (2 . (1.3))
        (agenda-date . (1.3))
        (agenda-structure . (variable-pitch light 1.8))
        (t . (1.1))))

(use-package lambda-themes
  :when sp-load-extras
  :init
  (unless (package-installed-p 'lambda-themes)
    (package-vc-install "https://codeberg.org/Lambda-Emacs/lambda-themes.git"))
  
  :custom
  (lambda-themes-set-italic-comments t)
  (lambda-themes-set-italic-keywords t)
  (lambda-themes-set-variable-pitch t) 
  
  :config
  ;; load preferred theme (this doesn't have the option of just loading in some cases, it will override the ef-themes I already have installed)
  (load-theme 'lambda-light) ;; this is enabled even though I would like to have a normal switch for it, because otherwise the ns-system switch for macos doesn't end up working
)

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
other theme), default to `lambda-dark'. The macOS system-appearance
hook is left untouched; the next macOS Light/Dark change will resync."
  (interactive)
  (let* ((current (car custom-enabled-themes))
         (target (if (eq current 'lambda-light) 'lambda-dark 'lambda-light)))
    (lem-disable-all-themes)
    (load-theme target t)))

;;;; After Load Theme Hook
(defvar lem-after-load-theme-hook nil
  "Hook run after a color theme is loaded using `load-theme'.")
(define-advice load-theme (:after (&rest _) lem-run-after-load-theme-hook)
  "Run `lem-after-load-theme-hook'."
  (run-hooks 'lem-after-load-theme-hook))

;;; Provide
(provide 'sp-themes)
;;; sp-themes.el ends here
