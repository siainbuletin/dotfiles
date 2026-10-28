;;; sp-search.el --- Search tools: Consult, grep front-ends and Recoll -*- lexical-binding: t; -*-

;;; Commentary:

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

;;; Code:

(use-package counsel
  :ensure t
)

(use-package consult
  :ensure t
  )

(keymap-global-set "C-c s l" #'consult-line)
(keymap-global-set "C-c s r" #'consult-ripgrep)

;; Global search

(use-package ag
  :ensure (:wait t))

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
;;;; Search given directory
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

;;;; Search menu
;; One transient menu that gathers every search command of the configuration.
;; Commands from packages that may be missing (or not installed yet) are shown
;; only when `fboundp' says they exist, so the menu never offers a dead key.
(require 'transient)

(defvar sp-notes-dir)

(defun sp-search--header ()
  "Return the dashboard-style header line of `sp-search-menu'."
  (let ((on (lambda (name active)
              (propertize name 'face (if active 'success 'shadow)))))
    (concat
     (propertize "Searching in " 'face 'transient-heading)
     (propertize (abbreviate-file-name default-directory) 'face 'bold)
     (when-let* ((proj (and (fboundp 'project-current) (project-current))))
       (concat "  (project "
               (propertize (file-name-nondirectory
                            (directory-file-name (project-root proj)))
                           'face 'bold)
               ")"))
     "\n"
     (propertize "Completion: " 'face 'transient-heading)
     (funcall on "vertico" (bound-and-true-p vertico-mode)) " "
     (funcall on "marginalia" (bound-and-true-p marginalia-mode)) " "
     (funcall on "orderless" (featurep 'orderless)) " "
     (funcall on "embark" (featurep 'embark))
     (unless (executable-find "rg")
       (concat "  " (propertize "rg not found" 'face 'error))))))

(defun sp-search-in-notes ()
  "Grep through the notes directory with `consult-ripgrep'."
  (interactive)
  (consult-ripgrep (and (boundp 'sp-notes-dir) sp-notes-dir)))

(transient-define-prefix sp-search-menu ()
  "All the search commands of the configuration in one place."
  [:description sp-search--header
   ["Here: buffer and directory"
    ("l" "Lines in this buffer (consult-line)" consult-line)
    ("i" "Headings and symbols (consult-imenu)" consult-imenu)
    ("r" "Ripgrep in the project (consult-ripgrep)" consult-ripgrep)
    ("d" "Ripgrep in a chosen directory" sp-search-in-input-dir)
    ("f" "Fast file names (consult-snapfile)" consult-snapfile
     :if (lambda () (fboundp 'consult-snapfile)))
    ("T" "TODO/FIXME comments (consult-todo)" consult-todo
     :if (lambda () (fboundp 'consult-todo)))]
   ["Grep buffers (editable results)"
    ("g" "rg: ripgrep with a menu" rg-menu
     :if (lambda () (fboundp 'rg-menu)))
    ("D" "deadgrep: interactive ripgrep" deadgrep
     :if (lambda () (fboundp 'deadgrep)))
    ("a" "ag: the silver searcher" ag
     :if (lambda () (fboundp 'ag)))
    ("R" "Recoll: full-text index (Ivy)" counsel-recoll
     :if (lambda () (and (fboundp 'counsel-recoll) (executable-find "recollq"))))]]
  [["Notes: plain text"
    ("n" "Grep the notes (consult-ripgrep)" sp-search-in-notes)
    ("N" "Grep org-node notes" org-node-grep
     :if (lambda () (fboundp 'org-node-grep)))
    ("v" "Grep vulpea notes" vulpea-grep
     :if (lambda () (fboundp 'vulpea-grep)))
    ("c" "Pick a note, then search all (consult-notes)" consult-notes
     :if (lambda () (fboundp 'consult-notes)))
    ("C" "Search in all notes (consult-notes)" consult-notes-search-in-all-notes
     :if (lambda () (fboundp 'consult-notes-search-in-all-notes)))]
   ["Semantic: by meaning"
    ("s" "Semantic search (org-semantic)" org-semantic-find
     :if (lambda () (fboundp 'org-semantic-find)))
    ("S" "Semantic search in a directory" org-semantic-find-in-directory
     :if (lambda () (fboundp 'org-semantic-find-in-directory)))
    ("." "Semantic search from point" org-semantic-find-at-point
     :if (lambda () (fboundp 'org-semantic-find-at-point)))
    ("p" "p-search: combine evidence" p-search
     :if (lambda () (fboundp 'p-search)))
    ("t" "Semantic search of the tab inbox" sp-tab-psearch
     :if (lambda () (fboundp 'sp-tab-psearch)))
    ("T" "Tab inbox p-search (search box)" sp-tab-psearch-engine
     :if (lambda () (fboundp 'sp-tab-psearch-engine)))
    ("X" "Rebuild the semantic index" org-semantic-reindex
     :if (lambda () (fboundp 'org-semantic-reindex)))]
   ["Web and more"
    ("o" "Omni search (consult-omni)" consult-omni
     :if (lambda () (fboundp 'consult-omni)))]]
  [("q" "Quit" transient-quit-one)])

(keymap-global-set "C-c s m" #'sp-search-menu)

(provide 'sp-search)
;; sp-search.el ends here
