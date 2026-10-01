;; -*- lexical-binding: t; -*-

(use-package nov
  :ensure t
  :config
  (setq nov-variable-pitch nil
        nov-text-width 70)
  :init
  (add-to-list 'auto-mode-alist '("\\.epub\\'" . nov-mode)))

(use-package calibredb
  :defer t
  :config
  (setq calibredb-root-dir "~/Documents/calibre-library")
  (setq calibredb-db-dir "~/Documents/calibre-library/metadata.db")
  )

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