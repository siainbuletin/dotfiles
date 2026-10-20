;;; sp-consult-snapfile.el --- summary -*- lexical-binding: t; -*-

;;; Commentary:

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

;;; Provide:
(provide 'sp-consult-snapfile)
;; sp-consult-snapfile.el ends here.
