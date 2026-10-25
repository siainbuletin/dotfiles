;;; sp-vcontrol.el --- Version control with Magit -*- lexical-binding: t; -*-

;;; Commentary:

;; A short module that installs Magit, adds a helper for using it with YADM,
;; the dotfile manager, and sets up Forge so Magit can work with GitHub pull
;; requests and issues, and installs `code-review' for reviewing pull requests
;; in Emacs. It depends on the `magit', `transient', `forge' and `code-review'
;; packages.

;;; Code:

;;;; Magit initial installation
(use-package magit
  :ensure t
  :defer t
  :after transient
  :bind
  (("C-M-g" . magit))
  :custom
  (magit-bury-buffer-function 'magit-restore-window-configuration))

;;;; YADM function to be able to work with dotfiles
(defun yadm ()
  (interactive)
  (magit-status "~/"))

;;;; Forge settings
(use-package forge
  :ensure t
  :after magit)

;; code review harness
(use-package code-review
  :ensure t
  ;; code-review defines its database class on `emacsql-sqlite-connection',
  ;; which forge pulls in. Loading code-review before that gives "Given parent
  ;; class emacsql-sqlite-connection is not a class".
  :after forge
  :init
  (require 'emacsql-sqlite)

  :custom
  (code-review-fill-column 80) ;; Define line wrap in comment sections.
  (code-review-new-buffer-window-strategy #'switch-to-buffer) ;; Change how code-review splits the buffer when opening a new PR. Defaults to #'switch-to-buffer-other-window.
  (code-review-download-dir "/tmp/code-review/") ;; Change the destination where binary files is downloaded.
)

;;;; For adding emojis
(add-hook 'code-review-mode-hook #'emojify-mode)

(provide 'sp-vcontrol)
;; sp-vcontrol.el ends here