;;; sp-treemacs.el --- A file tree for the emacs-modular folder -*- lexical-binding: t; -*-

;;; Commentary:

;; A file tree in a side window, used to keep the emacs-modular folder in view
;; while editing the literate docs in docs/tangles.
;;
;; Treemacs is opened on demand with <f9>, never at startup. The tree shows a
;; single project, `sp-treemacs-root', instead of the project of the current
;; buffer: the yadm repository's root is $HOME, so following the current
;; project would show the whole home folder.

;;; Code:

;; Moved to `sp-globals': `sp-treemacs-root', the folder shown in the treemacs
;; side window by `sp-treemacs-toggle'.

(use-package treemacs
  :ensure t
  :bind ("<f9>" . sp-treemacs-toggle)
  :custom
  ;; Keep the saved workspace out of the config folder.
  (treemacs-persist-file (expand-file-name "treemacs-persist" sp-cache-dir))
  (treemacs-width 35)
  :config
  ;; Move the tree's cursor to the file being edited.
  (treemacs-follow-mode t)

  ;; Defined here, after treemacs has loaded, because `treemacs-is-path' is
  ;; a macro. Until then <f9> is an autoload that loads treemacs.
  (defun sp-treemacs-toggle ()
    "Show or hide treemacs with `sp-treemacs-root' in its workspace.
The root is added to the workspace the first time it is shown."
    (interactive)
    (if (eq (treemacs-current-visibility) 'visible)
        (delete-window (treemacs-get-local-window))
      (let ((root (directory-file-name (expand-file-name sp-treemacs-root))))
        (unless (treemacs-is-path root :in-workspace)
          (treemacs-do-add-project-to-workspace
           root (file-name-nondirectory root))))
      (treemacs-select-window))))

;;;; Add nerd-icons for treemacs
(use-package treemacs-nerd-icons
  :ensure t
  :config
  (treemacs-nerd-icons-config))

(provide 'sp-treemacs)
;; sp-treemacs.el ends here.
