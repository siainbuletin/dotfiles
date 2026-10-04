;; -*- lexical-binding: t; -*-

(use-package yasnippet
  :ensure (:wait t)
  :demand t

  :config
  (yas-reload-all)

  :hook
  (sh-mode . yas-minor-mode))

;; install useful snippets
(use-package yasnippet-snippets
  :after yasnippet
  :ensure (:wait t))