;; -*- lexical-binding: t; -*-
;; sp-network.el

;;; Commentary:

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