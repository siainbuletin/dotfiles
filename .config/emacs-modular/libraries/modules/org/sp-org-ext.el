;;; -*- lexical-binding: t -*-

;; NOTE: some org-extensions are set in other setup files:
;; - org citations setup is in setup-citation

;;; Org Autolist (Smart Lists)
;; Better list behavior
;; this package should be researched a little bit more
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

(use-package org-journal
  :defer t
  :bind
  (("C-M-S-j" . (lambda () (interactive) (org-journal-new-entry nil nil t)))
   ("C-M-S-i" . (lambda () (interactive) (org-journal-new-entry nil))))
  :init
  (setq org-journal-dir "~/org/journal"
        org-journal-date-format "%Y-%m-%d"
        org-journal-enable-agenda-integration t
        org-journal-carryover-items "TODO={TODO\\|WAITING\\|DOING}"))

(use-package org-ranker
  :ensure (org-ranker :type git
                    :host github
                    :repo "CSJ7701/org-ranker"))

;; (add-to-list 'load-path "~/.config/emacs-include/cloned-modules/org-dataview")
;; (require 'org-dataview)

(provide 'sp-org-ext)