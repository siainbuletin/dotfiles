;; -*- lexical-binding: t ; -*-
;; sp-org-images.el

;; Dealing with images in org-mode (embedding them properly)
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

(provide 'sp-org-images)
;; sp-org-images.el ends here.