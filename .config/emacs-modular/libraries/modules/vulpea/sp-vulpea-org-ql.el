;;; sp-vulpea-org-ql.el --- Querying vulpea notes with org-ql (draft) -*- lexical-binding: t; -*-

;;; Commentary:

;; Use-cases:
;; - for inline querying

;;; Code:

;;;; Computing the relevance of certain literature notes
(let* ((notes (vulpea-db-query
               (lambda (n)
                 (>= (or (vulpea-note-meta-get n "relevance-factor" 'number) 0) 4))))
       (files (mapcar #'vulpea-note-path notes)))
  (org-ql-select files '(todo "OPENQ")
                 :action #'org-get-heading))

(provide 'sp-vulpea-org-ql)
;; sp-vulpea-org-ql.el ends here.
