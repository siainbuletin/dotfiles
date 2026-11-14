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

  ;; Keys: C-; B c, n, d, k, K, e (sp-keys).
  :commands (citar-create-note citar-open-notes citar-open-entry
             citar-vulpea-add-reference citar-vulpea-remove-reference
             citar-vulpea-dwim))

(require 'sp-litnotes-refs)
(require 'sp-litnotes-titles)
(require 'sp-litnotes-meta)

(provide 'sp-litnotes)
;; sp-litnotes.el ends here
