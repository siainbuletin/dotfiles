;; -*- lexical-binding: t; -*-
;; sp-bookmarks.el --- Bookmark management

;;; Commentary:

;;; Code:

(use-package bookmark
  :ensure nil
  :custom
  (bookmark-save-flag 1)
  :bind
  ("C-x r D" . bookmark-delete))

(provide 'sp-bookmarks)
;; sp-bookmarks.el ends here.
