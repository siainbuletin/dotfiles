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
                     (lambda () "[[id:p][Thesis]]"))
                    ((symbol-function 'sp-litnotes-meta--read-relevance) (lambda () "02"))
                    ((symbol-function 'sp-litnotes-meta--read-priority) (lambda () nil)))
            (should (equal (sp-litnotes-meta-fill "doe2015chapter" file)
                           '("pub-author" "pub-title" "pub-year" "bib-parent" "bib-project"
                             "read-status" "relevance-factor")))
            (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
              (should (string-match-p "- pub-author :: \\[\\[id:aid\\]\\[Jane Doe\\]\\]" text))
              (should (string-match-p "- pub-title :: A Chapter" text))
              (should (string-match-p "- pub-year :: 2014" text))
              (should (string-match-p "- bib-parent :: \\[\\[id:lit-book\\]\\[Reuten (2014) Book\\]\\]" text))
              (should (string-match-p "- bib-project :: \\[\\[id:p\\]\\[Thesis\\]\\]" text))
              (should (string-match-p "- read-status :: 02-preparing" text))
              (should (string-match-p "- relevance-factor :: 02" text))
              (should-not (string-match-p "read-priority" text)))
            ;; a second run changes nothing
            (should-not (sp-litnotes-meta-fill "doe2015chapter" file)))
        (delete-directory dir t)))))

(ert-deftest sp-litnotes-meta-read-scale-empty-skips ()
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "  ")))
    (should-not (sp-litnotes-meta--read-priority)))
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) " 05 ")))
    (should (equal (sp-litnotes-meta--read-relevance) "05"))))

(ert-deftest sp-litnotes-meta-status-report-and-change ()
  (let* ((dir (make-temp-file "sp-meta-status" t))
         (sp-author-notes-litnotes-directory dir)
         (a (expand-file-name "a.org" dir))
         (b (expand-file-name "b.org" dir))
         (c (expand-file-name "c.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file a
            (insert ":PROPERTIES:\n:ID: a\n:END:\n#+title: A\n\n- read-status :: 02-preparing\n- read-priority :: 01\n\n* H\n"))
          (with-temp-file b
            (insert ":PROPERTIES:\n:ID: b\n:END:\n#+title: B\n\n- read-status :: reading\n\n* H\n"))
          (with-temp-file c (insert ":PROPERTIES:\n:ID: c\n:END:\n#+title: C\n\n"))
          (let ((meta (sp-litnotes-meta--file-meta a)))
            (should (equal (plist-get meta :title) "A"))
            (should (equal (plist-get meta :read-status) "02-preparing"))
            (should (equal (plist-get meta :read-priority) "01"))
            (should (equal (plist-get meta :relevance-factor) "")))
          ;; the report flags the two notes with a bad or missing status
          (with-temp-buffer
            (sp-litnotes-meta-status-mode)
            (setq tabulated-list-entries (sp-litnotes-meta--status-entries))
            (should (string-match-p "02-preparing: 1.*other: 2" (sp-litnotes-meta--status-header))))
          ;; change replaces a value and adds a missing line
          (sp-litnotes-meta-set-status b "05-done")
          (sp-litnotes-meta-set-status c "03-review")
          (should (equal (plist-get (sp-litnotes-meta--file-meta b) :read-status) "05-done"))
          (should (equal (plist-get (sp-litnotes-meta--file-meta c) :read-status) "03-review")))
      (delete-directory dir t))))

