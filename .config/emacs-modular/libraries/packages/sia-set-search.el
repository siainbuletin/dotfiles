;; -*- lexical-binding: t; -*-
;; sia-set-search.el

;; dired-x is necessary for making counsel-fd work
;; This module includes packages that help with search within the buffer, in a directory
;; or more complicated grep-like searches.
;; 
;; It should also be somewhat integrated with sia-set-browsing.el, as it should pull in
;; omni-search and similar packages, for bringing in as much information as possible, and perhaps
;; acting on it in the future. The possibility of acting on this information is created through
;; the embark package. 
;;
;; See also possibilities for the vulpea ecosystem for this.

(use-package counsel
  :ensure (:wait t)
)

(use-package consult
  :ensure (:wait t)
  )

(keymap-global-set "C-c s l" #'consult-line)
(keymap-global-set "C-c s r" #'consult-ripgrep)

;; Global search

(use-package rg
  :ensure (:wait t)
  )

(use-package deadgrep
  :ensure (:wait t)
  )

(use-package p-search
  :ensure (:host github :repo "zkry/p-search"))

;; Personal functions for better searching

;; Acting on searches

(provide 'sia-set-search)

;; sia-set-search.el ends here