;; -*- lexical-binding: t; -*-

(defun sp-minibuffer ()
  "make minibuffer use larger font size."
  (text-scale-increase 2)) ; Unfortunately the 3 size is a little bit too extreme. it would be nice if I could do it all in increments

(add-hook 'minibuffer-mode-hook 'sp-minibuffer)

(defun sp-text-buffer ()
  "Make the font in the text buffer generally larger."
  (text-scale-increase 4))

(add-hook 'text-mode-hook 'sp-text-buffer)

; (defcustom siapip/minibuffer-completion-framework 'vertico
;  "The completion framework to use in minibuffer."
;  :type '(choice (const ido :tag "Ido (Classic)")
;                 (const vertico :tag "Vertico + Consult"))
;  :group 'siapip)
;(pcase siapip/minibuffer-completion-framework
;  ('ido
;   (require 'ido)
;   (ido-mode t)
;   (setq ido-everywhere t)
;   (setq ido-enable-flex-matching t)
;   (use-package ido-completing-read+
;     :ensure t
;     :demand t
;     :config
;     (ido-ubiquitous-mode 1))
;   (use-package ido-vertical-mode
;     :ensure t
;     :demand t
;    :init (ido-vertical-mode 1)))
;  ('vertico
;   (use-package vertico
;     :ensure t
;     :demand t
;    :init
;     (vertico-mode)
;     :custom
;     (vertico-count 25)
;    (vertico-resize t))
;   (use-package consult
;    :ensure t
;     :demand t
;     :bind (("C-x b" . consult-buffer)
;            ("C-x 4 b" . consult-buffer-other-window)
;            ("C-x r b" . consult-bookmark)
;            ("M-y" . consult-yank-pop)
;           ("M-g g" . consult-goto-line)
;            ("M-s r" . consult-ripgrep)))
;   (use-package orderless
;     :ensure t
;     :demand t
;     :config
;     (setq completion-styles '(orderless basic)))
;   (use-package marginalia
;     :ensure t
;     :demand t
;     :init
;     (marginalia-mode))))

;; -*- lexical-binding: t; -*-

(use-package counsel-fd
  :ensure t
  :after counsel)

;; Minibuffer completion
;; How much of this system can actually be replaced with the regular completion
;; that you now have in Emacs 31?
;; Can it also be customized to work better with vulpea?

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
  