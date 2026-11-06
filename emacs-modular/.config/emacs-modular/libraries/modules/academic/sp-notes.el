;;; sp-notes.el --- consult-notes and the notes picker -*- lexical-binding: t; -*-

;;; Commentary:

;; sia -set-notes.el --- packages for notes

;; For a framework that looks to bring notes together, you need more settings for different things.
;; This will be called as a module in itself later on
;; - this will include calling on features for org-capture
;; although the capture mechanism should be living somewhere separate.

;; This is the configuration that was taken from Lambda Emacs

;; This library provides `consult-notes' and `sp-notes-notebook' (Denote was removed).

;;; Code:

;;;; Consult Notes
;; Adapted from https://github.com/minad/consult/wiki/hrm-notes
;; this is taken from Lambda Emacs
(use-package consult-notes
  :ensure t
  ;; Not gated: I find that it makes the startup a lot slower if I have this turned on, it's not an extra, I want to be able to have it on hand.
  ;; :after consult

  :commands
  (consult-notes
             consult-notes-search-in-all-notes)

  :bind
  (("C-c w d f" . sp-notes-notebook)
   ("C-c w d g" . consult-notes-search-in-all-notes))

  :config
  ;; Without a source, consult-notes shows an empty picker. Denote is
  ;; gone: the notes are found by `vulpea-find' (see `sp-notes-notebook').
)

;; The notes are ID-based and indexed by vulpea, so the notebook is the vulpea picker.
(defun sp-notes-notebook ()
  "Pick a note with `vulpea-find', in the buffer window rather than the minibuffer."
  (interactive)
  (let ((vertico-buffer-display-action
         '(display-buffer-reuse-window)))
    (call-interactively #'vulpea-find)))

(provide 'sp-notes)
;;; sp-notes.el ends here
