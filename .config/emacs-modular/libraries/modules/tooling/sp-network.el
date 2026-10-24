;;; sp-network.el --- Network: TRAMP yadm method and HTTP library -*- lexical-binding: t; -*-

;;; Commentary:

;; A short tooling module for network and remote-file access. It adds a TRAMP
;; method that opens files inside the `yadm' dotfiles repository environment,
;; and installs the `plz' HTTP client library for other packages to use.

;;; Code:

(use-package tramp
  :config
  (add-to-list 'tramp-methods
               '("yadm"
                 (tramp-login-program "yadm")
                 (tramp-login-args (("enter")))
                 (tramp-login-env (("SHELL") ("/bin/sh")))
                 (tramp-remote-shell "/bin/sh")
                 (tramp-remote-shell-args ("-c")))))

;; HTTP library
(use-package plz
  :ensure (:wait t))

(provide 'sp-network)
;; sp-network.el ends here
