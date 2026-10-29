;;; sp-notes.el --- Denote workbook entries and consult-notes -*- lexical-binding: t; -*-

;;; Commentary:

;; sia -set-notes.el --- packages for notes

;; For a framework that looks to bring notes together, you need more settings for different things.
;; This will be called as a module in itself later on
;; this is a basic note-taking workflow that's based on denote (at first)
;; - this will include calling on features for org-capture
;; although the capture mechanism should be living somewhere separate.

;; This is the configuration that was taken from Lambda Emacs

;; This library provides settings fora basic notes workflow using the `Denote' package.

;;; Code:

(defun sp-denote-workbook-create-entry ()
  "Create an entry tagged \\='workbook\\=' with the date as its title.
Superseded by `sp-denote-log-entry' in the user layer, which writes into
log/ instead. Kept because old entries still live in workbook/."
  (interactive)
  (denote
   (format-time-string "%Y %A %e %B")   ; format like Tuesday 14 June 2022
   '("workbook")
   nil
   ;; `denote-directory' holds a list of trees, so the old
   ;; (concat denote-directory "workbook") is a type error here. The workbook
   ;; belongs to the notes tree, which denote returns as the first entry.
   (expand-file-name "workbook" (car (denote-directories)))
   nil
   nil)
  (sp-insert-header-and-time-property))

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
  (("C-c w d f" . consult-notes)
   ("C-c w d g" . consult-notes-search-in-all-notes))

  :config
  ;; Without a source, consult-notes shows an empty picker. The denote
  ;; source lists everything under `denote-directory'.
  (consult-notes-denote-mode 1)
)

;; Creating a notebook is a much more useful way of using consult-notes,
;; instead of the minibuffer. However, I don't make much use of denote
;; anymore, as I prefer having IDs.
;;
;; The better option would be adapting this to the ID-based workflow
;; by making it query IDs.
;;
;; But this means making use of a different consult plugin.
(defun sp-denote-notebook ()
  "Open `consult-notes in buffer window rather than minibuffer."
  (interactive)
  (let ((vertico-buffer-display-action
         '(display-buffer-reuse-window)))
    (consult-notes)))

(provide 'sp-notes)
;;; sp-notes.el ends here
