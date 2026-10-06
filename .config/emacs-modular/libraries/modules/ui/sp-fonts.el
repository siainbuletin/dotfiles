;; -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

;;;; Mixed pitch
(use-package mixed-pitch
  :ensure t

  :config
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-property-value)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-special-keyword)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'font-lock-comment-face)
  :hook (text-mode . mixed-pitch-mode)
)

(set-face-attribute 'default nil
                  :family "PT Mono"
                  :height 100)



;;;; Variables for fonts
;; This configuration is taken from HA macs and should be adapted better at some point
;; with better variables, so that it's easier to customize the fonts that are being used.
(defvar ha-fixed-font
  (when window-system
    (or
     ;; Choose favorite installed font from an ordered list (by preference):
     (seq-first
      (seq-filter (lambda (font) (when (x-list-fonts font) font))
                  '("Cascadia Code NF"         ; Microsoft's offical has Nerds
                    "CaskaydiaCove Nerd Font"  ; Best Nerd-based font
                    "NanumGothicCoding"        ; Winner of codingfont.com
                    "Hack Nerd Font"           ; no litagures!?
                    "FiraCode Nerd Font"       ; has too much ligatures
                    "Cousine Nerd Font"
                    "Iosevka Nerd Font"
                    "FantasqueSansMono Nerd Font"
                    "Monoid Nerd Font"
                    "Hasklig"
                    "Source Code Pro")))
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

; (set-face-attribute 'default nil
;                     :family "0xProto Nerd Font")

(set-face-attribute 'default nil
                  :family "Aporetic Sans Mono"
                  :height 100)

(set-face-attribute 'link nil
                  :family "IntoneMono Nerd Font"
                  :height 100)

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

(setq org-ellipsis " [+]")

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

(global-set-key (kbd "s-+") 'font-size-increase)
(global-set-key (kbd "s-=") 'font-size-increase)
(global-set-key (kbd "s--") 'font-size-decrease)

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

;;;; FONTSET
;; The fontset settings are necessary to make the lambda-line and lambda-dashboard work properly
(use-package fontset
  :ensure nil
  :config
  ;; Use symbola for proper unicode
  (when (member "Symbola" (font-family-list))
  (set-fontset-font
  t 'symbol "Symbola" nil))
)

(provide 'sp-fonts)
;; sp-fonts.el ends here.