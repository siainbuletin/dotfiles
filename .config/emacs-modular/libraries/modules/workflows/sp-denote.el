;; -*- lexical-binding: t; -*-

(use-package denote
  :ensure t
  :defer t
  :demand t

  :config
  (denote-rename-buffer-mode)
  (setq denote-file-type 'org) ; default is org
  (setq denote-history-completion-in-prompts nil)
  (setq denote-rename-confirmations '(modify-file-name add-front-matter))
  (setq denote-kill-buffers nil)
  (setq denote-sort-keywords t)
  (setq denote-known-keywords
        '("academic-journal"
          "blog-post"
          "book"
          "booksection"
          "concept"
          "course"
          "current"
          "docs"
          "group"
          "institution"
          "journal-article"
          "language"
          "library"
          "music"
          "package"
          "person"
          "process"
          "studyplace"
          "thesis"
          "workflow"
          "zettel"))
  ; (denote-link-description-function #'ews-denote-link-description-title-case) ; I need to actually rename this to my own function starting with sia-

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

(setq denote-directory (expand-file-name "~/notes/"))

(add-hook 'dired-mode-hook #'denote-dired-mode-in-directories)

(setq denote-save-buffers t)

(use-package denote-org
  :ensure t
  :after denote

  :custom
  ;; `denote-org-link-to-heading' controls the behavior of
  ;; `org-store-link': setting to id makes it insert an ID in the
  ;; PROPERTIES drawer
  ;;
  ;; (denote-org-store-link-to-heading 'context)
  (denote-org-store-link-to-heading 'id))

(use-package denote-merge
      :ensure (denote-merge :type git :host github :repo "protesilaos/denote-merge")
      :bind
      ("M-n m f" . denote-merge-file)
      ("M-n m r" . denote-merge-region))

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