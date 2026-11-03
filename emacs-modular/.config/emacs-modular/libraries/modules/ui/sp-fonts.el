;;; sp-fonts.el --- Fonts, text scaling and line highlighting -*- lexical-binding: t; -*-

;;; Commentary:

;; Typography for the whole configuration.  `fontaine' owns the font
;; families and sizes: its presets set the `default', `fixed-pitch' and
;; `variable-pitch' faces, line spacing and the mode line height in one
;; place, and the latest preset is restored at startup.  The rest of this
;; file reacts to those faces: symbol and emoji fallbacks, text scaling,
;; `mixed-pitch' for prose and `lin' for line highlighting.

;;; Code:

;;;; Check Fonts
;; See https://emacsredux.com/blog/2021/12/22/check-if-a-font-is-available-with-emacs-lisp/
(defun sp-font-available-p (font-name)
  "Check if font is available from system installed fonts."
  (member font-name (font-family-list)))

(defface sp-text-face '((t))
  "Size of the text in Org and the other text modes, set by the fontaine presets.
Only its `:height' is used, as a multiple of the `default' height."
  :group 'faces)

(use-package fontaine
  :ensure (:wait t)
  :demand t
  :custom
  (fontaine-latest-state-file (concat sp-cache-dir "fontaine-latest-state.eld"))
  (fontaine-presets
   '((regular
      :default-family "Aporetic Sans Mono"
      :default-height 150
      :variable-pitch-family "Aporetic Serif Mono"
      :variable-pitch-height 120
      :mode-line-active-height 150
      :mode-line-inactive-height 150
      :line-spacing 0.1)
     (presentation
      :default-family "Aporetic Sans Mono"
      :default-height 220
      :variable-pitch-family "Charter"
      :variable-pitch-height 220
      :mode-line-active-height 220
      :mode-line-inactive-height 220
      ;; The default height is already large here.
      :sp-text-face-height 1.0
      :line-spacing 0.2)
     (writing
      :default-family "Aporetic Sans Mono"
      :default-height 150
      :variable-pitch-family "Charter"
      :variable-pitch-height 170
      :mode-line-active-height 150
      :mode-line-inactive-height 150
      :line-spacing 0.25)
     (t
      ;; 1.0 keeps the dashboard boxes on the grid of the `default' font; any other
      ;; value makes the box text and the box lines differ in width and misalign.
      :sp-dashboard-menu-face-height 1.0
      ;; Org and the other text modes are
      ;; 1.36 times the `default' height (4 `text-scale' steps of 1.08).
      :sp-text-face-height 1.36
      :default-weight regular
      :bold-weight bold
      :italic-slant italic)))
  :config
  ;; Faces of this configuration that the presets also size: a preset reads
  ;; `:FACE-height' as a multiple of the `default' height.  This has to run
  ;; before the first preset is set.
  (dolist (face '(sp-dashboard-menu-face sp-text-face))
    (add-to-list 'fontaine-faces face t))
  (fontaine-set-preset (or (fontaine-restore-latest-preset) 'regular))
  (fontaine-mode 1))

(set-face-attribute 'link nil
                  :family "IntoneMono Nerd Font"
                  :height 150)

(defun sp-fonts-org-faces ()
  "Set the fonts of the Org title and quote, and keep headings at text size."
  (set-face-attribute 'org-document-title nil
                      :family "Atkinson Hyperlegible" :height 1.0)
  (set-face-attribute 'org-quote nil
                      :family "Literata" :height 1.0)
  (dotimes (n 8)
    (set-face-attribute (intern (format "org-level-%d" (1+ n))) nil
                        :height 1.0)))

(with-eval-after-load 'org
  (sp-fonts-org-faces))
(add-hook 'sp-after-load-theme-hook #'sp-fonts-org-faces)
(add-hook 'fontaine-set-preset-hook #'sp-fonts-org-faces)

;;;; Set Symbol & Emoji Fonts
;; The fontset settings are necessary to make the lambda-line and lambda-dashboard work properly
(use-package fontset
  :ensure nil

  :custom
  ;; Set this to nil to set symbols entirely separately
  ;; Need it set to `t` in order to display org-modern-indent faces properly
  (use-default-font-for-symbols t)

  :config
  ;; Use symbola for proper symbol glyphs, but have some fallbacks
  (cond ((sp-font-available-p "Symbola")
         (set-fontset-font
          t 'symbol "Symbola" nil))
        ((sp-font-available-p "Apple Symbols")
         (set-fontset-font
          t 'symbol "Apple Symbols" nil))
        ((sp-font-available-p "Symbol")
         (set-fontset-font
          t 'symbol "Symbol" nil))
        ((sp-font-available-p "Segoe UI Symbol")
         (set-fontset-font
          t 'symbol "Segoe UI Symbol" nil)))

  ;; Use Apple emoji
  ;; NOTE that emoji here may need to be set to unicode to get color emoji
  (when (and (>= emacs-major-version 28)
             (sp-font-available-p "Apple Color Emoji"))
    (set-fontset-font t 'emoji
                      '("Apple Color Emoji" . "iso10646-1") nil 'prepend))

  ;; Fall back font for missing glyph
  (defface fallback '((t :family "Fira Code"
                         :inherit fringe)) "Fallback")
  (set-display-table-slot standard-display-table 'truncation
                          (make-glyph-code ?… 'fallback))
  (set-display-table-slot standard-display-table 'wrap
                          (make-glyph-code ?↩ 'fallback)))

(use-package font-lock
  :ensure nil
  :defer 1
  :custom
  ;; Max font lock decoration (set nil for less)
  (font-lock-maximum-decoration t)
  ;; No limit on font lock
  (font-lock-maximum-size nil))

;;;; Scale Text
;; When using `text-scale-increase', this sets each 'step' to about one point size.
;;
;; This should be improved globally to adapt to the resolution of the screen that you're
;; working with.
(setopt text-scale-mode-step 1.08)
(bind-key* "s-=" #'text-scale-increase)
(bind-key* "s--" #'text-scale-decrease)
(bind-key* "s-0" #'text-scale-adjust)

(defun sp-text-buffer ()
  "Make the font in the text buffer generally larger, by `sp-text-face'."
  (face-remap-add-relative 'default 'sp-text-face))

(use-package mixed-pitch
  :ensure t

  :config
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-property-value)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-special-keyword)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'font-lock-comment-face)
  :hook (text-mode . mixed-pitch-mode)
)

(setq prettify-symbols-unprettify-at-point 'right-edge)

(global-prettify-symbols-mode +1)
(prettify-symbols-mode +1)

(add-hook 'text-mode-hook (lambda () (setq-local line-spacing 0.1)))

(defun font-size-adjust (delta)
  "Adjust the height of the `default' face by DELTA points.
DELTA would be something like 1 or -1.  The next
`fontaine-set-preset' restores the height of the preset."
  (interactive "nFont size difference: ")
  (set-face-attribute 'default nil
                      :height (max 60 (+ (face-attribute 'default :height)
                                         (* 10 (or delta 1))))))

(defun font-size-increase ()
   "Increase the `default' font size of all frames."
   (interactive)
   (font-size-adjust 1))

(defun font-size-decrease ()
   "Decrease the `default' font size of all frames."
   (interactive)
   (font-size-adjust -1))

(global-set-key (kbd "M-+") 'font-size-increase)
(global-set-key (kbd "M-=") 'font-size-increase)
(global-set-key (kbd "M--") 'font-size-decrease)

;;;; Font Cycling
(require 'seq)
(require 'subr-x)

(defcustom sp-font-cycle-families
  '("3270 Nerd Font Mono"
    "GoMono Nerd Font"
    "Hack Nerd Font Mono"
    "Hurmit Nerd Font Mono"
    "Inconsolata LGC Nerd Font"
    "Iosevka Nerd Font Mono"
    "IosevkaTerm Nerd Font Mono"
    "JetBrainsMono Nerd Font"
    "Lekton Nerd Font Mono"
    "M+CodeLat50 Nerd Font"
    "Maple Mono NF"
    "MartianMono Nerd Font"
    "SauceCodePro Nerd Font"
    "UbuntuMono Nerd Font Mono"
    "VictorMono Nerd Font Mono"
    "ZedMono Nerd Font Mono")
  "Families of the `curated' kind of `sp-font-cycle-kinds'.
The default families of the `fontaine-presets' are added to the list, and
only the installed ones are used."
  :type '(repeat string)
  :group 'faces)

(defcustom sp-font-cycle-kinds
  '((mono "fixed width" default mono)
    (proportional "proportional, for prose" variable-pitch proportional)
    (curated "curated list" default curated)
    (all "every font" default any))
  "The kinds of fonts `sp-font-cycle' can preview.
Each is (NAME DESCRIPTION FACE FAMILIES).  FACE is `default' or
`variable-pitch': the face that is previewed and that `sp-font-cycle-save'
writes into a fontaine preset (`:default-family' or `:variable-pitch-family').
FAMILIES is `mono' (every fixed width family of the system), `proportional'
(every other one), `any' (every family) or `curated' (see
`sp-font-cycle-families').  The first kind is the one the menu starts with."
  :type '(repeat (list symbol string
                       (choice (const default) (const variable-pitch))
                       (choice (const mono) (const proportional)
                               (const any) (const curated))))
  :group 'faces)

(defcustom sp-font-cycle-skip-regexp
  (pcase system-type
    ('darwin "\\`\\.")
    ('windows-nt "\\`@")
    (_ nil))
  "Families of the system lists that match this are left out.
macOS lists hidden system fonts that start with a dot (.SF NS), and Windows
lists vertical writing variants that start with @."
  :type '(choice (const nil) regexp)
  :group 'faces)

(defvar sp-font-cycle--kind nil
  "The name of the kind being previewed, from `sp-font-cycle-kinds'.")

(defvar sp-font-cycle--index 0
  "Position of the previewed family in `sp-font-cycle--installed'.")

(defvar sp-font-cycle--start nil
  "The (FAMILY . HEIGHT) of both faces when the menu was opened.")

(defvar sp-font-cycle--system-cache nil
  "The usable families of the system, kept until `sp-font-cycle-refresh'.")

(defvar sp-font-cycle--mono-cache (make-hash-table :test #'equal)
  "Whether a family is fixed width, by family name.")

(defun sp-font-cycle--kind ()
  "Return the entry of the current kind in `sp-font-cycle-kinds'."
  (or (assq sp-font-cycle--kind sp-font-cycle-kinds)
      (car sp-font-cycle-kinds)))

(defun sp-font-cycle--face ()
  "Return the face the current kind previews."
  (nth 2 (sp-font-cycle--kind)))

(defun sp-font-cycle--family ()
  "Return the family of the previewed face."
  (face-attribute (sp-font-cycle--face) :family nil t))

(defun sp-font-cycle--height ()
  "Return the height of the previewed face."
  (face-attribute (sp-font-cycle--face) :height nil t))

(defun sp-font-cycle--preset-families ()
  "Return the families the fontaine presets give to the previewed face."
  (when (boundp 'fontaine-presets)
    (let ((key (if (eq (sp-font-cycle--face) 'default)
                   :default-family :variable-pitch-family)))
      (delq nil (mapcar (lambda (preset) (plist-get (cdr preset) key))
                        fontaine-presets)))))

(defun sp-font-cycle--monospace-p (family)
  "Return non-nil when FAMILY is fixed width.
Compare the advance of \"i\" and \"M\" in the opened font, which every
backend (fontconfig, macOS, Windows) can answer, unlike the `:spacing'
property, which only fontconfig fills in."
  (pcase (gethash family sp-font-cycle--mono-cache 'unknown)
    ('unknown
     (puthash family
              (condition-case nil
                  (and-let* ((entity (find-font (font-spec :family family)))
                             (font (open-font entity 12))
                             (narrow (aref (aref (font-get-glyphs font 0 1 "i") 0) 4))
                             (wide (aref (aref (font-get-glyphs font 0 1 "M") 0) 4)))
                    (= narrow wide))
                (error nil))
              sp-font-cycle--mono-cache)
     (gethash family sp-font-cycle--mono-cache))
    (cached cached)))

(defun sp-font-cycle--system-families ()
  "Return the usable families of this system, sorted."
  (or sp-font-cycle--system-cache
      (setq sp-font-cycle--system-cache
            (sort (seq-remove
                   (lambda (family)
                     (and sp-font-cycle-skip-regexp
                          (string-match-p sp-font-cycle-skip-regexp family)))
                   (delete-dups (font-family-list)))
                  #'string-collate-lessp))))

(defun sp-font-cycle--installed ()
  "Return the families of the current kind that are installed on this system."
  (let ((which (nth 3 (sp-font-cycle--kind))))
    (if (and (memq which '(mono proportional any)) (display-graphic-p))
        (let ((all (sp-font-cycle--system-families)))
          (pcase which
            ('any all)
            ('mono (seq-filter #'sp-font-cycle--monospace-p all))
            (_ (seq-remove #'sp-font-cycle--monospace-p all))))
      (seq-filter (lambda (family) (find-font (font-spec :family family)))
                  (delete-dups (append (sp-font-cycle--preset-families)
                                       sp-font-cycle-families))))))

(defun sp-font-cycle--sync-index ()
  "Point `sp-font-cycle--index' at the family of the previewed face."
  (setq sp-font-cycle--index
        (or (seq-position (sp-font-cycle--installed) (sp-font-cycle--family))
            0)))

(defun sp-font-cycle-refresh ()
  "Forget the cached system families, after installing a font."
  (interactive)
  (setq sp-font-cycle--system-cache nil)
  (clrhash sp-font-cycle--mono-cache)
  (sp-font-cycle--sync-index))

(defun sp-font-cycle-kind (kind)
  "Preview fonts of KIND, one of `sp-font-cycle-kinds'."
  (interactive
   (list (intern (car (split-string
                       (completing-read
                        "Kind of font: "
                        (mapcar (lambda (kind)
                                  (format "%s (%s)" (car kind) (nth 1 kind)))
                                sp-font-cycle-kinds)
                        nil t))))))
  (setq sp-font-cycle--kind (if (stringp kind) (intern kind) kind))
  (sp-font-cycle--sync-index))

(defun sp-font-cycle--kind-label ()
  "Describe the current kind for the menu."
  (format "kind: %s (%s)" (car (sp-font-cycle--kind))
          (nth 1 (sp-font-cycle--kind))))

(defun sp-font-cycle--select (index)
  "Preview the installed family at INDEX, wrapping around both ends."
  (let ((fonts (sp-font-cycle--installed)))
    (unless fonts
      (user-error "No installed font of this kind; a terminal frame has no list"))
    (setq sp-font-cycle--index (mod index (length fonts)))
    (set-face-attribute (sp-font-cycle--face) nil
                        :family (nth sp-font-cycle--index fonts))))

(defun sp-font-cycle-next ()
  "Preview the next font."
  (interactive)
  (sp-font-cycle--select (1+ sp-font-cycle--index)))

(defun sp-font-cycle-previous ()
  "Preview the previous font."
  (interactive)
  (sp-font-cycle--select (1- sp-font-cycle--index)))

(defun sp-font-cycle--resize (delta)
  "Change the height of the previewed face by DELTA (1/10 pt), at least 6pt."
  (let ((height (sp-font-cycle--height)))
    (unless (integerp height)
      (user-error "The height of %s is relative; it has no size to change"
                  (sp-font-cycle--face)))
    (set-face-attribute (sp-font-cycle--face) nil :height (max 60 (+ height delta)))))

(defun sp-font-cycle-bigger ()
  "Increase the size of the previewed face by 1pt."
  (interactive)
  (sp-font-cycle--resize 10))

(defun sp-font-cycle-smaller ()
  "Decrease the size of the previewed face by 1pt."
  (interactive)
  (sp-font-cycle--resize -10))

(defun sp-font-cycle-restore ()
  "Go back to the fonts and sizes the menu was opened with."
  (interactive)
  (dolist (entry sp-font-cycle--start)
    (set-face-attribute (car entry) nil
                        :family (cadr entry) :height (cddr entry)))
  (sp-font-cycle--sync-index))

(defun sp-font-cycle--form ()
  "Return the `set-face-attribute' call for the previewed font."
  (format "(set-face-attribute '%s nil :family %S :height %d)"
          (sp-font-cycle--face) (sp-font-cycle--family) (sp-font-cycle--height)))

(defun sp-font-cycle-copy ()
  "Copy the previewed font as Elisp to the kill ring."
  (interactive)
  (kill-new (sp-font-cycle--form))
  (message "Copied: %s" (current-kill 0)))

(defun sp-font-cycle--description ()
  "Header showing the previewed font, its size and its place in the list."
  (format "%s  %dpt  [%d/%d]  %s face"
          (propertize (sp-font-cycle--family) 'face 'bold)
          (/ (sp-font-cycle--height) 10)
          (1+ sp-font-cycle--index)
          (length (sp-font-cycle--installed))
          (sp-font-cycle--face)))

(transient-define-prefix sp-font-cycle-menu ()
  "Preview fonts and sizes, and save them in a fontaine preset."
  [:description sp-font-cycle--description
   ["Font"
    ("<right>" "next" sp-font-cycle-next :transient t)
    ("<left>" "previous" sp-font-cycle-previous :transient t)
    ("k" "kind" sp-font-cycle-kind :description sp-font-cycle--kind-label
     :transient t)
    ("g" "rescan fonts" sp-font-cycle-refresh :transient t)]
   ["Size"
    ("<up>" "bigger" sp-font-cycle-bigger :transient t)
    ("<down>" "smaller" sp-font-cycle-smaller :transient t)]
   ["Keep"
    ("s" "save in config" sp-font-cycle-save)
    ("y" "copy as elisp" sp-font-cycle-copy)
    ("r" "restore" sp-font-cycle-restore :transient t)
    ("q" "quit" transient-quit-one)]])

(defun sp-font-cycle ()
  "Preview the installed fonts and sizes with a menu; `s' saves the choice."
  (interactive)
  (setq sp-font-cycle--kind (car (car sp-font-cycle-kinds))
        sp-font-cycle--start
        (mapcar (lambda (face)
                  (cons face (cons (face-attribute face :family nil t)
                                   (face-attribute face :height nil t))))
                '(default variable-pitch)))
  (sp-font-cycle--sync-index)
  (sp-font-cycle-menu))

;;;;; Saving the choice
;; The family and the height of a preset live in `fontaine-presets', in the
;; preset forms of this file and of its doc.  Saving edits both, so the doc
;; stays the source of the tangled file.

(defun sp-font-cycle--module-file ()
  "Return the path of this module."
  (expand-file-name "libraries/modules/ui/sp-fonts.el" user-emacs-directory))

(defun sp-font-cycle--doc-file ()
  "Return the path of the literate doc of this module."
  (expand-file-name "docs/tangles/ui/sp-fonts.org" user-emacs-directory))

(defun sp-font-cycle--table-row (preset face family height)
  "Update the row of PRESET in the preset table of the current buffer, if any.
FACE (`default' or `variable-pitch') picks the family and height columns;
FAMILY and HEIGHT are the new values; the cell widths are kept."
  (goto-char (point-min))
  (when (re-search-forward (format "^| *=%s= *|.*$" (regexp-quote (symbol-name preset)))
                           nil t)
    (let* ((beg (match-beginning 0))
           (end (match-end 0))
           (cells (split-string (match-string 0) "|"))
           (family-cell (if (eq face 'default) 2 3))
           (height-cell (if (eq face 'default) 4 5))
           (set-cell (lambda (n text)
                       (setf (nth n cells)
                             (string-pad (concat " " text)
                                         (max (length (nth n cells))
                                              (+ 1 (length text))))))))
      (when (>= (length cells) 6)
        (funcall set-cell family-cell family)
        (funcall set-cell height-cell (number-to-string height))
        (delete-region beg end)
        (goto-char beg)
        (insert (string-join cells "|"))))))

(defun sp-font-cycle--rewrite (file preset face family height)
  "Set the FACE family and height of PRESET in FILE to FAMILY and HEIGHT.
FACE is `default' or `variable-pitch'.  Return non-nil when FILE changed.
Signal a `user-error' when PRESET lacks the family and height of FACE in FILE."
  (let ((buffer (find-buffer-visiting file))
        (prefix (if (eq face 'default) ":default" ":variable-pitch")))
    (when (and buffer (buffer-modified-p buffer))
      (user-error "Save %s first" (abbreviate-file-name file)))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((original (buffer-string)))
        (goto-char (point-min))
        (unless (re-search-forward
                 (format "(%s$" (regexp-quote (symbol-name preset))) nil t)
          (user-error "No preset %s in %s" preset (abbreviate-file-name file)))
        (let ((start (match-beginning 0))
              end)
          (setq end (with-syntax-table emacs-lisp-mode-syntax-table
                      (scan-sexps start 1)))
          (save-restriction
            (narrow-to-region start end)
            (dolist (change `((,(format "%s-family \"[^\"]*\"" prefix)
                               . ,(format "%s-family %S" prefix family))
                              (,(format "%s-height [0-9]+" prefix)
                               . ,(format "%s-height %d" prefix height))))
              (goto-char (point-min))
              (unless (re-search-forward (car change) nil t)
                (user-error "Preset %s has no %s in %s" preset
                            (car change) (abbreviate-file-name file)))
              (replace-match (cdr change) t t))))
        (sp-font-cycle--table-row preset face family height)
        (unless (string= original (buffer-string))
          (write-region (point-min) (point-max) file nil 'silent)
          (when buffer
            (with-current-buffer buffer (revert-buffer t t t)))
          t)))))

(defun sp-font-cycle--read-preset ()
  "Ask for the fontaine preset to change, the current one by default."
  (let* ((names (mapcar #'symbol-name
                        (seq-remove (lambda (name) (eq name t))
                                    (mapcar #'car fontaine-presets))))
         (current (and (boundp 'fontaine-current-preset)
                       (symbol-name fontaine-current-preset))))
    (intern (completing-read
             (format "Save font in preset (default %s): "
                     (or current "regular"))
             names nil t nil nil (or current "regular")))))

(defun sp-font-cycle-save (&optional preset)
  "Make the previewed font the one of PRESET in the config, permanently.
The `default' face writes the default family and height of PRESET, the
`variable-pitch' face the variable-pitch ones.  Edit the preset in the doc
and in the module, then offer to reload the module.  PRESET is asked for,
with the current fontaine preset as the default."
  (interactive)
  (unless (require 'fontaine nil t)
    (user-error "Fontaine is not available"))
  (let* ((preset (or preset (sp-font-cycle--read-preset)))
         (face (sp-font-cycle--face))
         (family (sp-font-cycle--family))
         (height (sp-font-cycle--height))
         (files (list (sp-font-cycle--doc-file) (sp-font-cycle--module-file)))
         (changed (delq nil (mapcar (lambda (file)
                                      (and (sp-font-cycle--rewrite
                                            file preset face family height)
                                           (abbreviate-file-name file)))
                                    files))))
    (if (not changed)
        (message "Preset %s already has %s at %d for %s" preset family height face)
      (message "Preset %s now has %s at %d for %s in %s" preset family height face
               (string-join changed ", "))
      (when (y-or-n-p (format "Reload %s to make it permanent? "
                              (file-name-nondirectory
                               (sp-font-cycle--module-file))))
        (load (sp-font-cycle--module-file) nil 'nomessage)
        (fontaine-set-preset preset)))))

;;;; Lin package
(use-package lin
  :ensure t

  :custom
  (lin-face 'lin-blue)  ; this can be set to whatever color I might want otherwise
  (lin-mode-hooks
   '(bongo-mode-hook
     dired-mode-hook
     elfeed-search-mode-hook
     git-rebase-mode-hook
     grep-mode-hook
     ibuffer-mode-hook
     ilist-mode-hook
     ledger-report-mode-hook
     log-view-mode-hook
     magit-log-mode-hook
     mu4e-headers-mode-hook
     notmuch-search-mode-hook
     notmuch-tree-mode-hook
     occur-mode-hook
     org-agenda-mode-hook
     pdf-outline-buffer-mode-hook
     proced-mode-hook
     tabulated-list-mode-hook)))

;; You can use this to live update the face:
;;
;; (customize-set-variable 'lin-face 'lin-green)

;;; Provide
(provide 'sp-fonts)
;;; sp-fonts.el ends here
