;;; export.el --- Batch driver for docs/typst/Makefile -*- lexical-binding: t; -*-

;; Tangled from docs/tangles/text/sp-typst.org; edit it there.

;;; Code:

;; The package forms in sp-typst.el belong to the Elpaca session; here the
;; packages are on the load path already.
(defmacro use-package (&rest _) nil)

(require 'org)
(require 'ox-typst)

(let ((here (file-name-directory (or load-file-name buffer-file-name))))
  (load (expand-file-name "../../libraries/modules/text/sp-typst.el" here) nil t))

(setq sp-typst-root (file-name-as-directory
                     (or (getenv "SP_TYPST_ROOT")
                         (expand-file-name "../.." (file-name-directory
                                                    (or load-file-name buffer-file-name)))))
      sp-typst-executable (or (getenv "SP_TYPST_EXECUTABLE") "typst")
      sp-typst-font-paths (when-let ((paths (getenv "SP_TYPST_FONT_PATHS")))
                            (split-string paths path-separator t)))

;;; export.el ends here
