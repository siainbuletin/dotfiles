;; -*- lexical-binding: t; -*-
;; sp-reading.el

(use-package nov
  :ensure t
  :config
  (setq nov-variable-pitch nil
        nov-text-width 70)
  :init
  (add-to-list 'auto-mode-alist '("\\.epub\\'" . nov-mode)))

;; This one actually has to be installed from the source to work well
;; (use-package chai 
;;  :ensure t)

(use-package calibredb
  :defer t
  :config
  (setq calibredb-root-dir "~/Documents/calibre-library")
  (setq calibredb-db-dir "~/Documents/calibre-library/metadata.db")
  )

(provide 'sp-reading)