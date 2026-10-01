;; -*- lexical-binding: t; -*-

(defun sia/latex-setup ()
  "Setup the latex environment"
  (reftex-mode t)
  (auctex-latexmk-setup)
  (TeX-engine-set "luatex")
  (setq font-latex-fontify-script 'multi-level)
  (setq TeX-PDF-mode t)
  (setq TeX-source-correlate-mode t)
  (TeX-fold-mode 1)
  (rainbow-delimiters-mode t)
  (make-local-variable 'company-backends)
  (setq company-backends '(company-auctex
                           company-files))
  (company-auctex-init)
  (company-mode t))
(defun sia/latexmk-run ()
  "Run latexmk on the master file"
  (interactive)
  (let ((TeX-save-query nil)
        (TeX-process-asynchronous nil)
        (master-file (TeX-master-file)))
    (TeX-save-document "")
    (TeX-run-TeX "latexmk" "latexmk" master-file)
    (if (plist-get TeX-error-report-switches (intern master-file))
        (TeX-next-error)
      (minibuffer-message "latexmk-done"))))
(use-package auctex-latexmk
  :defer t)
(use-package company-auctex
  :defer t)

(use-package latex
  :ensure nil
  :defer t
  :hook (TeX-mode . sia/latex-setup)
  :bind (:map TeX-mode-map
              ([f5] . sia/latexmk-run)
              ([tab] . company-indent-or-complete-common)
              ([f1] . company-show-doc-buffer))
  :config
  (load "latex-compile-on-save.el"))



(setq org-latex-compiler "xelatex")
(setq org-latex-pdf-process
      (list (concat "latexmk -"
                    org-latex-compiler
                    " -recorder -synctex=1 -bibtex-cond %b")))

(setq org-latex-listings t)

(setq org-latex-default-packages-alist
      '(("" "graphicx" t)
        ("" "grffile" t)
        ("" "longtable" nil)
        ("" "wrapfig" nil)
        ("" "rotating" nil)
        ("normalem" "ulem" t)
        ("" "amsmath" t)
        ("" "textcomp" t)
        ("" "amssymb" t)
        ("" "capt-of" nil)
        ("" "hyperref" nil)))

(require 'ox-latex)
(unless (boundp 'org-latex-classes)
  (setq org-latex-classes nil))

(with-eval-after-load 'ox-latex
(add-to-list 'org-latex-classes
             '("org-plain-latex"
               "\\documentclass{article}
           [NO-DEFAULT-PACKAGES]
           [PACKAGES]
           [EXTRA]"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
               ("\\paragraph{%s}" . "\\paragraph*{%s}")
               ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))

(setq org-latex-listings 't)

;; (use-package org-present
;;   :ensure (:wait t)
;;   :after org-inline-anim
;;   :hook
;;   ((org-present-mode . (lambda ()
;;                          (org-present-big)
;;                          (org-display-inline-images)
;;                          (org-present-read-only)
;;                          (centaur-tabs-local-mode)
;;                          (org-inline-anim-mode)
;;                          (org-inline-anim-animate-all)))
;;    (org-present-mode-quit . (lambda ()
;;                               ;; TODO: actually turn on centaur tabs again.
;;                               ;;       Nothing works that I've tried so far
;;                               (org-present-small)
;;                               (org-present-read-write)
;;                               (org-present-show-cursor)))))


(use-package org-pandoc-import
  :ensure (:host github
               :repo "tecosaur/org-pandoc-import"
               :files ("*.el" "filters" "preprocessors")))