;;; -*- lexical-binding: t -*-

;; This doesn't include any settings for fonts, as they are declared separately in sia-set-fonts.
;;
;; However, the overall appearance of an org buffer is declared here.
;;
;; It should, in the future, hold a definition for the way that tables appear in a more modern fashion,
;; later on.

;; show markup at point -- this should be part of org!
(use-package org-appear
  :if (and sp-load-extras (locate-library "org-appear"))
  
  :commands 
  (org-appear-mode)
  
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

(require 'sia-set-org-appearance)