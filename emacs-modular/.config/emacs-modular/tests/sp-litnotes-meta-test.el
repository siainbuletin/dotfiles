;;; sp-litnotes-meta-test.el --- Tests for sp-litnotes-meta -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-async-work)
(require 'sp-litnotes-meta)

(defvar sp-bibtex-files)

(defmacro sp-litnotes-meta-test--with-bib (text &rest body)
  "Run BODY with a registered .bib file holding TEXT."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "sp-meta" t))
          (bib (expand-file-name "a.bib" dir))
          (sp-bibtex-files (list bib)))
     (with-temp-file bib (insert ,text))
     (unwind-protect (progn ,@body) (delete-directory dir t))))

(defconst sp-litnotes-meta-test--bib
  "@book{reuten2014book,
  author = {Reuten, Geert and Marx, Karl},
  title = {The {Book} of Things},
  year = {2014},
}
@incollection{doe2015chapter,
  author = {Doe, Jane},
  title = {A Chapter},
  crossref = {reuten2014book},
}
@article{lee2020,
  editor = {Lee, Ann},
  title = {Dated},
  date = {2020-05-01},
}
")

(ert-deftest sp-litnotes-meta-entry-fields ()
  (sp-litnotes-meta-test--with-bib sp-litnotes-meta-test--bib
    (let ((entry (sp-litnotes-meta--entry "reuten2014book")))
      (should (equal (sp-litnotes-meta--field entry "title") "The Book of Things"))
      (should (equal (sp-litnotes-meta--author-names entry) '("Geert Reuten" "Karl Marx")))
      (should (equal (sp-litnotes-meta--year entry) "2014")))
    (should-not (sp-litnotes-meta--entry "nokey"))))

(ert-deftest sp-litnotes-meta-year-from-crossref-and-date ()
  (sp-litnotes-meta-test--with-bib sp-litnotes-meta-test--bib
    (should (equal (sp-litnotes-meta--year (sp-litnotes-meta--entry "doe2015chapter")) "2014"))
    (let ((entry (sp-litnotes-meta--entry "lee2020")))
      (should (equal (sp-litnotes-meta--year entry) "2020"))
      (should-not (sp-litnotes-meta--author-names entry))
      (should (equal (sp-litnotes-meta--author-names entry "editor") '("Ann Lee"))))))

(ert-deftest sp-litnotes-meta-set-lines ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID: x\n:END:\n#+title: T\n\n- pub-year ::\n- other :: v\n\n* Heading\n")
    (should (eq (sp-litnotes-meta--set "pub-year" "2014") 'filled))
    (should (eq (sp-litnotes-meta--set "pub-title" "A Title") 'added))
    (should-not (sp-litnotes-meta--set "pub-title" "Other"))
    (should (sp-litnotes-meta--has-value-p "pub-year"))
    (should-not (sp-litnotes-meta--has-value-p "bib-parent"))
    (should (string-match-p "- pub-year :: 2014\n- other :: v\n- pub-title :: A Title\n\n\\* Heading"
                            (buffer-string)))))

(ert-deftest sp-litnotes-meta-set-line-without-meta ()
  (with-temp-buffer
    (insert "#+title: T\n")
    (sp-litnotes-meta--set "pub-year" "2014")
    (should (string-match-p "- pub-year :: 2014\n" (buffer-string)))))

(ert-deftest sp-litnotes-meta-author-note-found-or-made ()
  (let ((sp-litnotes-meta--created (make-hash-table :test #'equal))
        (made nil))
    (cl-letf (((symbol-function 'vulpea-db-query) (lambda (_pred) nil))
              ((symbol-function 'sp-org--write-note)
               (lambda (name _tags) (push name made) "new-id"))
              ((symbol-function 'require) (lambda (&rest _) t)))
      (should (equal (sp-litnotes-meta--author-note "Geert Reuten") '("new-id" . "Geert Reuten")))
      ;; the second lookup finds the note made before, so none is made again
      (should (equal (sp-litnotes-meta--author-note "geert reuten") '("new-id" . "Geert Reuten")))
      (should (equal made '("Geert Reuten"))))))

(ert-deftest sp-litnotes-meta-fill-note ()
  (sp-litnotes-meta-test--with-bib sp-litnotes-meta-test--bib
    (let* ((dir (make-temp-file "sp-meta-notes" t))
           (file (expand-file-name "doe2015chapter.org" dir))
           (sp-author-notes-litnotes-directory dir)
           (sp-litnotes-meta--created (make-hash-table :test #'equal)))
      (with-temp-file file
        (insert ":PROPERTIES:\n:ID: lit-chapter\n:ROAM_REFS: @doe2015chapter\n:END:\n#+title: x\n\n"))
      (with-temp-file (expand-file-name "reuten2014book.org" dir)
        (insert ":PROPERTIES:\n:ID: lit-book\n:ROAM_REFS: @reuten2014book\n:END:\n#+title: Reuten (2014) Book\n\n"))
      (unwind-protect
          (cl-letf (((symbol-function 'sp-litnotes-meta--author-note)
                     (lambda (name) (cons "aid" name)))
                    ((symbol-function 'sp-litnotes-meta--read-project)
                     (lambda () "[[id:p][Thesis]]")))
            (should (equal (sp-litnotes-meta-fill "doe2015chapter" file)
                           '("pub-author" "pub-title" "pub-year" "bib-parent" "bib-project")))
            (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
              (should (string-match-p "- pub-author :: \\[\\[id:aid\\]\\[Jane Doe\\]\\]" text))
              (should (string-match-p "- pub-title :: A Chapter" text))
              (should (string-match-p "- pub-year :: 2014" text))
              (should (string-match-p "- bib-parent :: \\[\\[id:lit-book\\]\\[Reuten (2014) Book\\]\\]" text))
              (should (string-match-p "- bib-project :: \\[\\[id:p\\]\\[Thesis\\]\\]" text)))
            ;; a second run changes nothing
            (should-not (sp-litnotes-meta-fill "doe2015chapter" file)))
        (delete-directory dir t)))))

(ert-deftest sp-litnotes-meta-offer-to-create-parent ()
  (sp-litnotes-meta-test--with-bib sp-litnotes-meta-test--bib
    (let* ((dir (make-temp-file "sp-meta-notes" t))
           (sp-author-notes-litnotes-directory dir)
           (sp-litnotes-meta-auto nil)
           (asked 0) (filled nil))
      (unwind-protect
          (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) (cl-incf asked) t))
                    ((symbol-function 'citar-create-note)
                     (lambda (key &rest _)
                       (with-temp-file (expand-file-name (concat key ".org") dir)
                         (insert (format ":PROPERTIES:\n:ID: new-%s\n:ROAM_REFS: @%s\n:END:\n#+title: %s\n\n"
                                         key key key)))))
                    ((symbol-function 'sp-litnotes-meta-fill)
                     (lambda (key &rest _) (push key filled))))
            (let ((entry (sp-litnotes-meta--entry "doe2015chapter")))
              (should (equal (sp-litnotes-meta--parent-value entry)
                             "[[id:new-reuten2014book][reuten2014book]]"))
              (should (= asked 1))
              (should (equal filled '("reuten2014book")))))
        (delete-directory dir t)))
    ;; saying no leaves the line out
    (let ((dir (make-temp-file "sp-meta-notes" t)))
      (unwind-protect
          (let ((sp-author-notes-litnotes-directory dir))
            (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
              (should-not (sp-litnotes-meta--parent-value
                           (sp-litnotes-meta--entry "doe2015chapter")))))
        (delete-directory dir t)))))

(provide 'sp-litnotes-meta-test)
;;; sp-litnotes-meta-test.el ends here
