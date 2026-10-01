;; -*- lexical-binding: t; -*-

(use-package projectile
  :ensure t
  :init
  (setq projectile-project-search-path
        '("~/writing/"
          "~/.config/"
          "~/playground"))
  :config
  ;; These are the configurations to use on Linux for projectile
  (define-key projectile-mode-map (kbd "C-c C-p") 'projectile-command-map)
  (global-set-key (kbd "C-c p") 'projectile-command-map)
  (projectile-mode +1))

(use-package ag
  :ensure (:wait t))