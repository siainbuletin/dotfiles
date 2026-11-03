;;; sp-rust.el --- Rust editing -*- lexical-binding: t; -*-

;;; Commentary:

;; Configures `rust-mode' with completion, Flycheck and LSP via
;; `rust-analyzer'. It depends on `flycheck-rust', `company', `lsp-mode' and
;; the external `rust-analyzer' binary.

;;; Code:

(use-package flycheck-rust
  :ensure t
  :defer t)
;(use-package racer)
(use-package rust-mode
  :ensure t
  :defer t
  :config
  (add-hook 'rust-mode-hook
            (lambda ()
              ;(racer-mode t)
              (eldoc-mode t)
              (company-mode t)
              (flycheck-mode t)
              (flycheck-rust-setup)
              (lsp)))
  (define-key rust-mode-map [(f5)] 'rust-compile)
  (define-key rust-mode-map [(tab)] 'company-indent-or-complete-common))
(setq lsp-rust-analyzer-server-command '("rust-analyzer"))
