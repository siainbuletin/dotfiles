;; -*- lexical-binding: t; -*-

(defcustom siapip/nix-mode-enable nil
  "Enable nix-mode with LSP support for editing Nix files."
  :type 'boolean
  :group 'spcustom
  :safe #'booleanp)

(when siapip/nix-mode-enable
  (use-package nix-mode
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
