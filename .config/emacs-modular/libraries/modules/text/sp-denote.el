;;; sp-denote.el --- Denote note-taking setup -*- lexical-binding: t; -*-

;;; Commentary:

;; Settings for Prot's denote package.
;;
;; This will at some point be phased out, as I prefer an ID-based
;; workflow for my notes, and I never seem to use the filenames
;; for anything. Plus, the filenames are much too long, they become
;; a lot harder to parse.

;;; Code:

(use-package denote
  :ensure t
  ;; :if (locate-library "denote")
  :commands (denote denote-create-note denote-link-ol-store)
  
  :config
  (denote-rename-buffer-mode)

  :custom
  ;; Use org-read-date
  (denote-date-prompt-use-org-read-date t)
  (denote-file-type 'org) ;; use org
  (denote-allow-multi-word-keywords t)
  (denote-rename-confirmations '(modify-file-name add-front-matter))
  (denote-sort-keywords t)

  ;; Set default prompts for note creation
  (denote-prompts '(title keywords))
  
  :hook
  (dired-mode . denote-dired-mode)

  :bind
  (:map global-map
      ("M-n c" . denote-open-or-create)
      ("M-n r" . denote-rename-file)
      ("M-n f" . denote-rename-file-using-front-matter)

      :map text-mode-map
      ("M-n I" . denote-add-links)

      :map dired-mode-map
      ("C-c C-d C-i" . denote-link-dired-marked-notes)
      ("C-c C-d C-r" . denote-dired-rename-marked-files)

      ;; these are copied directly from the Emacs Writing Studio configuration
      ("C-c w d b" . denote-find-backlink)
      ("C-c w d d" . denote-date)
      ("C-c w d l" . denote-find-link)
      ("C-c w d i" . denote-link-or-create)
      ("C-c w d k" . denote-rename-file-keywords)))

(setq denote-directory sp-notes-dir)

(setq denote-save-buffers t)

(global-set-key (kbd "C-c z") #'list-denotes)

(defvar my-denote-to-agenda-regexp "_project"
  "Denote file names that are added to the agenda.
See `my-add-denote-to-agenda'.")

(defun my-denote-add-to-agenda ()
  "Add current file to the `org-agenda-files', if needed.
The file's name must match the `my-denote-to-agenda-regexp'.

Add this to the `after-save-hook' or call it interactively."
  (interactive)
  (when-let* ((file (buffer-file-name))
              ((denote-file-is-note-p file))
              ((string-match-p my-denote-to-agenda-regexp (buffer-file-name))))
    (add-to-list 'org-agenda-files file)))

;; This will add the file automatically
(add-hook 'after-save-hook #'my-denote-add-to-agenda)

(defun my-denote-remove-from-agenda ()
  "Remove current file from the `org-agenda-files'.
See `my-denote-add-to-agenda' for how to add files to the Org
agenda."
  (interactive)
  (when-let* ((file (buffer-file-name))
              ((string-match-p my-denote-to-agenda-regexp (buffer-file-name))))
    (setq org-agenda-files (delete file org-agenda-files))))

(provide 'sp-denote)
;; sp-denote.el ends here.
