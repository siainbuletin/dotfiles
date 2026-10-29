;;; sp-md.el --- Markdown editing -*- lexical-binding: t; -*-

;;; Commentary:

;;

;;; Code:

;;;; Markdown-ts-mode (native emacs 21)
;; Emacs 31 brought Markdown-ts-mode, which is closer to the keybindings
;; that you may find in org-mode, it feels more native to Emacs itself
;; in a lot of ways.

(use-package markdown-ts-mode
  :ensure nil
  :defer t)

;; One caveat I want to be upfront about: markdown-ts-mode is still experimental,
;; and you have to opt into it. As the header of markdown-ts-mode.el notes, it
;; isn't wired up to auto-mode-alist yet, so it won't take over .md files on its
;; own. For now you pull in the library with M-x load-library RET markdown-ts-mode,
;; then turn it on in a bufferf, or add it to auto-mode-alist yourself if you're feeling brave.

;;;; Legacy markdown mode
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

(provide 'sp-md)
;; sp-md.el ends here.
