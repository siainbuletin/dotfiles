;; -*- lexical-binding: t; -*-
;; sp-search.el

;; This file is part of the category for /Navigation/ and should be treated as such.
;;
;; dired-x is necessary for making counsel-fd work
;; This module includes packages that help with search within the buffer, in a directory
;; or more complicated grep-like searches.
;; 
;; It should also be somewhat integrated with sp-browsing.el, as it should pull in
;; omni-search and similar packages, for bringing in as much information as possible, and perhaps
;; acting on it in the future. The possibility of acting on this information is created through
;; the embark package. 
;;
;; See also possibilities for the vulpea ecosystem for this.

(use-package counsel
  :ensure t
)

(use-package consult
  :ensure t
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

;; Functions written for searches
;;;;; Search given directory
(defun sp-search-in-input-dir ()
  "Grep for a string in the input directory using completing read function"
  (interactive)
  (let ((current-prefix-arg '(4))) (call-interactively #'consult-ripgrep)))

;; More advanced searching

(defun counsel-recoll-function (string &rest _unused)
  "Issue recallq for STRING."
  (if (< (length string) 3)
      (counsel-more-chars 3)
    (counsel--async-command
     (format "recollq -b '%s'" string))
    nil))

(defun counsel-recoll (&optional initial-input)
  "Search for a string in the recoll database.
You'll be given a list of files that match.
Selecting a file will launch `swiper' for that file.
INITIAL-INPUT can be given as the initial minibuffer input."
  (interactive)
  (ivy-read "recoll: " 'counsel-recoll-function
            :initial-input initial-input
            :dynamic-collection t
            :history 'counsel-git-grep-history
            :action (lambda (x)
                      (when (string-match "file://\\(.*\\)\\'" x)
                        (let ((file-name (match-string 1 x)))
                          (find-file file-name)
                          (unless (string-match "pdf$" x)
                            (swiper ivy-text)))))))

(provide 'sp-search)
;; sp-search.el ends here