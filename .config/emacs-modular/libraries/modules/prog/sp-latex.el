;;; sp-latex.el --- LaTeX editing with AUCTeX and Org LaTeX export -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets up LaTeX editing with AUCTeX, RefTeX, preview and latexmk,
;; configures Org's LaTeX exporter to compile with XeLaTeX through latexmk, and
;; adds a few spelling, indentation and BibTeX tweaks. It is listed in the
;; `plus-programming' profile in `sp-config-profiles.el'.

;;; Code:

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

(use-package auctex
  :ensure t
  :mode (("\\.tex\\'" . latex-mode)
         ("\\.latex\\'" . latex-mode))
  :commands (latex-mode LaTeX-mode plain-tex-mode)
  :init
  (progn
    (add-hook 'LaTeX-mode-hook #'LaTeX-preview-setup)
    (add-hook 'LaTeX-mode-hook #'flyspell-mode)
    (add-hook 'LaTeX-mode-hook #'turn-on-reftex)
    (setq-default TeX-engine 'xetex)
    (setq TeX-auto-save nil
          TeX-parse-self nil
          TeX-save-query nil
          TeX-PDF-mode t)
    (setq-default TeX-master nil)))

(use-package latex
  :ensure nil
  :defer t
  :hook (TeX-mode . sia/latex-setup)
  :bind (:map TeX-mode-map
              ([f5] . sia/latexmk-run)
              ([tab] . company-indent-or-complete-common)
              ([f1] . company-show-doc-buffer))
  :config
  (load (expand-file-name "latex-compile-on-save.el" sp-emacs-dir)))



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

;;;; Latex Packages
;; Basic settings


(use-package preview
  :ensure nil
  :after auctex
  :commands LaTeX-preview-setup
  :init
  (progn
    (setq-default preview-scale 1.4
                  preview-scale-function '(lambda () (* (/ 10.0 (preview-document-pt)) preview-scale)))))

(use-package reftex
  :ensure nil
  :commands turn-on-reftex
  :init
  (setq reftex-plug-into-AUCTeX t))

(use-package bibtex
  :ensure nil
  :defer t
  :mode ("\\.bib" . bibtex-mode)
  :init
  (progn
    (setq bibtex-align-at-equal-sign t)
    (add-hook 'bibtex-mode-hook (lambda () (set-fill-column 120)))))


;; Auto-fill for LaTeX
(defun lem-latex-auto-fill ()
  "Turn on auto-fill for LaTeX mode."
  (turn-on-auto-fill)
  (set-fill-column 80)
  (setq default-justification 'left))
(add-hook 'LaTeX-mode-hook #'lem-latex-auto-fill)

;; Compilation command
(add-hook 'LaTeX-mode-hook (lambda () (setq compile-command "latexmk -pdflatex=xelatex -f -pdf %f")))

;; Prevent ispell from verifying some LaTeX commands
;; http://stat.genopole.cnrs.fr/dw/~jchiquet/fr/latex/emacslatex
(defvar lem-ispell-tex-skip-alists
  '("cite" "nocite"
    "includegraphics"
    "author" "affil"
    "ref" "eqref" "pageref"
    "label"))
(setq ispell-tex-skip-alists
      (list
       (append (car ispell-tex-skip-alists)
               (mapcar #'(lambda (cmd) (list (concat "\\\\" cmd) 'ispell-tex-arg-end)) lem-ispell-tex-skip-alists))
       (cadr ispell-tex-skip-alists)))

;; Indentation with align-current in LaTeX environments
(defvar lem-LaTeX-align-environments '("tabular" "tabular*"))
(add-hook 'LaTeX-mode-hook
          (lambda ()
            (require 'align)
            (setq LaTeX-indent-environment-list
                  ;; For each item in the list...
                  (mapcar (lambda (item)
                            ;; The car is an environment
                            (let ((env (car item)))
                              ;; If this environment is in our list...
                              (if (member env lem-LaTeX-align-environments)
                                  ;; ...then replace this item with a correct one
                                  (list env 'align-current)
                                ;; else leave it alone
                                item)))
                          LaTeX-indent-environment-list))))

;; Use dvipdfmx to convert DVI files to PDF in AUCTeX
(eval-after-load 'tex
  '(add-to-list 'TeX-command-list
                '("DVI to PDF" "dvipdfmx %d" TeX-run-command t t) t))

;; SyncTeX (http://www.emacswiki.org/emacs/AUCTeX#toc19)
(defun synctex/un-urlify (fname-or-url)
  "A trivial function that replaces a prefix of file:/// with just /."
  (if (string= (substring fname-or-url 0 8) "file:///")
      (substring fname-or-url 7)
    fname-or-url))

(provide 'sp-latex)
