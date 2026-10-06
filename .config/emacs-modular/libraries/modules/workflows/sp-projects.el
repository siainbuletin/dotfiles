;; -*- lexical-binding: t; -*-

(use-package projectile
  :ensure t
  :init
  (setq projectile-project-search-path
        '("~/Documents/writing/"
          "~/.config/"))
  
  :config
  (projectile-mode +1)
  
  :bind (("C-c p" . projectile-command-map)
         :map projectile-mode-map
         ("C-c C-p" . projectile-command-map)
         ("<f5>" . projectile-compile-project)
         ("S-<f5>" . projectile-test-project)
         ("<f6>" . projectile-run-project))

  :custom
  (projectile-project-search-path '("~/git" "~/src"))
  (projectile-enable-caching t)
  )

(use-package ag
  :ensure (:wait t))

  