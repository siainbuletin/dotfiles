;;; sp-org-fn.el --- Scoped Org footnotes (experimental) -*- lexical-binding: t; -*-

;;; Commentary:

;; Commentary:

;; Org footnotes typically get placed at the end of the file in a footnote section. This
;; behaviour is generally very useful, however, in the case of wanting to refile a heading
;; to a different file with a function like ~vulpea-split-heading~, the footnotes don't get
;; copied over as well, which creates a lot of manual work.
;;
;; Working with Claude, I want to define custom logic for the footnotes so that I can restrict
;; how deep into the sections the footnotes can go, and when to decide when to actually keep
;; the regular footnotes at the end of the file (for much smaller files)

;; The current logic that has been written by Claude doesn't actually do anything and, in fact, it blocks
;; the functioning of creating a new footnote, because org-footnote-new is being adviced.

;; Code:

;; Footnotes
;; (org-footnote-section t) ;; place footnotes globally. replace with nil if you want to have local footnotes --- can this be set according to the file?
;; disabled in favor of new logic

;;; Code:

;; Autorenumbering for footnotes
;; this should only be kept on if you have the proper logic for nested headings working well
;; enough, because it makes sifting through for the correct reference really easy to get wrong
;; when trying to move notes around.
(setq org-footnote-auto-adjust t) ;; renumber footnotes

;; Defining the custom variables for this
(defvar sp-fn-max-lvl 3
  "Deepest heading level that may own a footnote section.")

(defvar sp-fn-small-file-max-lvl 2
  "Files with at most this many level-1 headings keep a file-end section.")

(defun sp-org-count-top-headings ()
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((n 0))
     (while (re-search-forward "^\\* " nil t) (cl-incf n))
     n)))

(defun sp-org-fn-scoped (orig &rest args)
  (if (or (<= (sp-org-count-top-headings) sp-fn-small-file-max-lvl)
          (org-before-first-heading-p))
      (let ((org-footnote-section "Footnotes"))
        (apply orig args))
    (save-excursion
      (save-restriction
        (org-back-to-heading t)
        (while (and (> (org-current-level) sp-fn-max-lvl)
                    (org-up-heading-safe)))
        (org-narrow-to-subtree)
        (let ((org-footnote-section "Footnotes"))
          (apply orig args))))))

(advice-add 'org-footnote-new :around #'sp-org-fn-scoped)

(provide 'sp-org-fn)
;; sp-org-fn.el ends here.
