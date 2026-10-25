;;; sp-theme-engine.el --- Flavors, semantic mappings and the sp themes -*- lexical-binding: t; -*-

;;; Commentary:

;; The engine behind the `sp-dark' and `sp-light' themes in
;; `libraries/themes/sp/'.  See the literate source in
;; `docs/tangles/ui/sp-theme-engine.org'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'doric-themes)

(defgroup sp-theme nil
  "Flavors, semantic mappings and faces of the sp themes."
  :group 'faces)

;;;; Flavors
(defvar sp-theme-flavors
  (copy-tree
   '((dark
     :colors ((bg-main . "#232025")
              (fg-main . "#efd5c5")
              (cursor  . "#f3c09a")
              (border  . "#635850")
              (red     . "#ff6f6f")
              (green   . "#51b04f")
              (yellow  . "#c0b24f")
              (blue    . "#57b0ff")
              (magenta . "#ffaacf")
              (cyan    . "#6fb3c0")
              (accent-1 . "#d09950")
              (accent-2 . "#d0b0ff"))
     :tint 0.28
     :mappings nil
     :semantic nil)
    (light
     :colors ((bg-main . "#fff5ea")
              (fg-main . "#584141")
              (cursor  . "#cf1f00")
              (border  . "#c8bdb6")
              (red     . "#ba2d2f")
              (green   . "#007a0a")
              (yellow  . "#a45a22")
              (blue    . "#375cc6")
              (magenta . "#ca3e54")
              (cyan    . "#2f7a8c")
              (accent-1 . "#b75515")
              (accent-2 . "#8448aa"))
     :tint 0.16
     :mappings nil
     :semantic nil)))
  "The flavors of the sp themes, an alist of (FLAVOR . PLIST).
Change a colour with `sp-theme-set-color'.")

(defun sp-theme--flavor (flavor)
  "Return the plist of FLAVOR, an error if there is no such flavor."
  (or (alist-get flavor sp-theme-flavors)
      (error "No flavor `%s' in `sp-theme-flavors'" flavor)))

(defun sp-theme-color (name &optional flavor)
  "Return the base colour NAME of FLAVOR (default: the current flavor)."
  (alist-get name (plist-get (sp-theme--flavor (or flavor (sp-theme-current-flavor)))
                             :colors)))

