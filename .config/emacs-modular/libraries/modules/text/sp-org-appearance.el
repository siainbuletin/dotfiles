;;; -*- lexical-binding: t -*-

;; This doesn't include any settings for fonts, as they are declared separately in sp-fonts.
;;
;; However, the overall appearance of an org buffer is declared here.
;;
;; It should, in the future, hold a definition for the way that tables appear in a more modern fashion,
;; later on.

;; show markup at point -- this should be part of org!
(use-package org-appear
  :if (and sp-load-extras (locate-library "org-appear"))
  :after org
  :ensure (:wait t)
 
  :hook
  (org-mode . org-appear-mode)

  :custom
  (org-appear-autoemphasis  t)
  (org-appear-autolinks nil)
  (org-appear-autosubmarkers t)
  :hook (org-mode . org-appear-mode))

(use-package org-modern
  :ensure t
  :defer t
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  
  :custom
  (org-modern-hide-stars 'leading)
  (org-modern-todo nil)
  (org-modern-tag t)
  
  ;; Customize this per your font
  (org-modern-label-border 1)
  ;; Note that these stars allow differentiation of levels
  ;; "①" "②" "③" "④" "⑤" "⑥" "⑦"
  (org-modern-star 'replace)
  (org-modern-replace-stars "⦶⦷⦹⊕⍟⊛⏣❂"))

(use-package olivetti
  :ensure t
  :demand t
  :after org
  :custom
  (olivetti-minimum-body 100)
  (olivetti-body-width 80)
  :bind
  (("C-c w o" . sia-olivetti))
  :hook
  (org-mode . olivetti-mode))

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

(set-face-attribute 'org-document-title nil
                    :font "Atkinson Hyperlegible"
                    :weight 'bold
                    :height 1.8)

;;;; Narrow/Widen with buffers
;; this could definitely be made a lot better for more complicated work with narrowed buffers

(defun lem-narrow-or-widen-dwim (p)
  "Widen if buffer is narrowed, narrow-dwim otherwise.
  Dwim means: region, org-src-block, org-subtree, markdown
  subtree, or defun, whichever applies first. Narrowing to
  org-src-block actually calls `org-edit-src-code'.

  With prefix P, don't widen, just narrow even if buffer
  is already narrowed."
  (declare (interactive-only t))
  (interactive "P")
  (cond ((and (buffer-narrowed-p) (not p)) (widen))
        ((region-active-p)
         (narrow-to-region (region-beginning)
                           (region-end)))
        ((derived-mode-p 'org-mode)
         ;; `org-edit-src-code' is not a real narrowing
         ;; command. Remove this first conditional if
         ;; you don't want it.
         (cond ((ignore-errors (org-edit-src-code) t)
                (delete-other-windows))
               ((ignore-errors (org-narrow-to-block) t))
               (t (org-narrow-to-subtree))))
        ((derived-mode-p 'markdown-mode)
         (markdown-narrow-to-subtree))
        ((derived-mode-p 'latex-mode)
         (LaTeX-narrow-to-environment))
        (t (narrow-to-defun))))

;;bind this in the narrow keymap
(bind-key* "C-x n n" #'lem-narrow-or-widen-dwim narrow-map)

(provide 'sp-org-appearance)