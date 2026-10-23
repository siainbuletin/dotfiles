;;; sp-dashboard.el --- Custom lambda splash screen -*- lexical-binding: t; -*-

;;; Commentary:

;;
;;  An alternative splash screen:
;; this is also including the ascii art of the lambda sign, which will show up in the dashboard
;; I gotta test to see if it works with the dashboard

;; Note: The screen is not shown if there are opened file buffers. For
;;       example, if you start emacs with a filename on the command
;;       line, the splash is not shown.

;;; Code:

(require 'cl-lib)
;; Guarded require: without this, a sandbox boot without nerd-icons
;; installed would crash module-load here.
;; Spec 02 caught the identical pattern in sp-dashboard.el.
(when (locate-library "nerd-icons")
  (require 'nerd-icons))

(defgroup sp-dashboard nil
  "Extensible splash screen."
  :group 'applications)

;;;; Splash Faces
(defface sp-dashboard-title-face nil
  "Face for splash title."
  :group 'faces)

(defface sp-dashboard-header-face nil
  "Face for splash header."
  :group 'faces)

(defface sp-dashboard-footer-face '((t :slant italic))
  "Face for splash footer."
  :group 'faces)

(defface sp-dashboard-menu-face nil
  "Face for splash menus."
  :group 'faces)

(defface sp-dashboard-box-face '((t :inherit shadow))
  "Face for the lines drawn around the splash menu blocks."
  :group 'faces)

(defface sp-dashboard-image-face nil
  "Face for splash image."
  :group 'faces)

(defface sp-dashboard-art-face
  '((((background dark))  :foreground "#454b5c")
    (((background light)) :foreground "#cfd3dc"))
  "Face for the lambda art behind the splash menu.
The colour follows the background of the current theme, so it changes
with `load-theme' the next time the splash is drawn."
  :group 'faces)

(defface sp-dashboard-banner-face
  '((((background dark))  :foreground "#6b7387")
    (((background light)) :foreground "#9aa1b3"))
  "Face for the dashboard banner art behind the splash menu."
  :group 'faces)

(defface sp-dashboard-accent-1-face '((t :inherit font-lock-keyword-face))
  "First accent of the splash: the line colour of the first menu block."
  :group 'faces)

(defface sp-dashboard-accent-2-face '((t :inherit font-lock-function-name-face))
  "Second accent of the splash: the line colour of the second menu block."
  :group 'faces)

(defface sp-dashboard-accent-3-face '((t :inherit font-lock-string-face))
  "Third accent of the splash: the line colour of the third menu block."
  :group 'faces)

(defface sp-dashboard-focus-face '((t :inherit highlight))
  "Face for the splash button that TAB has selected."
  :group 'faces)

;;;; Splash Variables

;; Init info
;; See https://github.com/emacs-dashboard/emacs-dashboard/blob/master/dashboard-widgets.el
;; https://github.com/hlissner/doom-emacs/blob/eddaae40e84b5eb1f0136aaba23d918f71b6a986/core/core.el#L479
(defcustom sp-dashboard-init-info
  (lambda ()
    (let ((package-count 0) (time (emacs-init-time)))
      (cond ((bound-and-true-p package-alist)
             (setq package-count (length package-activated-list)))
            ((boundp 'straight--profile-cache)
             (setq package-count (+ (hash-table-count straight--profile-cache) package-count))))
      (if (zerop package-count)
          (format "Emacs started in %s" time)
        (format "%d packages loaded in %s" package-count time))))
  "Init info with packages loaded and init time."
  :type '(function string)
  :group 'sp-dashboard)

;; Banner

;; Banner
(defcustom sp-dashboard-banner nil
  "Banner picture for splash-screen"
  :type '(string)
  :group 'sp-dashboard)

(defvar isep "   "
  "Separator for icon and title.")
(defvar ksep "   "
  "Separator for title and key.")

;;;; Art layers
;; Text art drawn behind the menu.  Each layer only fills blanks, so the title
;; and the menu buttons stay on top, and a layer that comes earlier in
;; `sp-dashboard-art-layers' covers the ones after it.

(defcustom sp-dashboard-art-directory "images/"
  "Folder of the splash art files; relative to `sp-library-dir'."
  :type 'directory
  :group 'sp-dashboard)

(defcustom sp-dashboard-art-layers
  (copy-tree
   '((banner :file "dashboard-banner-3.txt" :x 30 :y -8 :face sp-dashboard-banner-face)
     (lambda :file "lambda-splash.txt" :x -50 :y 0 :face sp-dashboard-art-face)))
  "Art drawn behind the splash menu, topmost layer first.
Each element is (NAME :file FILE :x X :y Y :face FACE).  FILE is a text
file (a relative name is looked up in `sp-dashboard-art-directory').  X and
Y move the art right and down from the centre of the window, in columns
and lines (negative: left and up).  Remove an element to hide its layer."
  :type '(alist :key-type symbol :value-type plist)
  :group 'sp-dashboard)

(defcustom sp-dashboard-art-x-step 2
  "Columns the art moves with `sp-dashboard-art-right' and `sp-dashboard-art-left'."
  :type 'integer
  :group 'sp-dashboard)

(defcustom sp-dashboard-art-y-step 1
  "Lines the art moves with `sp-dashboard-art-up' and `sp-dashboard-art-down'."
  :type 'integer
  :group 'sp-dashboard)

(defvar sp-dashboard-art-layer nil
  "Name of the layer the nudge commands move; nil means the first layer.")

(defun sp-dashboard--layer-file (file)
  "Return the path of the art FILE of a layer, or nil when it is missing.
A relative FILE is looked up in `sp-dashboard-art-directory'."
  (let ((path (expand-file-name file (expand-file-name sp-dashboard-art-directory
                                                       sp-library-dir))))
    (and (file-regular-p path) path)))

(defun sp-dashboard--art-lines (file)
  "Return the lines of the art FILE of a layer, or nil when unavailable."
  (when-let* ((path (sp-dashboard--layer-file file)))
    (let ((lines (with-temp-buffer
                   (insert-file-contents path)
                   (split-string (buffer-string) "\n"))))
      ;; Drop blank lines at the end so they don't count as height.
      (while (and lines (string-blank-p (car (last lines))))
        (setq lines (butlast lines)))
      lines)))

(defcustom sp-dashboard-content-layer 'banner
  "Name of the art layer the title and the menu sit under.
The text is centred on this layer, below it.  Nil, or a layer that is not
in `sp-dashboard-art-layers', centres the text on the window."
  :type '(choice (const :tag "Centre on the window" nil) symbol)
  :group 'sp-dashboard)

(defcustom sp-dashboard-footer-layer 'lambda
  "Name of the art layer the footer text is centred on, as for the menu."
  :type '(choice (const :tag "Centre on the window" nil) symbol)
  :group 'sp-dashboard)

(defun sp-dashboard--layer-box (name)
  "Return (LEFT TOP WIDTH HEIGHT) of the art layer NAME in the window, or nil."
  (when-let* ((layer (assq name sp-dashboard-art-layers))
              (lines (sp-dashboard--art-lines (plist-get (cdr layer) :file))))
    (let ((width (apply #'max (mapcar #'length lines)))
          (height (length lines)))
      (list (+ (- (/ (window-width) 2) (/ width 2))
               (or (plist-get (cdr layer) :x) 0))
            (+ (- (/ (window-body-height) 2) (/ height 2))
               (or (plist-get (cdr layer) :y) 0))
            width height))))

(defun sp-dashboard--layer-column (name)
  "Return the middle column of the art layer NAME, or of the window."
  (if-let* ((box (sp-dashboard--layer-box name)))
      (+ (nth 0 box) (/ (nth 2 box) 2))
    (/ (window-width) 2)))

(defun sp-dashboard--content-column ()
  "Return the column the title and the menu are centred on."
  (sp-dashboard--layer-column sp-dashboard-content-layer))

(defun sp-dashboard--put-art-char (col ch face)
  "Put CH in FACE at column COL of the current line if it is blank."
  (move-to-column col)
  (cond ((and (eolp) (<= (current-column) col))
         (insert-char ?\s (- col (current-column)))
         (insert (propertize (string ch) 'face face)))
        ((and (= (current-column) col)
              (eq (char-after) ?\s)
              (not (get-text-property (point) 'face))
              (not (get-text-property (point) 'button))
              (not (get-text-property (point) 'display)))
         (delete-char 1)
         (insert (propertize (string ch) 'face face)))))

(defun sp-dashboard--draw-layer (layer)
  "Draw the art LAYER, centred on the window and moved by its offsets.
Only plain blanks are replaced, so text, buttons and images are kept."
  (when-let* ((lines (sp-dashboard--art-lines (plist-get (cdr layer) :file))))
    (let* ((inhibit-read-only t)
           (indent-tabs-mode nil)
           (face (or (plist-get (cdr layer) :face) 'sp-dashboard-art-face))
           (box (sp-dashboard--layer-box (car layer)))
           (left (nth 0 box))
           (top (nth 1 box))
           (max-line (window-body-height))
           (row 0))
      (dolist (text lines)
        (let ((line (+ top row)))
          (when (and (>= line 1) (<= line max-line))
            ;; Grow the buffer when the art runs past its last line.
            (goto-char (point-max))
            (while (< (line-number-at-pos) line)
              (insert-char ?\n 1))
            (goto-char (point-min))
            (forward-line (1- line))
            (dotimes (i (length text))
              (let ((ch (aref text i))
                    (col (+ left i)))
                (when (and (/= ch ?\s) (>= col 0))
                  (sp-dashboard--put-art-char col ch face)
                  (forward-line 0)))))
          (setq row (1+ row)))))))

(defun sp-dashboard--draw-art ()
  "Draw every art layer behind the menu, the topmost layer first."
  (dolist (layer sp-dashboard-art-layers)
    (sp-dashboard--draw-layer layer)))

;;;; Move the art
(defun sp-dashboard--current-layer ()
  "Return the layer the nudge commands move."
  (or (assq sp-dashboard-art-layer sp-dashboard-art-layers)
      (car sp-dashboard-art-layers)))

(defun sp-dashboard-art-next-layer ()
  "Select the next art layer for the nudge commands."
  (interactive)
  (let* ((names (mapcar #'car sp-dashboard-art-layers))
         (rest (cdr (memq (car (sp-dashboard--current-layer)) names))))
    (setq sp-dashboard-art-layer (car (or rest names)))
    (message "Splash art layer: %s" sp-dashboard-art-layer)))

(defun sp-dashboard-art-nudge (dx dy)
  "Move the current art layer DX columns right and DY lines down, and redraw."
  (let ((layer (sp-dashboard--current-layer)))
    (unless layer (user-error "No splash art layers"))
    (plist-put (cdr layer) :x (+ (or (plist-get (cdr layer) :x) 0) dx))
    (plist-put (cdr layer) :y (+ (or (plist-get (cdr layer) :y) 0) dy))
    (message "Splash art %s: x %d, y %d" (car layer)
             (plist-get (cdr layer) :x) (plist-get (cdr layer) :y)))
  (sp-dashboard-refresh))

(defun sp-dashboard-art-left ()
  "Move the splash art left."
  (interactive)
  (sp-dashboard-art-nudge (- sp-dashboard-art-x-step) 0))

(defun sp-dashboard-art-right ()
  "Move the splash art right."
  (interactive)
  (sp-dashboard-art-nudge sp-dashboard-art-x-step 0))

(defun sp-dashboard-art-up ()
  "Move the splash art up."
  (interactive)
  (sp-dashboard-art-nudge 0 (- sp-dashboard-art-y-step)))

(defun sp-dashboard-art-down ()
  "Move the splash art down."
  (interactive)
  (sp-dashboard-art-nudge 0 sp-dashboard-art-y-step))

(defun sp-dashboard-art-reset ()
  "Put the art layers back at their default positions."
  (interactive)
  (setq sp-dashboard-art-layers
        (copy-tree (eval (car (get 'sp-dashboard-art-layers 'standard-value)))))
  (sp-dashboard-refresh))

(defun sp-dashboard-art-show-position ()
  "Show the art layers as a form to paste into the config.
The form is also copied to the kill ring."
  (interactive)
  (let ((form (format "(setq sp-dashboard-art-layers\n      '(%s))"
                      (mapconcat (lambda (layer) (format "%S" layer))
                                 sp-dashboard-art-layers "\n        "))))
    (kill-new form)
    (message "%s" form)))

;;;; Colour palette
;; The splash colours follow the theme.  A role (art, banner, accents...) takes
;; its colour from a face of the current theme, mixed towards the background,
;; unless `sp-dashboard-palettes' names a colour for that theme.

(defcustom sp-dashboard-accent-faces
  '(sp-dashboard-accent-1-face sp-dashboard-accent-2-face sp-dashboard-accent-3-face)
  "Faces that colour the menu blocks in turn, as their box lines."
  :type '(repeat face)
  :group 'sp-dashboard)

(defcustom sp-dashboard-palette-roles
  '((art      sp-dashboard-art-face      shadow                        :foreground 0.40)
    (banner   sp-dashboard-banner-face   shadow                        :foreground 0.75)
    (footer   sp-dashboard-footer-face   shadow                        :foreground 1.00)
    (accent-1 sp-dashboard-accent-1-face font-lock-keyword-face        :foreground 1.00)
    (accent-2 sp-dashboard-accent-2-face font-lock-function-name-face  :foreground 1.00)
    (accent-3 sp-dashboard-accent-3-face font-lock-string-face         :foreground 1.00))
  "How each colour role of the splash is derived from the theme.
Each element is (ROLE FACE SOURCE-FACE ATTRIBUTE MIX).  FACE, the splash
face of the role, gets the ATTRIBUTE of SOURCE-FACE mixed with the default
background: MIX 1 is the source colour, 0 the background."
  :type '(repeat (list symbol face face symbol number))
  :group 'sp-dashboard)

(defcustom sp-dashboard-palettes nil
  "Colours chosen by hand for themes, instead of the derived ones.
An alist of (THEME . COLORS) where COLORS is an alist of (ROLE . COLOR),
for example:

  \\='((modus-vivendi (art . \"#2a2e3a\") (accent-1 . \"#c678dd\")))

A role that is not listed for the current theme is derived from the
theme, see `sp-dashboard-palette-roles'."
  :type '(alist :key-type symbol :value-type (alist :key-type symbol :value-type string))
  :group 'sp-dashboard)

(defcustom sp-dashboard-palette-follow-theme t
  "Non-nil recolours the splash, and redraws it, when the theme changes."
  :type 'boolean
  :group 'sp-dashboard)

(defun sp-dashboard--rgb (color)
  "Return COLOR as a list of red, green and blue between 0 and 1, or nil."
  (if (and (stringp color) (string-match "\\`#\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\'" color))
      (mapcar (lambda (i) (/ (string-to-number (match-string i color) 16) 255.0))
              '(1 2 3))
    (and (stringp color) (color-name-to-rgb color))))

(defun sp-dashboard--mix (color background amount)
  "Return COLOR moved AMOUNT (0 to 1) of the way from BACKGROUND, as #rrggbb."
  (when-let* ((fg (sp-dashboard--rgb color))
              (bg (sp-dashboard--rgb background)))
    (apply #'format "#%02x%02x%02x"
           (cl-mapcar (lambda (f b) (round (* 255 (+ b (* amount (- f b))))))
                      fg bg))))

(defun sp-dashboard--role-color (role)
  "Return the colour of palette ROLE for the current theme, or nil."
  (or (alist-get role (alist-get (car custom-enabled-themes) sp-dashboard-palettes))
      (pcase-let ((`(,_ ,_ ,source ,attribute ,mix)
                   (assq role sp-dashboard-palette-roles)))
        (when source
          (sp-dashboard--mix (face-attribute source attribute nil 'default)
                          (face-attribute 'default :background nil 'default)
                          mix)))))

(defun sp-dashboard-apply-palette ()
  "Set the splash faces from the colours of the current theme."
  (interactive)
  (dolist (entry sp-dashboard-palette-roles)
    (when-let* ((color (sp-dashboard--role-color (car entry))))
      (face-spec-set (nth 1 entry) `((t :foreground ,color)) 'face-override-spec))))

(defun sp-dashboard--theme-changed (&rest _)
  "Recolour and redraw the splash after a theme change."
  (when sp-dashboard-palette-follow-theme
    (sp-dashboard-apply-palette)
    (when-let* ((buffer (get-buffer "Dashboard")))
      (with-current-buffer buffer
        (sp-dashboard-refresh)))))

(add-hook 'enable-theme-functions #'sp-dashboard--theme-changed)
(add-hook 'disable-theme-functions #'sp-dashboard--theme-changed)

(defun sp-dashboard-show-palette ()
  "Show the colour of every role for the current theme."
  (interactive)
  (message "%s: %s" (or (car custom-enabled-themes) "no theme")
           (mapconcat (lambda (entry)
                        (format "%s %s" (car entry)
                                (or (sp-dashboard--role-color (car entry)) "-")))
                      sp-dashboard-palette-roles ", ")))

;;;; Menu
;; The blocks under the banner.  Each element of `sp-dashboard-menu' is drawn as
;; a box, and a block with children shows them nested under its heading.
(defcustom sp-dashboard-menu
  '(("nf-fa-calendar" "Agenda" nil nil "Agendas"
     (("General agenda" "a" sp-dashboard-open-agenda "Open the general agenda")
      ("Thesis" "t" sp-dashboard-open-thesis-agenda "Open the thesis agenda")
      ("Issues" "i" sp-dashboard-open-issues-agenda "Open the issues agenda")
      ("Deadlines" "d" sp-dashboard-open-deadlines-agenda "Open the coming deadlines")))
    ("nf-fa-code" "Config" "c" sp-dashboard-open-config "Visit config directory" nil)
    ("nf-fa-book" "Notes" "n" sp-dashboard-open-notes "Open notes directory" nil))
  "Blocks of the splash menu, each drawn in a box.
Each element is (ICON LABEL KEY COMMAND HELP CHILDREN).  ICON is a
`nerd-icons-faicon' name.  CHILDREN, when non-nil, is a list of
\(LABEL KEY COMMAND HELP) shown nested under the heading, and the heading
then needs no KEY or COMMAND.  The keys must also be bound in
`sp-dashboard-mode-map'."
  :type '(repeat sexp)
  :group 'sp-dashboard)

(defun sp-dashboard--menu-rows (entry)
  "Return the rows of the menu block ENTRY, heading first.
Each row is (TEXT KEY COMMAND HELP)."
  (pcase-let ((`(,icon ,label ,key ,command ,help ,children) entry))
    (let ((count (length children))
          (index 0))
      (cons (list (concat (nerd-icons-faicon icon) isep label) key command help)
            (mapcar (lambda (child)
                      (setq index (1+ index))
                      (cons (concat "  " (if (= index count) "└─ " "├─ ") (car child))
                            (cdr child)))
                    children)))))

(defun sp-dashboard--insert-menu (content-col)
  "Insert the menu blocks in boxes, centred on column CONTENT-COL."
  (let* ((blocks (mapcar #'sp-dashboard--menu-rows sp-dashboard-menu))
         (text-width (apply #'max (mapcar (lambda (row) (string-width (car row)))
                                          (apply #'append blocks))))
         (body-width (+ text-width (length ksep) 3))
         (inner-width (+ body-width 2))
         (indent (max 0 (- content-col (/ (+ inner-width 2) 2))))
         (faces (copy-sequence sp-dashboard-accent-faces)))
    (when faces
      (setcdr (last faces) faces))
    (dolist (block blocks)
      (insert-char ?\s indent)
      (insert (propertize (concat "┌" (make-string inner-width ?─) "┐\n")
                          'face (or (car faces) 'sp-dashboard-box-face)))
      (dolist (row block)
        (pcase-let* ((`(,text ,key ,command ,help) row)
                     (body (concat text
                                   (make-string (- text-width (string-width text)) ?\s)
                                   ksep
                                   (if key (format "(%s)" key) "   "))))
          (insert-char ?\s indent)
          (insert (propertize "│ " 'face (or (car faces) 'sp-dashboard-box-face)))
          (if command
              (insert-text-button body
                                  'action (lambda (_) (funcall command))
                                  'help-echo help
                                  'face 'sp-dashboard-menu-face
                                  'follow-link t)
            (insert (propertize body 'face 'sp-dashboard-menu-face)))
          (insert (propertize " │\n" 'face (or (car faces) 'sp-dashboard-box-face)))))
      (insert-char ?\s indent)
      (insert (propertize (concat "└" (make-string inner-width ?─) "┘\n")
                          'face (or (car faces) 'sp-dashboard-box-face)))
      (insert "\n")
      (setq faces (cdr faces)))))

;;;; Define Splash

(defun sp-dashboard--erase ()
  ;; check if splash exists and switch if so
  (when (get-buffer "Dashboard")
    (switch-to-buffer "Dashboard")
    (let ((inhibit-read-only t))
      (erase-buffer))))

(defun sp-dashboard-terminal ()
  "A custom splash screen for terminal Emacs"
  (interactive)
  ;; Switch to or create splash buffer
  (or (when (get-buffer "Dashboard")
        (switch-to-buffer "Dashboard"))
      ;; Hide modeline before window-body-height is computed
      (let* ((splash-buffer (get-buffer-create "Dashboard")))
        (with-current-buffer splash-buffer
          (setq header-line-format nil)
          (setq mode-line-format nil)
          (erase-buffer))

        (let* ((buffer-read-only t)
               (midp  (/ (point-max) 2))
               (padding-top 3)
               (height (/ (window-height) 2))
	           (width (/ (window-width) 2))
               ;; Original ascii image from here:
               ;; https://github.com/Triagle/emax/blob/master/boot.txt
               (banner (sp-get-string-from-file (expand-file-name "lambda-splash.txt"
                                                          (expand-file-name sp-dashboard-art-directory
                                                                            sp-library-dir)))))

          (with-current-buffer splash-buffer
            ;; Buffer local settings
            (if (one-window-p)
                (setq mode-line-format nil))
            (setq-local cursor-type nil)
            (setq vertical-scroll-bar nil)
            (setq horizontal-scroll-bar nil)
            (setq fill-column width)
            (face-remap-add-relative 'link :underline nil)
            (unless (and (display-graphic-p) sys-mac) (menu-bar-mode 0))
            ;; Set margin padding locally
            (setq-local left-margin-width (/ width 6)
                        right-margin-width (/ width 6))
            (set-window-buffer nil (current-buffer))
            ;; Add padding at top
            (insert-char ?\n 1)
            (unless sp-dashboard-banner
              ;; Insert text banner
              (insert banner))
            ;; Position point
            (goto-char (point-min))
            (forward-line (- (/ (window-height) 2) 10))
            (end-of-line)
            ;; Insert header text
            (insert-rectangle `(,(propertize "           Welcome to 𝛌-Emacs"  'face 'sp-dashboard-title-face)
                                ,(concat (propertize "         GNU Emacs version" 'face 'sp-dashboard-header-face)
                                         " "
                                         (propertize (format "%d.%d" emacs-major-version emacs-minor-version) 'face 'sp-dashboard-header-face))
                                ,(let ((init-info (funcall sp-dashboard-init-info)))
                                   (concat " " (propertize init-info 'face 'sp-dashboard-header-face)))))
            ;; ;; Vertical padding to bottom
            (goto-char (point-max))
            ;; Footer text
            (defvar sp-dashboard-footer "   " "Footer text.")
            (save-excursion (insert-char ?\s (- (/ (window-width) 4) 10))
                            (insert
                             (propertize sp-dashboard-footer 'face 'sp-dashboard-footer-face)))
            (goto-char (point-min))
            (display-buffer-same-window splash-buffer nil))
          (switch-to-buffer "Dashboard"))
        (sp-dashboard-mode))))

(defun sp-dashboard-screen ()
  "A custom splash screen for Emacs.
Called interactively, it drops an existing Dashboard buffer first so the
splash is drawn again with the current settings."
  (interactive)
  (when (and (called-interactively-p 'any) (get-buffer "Dashboard"))
    (kill-buffer "Dashboard"))
  (when sp-dashboard-palette-follow-theme
    (sp-dashboard-apply-palette))
  ;; Switch to or create splash buffer
  (or (when (get-buffer "Dashboard")
        (switch-to-buffer "Dashboard"))
      ;; Hide modeline before window-body-height is computed
      (let* ((splash-buffer (get-buffer-create "Dashboard")))
        (with-current-buffer splash-buffer
          (setq header-line-format nil)
          (setq mode-line-format nil)
          (erase-buffer))

        (let* ((buffer-read-only t)
               (midp  (/ (point-max) 2))
               (padding-top 3)
               (height (/ (window-height) 2))
	           (width (/ (window-width) 2))
               (image-scaling-factor 2.2)
               ;; scale icons
               (nerd-icons-scale-factor 1.10)
               (nerd-icons-default-adjust -0.02)
               (content-col (sp-dashboard--content-column)))

          (with-current-buffer splash-buffer
            ;; Buffer local settings
            (if (one-window-p)
                (setq mode-line-format nil))
            (setq-local cursor-type nil)
            (setq vertical-scroll-bar nil)
            (setq horizontal-scroll-bar nil)
            (setq fill-column width)
            (face-remap-add-relative 'link :underline nil)
            (unless (and (display-graphic-p) sys-mac) (menu-bar-mode 0))

            ;; Set margin padding locally
            (setq-local left-margin-width 0
                        right-margin-width (/ width 6))
            (set-window-buffer nil (current-buffer))

            ;; Add padding at top
            (insert-char ?\n padding-top)

            ;; Start the title and the menu below the content layer
            (when-let* ((box (sp-dashboard--layer-box sp-dashboard-content-layer)))
              (insert-char ?\n (max 0 (- (+ (nth 1 box) (nth 3 box) 2)
                                         (line-number-at-pos)))))
            
            ;; Simple centered layout
            (let* ((center-col (max 0 (/ (- (window-width) 60) 2))))
              
              ;; Add the lambda image, centered and reasonably sized
              (when (and (> (window-width) 80) (> (window-height) 20)
                         (null sp-dashboard-art-layers))
                (let* ((image-file (if (eq (car custom-enabled-themes) 'lambda-dark)
                                       (concat sp-library-dir "lambda-logo-white.png")
                                     (concat sp-library-dir "lambda-logo-black.png")))
                       (image (create-image image-file 'png nil :width 175 :height 175)))
                  (insert-char ?\s (+ center-col 19))
                  (insert-image image)
                  (insert-char ?\n 2)))
              
              (let ((welcome-text "Welcome to λ-Emacs")
                    (version-text (format "GNU Emacs version %d.%d" emacs-major-version emacs-minor-version))
                    (init-info (funcall sp-dashboard-init-info)))
                
                ;; Welcome text
                (let ((welcome-center (max 0 (- content-col (/ (length welcome-text) 2)))))
                  (insert-char ?\s welcome-center)
                  (insert (propertize welcome-text 'face 'sp-dashboard-title-face))
                  (insert-char ?\n 2))
                
                ;; Version text
                (let ((version-center (max 0 (- content-col (/ (length version-text) 2)))))
                  (insert-char ?\s version-center)
                  (insert (propertize version-text 'face 'sp-dashboard-header-face))
                  (insert-char ?\n 1))
                
                ;; Init info
                (let ((init-center (max 0 (- content-col (/ (length init-info) 2)))))
                  (insert-char ?\s init-center)
                  (insert (propertize init-info 'face 'sp-dashboard-header-face))
                  (insert-char ?\n 2))))

            ;; Insert the menu blocks, in boxes under the banner
            (goto-char (point-max))
            (sp-dashboard--insert-menu content-col)

            ;; Add footer with some space above bottom
            (goto-char (point-max))
            (let* ((current-line (line-number-at-pos))
                   (window-height (window-height))
                   (footer-padding (max 1 (- window-height current-line 15))))
              (insert-char ?\n footer-padding))
            
            ;; Footer text centered
            (defvar sp-dashboard-footer "   " "Footer text.")
            (let ((footer-center (max 0 (- (sp-dashboard--layer-column sp-dashboard-footer-layer)
                                           (/ (length sp-dashboard-footer) 2)))))
              (insert-char ?\s footer-center)
              (insert (propertize sp-dashboard-footer 'face 'sp-dashboard-footer-face)))

            ;; Lambda art behind the menu (a no-op when the art is off)
            (sp-dashboard--draw-art)

            (goto-char (point-min))
            (display-buffer-same-window splash-buffer nil))
          (switch-to-buffer "Dashboard"))
        (sp-dashboard-mode))))

;;;;; Set Splash Footer
;; Set a footer for the splash screen
(setq sp-dashboard-footer  "wawawewa")

(defun sp-dashboard-screen-bury ()
  "Bury the splash screen buffer (immediately)."
  (interactive)
  (when (get-buffer "Dashboard")
    (bury-buffer)))

(defun sp-dashboard-screen-kill ()
  "Kill the splash screen buffer (immediately)."
  (interactive)
  (when (get-buffer "Dashboard")
    (kill-buffer)))

;;;; Workspace Dispatch
(defun sp-dashboard--workspace-dispatch (fn)
  "Call FN when it is defined, otherwise prompt to enable the workspaces module."
  (if (fboundp fn)
      (funcall fn)
    (message "Enable the workspaces module (sp-workspaces) for this action")))

(defcustom sp-dashboard-agenda-general-files nil
  "Files of the General agenda; nil uses `org-agenda-files'."
  :type '(choice (const :tag "All agenda files" nil) (repeat file))
  :group 'sp-dashboard)

(defcustom sp-dashboard-agenda-thesis-files nil
  "Files of the thesis agenda; nil uses `org-agenda-files'."
  :type '(choice (const :tag "All agenda files" nil) (repeat file))
  :group 'sp-dashboard)

(defcustom sp-dashboard-agenda-issues-files nil
  "Files of the issues agenda; nil uses `org-agenda-files'."
  :type '(choice (const :tag "All agenda files" nil) (repeat file))
  :group 'sp-dashboard)

(defcustom sp-dashboard-agenda-deadlines-files nil
  "Files searched for the coming deadlines; nil uses `org-agenda-files'."
  :type '(choice (const :tag "All agenda files" nil) (repeat file))
  :group 'sp-dashboard)

(defcustom sp-dashboard-deadlines-days 30
  "Days ahead the deadlines agenda looks."
  :type 'integer
  :group 'sp-dashboard)

(defun sp-dashboard--open-agenda (files &optional deadlines)
  "Show the agenda of FILES (nil: `org-agenda-files').
With DEADLINES, show only the deadlines of the next `sp-dashboard-deadlines-days'."
  (require 'org)
  (require 'org-agenda)
  (let ((org-agenda-files (or files org-agenda-files)))
    (if deadlines
        (let ((org-agenda-span sp-dashboard-deadlines-days)
              (org-agenda-entry-types '(:deadline))
              (org-deadline-warning-days sp-dashboard-deadlines-days))
          (org-agenda-list))
      (org-agenda-list))))

(defun sp-dashboard-open-agenda ()
  "Open the General agenda from the splash screen.
Without `sp-dashboard-agenda-general-files' this is the agenda workspace."
  (interactive)
  (if sp-dashboard-agenda-general-files
      (sp-dashboard--open-agenda sp-dashboard-agenda-general-files)
    (sp-dashboard--workspace-dispatch 'sp-open-agenda-in-workspace)))

(defun sp-dashboard-open-thesis-agenda ()
  "Open the thesis agenda from the splash screen."
  (interactive)
  (sp-dashboard--open-agenda sp-dashboard-agenda-thesis-files))

(defun sp-dashboard-open-issues-agenda ()
  "Open the issues agenda from the splash screen."
  (interactive)
  (sp-dashboard--open-agenda sp-dashboard-agenda-issues-files))

(defun sp-dashboard-open-deadlines-agenda ()
  "Open the coming deadlines from the splash screen."
  (interactive)
  (sp-dashboard--open-agenda sp-dashboard-agenda-deadlines-files t))

(defun sp-dashboard-open-config ()
  "Open the emacs.d workspace from the splash screen."
  (interactive)
  (sp-dashboard--workspace-dispatch 'sp-open-emacsd-in-workspace))

(defun sp-dashboard-open-notes ()
  "Open the notes workspace from the splash screen."
  (interactive)
  (sp-dashboard--workspace-dispatch 'sp-open-notes-in-workspace))

;;;; Define Minor Mode
;; Custom splash screen
(defvar sp-dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") 'sp-dashboard-open-agenda)
    (define-key map (kbd "c") 'sp-dashboard-open-config)
    (define-key map (kbd "n") 'sp-dashboard-open-notes)
    (define-key map (kbd "t") 'sp-dashboard-open-thesis-agenda)
    (define-key map (kbd "i") 'sp-dashboard-open-issues-agenda)
    (define-key map (kbd "d") 'sp-dashboard-open-deadlines-agenda)
    (define-key map (kbd "S-<left>") 'sp-dashboard-art-left)
    (define-key map (kbd "S-<right>") 'sp-dashboard-art-right)
    (define-key map (kbd "S-<up>") 'sp-dashboard-art-up)
    (define-key map (kbd "S-<down>") 'sp-dashboard-art-down)
    (define-key map (kbd "TAB") 'sp-dashboard-next-button)
    (define-key map (kbd "<backtab>") 'sp-dashboard-previous-button)
    (define-key map (kbd "l") 'sp-dashboard-art-next-layer)
    (define-key map (kbd "0") 'sp-dashboard-art-reset)
    (define-key map (kbd "s") 'sp-dashboard-art-show-position)
    (define-key map (kbd "q") 'sp-dashboard-screen-kill)
    (define-key map (kbd "<escape>") 'sp-dashboard-screen-bury)
    (define-key map (kbd "k") 'sp-dashboard-screen-kill)
    ;; The splash is not for scrolling, moving the cursor or marking text:
    ;; only TAB and S-TAB move, between the buttons.
    (dolist (command '(next-line previous-line forward-char backward-char
                       forward-word backward-word left-word right-word
                       beginning-of-line end-of-line move-beginning-of-line
                       move-end-of-line beginning-of-buffer end-of-buffer
                       scroll-up-command scroll-down-command scroll-left
                       scroll-right scroll-other-window recenter
                       recenter-top-bottom reposition-window
                       set-mark-command mark-whole-buffer mark-word
                       mark-paragraph mark-sexp exchange-point-and-mark
                       mouse-set-region mouse-drag-region mouse-save-then-kill
                       mouse-set-point mouse-secondary-save-then-kill
                       mwheel-scroll pixel-scroll-precision
                       isearch-forward isearch-backward))
      (define-key map `[remap ,command] #'ignore))
    (dolist (event '(wheel-up wheel-down wheel-left wheel-right mouse-4 mouse-5
                     mouse-6 mouse-7 double-wheel-up double-wheel-down
                     triple-wheel-up triple-wheel-down down-mouse-1
                     drag-mouse-1 double-mouse-1 triple-mouse-1))
      (define-key map (vector event) #'ignore))
    map)
  "Keymap for sp-dashboard-mode.")

(defvar-local sp-dashboard--focus-overlay nil
  "Overlay marking the selected button of the splash.")

(defun sp-dashboard-next-button ()
  "Select the next button of the splash, wrapping around."
  (interactive)
  (forward-button 1 t nil t))

(defun sp-dashboard-previous-button ()
  "Select the previous button of the splash, wrapping around."
  (interactive)
  (backward-button 1 t nil t))

(defun sp-dashboard--mark-focus ()
  "Highlight the button at point, since the cursor is hidden."
  (when sp-dashboard--focus-overlay
    (delete-overlay sp-dashboard--focus-overlay))
  (when-let* ((button (button-at (point))))
    (setq sp-dashboard--focus-overlay
          (make-overlay (button-start button) (button-end button)))
    (overlay-put sp-dashboard--focus-overlay 'face 'sp-dashboard-focus-face)))

(defun sp-dashboard--no-region ()
  "Drop the region at once: the splash never marks text."
  (deactivate-mark))

(define-minor-mode sp-dashboard-mode
  "Emacs minor mode for splash screen."
  :global nil
  :keymap sp-dashboard-mode-map
  :group 'sp-dashboard
  
  :require 'sp-dashboard
  (buffer-disable-undo)
  (auto-revert-mode -1)
  (whitespace-mode -1)
  (when (fboundp 'linum-mode)
    (linum-mode -1))
  (when (>= emacs-major-version 26)
    (display-line-numbers-mode -1))
  
  (setq-local buffer-read-only t)
  (setq-local cursor-type nil)
  (setq-local hl-line-mode -1)
  (setq-local mode-line-format nil)
  (setq-local header-line-format nil)
  
  ;; No margin or fringe in splash buffer
  (setq-local left-margin-width nil
              right-margin-width nil)
  (set-window-fringes (selected-window) 0 0 nil)
  (setq inhibit-startup-screen t
        truncate-lines nil
        inhibit-startup-message t
        inhibit-startup-echo-area-message t)

  ;; The splash fills the window and never scrolls or wraps
  (setq-local truncate-lines t
              scroll-margin 0
              scroll-conservatively 0
              auto-window-vscroll nil
              shift-select-mode nil
              mouse-wheel-mode nil)
  (add-hook 'activate-mark-hook #'sp-dashboard--no-region nil t)
  (add-hook 'post-command-hook #'sp-dashboard--mark-focus nil t)
  
  ;; Use Emacs state if Evil is active so single-key bindings work
  (when (bound-and-true-p evil-mode)
    (evil-emacs-state))
  (goto-char (point-min))
  (set-window-start (selected-window) (point-min))
  (forward-button 1 t nil t)
  (sp-dashboard--mark-focus))

;;;; Splash Setup & Refresh Functions
(defun sp-dashboard-refresh ()
  "Refresh & recenter splash after window switch."
  (interactive)
  (when (string= (buffer-name) "Dashboard")
    (progn
      (ignore-errors
        (sp-dashboard-screen-kill)
        (sp-dashboard-screen)))))

(defun sp-dashboard--setup-splash-hooks ()
  "Initialize splash and setup hooks."
  (progn
    (if (display-graphic-p)
        (sp-dashboard-screen)
      (sp-dashboard-terminal))
    (add-hook 'window-state-change-hook #'sp-dashboard-refresh)
    (add-hook 'window-configuration-change-hook  #'sp-dashboard-refresh)
    (add-hook 'sp-switch-buffer-hook #'sp-dashboard-refresh)))

;; Install hook after frame parameters have been applied and only if
;; no option on the command line
(when (and (not (member "--no-splash" command-line-args))
           (not (member "--file"      command-line-args))
           (not (member "--insert"    command-line-args))
           (not (member "--find-file" command-line-args)))
  (add-hook 'window-setup-hook #'sp-dashboard--setup-splash-hooks))

(provide 'sp-dashboard)
;;; sp-dashboard.el ends here