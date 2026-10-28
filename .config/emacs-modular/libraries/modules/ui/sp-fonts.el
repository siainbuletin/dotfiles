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
