;; -*- lexical-binding: t; -*-

(use-package markdown-mode
  :ensure t
  :commands (markdown-mode gfm-mode)
  
  :mode (("\\.markdown\\'" . markdown-mode)
         ("\\.md\\'"       . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  
  :bind (:map markdown-mode-map
         ("s-*" . markdown-insert-list-item)
         ("s-b" . markdown-insert-bold)
         ("s-i" . markdown-insert-italic))
  
  :config
  (setq markdown-enable-math nil
        markdown-enable-wiki-links t
        markdown-nested-imenu-heading-index t
        markdown-open-command "~/bin/mark.sh"
        markdown-footnote-location 'immediately

        markdown-unordered-list-item-prefix "-   "
        markdown-header-scaling t
        markdown-use-pandoc-style-yaml-metadata t)
  
  (setq markdown-live-preview-window-function 'sp--markdown-live-preview-window-xwidget)

  (defun sp--markdown-live-preview-window-xwidget (file)
    "Preview file with xwidget browser"
    (xwidget-webkit-browse-url (concat "file://" file))
    (let ((buf (xwidget-buffer (xwidget-webkit-current-session))))
      (when (buffer-live-p buf)
        (and (eq buf (current-buffer)) (quit-window))
        (pop-to-buffer buf))))

  (defun sp--markdown-settings ()
    "settings for markdown mode"
    (progn
      (flyspell-mode 1)
      ;; (auto-fill-mode)
      (hl-todo-mode))
   )

  ;; markdown hooks
  (add-hook 'markdown-mode-hook 'sp--markdown-settings)

  ;; for use with meow point movement
  (modify-syntax-entry ?@ "_" markdown-mode-syntax-table))

;;;; Markdown TOC
(use-package markdown-toc
  :ensure t
  :after markdown-mode
  :hook 
  (markdown-mode . markdown-toc-mode))

;; macro: delete backslashes in paragraph to cleanup markdown conversion
(fset 'lem-md-delete-backslash
      (lambda (&optional arg) "Keyboard macro." (interactive "p") (funcall (kmacro "\361\361f\\x" 0 "%d") arg)))