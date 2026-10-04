;;; -*- lexical-binding: t -*-

;; NOTE: some org-extensions are set in other setup files:
;; - org citations setup is in setup-citation
;; - some org export functions are in setup-teaching

;;; Org Autolist (Smart Lists)
;; Better list behavior
(use-package org-autolist
  :if (and sp-load-extras (locate-library "org-autolist"))
  :hook (org-mode . org-autolist-mode))

;;; Org-Download
;; Drag and drop images to Emacs org-mode. Courtesy of abo-abo.
;; https://github.com/abo-abo/org-download.

(use-package org-download
  :if (and sp-load-extras (locate-library "org-download"))
  :commands (org-download-yank org-download-screenshot org-download-image)
  :custom
  (org-download-method 'directory)
  (org-download-image-dir (concat org-directory "org-pictures/"))
  (org-download-image-latex-width 500)
  (org-download-timestamp "%Y-%m-%d"))

(provide 'sia-set-org-extensions)