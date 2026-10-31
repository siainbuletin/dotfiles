;;; sp-litnotes.el --- Literature notes with citar-vulpea -*- lexical-binding: t; -*-

;;; Commentary:

;; This academic module connects bibliography entries to notes.  `citar-vulpea'
;; makes Citar use Vulpea notes as literature notes, with the citation key in
;; the `ROAM_REFS' property.  `sp-litnotes-refs' converts notes made by
;; `citar-denote' (which used a `#+reference:' keyword).

;;; Code:

;;;; Literature notes as Vulpea nodes
(use-package citar-vulpea
  :ensure t
  :after (citar vulpea)

  :custom
  ;; Tag used to identify bibliographic notes
  (citar-vulpea-keyword "litnote")

  ;; Name of the property used for citation keys
  (citar-vulpea-references-property "ROAM_REFS")

  ;; Template for new note titles
  (citar-vulpea-note-title-template "${author} (${date}) ${title}") ;; this has to be adapted to the titles of the existing notes

  (citar-vulpea-notes-directory (sp-path sp-notes-dir "litnotes/")) ;; Directory to store notes (nil uses vulpea-default-notes-directory)

  ;; Create a note when opening notes for a reference that has none
  (citar-open-always-create-notes t)

  :config
  (citar-vulpea-mode 1)

  :bind
  (("C-c w b c" . citar-create-note)
   ("C-c w b n" . citar-open-notes)

   :map org-mode-map
   ("C-c w b k" . citar-vulpea-add-reference)
   ("C-c w b K" . citar-vulpea-remove-reference)
   ("C-c w b d" . citar-vulpea-dwim)
   ("C-c w b e" . citar-open-entry)))

(require 'sp-litnotes-refs)

(provide 'sp-litnotes)
;; sp-litnotes.el ends here
