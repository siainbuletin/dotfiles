;;; sp-org-images.el --- Images in Org with org-download -*- lexical-binding: t; -*-

;;; Commentary:

;; Dealing with images in org-mode (embedding them properly)

;;; Code:

;;;; Org-Download
;; Drag and drop images to Emacs org-mode. Courtesy of abo-abo.
;; https://github.com/abo-abo/org-download.

(use-package org-download
  :ensure t
  :commands (org-download-yank org-download-screenshot org-download-image)
  :custom
  (org-download-method 'directory)
  (org-download-image-dir (concat org-directory "org-pictures/"))
  (org-download-image-latex-width 500)
  (org-download-timestamp "%Y-%m-%d"))

(provide 'sp-org-images)
;; sp-org-images.el ends here.
