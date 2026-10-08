;; -*- lexical-binding: t; -*-
;; sp-minibuffer.el --- Minibuffer settings

;;; Commentary:

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

;;; Provide:

(provide 'sp-minibuffer)
;; sp-minibuffer.el ends here.
