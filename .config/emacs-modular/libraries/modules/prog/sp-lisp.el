;; -*- lexical-binding: t; -*-
;; sp-lisp.el --- Lisp and Emacs Lisp settings

;;; Commentary:

;;

;;; Code

(defcustom siapip/lisp-paredit:enabled nil
  "When enabled, this option automatically activates paredit mode in Lisp modes."
  :group 'spconfig
  :type 'boolean)

;; This will make the matching parentheses show up faster.
;; source: https://www.jamescherti.com/emacs-user-interface-better-responsiveness-and-latency/
(setq show-paren-delay 0.05)

;;;; Interpreter
(use-package sly
  :ensure t
  :defer t
  :init
  (setq inferior-lisp-program "sbcl")
  :config
  (setq sly-complete-symbol-function 'sly-flex-completions)
  :hook ((lisp-mode . (lambda ()
                        (sly-mode t)))
         (sly-repl-mode . (lambda ()
                            (company-mode t)))))

;;;; Editing modes
(use-package lisp-mode
  :ensure nil
  :demand t
  :bind
  (:map lisp-mode-map
        ;;([tab] . sly-complete-symbol)
        ([tab] . company-indent-or-complete-common)
        ("C-c C-d h" . sly-documentation-lookup)
        ("C-c C-z" . sly))
  :hook
  ((lisp-mode . (lambda ()
                 (setq company-backends '(company-capf
                                          company-files))
                 ;; (highlight-indent-guides-mode t)
                 (company-mode t)))))

(use-package elisp-mode
  :ensure nil
  :demand t
  :bind (:map emacs-lisp-mode-map ([tab] . 'company-indent-or-complete-common))
  :hook
  (emacs-lisp-mode . (lambda ()
                       (company-mode t)
                       (eldoc-mode t)
                       (prettify-symbols-mode t)
                       ;; (setq lisp-indent-function nil)
                       ;; (highlight-indent-guides-mode t)
                       (setq company-backends '(company-capf
                                                company-files
                                                company-dabbrev-code)))))

;;;; Show code examples
;; Show code examples with the elisp-demos package.
;; Find a function without a good demonstration? Call elisp-demos-add-demo.

(use-package elisp-demos
  :ensure t
  :after helpful ; this can enhance the `describe-function` call
  :config
  (advice-add 'describe-function-1 :after #'elisp-demos-advice-describe-function-1))

;;;; Finding better functions
;; Wilfred’s suggest function helps you find the right function. 
;; Basically, you type in the parameters of a function, and then 
;; the desired output, and it will write the function call.
(use-package suggest
  :ensure t)

;;;; Better appearance
;;;;; Showing the parantheses better
;; source: https://howardabrams.com/hamacs/ha-programming-elisp.html
(use-package paren-face
  :ensure t
  :hook (emacs-lisp-mode . paren-face-mode))

(use-package paredit
    :ensure t
    :defer t
    ;;:diminish paredit-mode
    :hook ((emacs-lisp-mode . paredit-mode)
           (lisp-mode . paredit-mode)
           (lisp-interaction-mode . paredit-mode)
           (sly-repl-mode . paredit-mode))
    :bind (:map paredit-mode-map
                ("C-M-f" . paredit-forward)
                ("C-M-b" . paredit-backward)))

;; Evaluating an expression at point
;; source: https://www.reddit.com/r/emacs/comments/1x4806c/comment/pge1kz7/
(defun eval-outer-sexp (point)
  "Evaluate the smallest patenthesized sexp that contains point, and echo its value."
  (interactive (list (point)))
  (let (sexp)
    (save-excursion
      (backward-up-list 1 t t)
      (while (not (looking-at "("))
        (backward-up-list 1 t t))
      (setq sexp (read (point-marker))))
    (message "%s" (eval sexp))))

;;; Provide:

(provide 'sp-lisp)
;; sp-lisp.el ends here.