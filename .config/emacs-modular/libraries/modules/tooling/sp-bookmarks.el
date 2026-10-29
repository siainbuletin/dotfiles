;;; sp-bookmarks.el --- Bookmark management -*- lexical-binding: t; -*-

;;; Commentary:

;; A tiny module that configures Emacs' built-in `bookmark' library. It has no
;; external dependencies and is loaded from `init.el' as part of the general
;; tooling modules.

;;; Code:

(use-package bookmark
  :ensure nil
  :custom
  (bookmark-default-file (expand-file-name "bookmarks" sp-user-dir))
  (bookmark-save-flag 1)
  :bind
  ("C-x r D" . bookmark-delete))

(provide 'sp-bookmarks)
;; sp-bookmarks.el ends here.
