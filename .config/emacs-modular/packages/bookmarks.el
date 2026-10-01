;; -*- lexical-binding: t; -*-

;;; Bookmarks
  (use-package bookmark
    :ensure nil
    :custom
    (bookmark-save-flag 1)
    :bind
    ("C-x r D" . bookmark-delete))
    