(defun sp-theme-set-color (name value &optional flavor)
  "Set the base colour NAME of FLAVOR to VALUE and reload the theme."
  (interactive
   (let* ((flavor (intern (completing-read "Flavor: " '("dark" "light") nil t)))
          (names (mapcar (lambda (c) (symbol-name (car c)))
                         (plist-get (sp-theme--flavor flavor) :colors)))
          (name (intern (completing-read "Colour: " names nil t))))
     (list name (read-string (format "%s of %s: " name flavor)
                             (sp-theme-color name flavor))
           flavor)))
  (let* ((flavor (or flavor (sp-theme-current-flavor)))
         (colors (plist-get (sp-theme--flavor flavor) :colors)))
    (setcdr (assq name colors) value)
    (sp-theme-reload)))

(defun sp-theme-current-flavor ()
  "Return the flavor of the enabled sp theme, `dark' if there is none."
  (or (seq-some (lambda (theme) (get theme 'sp-theme-flavor)) custom-enabled-themes)
      'dark))

(defun sp-theme-reload ()
  "Load the current sp theme again, to pick up changed colours."
  (interactive)
  (when-let* ((theme (seq-find (lambda (th) (string-prefix-p "sp-" (symbol-name th)))
                               custom-enabled-themes)))
    (disable-theme theme)
    (load-theme theme t)))

;;;; Palette
(defun sp-theme--rgb (hex)
  "Return the (R G B) components, 0 to 255, of the colour HEX."
  (unless (string-match "\\`#\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\'" hex)
    (error "Not a #rrggbb colour: %S" hex))
  (mapcar (lambda (i) (string-to-number (match-string i hex) 16)) '(1 2 3)))

(defun sp-theme-blend (a b weight)
  "Return the colour made of WEIGHT (0 to 1) of B and the rest of A."
  (apply #'format "#%02x%02x%02x"
         (cl-mapcar (lambda (x y) (round (+ (* x (- 1 weight)) (* y weight))))
                    (sp-theme--rgb a) (sp-theme--rgb b))))

(defun sp-theme-palette (&optional flavor)
  "Return the Doric palette of FLAVOR, a list of (KEY COLOR)."
  (let* ((flavor (or flavor (sp-theme-current-flavor)))
         (tint (plist-get (sp-theme--flavor flavor) :tint))
         (c (lambda (name) (sp-theme-color name flavor)))
         (bg (funcall c 'bg-main))
         (fg (funcall c 'fg-main))
         (a1 (funcall c 'accent-1))
         (a2 (funcall c 'accent-2)))
    `((cursor ,(funcall c 'cursor))
      (bg-main ,bg)
      (fg-main ,fg)
      (border ,(funcall c 'border))
      (bg-shadow-subtle ,(sp-theme-blend bg fg 0.08))
      (fg-shadow-subtle ,(sp-theme-blend fg bg 0.35))
      (bg-neutral ,(sp-theme-blend bg fg 0.18))
      (fg-neutral ,(sp-theme-blend fg bg 0.12))
      (bg-shadow-intense ,(sp-theme-blend bg a1 (+ tint 0.12)))
      (fg-shadow-intense ,a1)
      (bg-accent-primary ,(sp-theme-blend bg a1 tint))
      (fg-accent-primary ,(sp-theme-blend a1 fg 0.25))
      (bg-accent-secondary ,(sp-theme-blend bg a2 tint))
      (fg-accent-secondary ,(sp-theme-blend a2 fg 0.25))
      ,@(mapcan (lambda (hue)
                  (let ((color (funcall c hue)))
                    (list (list (intern (format "fg-%s" hue)) color)
                          (list (intern (format "bg-%s" hue))
                                (sp-theme-blend bg color tint)))))
                '(red green yellow blue magenta cyan)))))

;;;; Semantic mappings
(defvar sp-theme-mappings
  '((fg-link . fg-blue)
    (fg-link-visited . fg-magenta)
    (bg-region . bg-accent-primary)
    (fg-region . fg-main)
    (bg-hl-line . bg-shadow-subtle)
    (bg-mode-line-active . bg-neutral)
    (fg-mode-line-active . fg-main)
    (bg-mode-line-inactive . bg-shadow-subtle)
    (fg-mode-line-inactive . fg-shadow-subtle)
    (bg-search-current . bg-yellow)
    (bg-search-lazy . bg-accent-secondary)
    (err . fg-red)
    (warning . fg-yellow)
    (success . fg-green)
    (info . fg-cyan)
    (fg-heading-1 . fg-accent-primary)
    (fg-heading-2 . fg-accent-secondary)
    (fg-heading-3 . fg-green)
    (fg-heading-4 . fg-blue)
    (fg-heading-other . fg-shadow-intense)
    (fg-prose-code . fg-cyan)
    (fg-prose-verbatim . fg-yellow)
    (bg-prose-block . bg-shadow-subtle)
    (fg-prose-block-delimiter . fg-shadow-subtle))
  "Semantic roles of the sp themes, an alist of (ROLE . TARGET).
TARGET is a key of the palette, another role, or a #rrggbb string.")

(defun sp-theme-role (role &optional flavor)
  "Return the colour that ROLE has in FLAVOR, or nil if it has none."
  (let* ((flavor (or flavor (sp-theme-current-flavor)))
         (palette (sp-theme-palette flavor))
         (own (plist-get (sp-theme--flavor flavor) :mappings))
         (target role)
         (steps 0))
    (while (and target (symbolp target) (< steps 10))
      (setq steps (1+ steps)
            target (or (alist-get target own)
                       (alist-get target sp-theme-mappings)
                       (cadr (assq target palette)))))
    (when (stringp target) target)))

(defun sp-theme-set-mapping (role target &optional flavor)
  "Make ROLE point at TARGET in FLAVOR, or in every flavor if nil, and reload."
  (interactive
   (list (intern (completing-read "Role: " (mapcar (lambda (m) (symbol-name (car m)))
                                                    sp-theme-mappings)
                                  nil t))
         (intern (read-string "Target (palette key or role): "))
         nil))
  (dolist (flavor (if flavor (list flavor) (mapcar #'car sp-theme-flavors)))
    (let ((cell (plist-member (sp-theme--flavor flavor) :mappings)))
      (setcar (cdr cell) (cons (cons role target) (assq-delete-all role (cadr cell))))))
  (sp-theme-reload))

(defvar sp-theme-mapped-faces
  '((region :background bg-region :foreground fg-region :extend t)
    (hl-line :background bg-hl-line :extend t)
    (mode-line :background bg-mode-line-active :foreground fg-mode-line-active)
    (mode-line-active :inherit mode-line)
    (mode-line-inactive :background bg-mode-line-inactive :foreground fg-mode-line-inactive)
    (link :foreground fg-link :underline t)
    (link-visited :foreground fg-link-visited :underline t)
    (isearch :background bg-search-current :foreground fg-main)
    (lazy-highlight :background bg-search-lazy :foreground fg-main)
    (error :foreground err)
    (warning :foreground warning)
    (success :foreground success)
    (org-level-1 :foreground fg-heading-1)
    (org-level-2 :foreground fg-heading-2)
    (org-level-3 :foreground fg-heading-3)
    (org-level-4 :foreground fg-heading-4)
    (org-level-5 :foreground fg-heading-other)
    (org-level-6 :foreground fg-heading-other)
    (org-level-7 :foreground fg-heading-other)
    (org-level-8 :foreground fg-heading-other)
    (outline-1 :foreground fg-heading-1)
    (outline-2 :foreground fg-heading-2)
    (outline-3 :foreground fg-heading-3)
    (outline-4 :foreground fg-heading-4)
    (outline-5 :foreground fg-heading-other)
    (outline-6 :foreground fg-heading-other)
    (outline-7 :foreground fg-heading-other)
    (outline-8 :foreground fg-heading-other)
    (markdown-header-face-1 :foreground fg-heading-1)
    (markdown-header-face-2 :foreground fg-heading-2)
    (markdown-header-face-3 :foreground fg-heading-3)
    (markdown-header-face-4 :foreground fg-heading-4)
    (markdown-header-face-5 :foreground fg-heading-other)
    (markdown-header-face-6 :foreground fg-heading-other)
    (org-code :foreground fg-prose-code)
    (org-verbatim :foreground fg-prose-verbatim)
    (org-block :background bg-prose-block :extend t)
    (org-block-begin-line :foreground fg-prose-block-delimiter :extend t)
    (org-block-end-line :foreground fg-prose-block-delimiter :extend t))
  "Faces of the sp themes written against `sp-theme-mappings'.
Each entry is (FACE ATTRIBUTE VALUE ...); colour values that name a role
are replaced by the colour of that role.")

(defconst sp-theme--colour-attributes
  '(:foreground :background :distant-foreground :overline)
  "The face attributes whose value may be a role.")

(defun sp-theme--face-attributes (entry flavor)
  "Return the attribute list of ENTRY in FLAVOR, with the roles replaced."
  (let ((attrs (cdr entry)) result)
    (while attrs
      (let* ((attr (pop attrs))
             (value (pop attrs)))
        (when (and (memq attr sp-theme--colour-attributes) (symbolp value))
          (setq value (sp-theme-role value flavor)))
        (when value
          (setq result (append result (list attr value))))))
    result))

;;;; Semantic face names
(defface sp-fg nil "The main foreground." :group 'sp-theme)
(defface sp-bg nil "The main background." :group 'sp-theme)
(defface sp-ultralight nil "A bright background highlight." :group 'sp-theme)
(defface sp-highlight nil "A background highlight." :group 'sp-theme)
(defface sp-lowlight nil "A dim background highlight." :group 'sp-theme)
(defface sp-urgent nil "Needs attention now: errors, overdue." :group 'sp-theme)
(defface sp-crucial nil "Important: warnings, deadlines." :group 'sp-theme)
(defface sp-focus nil "Useful or pertinent: links, the current item." :group 'sp-theme)
(defface sp-strong nil "A structural accent against the normal foreground." :group 'sp-theme)
(defface sp-meek nil "Useful but less important text." :group 'sp-theme)
(defface sp-mild nil "Background noise: separators." :group 'sp-theme)
(defface sp-faint nil "The faintest background." :group 'sp-theme)

(defvar sp-theme-semantic
  '((sp-fg :foreground fg-main)
    (sp-bg :background bg-main)
    (sp-ultralight :background bg-neutral)
    (sp-highlight :background bg-hl-line)
    (sp-lowlight :background bg-shadow-subtle)
    (sp-urgent :foreground err)
    (sp-crucial :foreground warning)
    (sp-focus :foreground fg-link)
    (sp-strong :foreground fg-main :weight bold)
    (sp-meek :foreground fg-shadow-subtle)
    (sp-mild :foreground fg-neutral)
    (sp-faint :background bg-shadow-subtle))
  "The semantic faces of the sp themes, entries like `sp-theme-mapped-faces'.")

;;;; Ported Modus mechanisms
(defcustom sp-theme-headings
  '((title :weight bold :height 1.4)
    (1 :weight bold :height 1.25)
    (2 :weight bold :height 1.15)
    (3 :weight bold :height 1.05)
    (t :weight bold))
  "Attributes of the headings in the sp themes.
An alist of (LEVEL . ATTRIBUTES), LEVEL being 1 to 8, `title' or t for
the levels not listed."
  :group 'sp-theme
  :type '(alist :key-type (choice integer symbol) :value-type (plist)))

(defvar sp-theme-heading-faces
  '((title org-document-title)
    (1 org-level-1 outline-1 markdown-header-face-1 info-title-1)
    (2 org-level-2 outline-2 markdown-header-face-2 info-title-2)
    (3 org-level-3 outline-3 markdown-header-face-3 info-title-3)
    (4 org-level-4 outline-4 markdown-header-face-4 info-title-4)
    (5 org-level-5 outline-5 markdown-header-face-5)
    (6 org-level-6 outline-6 markdown-header-face-6)
    (7 org-level-7 outline-7)
    (8 org-level-8 outline-8))
  "The faces that are the headings of each level, see `sp-theme-headings'.")

(defun sp-theme--heading-faces ()
  "Return a list of (FACE . ATTRIBUTES) for `sp-theme-headings'."
  (mapcan (lambda (level)
            (when-let* ((attrs (or (cdr (assq (car level) sp-theme-headings))
                                   (and (integerp (car level))
                                        (cdr (assq t sp-theme-headings))))))
              (mapcar (lambda (face) (cons face attrs))
                      (cdr level))))
          sp-theme-heading-faces))

(defcustom sp-theme-mixed-fonts t
  "When non-nil, code, tables and markup stay fixed-pitch."
  :group 'sp-theme
  :type 'boolean)

(defvar sp-theme-fixed-pitch-faces
  '(org-block org-block-begin-line org-block-end-line org-code org-verbatim
    org-table org-formula org-meta-line org-checkbox org-date org-drawer
    org-special-keyword org-property-value org-cite-key org-footnote
    markdown-code-face markdown-pre-face markdown-inline-code-face
    markdown-language-keyword-face markdown-table-face markdown-metadata-key-face
    markdown-metadata-value-face line-number)
  "The faces that stay fixed-pitch with `sp-theme-mixed-fonts'.")

(defcustom sp-theme-variable-pitch-ui nil
  "When non-nil, the mode line, header line and tabs use `variable-pitch'."
  :group 'sp-theme
  :type 'boolean)

(defvar sp-theme-ui-faces
  '(mode-line mode-line-active mode-line-inactive header-line tab-bar
    tab-bar-tab tab-bar-tab-inactive tab-line tab-line-tab
    tab-line-tab-current tab-line-tab-inactive)
  "The faces of the user interface chrome, see `sp-theme-variable-pitch-ui'.")

;;;; Defining a theme
(defun sp-theme--plist (attrs)
  "Return ATTRS as a plain plist, whether it is one or a list holding one."
  (if (and (= (length attrs) 1) (listp (car attrs))) (car attrs) attrs))

(defun sp-theme--merge-attrs (old new)
  "Return the plist OLD with the attributes of the plist NEW added.
`:inherit' values are joined, any other attribute of NEW replaces the old one."
  (let ((result (copy-sequence (sp-theme--plist old))))
    (while new
      (let ((attr (pop new))
            (value (pop new)))
        (if (eq attr :inherit)
            (let ((joined (delete-dups
                           (append (ensure-list (plist-get result :inherit))
                                   (ensure-list value)))))
              (setq result (plist-put result :inherit
                                      (if (cdr joined) joined (car joined)))))
          (setq result (plist-put result attr value)))))
    result))

(defun sp-theme--drop-old-settings (theme face)
  "Keep only the newest setting of FACE in THEME.
Emacs records every `custom-theme-set-faces' call of a theme, and when the
theme is enabled the oldest record of a face wins, so a second call would
have no effect."
  (let* ((same (lambda (setting)
                 (and (eq (car setting) 'theme-face) (eq (cadr setting) face))))
         (settings (get theme 'theme-settings))
         (newest (seq-find same settings)))
    (put theme 'theme-settings (cons newest (seq-remove same settings)))))

(defun sp-theme--set-face (theme face attrs)
  "Add ATTRS to FACE in THEME, keeping what THEME already sets for it."
  (let* ((old (nth 3 (seq-find (lambda (setting)
                                 (and (eq (car setting) 'theme-face)
                                      (eq (cadr setting) face)))
                               (get theme 'theme-settings))))
         (clauses (or old '((t)))))
    (custom-theme-set-faces
     theme
     (list face (mapcar (lambda (clause)
                          (cons (car clause)
                                (sp-theme--merge-attrs (cdr clause) attrs)))
                        clauses)))
    (sp-theme--drop-old-settings theme face)))

(defun sp-theme--merge (shared own)
  "Return SHARED with the entries of OWN replacing those of the same name."
  (append (seq-remove (lambda (e) (assq (car e) own)) shared) own))

(defun sp-theme--extend (theme flavor)
  "Add the mapped, semantic and ported faces to THEME of FLAVOR."
  (put theme 'sp-theme-flavor flavor)
  (let ((own-semantic (plist-get (sp-theme--flavor flavor) :semantic)))
    (dolist (entry (append sp-theme-mapped-faces
                           (sp-theme--merge sp-theme-semantic own-semantic)))
      (sp-theme--set-face theme (car entry) (sp-theme--face-attributes entry flavor))))
  (dolist (entry (sp-theme--heading-faces))
    (sp-theme--set-face theme (car entry) (cdr entry)))
  (when sp-theme-mixed-fonts
    (dolist (face sp-theme-fixed-pitch-faces)
      (sp-theme--set-face theme face '(:inherit fixed-pitch))))
  (when sp-theme-variable-pitch-ui
    (dolist (face sp-theme-ui-faces)
      (sp-theme--set-face theme face '(:inherit variable-pitch)))))

(defmacro sp-theme-define (name flavor &optional description)
  "Define the theme NAME from FLAVOR, `dark' or `light'.
DESCRIPTION is the one-line description of the theme."
  (declare (indent 0))
  (let ((palette (intern (format "%s-palette" name))))
    (set palette (sp-theme-palette flavor))
    `(progn
       (defvar ,palette nil)
       (setq ,palette ',(sp-theme-palette flavor))
       (doric-themes-define-theme ,name ,flavor ,description)
       (sp-theme--extend ',name ',flavor))))

(provide 'sp-theme-engine)
;;; sp-theme-engine.el ends here
