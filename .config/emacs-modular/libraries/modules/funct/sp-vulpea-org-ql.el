;; -*- lexical-binding: t -*-
;; sp-vulpea-org-ql.el --- Bridge between vulpea and org-ql

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

;;; Provide:

(provide 'sp-vulpea-org-ql)
;; sp-vulpea-org-ql.el ends here.