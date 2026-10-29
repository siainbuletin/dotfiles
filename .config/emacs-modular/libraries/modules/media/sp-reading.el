;;; sp-reading.el --- Reading e-books -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets up e-book reading: `nov' for reading EPUB files inside
;; Emacs and `calibredb' for browsing a Calibre library. A third reader is left
;; commented out.

;;; Code:

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
  :ensure t
  :defer t
  :config
  (setq calibredb-root-dir (sp-path sp-documents-dir "calibre-library"))
  (setq calibredb-db-dir (sp-path sp-documents-dir "calibre-library/metadata.db"))
  )

(provide 'sp-reading)