(ert-deftest sp-litnotes-meta-status-region-marks ()
  "Marking and changing act on every note in the active region."
  (let* ((dir (make-temp-file "sp-meta-region" t))
         (sp-author-notes-litnotes-directory dir)
         (files (mapcar (lambda (n) (expand-file-name (concat n ".org") dir))
                        '("a" "b" "c"))))
    (unwind-protect
        (progn
          (dolist (f files)
            (with-temp-file f
              (insert (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: %s\n\n- read-status :: 01-new\n\n* H\n"
                              (file-name-base f) (file-name-base f)))))
          (with-current-buffer (get-buffer-create "*litnote status test*")
            (sp-litnotes-meta-status-mode)
            (transient-mark-mode 1)
            (sp-litnotes-meta-status-refresh)
            ;; region over the first two lines, ending at the start of line 3
            (goto-char (point-min))
            (set-mark (point))
            (forward-line 2)
            (activate-mark)
            (should (= (length (sp-litnotes-meta--region-files)) 2))
            (sp-litnotes-meta-status-mark)
            (should (= (length sp-litnotes-meta--marked) 2))
            ;; the row order is the sort order, so check the third row
            (goto-char (point-min))
            (forward-line 2)
            (should-not (member (tabulated-list-get-id) sp-litnotes-meta--marked))
            ;; unmark one line with a region of one line
            (goto-char (point-min))
            (set-mark (point))
            (end-of-line)
            (activate-mark)
            (sp-litnotes-meta-status-unmark)
            (should (= (length sp-litnotes-meta--marked) 1))
            ;; with no marks, change uses the region
            (sp-litnotes-meta-status-unmark-all)
            (goto-char (point-min))
            (set-mark (point))
            (goto-char (point-max))
            (activate-mark)
            (sp-litnotes-meta-status-change "05-done")
            (dolist (f files)
              (should (equal (plist-get (sp-litnotes-meta--file-meta f) :read-status)
                             "05-done")))
            (kill-buffer)))
      (delete-directory dir t))))

(ert-deftest sp-litnotes-meta-backfill-children ()
  (sp-litnotes-meta-test--with-bib (concat sp-litnotes-meta-test--bib
                                           "@incollection{roe2016chapter,
  author = {Roe, Rick},
  title = {Second Chapter},
  crossref = {Reuten2014Book},
}
")
    (let* ((dir (make-temp-file "sp-meta-notes" t))
           (sp-author-notes-litnotes-directory dir)
           (sp-litnotes-meta-auto nil)
           (made nil) (presets nil))
      (unwind-protect
          (progn
            (with-temp-file (expand-file-name "doe2015chapter.org" dir)
              (insert ":PROPERTIES:\n:ID: c1\n:ROAM_REFS: @doe2015chapter\n:END:\n#+title: x\n\n"))
            ;; doe2015chapter already has a note, so only roe2016chapter is a candidate
            (should (equal (mapcar (lambda (c) (plist-get c :key))
                                   (sp-litnotes-meta--children "reuten2014book"))
                           '("roe2016chapter")))
            (with-temp-buffer
              (org-mode)
              (insert "#+title: Book\n\n- bib-project :: [[id:p][Thesis]]\n\n")
              (cl-letf (((symbol-function 'citar-create-note) (lambda (key &rest _) (push key made)))
                        ((symbol-function 'sp-litnotes-meta-fill)
                         (lambda (key &rest _) (push (cons key sp-litnotes-meta--preset) presets))))
                (should (equal (sp-litnotes-meta-backfill-children "reuten2014book" '("roe2016chapter"))
                               '("roe2016chapter")))))
            (should (equal made '("roe2016chapter")))
            (should (equal (cdr (assoc "bib-project" (cdr (car presets)))) "[[id:p][Thesis]]")))
        (delete-directory dir t)))))

(ert-deftest sp-litnotes-meta-backfill-all-children-adds-and-updates-table ()
  (sp-litnotes-meta-test--with-bib (concat sp-litnotes-meta-test--bib
                                           "@incollection{roe2016chapter,
  title = {Second Chapter},
  crossref = {reuten2014book},
}
")
    (let* ((dir (make-temp-file "sp-meta-notes" t))
           (sp-author-notes-litnotes-directory dir)
           (sp-litnotes-meta-auto nil)
           (made nil) (updates 0))
      (unwind-protect
          (progn
            (provide 'sp-collection-query-tables-org)
            (cl-letf (((symbol-function 'citar-create-note) (lambda (key &rest _) (push key made)))
                      ((symbol-function 'sp-litnotes-meta-fill) #'ignore)
                      ((symbol-function 'sp-litnotes-meta--read-relevance) (lambda () nil))
                      ((symbol-function 'sp-litnotes-meta--read-priority) (lambda () nil))
                      ((symbol-function 'completing-read-multiple)
                       (lambda (&rest _) (error "Nothing should be picked")))
                      ((symbol-function 'sp-collec-query-dblock-has-block-p)
                       (lambda () (save-excursion (goto-char (point-min))
                                                  (re-search-forward "^#\\+BEGIN: collection-query-table" nil t))))
                      ((symbol-function 'sp-collec-query-dblock-update-buffer)
                       (lambda () (cl-incf updates)))
                      ((symbol-function 'org-update-dblock) #'ignore))
              (with-temp-buffer
                (org-mode)
                (insert ":PROPERTIES:\n:ID: b\n:ROAM_REFS: @reuten2014book\n:END:\n#+title: Book\n\n* H\n")
                ;; doe2015chapter and roe2016chapter both lack a note: all are made, none picked
                (should (equal (sp-litnotes-meta-backfill-all-children "reuten2014book")
                               '("doe2015chapter" "roe2016chapter")))
                (should (equal (reverse made) '("doe2015chapter" "roe2016chapter")))
                (should (string-match-p
                         "#\\+BEGIN: collection-query-table :view \"book-sections\"\n\n#\\+END:\n\n\\* H"
                         (buffer-string)))
                (should (= updates 1))
                ;; a second run finds nothing left, keeps one block and refreshes it
                (setq made nil)
                (cl-letf (((symbol-function 'sp-litnotes-meta--children) (lambda (_) nil)))
                  (should-not (sp-litnotes-meta-backfill-children "reuten2014book" nil t)))
                (should-not made)
                (should (= (how-many "#\\+BEGIN: collection-query-table" (point-min)) 1))
                (should (= updates 2)))))
        (delete-directory dir t)))))

(ert-deftest sp-litnotes-meta-table-view-by-type ()
  (sp-litnotes-meta-test--with-bib "@book{b, title = {B}}\n@collection{c, title = {C}}\n"
    (should (equal (sp-litnotes-meta--table-view "b") "book-sections"))
    (should (equal (sp-litnotes-meta--table-view "c") "collection-articles"))))

(ert-deftest sp-litnotes-meta-tidy-new-note ()
  (sp-litnotes-meta-test--with-bib sp-litnotes-meta-test--bib
    (let* ((dir (make-temp-file "sp-meta-notes" t))
           (sp-author-notes-litnotes-directory dir)
           (file (expand-file-name "doe2015chapter.org" dir))
           (text ":PROPERTIES:\n:ID: c1\n:ROAM_REFS: @doe2015chapter\n:END:\n#+title: Notes on Doe, A Chapter\n#+print_bibliography:\n\n- pub-year :: 2014\n"))
      (unwind-protect
          (progn
            (with-temp-file file (insert text))
            (should (sp-litnotes-meta--tidy-new-note "doe2015chapter"))
            (let ((new (with-temp-buffer (insert-file-contents file) (buffer-string))))
              (should (string-match-p "^#\\+title: A Chapter$" new))
              (should-not (string-match-p "print_bibliography\\|Notes on" new))
              (should (string-match-p "- pub-year :: 2014" new)))
            ;; a second run changes nothing
            (should-not (sp-litnotes-meta--tidy-new-note "doe2015chapter"))
            ;; the standard form is available
            (let ((sp-litnotes-meta-new-title 'standard))
              (should (equal (sp-litnotes-meta--new-title (sp-litnotes-meta--entry "doe2015chapter"))
                             "Doe (2014) A Chapter"))))
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
