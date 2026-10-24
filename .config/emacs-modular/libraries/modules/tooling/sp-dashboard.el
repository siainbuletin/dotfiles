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
  :group 'spcustom)

;; Banner

;; Banner
(defcustom sp-dashboard-banner nil
  "Banner picture for splash-screen"
  :type '(string)
  :group 'spcustom)

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
  :group 'spcustom)

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
  :group 'spcustom)

(defcustom sp-dashboard-art-x-step 2
  "Columns the art moves with `sp-dashboard-art-right' and `sp-dashboard-art-left'."
  :type 'integer
  :group 'spcustom)

(defcustom sp-dashboard-art-y-step 1
  "Lines the art moves with `sp-dashboard-art-up' and `sp-dashboard-art-down'."
  :type 'integer
  :group 'spcustom)

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
  :group 'spcustom)

(defcustom sp-dashboard-footer-layer 'lambda
  "Name of the art layer the footer text is centred on, as for the menu."
  :type '(choice (const :tag "Centre on the window" nil) symbol)
  :group 'spcustom)

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
  :group 'spcustom)

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
  :group 'spcustom)

(defcustom sp-dashboard-palettes nil
  "Colours chosen by hand for themes, instead of the derived ones.
An alist of (THEME . COLORS) where COLORS is an alist of (ROLE . COLOR),
for example:

  \\='((modus-vivendi (art . \"#2a2e3a\") (accent-1 . \"#c678dd\")))

A role that is not listed for the current theme is derived from the
theme, see `sp-dashboard-palette-roles'."
  :type '(alist :key-type symbol :value-type (alist :key-type symbol :value-type string))
  :group 'spcustom)

(defcustom sp-dashboard-palette-follow-theme t
  "Non-nil recolours the splash, and redraws it, when the theme changes."
  :type 'boolean
  :group 'spcustom)

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
  '(("nf-fa-code" "Config" "c" sp-dashboard-open-config "Visit config directory" nil)
    ("nf-fa-book" "Notes" "n" sp-dashboard-open-notes "Open notes directory" nil))
  "Blocks of the splash menu, each drawn in a box.
Each element is (ICON LABEL KEY COMMAND HELP CHILDREN).  ICON is a
`nerd-icons-faicon' name.  CHILDREN, when non-nil, is a list of
\(LABEL KEY COMMAND HELP) shown nested under the heading, and the heading
then needs no KEY or COMMAND.  The keys must also be bound in
`sp-dashboard-mode-map'."
  :type '(repeat sexp)
  :group 'spcustom)

;;;; Agenda boxes
;; One box per agenda, laid out in a grid, each listing its most urgent TODOs.
(defcustom sp-dashboard-agendas
  '(("nf-fa-calendar" "General agenda" "a" sp-dashboard-open-agenda
     "Open the general agenda" sp-dashboard-agenda-general-files urgent)
    ("nf-fa-graduation_cap" "Thesis" "t" sp-dashboard-open-thesis-agenda
     "Open the thesis agenda" sp-dashboard-agenda-thesis-files urgent)
    ("nf-fa-code" "Issues" "i" sp-dashboard-open-issues-agenda
     "Open the issues agenda" sp-dashboard-agenda-issues-files urgent)
    ("nf-fa-clock_o" "Deadlines" "d" sp-dashboard-open-deadlines-agenda
     "Open the coming deadlines" sp-dashboard-agenda-deadlines-files deadline))
  "Agenda boxes of the dashboard.
Each element is (ICON LABEL KEY COMMAND HELP FILES-VAR MODE).  FILES-VAR is
a variable holding the files to read (nil: `org-agenda-files').  MODE is
`urgent' to list the most urgent open TODOs, or `deadline' to list the
nearest deadlines.  The keys must also be bound in `sp-dashboard-mode-map'."
  :type '(repeat sexp)
  :group 'spcustom)

(defcustom sp-dashboard-lane-width nil
  "Width, in columns, of the lane all the boxes fill, centred under the banner.
nil uses the width of the content layer, so the boxes line up with the banner."
  :type '(choice (const :tag "Width of the banner" nil) integer)
  :group 'spcustom)

(defcustom sp-dashboard-agenda-columns 2
  "Boxes side by side in the lane; fewer when the lane is too narrow for them."
  :type 'integer
  :group 'spcustom)

(defcustom sp-dashboard-agenda-todo-count 3
  "TODOs listed in each agenda box."
  :type 'integer
  :group 'spcustom)

(defcustom sp-dashboard-agenda-todo-lines 2
  "Lines one TODO may wrap onto before it is cut with an ellipsis."
  :type 'integer
  :group 'spcustom)

(defcustom sp-dashboard-agenda-todos-clickable t
  "Non-nil makes the first line of each TODO a button that visits the entry.
Each one is then another stop for \\`TAB'."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-dashboard-urgent-states '("NEXT" "PROG")
  "TODO keywords that rank an entry higher among the most urgent."
  :type '(repeat string)
  :group 'spcustom)

;;;;; Privacy
;; Private entries are left out of the boxes while the dashboard is public.
(defcustom sp-dashboard-private-tags '("private")
  "Entries with one of these tags (inherited) are private."
  :type '(repeat string)
  :group 'spcustom)

(defcustom sp-dashboard-private-files nil
  "Regexps of files whose entries are all private."
  :type '(repeat regexp)
  :group 'spcustom)

(defcustom sp-dashboard-public-conditions '(sp-dashboard-condition-focus)
  "Functions, without arguments, that return non-nil when you are in public.
In `auto' mode the dashboard is public as soon as one of them returns non-nil,
or signals an error (a check that cannot run counts as public)."
  :type '(repeat function)
  :group 'spcustom)

(defvar sp-dashboard-public-mode 'auto
  "Whether the dashboard hides private entries.
`auto' follows `sp-dashboard-public-conditions', `public' always hides them
and `private' always shows them.  Cycle it with `sp-dashboard-toggle-public-mode'.")

(defcustom sp-dashboard-trusted-networks nil
  "Wi-Fi names that count as private, for `sp-dashboard-condition-untrusted-network'."
  :type '(repeat string)
  :group 'spcustom)

(defcustom sp-dashboard-screen-share-processes nil
  "Process names that mean the screen is shared, such as a call app's helper.
Used by `sp-dashboard-condition-screen-share'."
  :type '(repeat string)
  :group 'spcustom)

(defun sp-dashboard-condition-untrusted-network ()
  "Return non-nil when the Wi-Fi network is not in `sp-dashboard-trusted-networks'.
Always nil when that list is empty, so it does nothing until configured."
  (when sp-dashboard-trusted-networks
    (let ((name (string-trim
                 (shell-command-to-string
                  (if sys-mac
                      "networksetup -getairportnetwork en0 | sed 's/^[^:]*: //'"
                    "nmcli -t -f active,ssid dev wifi | sed -n 's/^yes://p'")))))
      (not (member name sp-dashboard-trusted-networks)))))

(defun sp-dashboard-condition-screen-share ()
  "Return non-nil when a process of `sp-dashboard-screen-share-processes' runs."
  (seq-some (lambda (name) (zerop (call-process "pgrep" nil nil nil "-x" name)))
            sp-dashboard-screen-share-processes))

(defcustom sp-dashboard-focus-flag-file "~/.cache/sp-dashboard-public-focus"
  "File whose existence means a Focus is on, for `sp-dashboard-condition-focus'.
Create it when a Focus turns on and delete it when it turns off, for example
with a macOS Shortcuts automation that runs `touch' or `rm' on it."
  :type 'file
  :group 'spcustom)

(defcustom sp-dashboard-focus-modes nil
  "Substrings of the macOS Focus identifiers that count as public.
nil means any Focus that macOS reports as on."
  :type '(repeat string)
  :group 'spcustom)

(defconst sp-dashboard--focus-assertions-file
  "~/Library/DoNotDisturb/DB/Assertions.json"
  "Where macOS records the Focus modes that are on.")

(defun sp-dashboard--active-focus-identifiers ()
  "Return the identifiers of the Focus modes macOS reports as on, or nil.
Reading the file can need Full Disk Access for Emacs; without it this is nil."
  (let ((file (expand-file-name sp-dashboard--focus-assertions-file))
        ids)
    (when (file-readable-p file)
      (condition-case nil
          (let ((json (with-temp-buffer
                        (insert-file-contents file)
                        (json-parse-buffer :object-type 'alist :array-type 'list))))
            (dolist (item (alist-get 'data json))
              (dolist (record (alist-get 'storeAssertionRecords item))
                (push (or (let-alist record
                            .assertionDetails.assertionDetailsModeIdentifier)
                          "focus")
                      ids))))
        (error nil)))
    ids))

(defun sp-dashboard-condition-focus ()
  "Return non-nil when a Focus that counts as public is on.
That is the existence of `sp-dashboard-focus-flag-file', or a macOS Focus
mode (matching `sp-dashboard-focus-modes') that macOS reports as on."
  (or (file-exists-p (expand-file-name sp-dashboard-focus-flag-file))
      (let ((ids (sp-dashboard--active-focus-identifiers)))
        (and ids
             (or (null sp-dashboard-focus-modes)
                 (seq-some (lambda (id)
                             (seq-some (lambda (mode)
                                         (string-match-p (regexp-quote mode) id))
                                       sp-dashboard-focus-modes))
                           ids))))))

(define-minor-mode sp-dashboard-public-facing-mode
  "Tell the dashboard you are in public: private entries are hidden.
This overrides `sp-dashboard-public-mode', and the dashboard redraws."
  :global t
  :lighter " Public"
  :group 'sp-dashboard
  (sp-dashboard--check-public))

;;;;; Redrawing when the status changes
;; The dashboard remembers whether it was drawn as public.  A timer and file
;; watches on the Focus files compare that with the current status while the
;; Dashboard buffer exists.  A hidden Dashboard is killed instead of redrawn, so
;; it never comes back showing entries it should no longer show.
(defcustom sp-dashboard-public-check-interval 30
  "Seconds between checks of the public status while the Dashboard exists.
nil turns the timer off; the Focus files are still watched."
  :type '(choice (const :tag "No timer" nil) integer)
  :group 'spcustom)

(defvar sp-dashboard--drawn-public nil
  "Whether the Dashboard was last drawn as public.")

(defvar sp-dashboard--public-timer nil
  "Timer that checks the public status.")

(defvar sp-dashboard--public-watches nil
  "File watches on the Focus files.")

(defun sp-dashboard--stop-public-watch ()
  "Stop the timer and the file watches of the public status."
  (when sp-dashboard--public-timer
    (cancel-timer sp-dashboard--public-timer)
    (setq sp-dashboard--public-timer nil))
  (dolist (watch sp-dashboard--public-watches)
    (ignore-errors (file-notify-rm-watch watch)))
  (setq sp-dashboard--public-watches nil))

(defun sp-dashboard--check-public ()
  "Redraw the Dashboard when its public status changed since it was drawn."
  (if (not (get-buffer "Dashboard"))
      (sp-dashboard--stop-public-watch)
    (unless (eq (and (sp-dashboard-public-p) t) sp-dashboard--drawn-public)
      (if-let* ((window (get-buffer-window "Dashboard" t)))
          (with-selected-window window
            (sp-dashboard-refresh))
        (kill-buffer "Dashboard")))))

(defun sp-dashboard--watch-file (file)
  "Run `sp-dashboard--check-public' when FILE changes, if its folder exists."
  (let* ((file (expand-file-name file))
         (name (file-name-nondirectory file)))
    (when (file-directory-p (file-name-directory file))
      (ignore-errors
        (push (file-notify-add-watch
               (file-name-directory file) '(change)
               (lambda (event)
                 (when (string= (file-name-nondirectory (nth 2 event)) name)
                   (sp-dashboard--check-public))))
              sp-dashboard--public-watches)))))

(defun sp-dashboard--start-public-watch ()
  "Start checking the public status, if that is not already going on."
  (when (and sp-dashboard-public-check-interval (not sp-dashboard--public-timer))
    (setq sp-dashboard--public-timer
          (run-with-timer sp-dashboard-public-check-interval
                          sp-dashboard-public-check-interval
                          #'sp-dashboard--check-public)))
  (unless sp-dashboard--public-watches
    (require 'filenotify)
    (sp-dashboard--watch-file sp-dashboard-focus-flag-file)
    (sp-dashboard--watch-file sp-dashboard--focus-assertions-file)))

(defun sp-dashboard-public-p ()
  "Return non-nil when private entries must stay out of the dashboard."
  (or sp-dashboard-public-facing-mode
      (pcase sp-dashboard-public-mode
        ('public t)
        ('private nil)
        (_ (condition-case nil
               (and (seq-some #'funcall sp-dashboard-public-conditions) t)
             (error t))))))

(defun sp-dashboard-toggle-public-mode ()
  "Cycle `sp-dashboard-public-mode' (auto, public, private) and redraw."
  (interactive)
  (setq sp-dashboard-public-mode
        (pcase sp-dashboard-public-mode
          ('auto 'public) ('public 'private) (_ 'auto)))
  (message "Dashboard privacy: %s" sp-dashboard-public-mode)
  (sp-dashboard-refresh))

(defun sp-dashboard--private-p (file tags)
  "Return non-nil when an entry in FILE with TAGS is private."
  (or (seq-some (lambda (regexp) (string-match-p regexp file))
                sp-dashboard-private-files)
      (seq-some (lambda (tag) (member tag tags)) sp-dashboard-private-tags)))

;;;;; Collecting the TODOs
(defun sp-dashboard--days-until (timestamp)
  "Return the days from today to the Org TIMESTAMP string, or nil."
  (when timestamp
    (- (org-time-string-to-absolute timestamp) (org-today))))

(defun sp-dashboard--entry ()
  "Return a plist describing the open TODO at point, or nil."
  (when (org-entry-is-todo-p)
    (let ((heading (org-get-heading t t t t)))
      (list :heading heading
            :state (org-get-todo-state)
            :priority (org-get-priority
                       (buffer-substring (line-beginning-position)
                                         (line-end-position)))
            :deadline (sp-dashboard--days-until (org-entry-get nil "DEADLINE"))
            :scheduled (sp-dashboard--days-until (org-entry-get nil "SCHEDULED"))
            :tags (org-get-tags)
            :file buffer-file-name
            :pos (point)))))

(defun sp-dashboard--score (entry)
  "Return how urgent ENTRY is; higher is more urgent."
  (let ((deadline (plist-get entry :deadline))
        (scheduled (plist-get entry :scheduled)))
    (+ (plist-get entry :priority)
       (if deadline (max 0 (- 3000 (* 100 deadline))) 0)
       (if (and scheduled (<= scheduled 0)) 1000 0)
       (if (member (plist-get entry :state) sp-dashboard-urgent-states) 500 0))))

(defun sp-dashboard--todos (files mode)
  "Return the entries of FILES to list for MODE, most urgent first.
Private entries are left out while `sp-dashboard-public-p'."
  (require 'org)
  (let ((public (sp-dashboard-public-p))
        entries)
    (dolist (file files)
      (when (file-readable-p file)
        (condition-case nil
            (dolist (entry (org-map-entries #'sp-dashboard--entry nil (list file) 'archive))
              (unless (or (null entry)
                          (and public (sp-dashboard--private-p file (plist-get entry :tags))))
                (push entry entries)))
          (error nil))))
    (when (eq mode 'deadline)
      (setq entries (seq-filter (lambda (entry)
                                  (let ((days (plist-get entry :deadline)))
                                    (and days (<= days sp-dashboard-deadlines-days))))
                                entries)))
    (seq-take (if (eq mode 'deadline)
                  (sort entries (lambda (a b) (< (plist-get a :deadline)
                                                 (plist-get b :deadline))))
                (sort entries (lambda (a b) (> (sp-dashboard--score a)
                                               (sp-dashboard--score b)))))
              sp-dashboard-agenda-todo-count)))

(defun sp-dashboard--wrap (text width max-lines)
  "Wrap TEXT to WIDTH columns, at most MAX-LINES lines, the last one cut with an ellipsis."
  (let ((line "")
        lines)
    (dolist (word (split-string text))
      (while (> (string-width word) width)
        (let ((cut (truncate-string-to-width word width)))
          (unless (string= line "")
            (push line lines)
            (setq line ""))
          (push cut lines)
          (setq word (substring word (length cut)))))
      (cond ((string= line "") (setq line word))
            ((<= (+ (string-width line) 1 (string-width word)) width)
             (setq line (concat line " " word)))
            (t (push line lines)
               (setq line word))))
    (unless (string= line "")
      (push line lines))
    (setq lines (nreverse lines))
    (if (<= (length lines) max-lines)
        lines
      (let ((kept (seq-take lines max-lines)))
        (setcar (last kept)
                (concat (truncate-string-to-width (car (last kept)) (1- width)) "…"))
        kept))))

;;;;; Drawing the boxes
;; A box is a list of lines and a line a list of segments (TEXT FACE BUTTON),
;; so boxes can be laid side by side before anything is inserted.
(defun sp-dashboard--visit-entry (file pos)
  "Visit the entry at POS in FILE."
  (find-file file)
  (goto-char pos)
  (org-reveal))

(defun sp-dashboard--box-line (width box-face &rest segments)
  "Return a box line of text WIDTH holding SEGMENTS, padded to that width."
  (let ((used (apply #'+ (mapcar (lambda (segment) (string-width (car segment)))
                                 segments))))
    (append (list (list "│ " box-face))
            segments
            (list (list (make-string (max 0 (- width used)) ?\s)
                        'sp-dashboard-menu-face)
                  (list " │" box-face)))))

(defun sp-dashboard--title-segment (text key command help width)
  "Return the segment of a title or menu row, TEXT with KEY at the right of WIDTH.
It is a button calling COMMAND, with HELP, when COMMAND is non-nil."
  (let* ((keytext (if key (format "(%s)" key) ""))
         (body (concat text
                       (make-string (max 1 (- width (string-width text)
                                              (string-width keytext)))
                                    ?\s)
                       keytext)))
    (if command
        (list body 'sp-dashboard-menu-face (lambda (_) (funcall command)) help)
      (list body 'sp-dashboard-menu-face))))

(defun sp-dashboard--menu-box (entry width box-face)
  "Return the menu block ENTRY as a box of text WIDTH, drawn with BOX-FACE."
  (pcase-let* ((`(,icon ,label ,key ,command ,help ,children) entry)
               (rule (make-string (+ width 2) ?─))
               (count (length children))
               (index 0)
               (lines (list (list (list (concat "┌" rule "┐") box-face))
                            (sp-dashboard--box-line
                             width box-face
                             (sp-dashboard--title-segment
                              (concat (nerd-icons-faicon icon) isep label)
                              key command help width)))))
    (dolist (child children)
      (setq index (1+ index))
      (pcase-let ((`(,child-label ,child-key ,child-command ,child-help) child))
        (setq lines
              (append lines
                      (list (sp-dashboard--box-line
                             width box-face
                             (sp-dashboard--title-segment
                              (concat "  " (if (= index count) "└─ " "├─ ") child-label)
                              child-key child-command child-help width)))))))
    (append lines (list (list (list (concat "└" rule "┘") box-face))))))

(defun sp-dashboard--agenda-box (agenda width box-face)
  "Return AGENDA as a box of text WIDTH, drawn with BOX-FACE."
  (pcase-let* ((`(,icon ,label ,key ,command ,help ,files-var ,mode) agenda)
               (rule (make-string (+ width 2) ?─))
               (todos (condition-case nil
                          (sp-dashboard--todos
                           (or (symbol-value files-var) (org-agenda-files)) mode)
                        (error nil)))
               (lines (list (list (list (concat "┌" rule "┐") box-face))
                            (sp-dashboard--box-line
                             width box-face
                             (sp-dashboard--title-segment
                              (concat (nerd-icons-faicon icon) isep label)
                              key command help width))
                            (list (list (concat "├" rule "┤") box-face)))))
    (if (null todos)
        (setq lines (append lines (list (sp-dashboard--box-line
                                         width box-face (list "  nothing open" 'shadow)))))
      (dolist (entry todos)
        (let* ((prefix (if (eq mode 'deadline)
                           (format-time-string
                            "%m-%d "
                            (time-add (current-time)
                                      (days-to-time (plist-get entry :deadline))))
                         (concat (plist-get entry :state) " ")))
               (wrapped (sp-dashboard--wrap (concat prefix (plist-get entry :heading))
                                            (- width 2)
                                            sp-dashboard-agenda-todo-lines))
               (first t))
          (dolist (text wrapped)
            (let ((segment (list (concat (if first "• " "  ") text)
                                 'sp-dashboard-menu-face)))
              (when (and first sp-dashboard-agenda-todos-clickable)
                (let ((file (plist-get entry :file))
                      (pos (plist-get entry :pos)))
                  (setq segment
                        (append segment
                                (list (lambda (_) (sp-dashboard--visit-entry file pos))
                                      "Visit the entry")))))
              (setq lines (append lines (list (sp-dashboard--box-line width box-face segment)))
                    first nil))))))
    (append lines (list (list (list (concat "└" rule "┘") box-face))))))

(defun sp-dashboard--insert-segment (segment)
  "Insert SEGMENT, a list (TEXT FACE [ACTION HELP])."
  (pcase-let ((`(,text ,face ,action ,help) segment))
    (if action
        (insert-text-button text 'action action 'help-echo help
                            'face face 'follow-link t)
      (insert (propertize text 'face face)))))

(defun sp-dashboard--lane-width ()
  "Return the width, in columns, of the lane all the boxes fill."
  (min (window-width)
       (or sp-dashboard-lane-width
           (nth 2 (sp-dashboard--layer-box sp-dashboard-content-layer))
           60)))

(defun sp-dashboard--insert-boxes (content-col)
  "Insert the agenda and menu boxes in one lane centred on column CONTENT-COL.
The lane is `sp-dashboard--lane-width' wide, so the outer edges of the boxes
line up with the banner it is centred on."
  (let* ((gap 2)
         (lane (sp-dashboard--lane-width))
         (columns (max 1 (min sp-dashboard-agenda-columns
                              (/ (+ lane gap) (+ 24 gap)))))
         (base (/ (- lane (* gap (1- columns))) columns))
         (extra (- lane (* gap (1- columns)) (* base columns)))
         (totals (mapcar (lambda (column) (+ base (if (< column extra) 1 0)))
                         (number-sequence 0 (1- columns))))
         (indent (max 0 (- content-col (/ lane 2))))
         (faces (copy-sequence sp-dashboard-accent-faces))
         (index 0)
         (boxes nil))
    (when faces
      (setcdr (last faces) faces))
    (dolist (entry (append (mapcar (lambda (agenda) (cons 'agenda agenda))
                                   sp-dashboard-agendas)
                           (mapcar (lambda (block) (cons 'menu block))
                                   sp-dashboard-menu)))
      (let ((width (- (nth (% index columns) totals) 4))
            (face (or (pop faces) 'sp-dashboard-box-face)))
        (push (if (eq (car entry) 'agenda)
                  (sp-dashboard--agenda-box (cdr entry) width face)
                (sp-dashboard--menu-box (cdr entry) width face))
              boxes)
        (setq index (1+ index))))
    (setq boxes (nreverse boxes))
    (setq sp-dashboard--drawn-public (and (sp-dashboard-public-p) t))
    (when sp-dashboard--drawn-public
      (insert-char ?\s indent)
      (insert (propertize "public: private entries are hidden (P)\n"
                          'face 'sp-dashboard-footer-face)))
    (while boxes
      (let* ((row (seq-take boxes columns))
             (height (apply #'max (mapcar #'length row))))
        (setq boxes (seq-drop boxes columns))
        (dotimes (line-index height)
          (insert-char ?\s indent)
          (let ((column 0))
            (dolist (box row)
              (when (> column 0)
                (insert-char ?\s gap))
              (if-let* ((line (nth line-index box)))
                  (dolist (segment line)
                    (sp-dashboard--insert-segment segment))
                (insert-char ?\s (nth column totals)))
              (setq column (1+ column))))
          (insert "\n"))
        (insert "\n")))))

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
            ;; The margins just set narrowed the window, so find the column
            ;; again: the art is placed by the same width, and the title and
            ;; the boxes must be centred on the same column as the banner.
            (setq content-col (sp-dashboard--content-column))

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
            (sp-dashboard--insert-boxes content-col)
            (sp-dashboard--start-public-watch)

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
  :group 'spcustom)

(defcustom sp-dashboard-agenda-thesis-files nil
  "Files of the thesis agenda; nil uses `org-agenda-files'."
  :type '(choice (const :tag "All agenda files" nil) (repeat file))
  :group 'spcustom)

(defcustom sp-dashboard-agenda-issues-files nil
  "Files of the issues agenda; nil uses `org-agenda-files'."
  :type '(choice (const :tag "All agenda files" nil) (repeat file))
  :group 'spcustom)

(defcustom sp-dashboard-agenda-deadlines-files nil
  "Files searched for the coming deadlines; nil uses `org-agenda-files'."
  :type '(choice (const :tag "All agenda files" nil) (repeat file))
  :group 'spcustom)

(defcustom sp-dashboard-deadlines-days 30
  "Days ahead the deadlines agenda looks."
  :type 'integer
  :group 'spcustom)

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
    (define-key map (kbd "g") 'sp-dashboard-refresh)
    (define-key map (kbd "P") 'sp-dashboard-toggle-public-mode)
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
    (define-key map (kbd "RET") 'push-button)
    (define-key map [mouse-2] 'push-button)
    (define-key map [follow-link] 'mouse-face)
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

(defun sp-dashboard--isolate-menu ()
  "Make the buttons the only part of the dashboard that can be reached.
The rest of the buffer, the art and the text around the buttons, is marked
`cursor-intangible', so point can only rest on a button.  An overlay over
the whole buffer carries `sp-dashboard-mode-map' as its keymap, which ranks
above the other keymaps, so the keys of the dashboard are the same wherever
point is."
  (let ((inhibit-read-only t)
        (position (point-min)))
    (add-text-properties (point-min) (point-max) '(cursor-intangible t))
    (let (button)
      (while (setq button (next-button position))
        (remove-text-properties (button-start button) (button-end button)
                                '(cursor-intangible nil))
        (setq position (button-end button)))))
  (cursor-intangible-mode 1)
  (let ((overlay (make-overlay (point-min) (point-max))))
    (overlay-put overlay 'keymap sp-dashboard-mode-map)
    (overlay-put overlay 'priority 100)))

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
  (sp-dashboard--isolate-menu)
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