;;; sp-minibuffer.el --- Minibuffer and completion packages -*- lexical-binding: t; -*-

;;; Commentary:

;; This module gathers the packages behind minibuffer and in-buffer completion.
;; It pulls in `sp-completion' and then installs the `prescient' sorting and
;; filtering library together with its adapters for Company, Ivy, Selectrum,
;; Vertico and Corfu, plus Corfu itself and `counsel-fd'.

;;; Code:

(add-hook 'text-mode-hook 'sp-text-buffer)

(use-package counsel-fd
  :ensure t
  :after counsel)

;; Minibuffer completion
;; How much of this system can actually be replaced with the regular completion
;; that you now have in Emacs 31?
;; Can it also be customized to work better with vulpea?

(require 'sp-completion)


;; prescient ecosystem
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

(provide 'sp-minibuffer)
;; sp-minibuffer.el ends here.
