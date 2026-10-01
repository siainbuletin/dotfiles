;; -*- lexical-binding: t; -*-

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