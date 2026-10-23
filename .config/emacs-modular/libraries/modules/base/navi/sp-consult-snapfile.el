;;; sp-consult-snapfile.el --- Fast file search with consult-snapfile -*- lexical-binding: t; -*-

;;; Commentary:

;; This navigation sub-module, loaded by `sp-navi', configures
;; `consult-snapfile', a Consult front-end that queries a local file-search
;; server over a websocket.

;;; Code:

(use-package consult-snapfile
  :load-path (sp-path sp-clones-dir "cloned-utilities/consult-snapfile/emacs")
  :after (consult websocket)
  ;; Optional: bind to your preferred key
  :bind ("C-c s f" . consult-snapfile))

;; Server settings
(setq consult-snapfile-server-port 9876)
(setq consult-snapfile-server-host "127.0.0.1")

;; Max results to return
(setq consult-snapfile-max-results 100)

(provide 'sp-consult-snapfile)
;; sp-consult-snapfile.el ends here.
