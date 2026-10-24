;;; sp-semantic.el --- Semantic search over notes -*- lexical-binding: t; -*-

;;; Commentary:

;; Oftentimes the search functions that I have enabled in Emacs aren't enough for me to actually
;; be able to find something.
;;
;; There are several packages that are concerned with getting to the information as fast as
;; possible, focusing specifically on linking information that may be found in a database.

;;; Code:

;;;; org-semantic
(use-package org-semantic-results
  :ensure (org-semantic :host github :repo "alberti42/org-semantic")
  :custom 
  (org-semantic-vault-root (directory-file-name sp-notes-dir))
  
  :bind (("C-c k s" . org-semantic-find)
         ("C-c k S" . org-semantic-find-in-directory)
         ("C-c k ." . org-semantic-find-at-point)
         ("C-c k R" . org-semantic-reindex))
  
  ;; Follow mode, on for every results buffer.
  :hook 
  (org-semantic-results-mode . next-error-follow-minor-mode)
  
  ;; Reindex a vault as its notes are saved.
  :init (org-semantic-auto-reindex-mode 1)
)

(provide 'sp-semantic)
;; sp-semantic.el ends here.
