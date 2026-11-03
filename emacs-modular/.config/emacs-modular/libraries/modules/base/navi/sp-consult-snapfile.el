;;; sp-consult-snapfile.el --- Fast file search with consult-snapfile -*- lexical-binding: t; -*-

;;; Commentary:

;; This navigation sub-module, loaded by `sp-navi', configures
;; `consult-snapfile', a Consult front-end that queries a local file-search
;; server over a websocket.

;;; Code:

;; `:load-path' reads a list as a list of paths and evaluates each symbol in it as a
;; variable, so a call to `sp-path' has to go through a variable.
(defconst sp-consult-snapfile-dir
  (sp-path sp-clones-dir "cloned-utilities/consult-snapfile/emacs")
  "Local checkout of the consult-snapfile client.")

(use-package consult-snapfile
  :ensure nil
  :load-path sp-consult-snapfile-dir
  :after (consult websocket)
  ;; Optional: bind to your preferred key
  :bind ("C-c s f" . consult-snapfile)

  :custom
  ;; Server settings
  (consult-snapfile-server-port 9876)
  (consult-snapfile-server-host "127.0.0.1")
  ;; Max results to return
  (consult-snapfile-max-results 100))

(provide 'sp-consult-snapfile)
;; sp-consult-snapfile.el ends here.
