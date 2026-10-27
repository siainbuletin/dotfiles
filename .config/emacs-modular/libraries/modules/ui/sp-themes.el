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
    (faded-light lambda-light-faded ef-day ef-melissa-light sp-light)
    (faded-dark  lambda-dark-faded doric-fire)
    (hard-dark   ef-dream sp-dark))
  "The themes in use, in families: a list of (FAMILY THEME...).
The first THEME of a family is the one `sp-load-theme-family' loads."
  :group 'spcustom
  :type '(alist :key-type symbol :value-type (repeat symbol)))

(defun sp-theme-family (theme)
  "Return the family of THEME, or nil if it is not in one."
  (car (seq-find (lambda (family) (memq theme (cdr family)))
                 sp-theme-families)))

;;;; The registry
(defvar sp-theme-metadata-patterns
  '(("(modus-themes-theme[[:space:]]+'\\([^[:space:]]+\\)[[:space:]]+'[^[:space:]]+[[:space:]]+\"\\([^\"]*\\)\"[[:space:]]+'\\(light\\|dark\\)"
     1 2 3)
    ("(\\(?:doric-themes-define-theme\\|sp-theme-define\\)[[:space:]]+\\([^[:space:]]+\\)[[:space:]]+\\(light\\|dark\\)\\(?:[[:space:]]+\"\\([^\"]*\\)\"\\)?"
     1 3 2)
    ("(sp-theme-define[[:space:]]+\\([^[:space:]]+\\)[[:space:]]+[^[:space:]]+[[:space:]]+\"\\([^\"]*\\)\""
     1 2 nil)
    ("(deftheme[[:space:]]+\\([^[:space:])]+\\)\\(?:[[:space:]]+\"\\([^\"]*\\)\"\\)?"
     1 2 nil))
  "How to read a theme file: a list of (REGEXP NAME DESCRIPTION BACKGROUND).
The last three are the numbers of the regexp groups holding that part, or nil.")

(defvar sp-theme-metadata-exceptions
  '(
    ;; (catppuccin :background dark :description "Catppuccin, its flavor is `catppuccin-flavor'") ;; catppuccin has been removed
    )
  "Metadata that a theme file cannot give, an alist of (THEME . PLIST).")

(defun sp-theme--file-metadata (file)
  "Return the plist describing the theme in FILE, or nil if it has no theme."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((guess (intern (string-remove-suffix "-theme.el" (file-name-nondirectory file)))))
      (or (seq-some
           (lambda (pattern)
             (goto-char (point-min))
             (when (re-search-forward (nth 0 pattern) nil t)
               (let* ((group (lambda (n) (and n (match-string-no-properties n))))
                      (name (funcall group (nth 1 pattern)))
                      (description (funcall group (nth 2 pattern)))
                      (background (funcall group (nth 3 pattern))))
                 ;; `split-string' changes the match data: read the groups first.
                 (list :name (intern name)
                       :description (when description
                                      (string-join (split-string description) " "))
                       :background (cond (background (intern background))
                                         ;; A theme made by `sp-theme-import-palette'.
                                         ((progn (goto-char (point-min))
                                                 (re-search-forward ":variant '\\(light\\|dark\\)" nil t))
                                          (intern (match-string-no-properties 1))))))))
           sp-theme-metadata-patterns)
          (list :name guess)))))

