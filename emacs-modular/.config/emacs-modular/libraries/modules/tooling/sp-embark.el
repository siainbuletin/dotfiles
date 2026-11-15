;;; sp-embark.el --- Embark contextual actions -*- lexical-binding: t; -*-

;;; Commentary:

;; sp-embark ---

;;; Code:

(use-package embark
  :ensure t
  :bind
  (("C-." . embark-act)
   ("M-." . embark-dwim)
   ("C-h B" . embark-bindings))

  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(defvar sp-prefix)

;; Leader submenu: every Embark entry point under `sp-prefix' E.
;; The commands are autoloaded, so the keys work before Embark is loaded.
(bind-keys :prefix-map lem+embark-keys
           :prefix (concat sp-prefix " E")
           ("a" . embark-act)
           ("A" . embark-act-all)
           ("s" . embark-select)
           ("c" . embark-collect)
           ("l" . embark-live)
           ("e" . embark-export)
           ("b" . embark-become)
           ("d" . embark-dwim)
           ("B" . embark-bindings))

;; Quick toggle for marking candidates in the minibuffer.
(keymap-set minibuffer-local-map "C-," #'embark-select)

(use-package embark-consult
  :ensure t
  :after (embark consult))

(provide 'sp-embark)
;; sp-embark ends here.
