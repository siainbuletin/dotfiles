;;; sp-fonts.el --- Fonts, text scaling and line highlighting -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets up typography: the default, variable-pitch and symbol
;; fonts, emoji and fallback glyphs, line spacing, text scaling keys, a larger
;; minibuffer font, `mixed-pitch' for prose buffers, and the `lin'
;; line-highlighting package.

;;; Code:

;;;; Check Fonts
;; See https://emacsredux.com/blog/2021/12/22/check-if-a-font-is-available-with-emacs-lisp/
(defun sp-font-available-p (font-name)
  "Check if font is available from system instaxlled fonts."
  (member font-name (font-family-list)))

;;;; Set Default & Variable Pitch Fonts
(defun sp-ui--set-default-font (spec)
  "Set the default font based on SPEC.
SPEC is expected to be a plist with the same key names
as accepted by `set-face-attribute'."
  (when spec
    (apply 'set-face-attribute 'default nil spec)))

(defun sp-ui--set-variable-width-font (spec)
  "Set the default font based on SPEC.
SPEC is expected to be a plist with the same key names
as accepted by `set-face-attribute'."
  (when spec
    (apply 'set-face-attribute 'variable-pitch nil spec)))

(defcustom sp-ui-default-font nil
  "The configuration of the `default' face.
Use a plist with the same key names as accepted by `set-face-attribute'."
  :group 'sia-lambda
  :type '(plist :key-type: symbol)
  :tag "Lambda-Emacs Default font"
  :set (lambda (sym val)
         (let ((prev-val (if (boundp 'sp-ui-default-font)
                             sp-ui-default-font
                           nil)))
           (set-default sym val)
           (when (and val (not (eq val prev-val)))
             (sp-ui--set-default-font val)))))

(defcustom sp-ui-variable-width-font nil
  "The configuration of the `default' face.
Use a plist with the same key names as accepted by `set-face-attribute'."
  :group 'sia-lambda
  :type '(plist :key-type: symbol)
  :tag "Lambda-Emacs Variable width font"
  :set (lambda (sym val)
         (let ((prev-val (if (boundp 'sp-ui-variable-width-font)
                             sp-ui-variable-width-font
                           nil)))
           (set-default sym val)
           (when (and val (not (eq val prev-val)))
             (sp-ui--set-variable-width-font val)))))

;; Uncomment and set below variables for fonts other than the defaults
(custom-set-variables
 '(sp-ui-default-font
   '(:font "PT Mono" :height 120)))

(custom-set-variables
 '(sp-ui-variable-width-font
   '(:font "Aporetic Serif Mono" :height 120)))
   
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

;; Set default line spacing. If the value is an integer, it indicates
;; the number of pixels below each line. A decimal number is a scaling factor
;; relative to the current window's default line height. The setq-default
;; function sets this for all buffers. Otherwise, it only applies to the current
;; open buffer
(setq-default line-spacing 0.1)

;;;; Font Lock
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

;; NOTE: This is a hack and it's not at all written nicely in the sense of being able to
;; properly adapt to the system.
;;
;; I should probably try to hook into the faces system of Emacs to get it to work well.
(defun sp-minibuffer ()
  "make minibuffer use larger font size."
  (text-scale-increase 2)) ; Unfortunately the 3 size is a little bit too extreme. it would be nice if I could do it all in increments

(add-hook 'minibuffer-mode-hook 'sp-minibuffer)

(defun sp-text-buffer ()
  "Make the font in the text buffer generally larger."
  (text-scale-increase 4))

;;;; Mixed pitch
(use-package mixed-pitch
  :ensure t

  :config
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-property-value)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-special-keyword)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'font-lock-comment-face)
  :hook (text-mode . mixed-pitch-mode)
)

;;;; Variables for fonts
;; This configuration is taken from HA macs and should be adapted better at some point
;; with better variables, so that it's easier to customize the fonts that are being used.
(defvar ha-fixed-font
  (when window-system
    (or
     ;; Choose favorite installed font from an ordered list (by preference):
     (seq-first
      (seq-filter (lambda (font) (when (x-list-fonts font) font))
                  '("Source Code Pro"
                    "Cousine Nerd Font"
                    "Cascadia Code NF"         ; Microsoft's offical has Nerds
                    "CaskaydiaCove Nerd Font"  ; Best Nerd-based font
                    "NanumGothicCoding"        ; Winner of codingfont.com
                    "Hack Nerd Font"           ; no litagures!?
                    "FiraCode Nerd Font"       ; has too much ligatures
                    "FantasqueSansMono Nerd Font"
                    "Monoid Nerd Font"
                    "Hasklig"
                    )))
     "monospaced"))
  "My fixed width font based on what I have installed.")

(defvar ha-variable-font
  (when window-system
    (or
     (seq-first
      (seq-filter (lambda (font) (when (x-list-fonts font) font))
                  '("SN Pro"
                    "Atkinson Hyperlegible"
                    "Literata"
                    "XCharter"
                    "Charter"
                    "Serif")))
     (warn "Cannot find a Serif Font.  Install Source Sans Pro."))))

(defvar ha-variable-header-font
  (when window-system
    (or
     (seq-first
      (seq-filter (lambda (font) (when (x-list-fonts font) font))
                  '("SN Pro" "Overpass" "DejaVu Sans"
                    "Verdana" "Overpass"
                    "Source Sans Pro"
                    "Lucida Grande"
                    "Sans Serif")))
     (warn "Cannot find a Sans Serif Font.  Install Source Sans Pro."))))

(defun ha-set-favorite-font-size (size)
  "Set the default font size as well as equalize the fixed and variable fonts."

  (let ((fixed-font (format "%s-%d" ha-fixed-font size))
        (prop-font  (format "%s-%d" ha-variable-font size)))
    (when (fboundp 'mixed-pitch-mode)
      (mixed-pitch-mode -1))

    ;; The font specification is the name and the size ... odd enough I guess:
    (set-face-attribute 'default nil :font fixed-font)
    (set-face-attribute 'fixed-pitch nil :font fixed-font :inherit 'default
                        :height 'unspecified)
    (set-face-attribute 'variable-pitch nil :font prop-font :inherit 'default
                        :height 'unspecified)))

(set-face-attribute 'default nil
                  :family "Aporetic Sans Mono"
                  :height 150)

(set-face-attribute 'link nil
                  :family "IntoneMono Nerd Font"
                  :height 150)

(use-package fontaine
  :ensure (:wait t)
  :init
  (fontaine-mode))

(setq prettify-symbols-unprettify-at-point 'right-edge)

(global-prettify-symbols-mode +1)
(prettify-symbols-mode +1)

(add-hook 'text-mode-hook (lambda () (setq-local line-spacing 0.1)))

(set-face-attribute 'org-quote nil
                  :family "Aporetic Serif Mono")

(set-face-attribute 'mode-line nil :height 150)
(set-face-attribute 'mode-line-inactive nil :height 150)

(defun font-size-adjust (delta)
  "Adjust the current frame's font size.
DELTA would be something like 1 or -1."
  (interactive "nFont size difference: ")
  (when (null delta) (setq delta 1))

  (let* ((font-family (face-attribute 'default :font))
         (font-size   (font-get font-family :size))
         (new-size    (+ delta font-size)))
    (ha-set-favorite-font-size new-size)))

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
  :ensure t)

(setq lin-face 'lin-blue) ; this can be set to whatever color I might want otherwise

;; You can use this to live update the face:
;;
;; (customize-set-variable 'lin-face 'lin-green)

(setq lin-mode-hooks
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
        tabulated-list-mode-hook))

(provide 'sp-fonts)
;; sp-fonts.el ends here.