(defun sp-theme--background-from-name (name)
  "Guess the background of the theme NAME from its name."
  (cond ((string-match-p "dark\\|night\\|dream\\|vivendi" (symbol-name name)) 'dark)
        ((string-match-p "light\\|day\\|operandi" (symbol-name name)) 'light)))

(defun sp-theme--scan ()
  "Read every theme file of the themes folder and return the registry."
  (let ((root sp-custom-themes-dir) entries)
    (dolist (dir (append (list (cons (expand-file-name "active/" root) "active")
                               (cons (expand-file-name "sp/" root) "sp"))
                         (mapcar (lambda (d) (cons d (file-name-nondirectory d)))
                                 (sp-themes-library-dirs))))
      (when (file-directory-p (car dir))
        (dolist (file (directory-files (car dir) t "-theme\\.el\\'"))
          (when-let* ((meta (sp-theme--file-metadata file))
                      (name (plist-get meta :name)))
            (let ((entry (append meta
                                 (list :file file
                                       :package (cdr dir)
                                       :folder (if (member (cdr dir) '("active" "sp"))
                                                   (cdr dir)
                                                 "library")
                                       :family (sp-theme-family name)))))
              (setq entry (append (alist-get name sp-theme-metadata-exceptions) entry))
              (unless (plist-get entry :background)
                (setq entry (plist-put entry :background (sp-theme--background-from-name name))))
              (push entry entries))))))
    (sort entries (lambda (a b) (string< (plist-get a :name) (plist-get b :name))))))

(defvar sp-theme--registry nil
  "The cached registry, see `sp-theme-registry'.")

(defun sp-theme-registry (&optional refresh)
  "Return the list of theme plists, reading the theme files if needed.
With REFRESH, read them again."
  (when (or refresh (null sp-theme--registry))
    (setq sp-theme--registry (sp-theme--scan))
    (dolist (family sp-theme-families)
      (dolist (theme (cdr family))
        (unless (sp-theme-info theme)
          (message "sp-themes: %s, in the family %s, has no theme file" theme (car family))))))
  sp-theme--registry)

(defun sp-theme-info (theme)
  "Return the registry plist of THEME, or nil."
  (seq-find (lambda (entry) (eq (plist-get entry :name) theme))
            (or sp-theme--registry (sp-theme-registry))))

(defun sp-themes-rescan ()
  "Read the theme files again, after adding or moving one."
  (interactive)
  (message "%d themes" (length (sp-theme-registry t))))

(defun sp-theme-dark-p ()
  "Return non-nil if the default background is dark."
  (when-let* ((bg (face-background 'default nil t))
              (rgb (ignore-errors (color-values bg))))
    (< (apply #'+ rgb) (* 3 32768))))

;;;; The sp themes
(autoload 'sp-theme-set-color "sp-theme-engine" nil t)
(autoload 'sp-theme-set-mapping "sp-theme-engine" nil t)
(autoload 'sp-theme-reload "sp-theme-engine" nil t)
(autoload 'sp-theme-color "sp-theme-engine")
(autoload 'sp-theme-role "sp-theme-engine")

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
  "Return an alist of (NAME . GROUP) for the themes `sp-load-theme' offers.
The themes of each family come first, in the order of `sp-theme-families',
then the other themes of `active/' and `sp/', then the library."
  (let (cands)
    (dolist (family sp-theme-families)
      (dolist (theme (cdr family))
        (when (sp-theme-info theme)
          (push (cons (symbol-name theme) (symbol-name (car family))) cands))))
    (dolist (entry (sp-theme-registry))
      (let ((name (symbol-name (plist-get entry :name))))
        (unless (assoc name cands)
          (push (cons name (if (equal (plist-get entry :folder) "library")
                               (format "library: %s" (plist-get entry :package))
                             "other"))
                cands))))
    (nreverse cands)))

(defun sp-theme--annotate (name)
  "Return the annotation of the theme NAME: background, package, description."
  (when-let* ((info (sp-theme-info (intern name))))
    (format "  %s  %s  %s"
            (or (plist-get info :background) "?")
            (plist-get info :package)
            (truncate-string-to-width (or (plist-get info :description) "") 70 nil nil t))))

(defun sp-theme--read (prompt)
  "Read a theme name with PROMPT, grouped by family, and return the symbol."
  (let* ((cands (sp-theme--candidates))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      `(metadata
                        (display-sort-function . identity)
                        (cycle-sort-function . identity)
                        (annotation-function . ,#'sp-theme--annotate)
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

(defcustom sp-theme-auto-source 'system
  "Where `sp-theme-auto-mode' reads light or dark from.
`system' asks the operating system, `ambient' asks the light sensor
\(macOS) and loads one of the four families, and `time' uses the time
of day.  A source that has no
answer falls back to `time'."
  :group 'spcustom
  :type '(choice (const :tag "The system appearance" system)
                 (const :tag "The light level in the room (macOS)" ambient)
                 (const :tag "The time of day" time)))

(defcustom sp-theme-system-providers
  '((macos   . sp-macos-appearance)
    (windows . sp-syswin-appearance)
    (linux   . sp-syslinux-appearance))
  "The function that reads the system appearance, per platform.
An alist of (PLATFORM . FUNCTION), PLATFORM being what
`sp-theme-platform' returns.  FUNCTION takes no arguments and returns
`light', `dark' or nil."
  :group 'spcustom
  :type '(alist :key-type symbol :value-type function))

(defcustom sp-theme-system-watchers
  '((macos . sp-macos-watch-appearance)
    (linux . sp-syslinux-watch-appearance))
  "The function that watches the system appearance, per platform.
FUNCTION takes a callback, calls it with `light' or `dark' when the
system changes, and returns a function that stops watching (or nil
when it cannot watch)."
  :group 'spcustom
  :type '(alist :key-type symbol :value-type function))

(defcustom sp-theme-ambient-providers
  '((macos . sp-macos-ambient-family))
  "The function that reads the light level of the room, per platform.
An alist of (PLATFORM . FUNCTION).  FUNCTION takes no arguments and
returns a family of `sp-theme-families', or nil when it cannot tell."
  :group 'spcustom
  :type '(alist :key-type symbol :value-type function))

(defcustom sp-theme-ambient-interval 60
  "Seconds between the checks of the timer when the source is `ambient'."
  :group 'spcustom
  :type 'integer)

(defun sp-theme-platform ()
  "Return `macos', `windows' or `linux' for this system, or nil."
  (pcase system-type
    ('darwin 'macos)
    ((or 'windows-nt 'cygwin 'ms-dos) 'windows)
    ('gnu/linux 'linux)))

(defun sp-theme--platform-function (alist)
  "Return the function ALIST has for this platform, if it can be called.
The platform module is required first, so that this works whatever
the load order is."
  (let ((fn (alist-get (sp-theme-platform) alist)))
    (when fn
      (unless (fboundp fn)
        (let ((feature (pcase (sp-theme-platform)
                         ('macos 'sp-macos)
                         ('windows 'sp-syswin)
                         ('linux 'sp-syslinux))))
          (require feature nil t)))
      (and (fboundp fn) fn))))

(defcustom sp-theme-day-hours '(7 . 19)
  "The hours (FROM . TO) in which the `time' source says light."
  :group 'spcustom
  :type '(cons integer integer))

(defun sp-theme-load-appearance (appearance)
  "Load the theme for APPEARANCE, `light' or `dark', unless it is current."
  (let ((target (alist-get appearance sp-theme-appearance-themes)))
    (unless (or (null target) (eq target (car custom-enabled-themes)))
      (sp-load-theme target))))

(defun sp-theme--time-appearance ()
  "Return `light' during `sp-theme-day-hours', `dark' otherwise."
  (let ((hour (decoded-time-hour (decode-time))))
    (if (and (>= hour (car sp-theme-day-hours)) (< hour (cdr sp-theme-day-hours)))
        'light
      'dark)))

(defun sp-theme--provided-appearance (alist)
  "Return `light' or `dark' from the provider ALIST has for this platform."
  (let ((fn (sp-theme--platform-function alist)))
    (when fn
      (let ((appearance (condition-case nil (funcall fn) (error nil))))
        (and (memq appearance '(light dark)) appearance)))))

(defun sp-theme--system-appearance ()
  "Return the system appearance, `light' or `dark', or nil if unknown."
  (sp-theme--provided-appearance sp-theme-system-providers))

(defun sp-theme--ambient-family ()
  "Return the family the light level of the room asks for, or nil."
  (let ((fn (and (eq sp-theme-auto-source 'ambient)
                 (sp-theme--platform-function sp-theme-ambient-providers))))
    (when fn
      (let ((family (condition-case nil (funcall fn) (error nil))))
        (and (assq family sp-theme-families) family)))))

(defun sp-theme-appearance ()
  "Return `light' or `dark' according to `sp-theme-auto-source'."
  (or (and (eq sp-theme-auto-source 'system) (sp-theme--system-appearance))
      (sp-theme--time-appearance)))

(defun sp-theme-sync (&rest _)
  "Load the theme for the light level, or for the appearance.
With the source `ambient' the family the sensor asks for is loaded;
without a reading, and with the other sources, the theme for the
appearance `sp-theme-appearance' reports."
  (interactive)
  (let ((family (sp-theme--ambient-family)))
    (if family
        (let ((theme (cadr (assq family sp-theme-families))))
          (unless (eq theme (car custom-enabled-themes))
            (sp-load-theme theme)))
      (sp-theme-load-appearance (sp-theme-appearance)))))

(defun toggle-dark-light-theme ()
  "Switch between the light and the dark theme of `sp-theme-appearance-themes'."
  (interactive)
  (sp-theme-load-appearance (if (sp-theme-dark-p) 'light 'dark)))

(defcustom sp-theme-auto-interval 900
  "Seconds between the checks of the timer of `sp-theme-auto-mode'."
  :group 'spcustom
  :type 'integer)

(defvar sp-theme--auto-timer nil
  "The timer of `sp-theme-auto-mode', if one is running.")

(defvar sp-theme--auto-unwatch nil
  "The function that stops the system watcher of `sp-theme-auto-mode'.")

(defun sp-theme--on-system-change (appearance)
  "Load the theme for APPEARANCE when the system flips and it is the source."
  (when (eq sp-theme-auto-source 'system)
    (sp-theme-load-appearance appearance)))

(defun sp-theme--stop-auto ()
  "Stop the timer and the watcher of `sp-theme-auto-mode'."
  (when (timerp sp-theme--auto-timer)
    (cancel-timer sp-theme--auto-timer)
    (setq sp-theme--auto-timer nil))
  (when (functionp sp-theme--auto-unwatch)
    (ignore-errors (funcall sp-theme--auto-unwatch)))
  (setq sp-theme--auto-unwatch nil))

(define-minor-mode sp-theme-auto-mode
  "Load the light or the dark theme as the appearance changes."
  :global t
  :group 'spcustom
  (sp-theme--stop-auto)
  (if sp-theme-auto-mode
      (let* ((watch (and (eq sp-theme-auto-source 'system)
                         (sp-theme--platform-function sp-theme-system-watchers)))
             (unwatch (and watch
                           (ignore-errors
                             (funcall watch #'sp-theme--on-system-change))))
             (interval (if (eq sp-theme-auto-source 'ambient)
                           sp-theme-ambient-interval
                         sp-theme-auto-interval)))
        (setq sp-theme--auto-unwatch unwatch)
        (add-hook 'server-after-make-frame-hook #'sp-theme-sync)
        (unless unwatch
          (setq sp-theme--auto-timer
                (run-with-timer interval interval #'sp-theme-sync)))
        (sp-theme-sync))
    (remove-hook 'server-after-make-frame-hook #'sp-theme-sync)))

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
