;; -*- lexical-binding: t; -*-
;; sp-snippets.el

;;; Code:

(use-package yasnippet
  :ensure (:wait t)
  :demand t

  :config
  (yas-reload-all)
  (progn
    (add-to-list 'yas-snippet-dirs (expand-file-name "snippets" user-emacs-directory))
    (add-to-list 'yas-snippet-dirs (expand-file-name "snippets" sp-load-path))
    (yas-global-mode 1))
  :bind (("C-M-S-y" . 'yas-describe-tables))

  :hook
  (sh-mode . yas-minor-mode))

;; install useful snippets
(use-package yasnippet-snippets
  :after yasnippet
  :ensure (:wait t))

;;; Provide:

(provide 'sp-snippets)
;; sp-snippets.el ends here.