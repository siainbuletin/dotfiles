;; -*- lexical-binding: t -*-
;; sia -set-notes.el --- packages for notes

;; For a framework that looks to bring notes together, you need more settings for different things.
;; This will be called as a module in itself later on
;; this is a basic note-taking workflow that's based on denote (at first)
;; - this will include calling on features for org-capture
;; although the capture mechanism should be living somewhere separate.

;; This is the configuration that was taken from Lambda Emacs

;; This library provides settings fora basic notes workflow using the `Denote' package.

;;; Code:

;;;; Notebook Setup

(defcustom lem-notes-dir nil
  "Set a directory path for notes."
  :group 'sia-lambda
  :type 'string)

(use-package denote
  :if (and sp-load-extras (locate-library "denote"))
  :commands (denote denote-create-note denote-link-ol-store)
  
  :custom
  ;; Use org-read-date
  (denote-date-prompt-use-org-read-date t)
  (denote-file-type 'org) ;; use org
  (denote-allow-multi-word-keywords nil) ;; single word keywords only
  
  ;; Set default prompts for note creation
  (denote-prompts '(title keywords subdirectory))
  ;; Set multiple keywords as a list of strings
  (denote-known-keywords '("workbook" "project" "idea")))

;; Org-capture note creation with Denote
(with-eval-after-load 'org-capture
  (add-to-list 'org-capture-templates
               '("n" "New note (with Denote)" plain
                 (file denote-last-path)
                 #'denote-org-capture
                 :no-save t
                 :immediate-finish nil
                 :kill-buffer t
                 :jump-to-captured t)))

(defun sia-denote-capture-note ()
  "Create a new note with denote."
  (interactive)
  (org-capture nil "n"))

;; Example note creation function
(defun lem-insert-header-and-time-property ()
  "Insert an org heading with a created time string property."
  (interactive)
  (insert "* ")
  (org-set-property "CREATED" (format-time-string "[%Y-%m-%d %T]")))

(defun lem-denote-workbook-create-entry ()
  "Create an entry tagged \\='workbook\\=' with the date as its title.
Superseded by `lem-denote-log-entry' in the user layer, which writes into
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
  (lem-insert-header-and-time-property))

;;;; Consult Notes
;; Adapted from https://github.com/minad/consult/wiki/hrm-notes
(use-package consult-notes
  :if (and sp-load-extras (locate-library "consult-notes"))
  :commands (consult-notes
             consult-notes-search-in-all-notes)
  :config
  ;; Without a source, consult-notes shows an empty picker. The denote
  ;; source lists everything under `denote-directory' (~/Documents/notes).
  (consult-notes-denote-mode 1))

(defun lem-notebook ()
  "Open `consult-notes in buffer window rather than minibuffer."
  (interactive)
  (let ((vertico-buffer-display-action
         '(display-buffer-reuse-window)))
    (consult-notes)))


;;; Provide Setup-Notes
(provide 'sp-setup-notes)
;;; sp-setup-notes.el ends here

