;; -*- lexical-binding: t; -*-
;; sia-set-beets.el

;; How should this be plugged in with an actual installation of beets?

(use-package beets-edit-mode
  :ensure (:host github :repo "emreyolcu/beets-edit-mode")
  :init
  ;; The plugin's buffers have random temporary file names,
  ;; so nothing associates them with the mode; detect them by content.
  (add-to-list 'magic-mode-alist '(beets-edit-buffer-p . beets-edit-mode))
  :hook
  ;; Both are optional.
  ((beets-edit-mode . beets-edit-compact-mode)      ; start in the compact view
   (beets-edit-mode . electric-quote-local-mode)))  ; curly quotes as you type

;; sia-set-beets.el ends here.