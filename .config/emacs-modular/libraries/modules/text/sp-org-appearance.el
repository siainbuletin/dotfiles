;;; -*- lexical-binding: t -*-
;; sp-org-appearance.el

;;; Commentary:

;; This doesn't include any settings for fonts, as they are declared separately in sp-fonts.
;;
;; However, the overall appearance of an org buffer is declared here.
;;
;; It should, in the future, hold a definition for the way that tables appear in a more modern fashion,
;; later on.

;;; Code:

;;;; General org basic appearance options
;;; these were taken initially from Lambda Emacs
(setq org-cycle-separator-lines 0) ;; no empty lines in collapsed view
;; (setq org-ellipsis "…") ;; nicer elipses "↷" "↴" "▼"
(setq org-ellipsis " [+]")
(setq org-fontify-quote-and-verse-blocks t) ;; make quotes stand out

(setq org-hide-leading-stars t)  ;; hide leading stars

(setq org-read-date-prefer-future 'time) ;; Incomplete dates refer to future dates & times
(setq org-startup-folded 'content) ;; Show the content when starting up

;;;;; Working with inline images
(setq org-image-actual-width  500) ;; show all images at 500px using imagemagik
(setq org-startup-with-inline-images t)

;;;;; Prettify
(setq org-pretty-entities t) ;; make latex look good, etc.
(setq org-pretty-entities-include-sub-superscripts t) ;; prettify sub/superscripts

;;;;; Tags
(setq org-auto-align-tags nil) ;; don't auto-align tags
(setq org-tags-column 0) ;; place tags directly next to headline text

;;;;; Fontification
(setq org-src-fontify-natively t)
(setq org-fontify-quote-and-verse-blocks t)

;;;;; Emphasis
(setq org-hide-emphasis-markers t)  ;; hide emph markers

;; show markup at point -- this should be part of org!
;; it seems that this creates quite a bit of issues with the invisible section, so it's turned off for now
;; (use-package org-appear
;;   ;; :if (and sp-load-extras (locate-library "org-appear"))
;;   :ensure (:wait t)
;;   :after org

;;   :hook
;;   (org-mode . org-appear-mode)

;;   :custom
;;   (org-appear-autoemphasis  t)
;;   (org-appear-autolinks nil)
;;   (org-appear-autosubmarkers t))

;;;; Org-modern
(use-package org-modern
  :ensure t
  :defer t
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))

  :custom
  ;; (org-modern-hide-stars 'leading) ;; this causes issues with the invisible region -- this should be fixed at some point
  (org-modern-todo nil)
  (org-modern-tag nil)

  ;; Customize this per your font
  (org-modern-label-border 1)
  ;; Note that these stars allow differentiation of levels
  ;; "①" "②" "③" "④" "⑤" "⑥" "⑦"
  ;; Modify these levels so they don't actually show the numbers (that's bad)
  (org-modern-star 'replace)
  (org-modern-replace-stars "⦶⦷⦹⊕⍟⊛⏣❂"))

;;;; List behavior
(use-package org-autolist
  :ensure t)

(use-package org-bulletproof
  :ensure (:wait t)
  :after (org org-modern)
  :init
(global-org-bulletproof-mode))

(defface org-checkbox-done-text
  '((t (:foreground "#71696A" :strike-through t)))
  "Face for the text part of a checked org-mode checkbox.")

(font-lock-add-keywords
 'org-mode
 `(("^[ \t]*\\(?:[-+*]\\|[0-9]+[).]\\)[ \t]+\\(\\(?:\\[@\\(?:start:\\)?[0-9]+\\][ \t]*\\)?\\[\\(?:X\\|\\([0-9]+\\)/\\2\\)\\][^\n]*\n\\)"
    1 'org-checkbox-done-text prepend))
 'append)

;;;; Spacious padding --- and other padding settings
(use-package spacious-padding
  :ensure t
  :init
  (spacious-padding-mode))

(setq spacious-padding-widths
      '( :internal-border-width 25
         :header-line-width 4
         :mode-line-width 10
         :tab-width 7
         :right-divider-width 30
         :scroll-bar-width 8
         :fringe-width 8))

(setq spacious-padding-subtle-frame-lines
      `( :mode-line-active default
         :mode-line-inactive shadow))

;; On a tty frame (`emacsclient -c' from a terminal, `-t') the theme faces
;; have unspecified colors, and `spacious-padding-set-faces' builds an
;; invalid `:underline (:color unspecified ...)' for `header-line-inactive'.
;; The error aborts `make-frame', so the server deletes the new frame.
;; Padding only matters on graphic frames, so skip the rest.
(define-advice spacious-padding-set-parameters-of-frame
    (:around (fn &optional frame) sp-graphic-only)
  "Only apply spacious padding to graphic FRAME."
  (when (display-graphic-p frame)
    (funcall fn frame)))

;;; Provide:

(provide 'sp-org-appearance)
;; sp-org-appearance.el ends here.
