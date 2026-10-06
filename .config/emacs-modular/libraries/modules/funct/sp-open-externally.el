;; -*- lexical-binding: t; -*-
;; sp-open-externally.el

;; De văzut cum fac asta să funcționeze bine

;; Taken from Emacs Writing Studio.
(use-package openwith
  :config
  (openwith-mode t)
  :custom
  (openwith-associations nil))

;; There should be a way to include working with PDFs as well.
;; And especially DEVONthink in a satisfying manner.

(provide 'sp-open-externally)
;; sp-open-externally.el ends here.