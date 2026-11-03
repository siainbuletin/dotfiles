;;; sp-network.el --- Network: HTTP library -*- lexical-binding: t; -*-

;;; Commentary:

;; A short tooling module for network access. It installs the `plz' HTTP client
;; library for other packages to use.

;;; Code:

;; HTTP library
(use-package plz
  :ensure (:wait t))

(provide 'sp-network)
;; sp-network.el ends here
