;; -*- lexical-binding: t; -*-

(use-package elfeed
  :custom
  (elfeed-db-directory
   (expand-file-name "elfeed" user-emacs-directory))
  (elfeed-show-entry-switch 'display-buffer)
  :bind
  ("C-c w e" . elfeed))

(use-package elfeed-org
  :ensure t
  :config
  (elfeed-org)
  :custom
  (setq sia-elfeed-org-files (list "~/Documents/elfeed.org")))