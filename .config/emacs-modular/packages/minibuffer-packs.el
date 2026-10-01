;; -*- lexical-binding: t; -*-

(use-package counsel-fd
  :ensure t
  :after counsel)

(use-package vertico
  :ensure (:wait t)
  :demand t
  :custom
  (vertico-count 13) ; Number of candidates to display
  (vertico-resize t)
  (vertico-cycle t) ; Once passing the last candidate in the list, it will loop back to the first
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

(use-package prescient
    :ensure (:wait t)
)

(use-package company-prescient
  :ensure (:wait t)
)

(use-package ivy-prescient
  :ensure (:wait t)
)

(use-package selectrum-prescient
  :ensure (:wait t)
)

(use-package vertico-prescient
  :ensure (:wait t)
)

(use-package corfu
  :ensure (:wait t))

(use-package corfu-prescient
  :ensure (:wait t))