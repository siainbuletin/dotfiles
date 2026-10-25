;;; sp-themes.el --- Theme folders, families and sp-load-theme -*- lexical-binding: t; -*-

;;; Commentary:

;; Every theme is vendored in `libraries/themes/' (see the README.org
;; there) and every theme is loaded with `sp-load-theme'.  Themes are
;; grouped in four families, after the Lambda themes: hard light, faded
;; light, faded dark and hard dark.

;;; Code:

;;;; No-confirm themes
;; Hard-coded on purpose: custom.el is never loaded (see early-init.el).
(setq custom-safe-themes t)

;;;; Configuring the custom theme folder
(defcustom sp-custom-themes-dir (concat sp-library-dir "themes/")
  "The folder with the vendored themes, see its README.org."
  :group 'spcustom
  :type 'directory)

(setq-default custom-theme-directory sp-custom-themes-dir)

;;;; Paths
(defun sp-themes--subdirs (dir)
  "Return the subfolders of DIR, or nil if DIR does not exist."
  (when (file-directory-p dir)
    (seq-filter #'file-directory-p
                (directory-files dir t directory-files-no-dot-files-regexp))))

(defun sp-themes-library-dirs ()
  "Return the package folders of the theme library."
  (sp-themes--subdirs (expand-file-name "library/" sp-custom-themes-dir)))

(add-to-list 'load-path (expand-file-name "lib/" sp-custom-themes-dir))

(dolist (dir (append (sp-themes-library-dirs)
                     (list (expand-file-name "sp/" sp-custom-themes-dir)
                           (expand-file-name "active/" sp-custom-themes-dir))))
  (add-to-list 'custom-theme-load-path dir))

;;;; Theme families
(defcustom sp-theme-families
  '((hard-light  lambda-light)
    (faded-light lambda-light-faded ef-day ef-melissa-light)
    (faded-dark  lambda-dark-faded doric-fire)
    (hard-dark   ef-dream))
  "The themes in use, in families: a list of (FAMILY THEME...).
The first THEME of a family is the one `sp-load-theme-family' loads."
  :group 'spcustom
  :type '(alist :key-type symbol :value-type (repeat symbol)))

(defun sp-themes-library ()
  "Return an alist of (THEME . PACKAGE) for every theme in the library."
  (let (themes)
    (dolist (dir (sp-themes-library-dirs))
      (dolist (file (directory-files dir nil "-theme\\.el\\'"))
        (push (cons (intern (string-remove-suffix "-theme.el" file))
                    (file-name-nondirectory dir))
              themes)))
    (sort themes (lambda (a b) (string< (car a) (car b))))))

(defun sp-theme-family (theme)
  "Return the family of THEME, or nil if it is not in one."
  (car (seq-find (lambda (family) (memq theme (cdr family)))
                 sp-theme-families)))

(defun sp-theme-dark-p ()
  "Return non-nil if the default background is dark."
  (when-let* ((bg (face-background 'default nil t))
              (rgb (ignore-errors (color-values bg))))
    (< (apply #'+ rgb) (* 3 32768))))

;;;; Never ask for confirmation
(define-advice load-theme (:filter-args (args) sp-no-confirm)
  "Always pass NO-CONFIRM, so a theme is never refused or asked about."
  (list (nth 0 args) t (nth 2 args)))

;;;; Options of the theme packages
;; Modus engine (also used by the Ef themes)
(setq modus-themes-italic-constructs t
      modus-themes-bold-constructs nil
      modus-themes-mixed-fonts t
      modus-themes-variable-pitch-ui nil)

;; Lambda themes
(setq lambda-themes-set-italic-comments t
      lambda-themes-set-italic-keywords t
      lambda-themes-set-variable-pitch t)

;;;; Palette overrides
(defcustom sp-theme-palette-overrides nil
  "Palette overrides per theme, an alist of (THEME . OVERRIDES).
OVERRIDES is a list of (NAME COLOR) as in `ef-day-palette-overrides'.
Only the Ef and Modus themes support them."
  :group 'spcustom
  :type '(alist :key-type symbol
                :value-type (repeat (list symbol (choice symbol string)))))

(defun sp-theme--apply-overrides (theme)
  "Set the palette overrides of THEME, if it has any."
  (when-let* ((overrides (alist-get theme sp-theme-palette-overrides)))
    (if (string-match-p "\\`\\(ef\\|modus\\)-" (symbol-name theme))
        (set (intern (format "%s-palette-overrides" theme)) overrides)
      (message "sp-themes: %s has no palette overrides, ignoring them" theme))))

;;;; The one way to load a theme
(defcustom sp-theme-disable-others 'after-load
  "What `sp-load-theme' does to the themes that were enabled.
`after-load' disables them once the new theme has loaded.  Nil leaves
them enabled, so their faces stay under the new theme."
  :group 'spcustom
  :type '(choice (const :tag "Disable after the new theme loads" after-load)
                 (const :tag "Leave enabled" nil)))

(defvar sp-theme-history nil
  "Minibuffer history of `sp-load-theme'.")

(defun sp-theme--candidates ()
  "Return an alist of (NAME . GROUP) for the themes `sp-load-theme' offers."
  (let (cands)
    (dolist (family sp-theme-families)
      (dolist (theme (cdr family))
        (push (cons (symbol-name theme) (symbol-name (car family))) cands)))
    (dolist (entry (sp-themes-library))
      (unless (assoc (symbol-name (car entry)) cands)
        (push (cons (symbol-name (car entry))
                    (format "library: %s" (cdr entry)))
              cands)))
    (nreverse cands)))

(defun sp-theme--read (prompt)
  "Read a theme name with PROMPT, grouped by family, and return the symbol."
  (let* ((cands (sp-theme--candidates))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      `(metadata
                        (display-sort-function . identity)
                        (cycle-sort-function . identity)
                        (group-function
                         . ,(lambda (cand transform)
                              (if transform cand (cdr (assoc cand cands))))))
                    (complete-with-action action cands string pred)))))
    (intern (completing-read prompt table nil t nil 'sp-theme-history
                             (when custom-enabled-themes
                               (symbol-name (car custom-enabled-themes)))))))

(defun sp-load-theme (theme)
  "Load THEME, the one way themes are loaded in this configuration.
Interactively, choose among the families first and the library after."
  (interactive (list (sp-theme--read "Load theme: ")))
  (let ((previous custom-enabled-themes))
    (sp-theme--apply-overrides theme)
    (load-theme theme t)
    (when (eq sp-theme-disable-others 'after-load)
      (dolist (old (remq theme previous))
        (disable-theme old)))
    theme))

(defun sp-load-theme-family (family)
  "Load the first theme of FAMILY, see `sp-theme-families'."
  (interactive
   (list (intern (completing-read "Theme family: "
                                  (mapcar (lambda (f) (symbol-name (car f)))
                                          sp-theme-families)
                                  nil t))))
  (sp-load-theme (cadr (assq family sp-theme-families))))

;;;; Light and dark
(defcustom sp-theme-appearance-themes
  '((light . lambda-light-faded)
    (dark  . ef-dream))
  "The theme for the system appearance, an alist of (APPEARANCE . THEME)."
  :group 'spcustom
  :type '(alist :key-type (choice (const light) (const dark))
                :value-type symbol))

(defun sp-theme-load-appearance (appearance)
  "Load the theme for APPEARANCE, `light' or `dark', unless it is current."
  (let ((target (alist-get appearance sp-theme-appearance-themes)))
    (unless (or (null target) (eq target (car custom-enabled-themes)))
      (sp-load-theme target))))

(defun toggle-dark-light-theme ()
  "Switch between the light and the dark theme of `sp-theme-appearance-themes'."
  (interactive)
  (sp-theme-load-appearance (if (sp-theme-dark-p) 'light 'dark)))

;;;; After Load Theme Hook
(defvar sp-after-load-theme-hook nil
  "Hook run after a color theme is loaded using `load-theme'.")
(define-advice load-theme (:after (&rest _) sp-run-after-load-theme-hook)
  "Run `sp-after-load-theme-hook'."
  (run-hooks 'sp-after-load-theme-hook))

(with-eval-after-load 'kind-icon
  (add-hook 'sp-after-load-theme-hook #'kind-icon-reset-cache))

(use-package easy-theme-preview
  :ensure t)

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

(provide 'sp-themes)
;;; sp-themes.el ends here
