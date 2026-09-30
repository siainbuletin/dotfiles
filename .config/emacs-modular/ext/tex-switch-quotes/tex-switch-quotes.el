(defadvice tex-insert-quote (around tex-switch-quotes activate compile)
  "Insert german or english quotes by looking at the LaTeX context.

English quotes are the default. German quotes are used when the
german language is selected in the documentclass or a usepackage
option."
  (let ((tex-german-regexp
         "\\(documentclass\\|usepackage\\)\\[[^]]*\\<n?german\\>")
        ;; english LaTeX quotes as default
        (tex-open-quote  "``")
        (tex-close-quote "''"))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (if (re-search-forward tex-german-regexp nil t)
            ;; switch to german LaTeX quotes
            (setq tex-open-quote  "\"`"
                  tex-close-quote "\"'"))))
    ad-do-it))
