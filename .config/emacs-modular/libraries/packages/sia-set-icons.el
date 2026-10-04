;; -*- lexical-binding: t; -*-
;; sia-set-icons.el

(use-package nerd-icons
  :ensure (:wait t)
  :custom
  ;; The Nerd Font you want to use in GUI defaults to fixed-font:
  (nerd-icons-font-family "Symbols Nerd Font Mono"))

(use-package nerd-icons-ibuffer
  :ensure t
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

(use-package all-the-icons
  :ensure t
  :if (display-graphic-p))

(provide 'sia-set-icons)

;; sia-set-icons.el ends here.