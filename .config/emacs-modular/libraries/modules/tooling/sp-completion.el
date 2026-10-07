;; -*- lexical-binding: t; -*-
;; sp-completion.el

;;; Commentary:

;;; Code:

(use-package vertico
  :ensure t
  :demand t

  :custom
  (vertico-count 13) ; Number of candidates to display
  (vertico-resize t)
  (vertico-cycle t) ; Once passing the last candidate in the list, it will loop back to the first
  (vertico-sort-function
           'vertico-sort-history-alpha)

  :config
  (vertico-mode))

(use-package marginalia
  :ensure (:wait t)
  :init
  (marginalia-mode)
  (setf
    (alist-get 'elpaca-info marginalia-command-categories) 'elpaca))

(use-package orderless
  :ensure (:wait t)
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides
   '((file (styles partial-completion)))))

(use-package company
  :ensure (:wait t))

;;; Provide:

(provide 'sp-completion)
;; sp-completion.el ends here.