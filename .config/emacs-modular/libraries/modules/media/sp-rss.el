;;; sp-rss.el --- RSS reading with Elfeed -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets up the `elfeed' feed reader, `elfeed-org' for keeping the
;; feed list in an Org file, and a command for capturing feed entries into Org
;; through `org-protocol'. It is not in any module list in `init.el', and the
;; notes in `conditional-loading.org' describe it as unconfigured, so it is a
;; work in progress that does not currently load.

;;; Code:

(use-package elfeed
  :ensure t
  :custom
  (elfeed-db-directory
   (expand-file-name "elfeed" user-emacs-directory))
  (elfeed-show-entry-switch 'display-buffer)
  :bind
  ("C-c w e" . elfeed))

(use-package elfeed-org
  :ensure t
  :config
  (elfeed-org)
  :custom
  (rmh-elfeed-org-files (list (sp-path sp-documents-dir "elfeed.org"))))

(defun yant/elfeed-capture-entry ()
  "Capture selected entries into inbox."
  (interactive)
  (elfeed-search-tag-all 'opened)
  (previous-logical-line)
  (let ((entries (elfeed-search-selected)))
    (cl-loop for entry in entries
             do (elfeed-untag entry 'unread)
             when (elfeed-entry-link entry)
             do (cl-letf (((symbol-function 'raise-frame) #'ignore))
                  (org-protocol-capture (list :template "B"
                                              :url it
                                              :title (format "%s: %s"
                                                             (elfeed-feed-title (elfeed-entry-feed entry))
                                                             (elfeed-entry-title entry))
                                              :elfeed-data entry))))
    (mapc #'elfeed-search-update-entry entries)
    (unless (use-region-p) (forward-line))))

;; How can this be made to integrate with general bibliography management?
;; It would probably have to be studied in the way that it works for Emacs Writing Studio.

(provide 'sp-rss)
