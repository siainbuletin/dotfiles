;;; sp-litnotes.el --- Literature notes with citar-denote and citar-vulpea -*- lexical-binding: t; -*-

;;; Commentary:

;; This academic module connects bibliography entries to notes. `citar-denote'
;; creates one Denote file per reference (file-level literature notes) in a
;; `litnotes' subdirectory, and `citar-vulpea' supports literature notes as
;; Vulpea nodes inside larger files.

;;; Code:

;;; File-level literature notes
(use-package citar-denote
  :ensure (:wait t)

  :custom
  (citar-open-always-create-notes t)
  
  :init
  (citar-denote-mode)
  
  :bind
  (("C-c w b c" . citar-create-note)
   ("C-c w b n" . citar-denote-open-note)
   ("C-c w b x" . citar-denote-nocite)
   
   :map org-mode-map
   ("C-c w b k" . citar-denote-add-citekey)
   ("C-c w b K" . citar-denote-remove-citekey)
   ("C-c w b d" . citar-denote-dwim)
   ("C-c w b e" . citar-denote-open-reference-entry)))

(setq citar-denote-title-format 'author-year-title)

(setq citar-denote-title-format-authors '2)

(setq citar-denote-keyword "litnote")

(setq citar-denote-subdir "litnotes")

;;; Node-level literature note configuration
(use-package citar-vulpea
  :ensure t
  :after (citar vulpea)
  
  :custom
  ;; Tag used to identify bibliographic notes
  (citar-vulpea-keyword "litnote")
  
  ;; Name of the property used for citation keys
  (citar-vulpea-references-property "REFERENCES")
  
  ;; Template for new note titles
  (citar-vulpea-note-title-template "${author} (${date}) ${title}") ;; this has to be adapted to the citar-denote workflow

  (citar-vulpea-notes-directory (sp-path sp-notes-dir "litnotes/")) ;; Directory to store notes (nil uses vulpea-default-notes-directory)
)

(provide 'sp-litnotes)
;; sp-litnotes.el ends here
