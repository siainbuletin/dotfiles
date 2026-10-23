;;; sp-nix.el --- Nix editing with the nixd language server -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets up editing of Nix files with `nix-mode' and the `nixd'
;; language server through `lsp-mode'. It is off by default behind a custom
;; option, `siapip/nix-mode-enable'.

;;; Code:

(defcustom siapip/nix-mode-enable nil
  "Enable nix-mode with LSP support for editing Nix files."
  :type 'boolean
  :group 'siapip
  :safe #'booleanp)

(when siapip/nix-mode-enable
  (use-package nix-mode
    :ensure t
    :mode "\\.nix\\'"
    :hook (nix-mode . lsp-deferred)
    :bind (:map nix-mode-map
                ([tab] . company-indent-or-complete-common)
                ([f1] . lsp-describe-thing-at-point)
                ([f12] . lsp-find-definition))
    :config
    (with-eval-after-load 'lsp-mode
      (add-to-list 'lsp-language-id-configuration '(nix-mode . "nix"))
      (lsp-register-client
       (make-lsp-client :new-connection (lsp-stdio-connection "nixd")
                        :major-modes '(nix-mode)
                        :server-id 'nixd)))))
