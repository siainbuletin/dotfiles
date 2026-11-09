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
                             "read-status" "relevance-factor" "tag")))
            (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
              (should (string-match-p "- pub-author :: \\[\\[id:aid\\]\\[Jane Doe\\]\\]" text))
              (should (string-match-p "- pub-title :: A Chapter" text))
              (should (string-match-p "- pub-year :: 2014" text))
              (should (string-match-p "- bib-parent :: \\[\\[id:lit-book\\]\\[Reuten (2014) Book\\]\\]" text))
              (should (string-match-p "- bib-project :: \\[\\[id:p\\]\\[Thesis\\]\\]" text))
              (should (string-match-p "- read-status :: 02-preparing" text))
              (should (string-match-p "- relevance-factor :: 02" text))
              (should (string-match-p "#\\+filetags: :litnote:incollection:" text))
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
              (cl-letf* ((sp-litnotes-meta-create-function
                          (lambda (key) (push key made) (expand-file-name (concat key ".org") dir)))
                         ((symbol-function 'sp-litnotes-meta--tidy-new-note) #'ignore)
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
            (cl-letf* ((sp-litnotes-meta-create-function
                        (lambda (key) (push key made) (expand-file-name (concat key ".org") dir)))
                       ((symbol-function 'sp-litnotes-meta--tidy-new-note) #'ignore)
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
              (should (string-match-p "^#\\+title: Doe (2014) A Chapter$" new))
              (should-not (string-match-p "print_bibliography\\|Notes on" new))
              (should (string-match-p "- pub-year :: 2014" new)))
            ;; a second run changes nothing
            (should-not (sp-litnotes-meta--tidy-new-note "doe2015chapter"))
            ;; the plain title is available
            (let ((sp-litnotes-meta-new-title 'title))
              (should (equal (sp-litnotes-meta--new-title (sp-litnotes-meta--entry "doe2015chapter"))
                             "A Chapter"))))
        (delete-directory dir t)))))

(ert-deftest sp-litnotes-meta-create-note-has-id-created-refs ()
  (sp-litnotes-meta-test--with-bib sp-litnotes-meta-test--bib
    (let* ((dir (make-temp-file "sp-meta-notes" t))
           (sp-author-notes-litnotes-directory dir)
           (args nil))
      (unwind-protect
          (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                    ((symbol-function 'sp-org-created-stamp) (lambda () "[2026-11-09 10:00]"))
                    ((symbol-function 'sp-notes-ensure-created) #'ignore)
                    ((symbol-function 'vulpea-note-path) (lambda (n) n))
                    ((symbol-function 'vulpea-create)
                     (lambda (title template &rest keys)
                       (setq args (list title template keys))
                       (with-temp-file template (insert "x"))
                       template)))
            (let ((file (sp-litnotes-meta-create-note "doe2015chapter")))
              (should (equal file (expand-file-name "doe2015chapter.org" dir)))
              (should (equal (car args) "Doe (2014) A Chapter"))
              (should (equal (plist-get (nth 2 args) :tags) '("litnote" "incollection")))
              (should (equal (plist-get (nth 2 args) :properties)
                             '(("ROAM_REFS" . "@doe2015chapter") ("CREATED" . "[2026-11-09 10:00]"))))))
        (delete-directory dir t)))))

(ert-deftest sp-litnotes-meta-backfill-fills-bibtex-and-indexes-note ()
  (sp-litnotes-meta-test--with-bib sp-litnotes-meta-test--bib
    (let* ((dir (make-temp-file "sp-meta-notes" t))
           (sp-author-notes-litnotes-directory dir)
           (sp-litnotes-meta-auto nil)
           (sp-litnotes-meta--created (make-hash-table :test #'equal))
           (indexed nil))
      (unwind-protect
          (progn
            (with-temp-file (expand-file-name "reuten2014book.org" dir)
              (insert ":PROPERTIES:\n:ID: lit-book\n:ROAM_REFS: @reuten2014book\n:END:\n#+title: Reuten (2014) Book\n\n"))
            (cl-letf* ((sp-litnotes-meta-create-function
                        (lambda (key)
                          (let ((f (expand-file-name (concat key ".org") dir)))
                            (with-temp-file f
                              (insert (format ":PROPERTIES:\n:ID: n1\n:ROAM_REFS: @%s\n:CREATED: [2026-11-09 10:00]\n:END:\n#+title: Notes on Doe, A Chapter\n#+print_bibliography:\n\n" key)))
                            f)))
                       ((symbol-function 'sp-litnotes-meta--author-note)
                        (lambda (name) (cons "aid" name)))
                       ((symbol-function 'sp-litnotes-meta--read-project) (lambda () nil))
                       ((symbol-function 'sp-litnotes-meta--read-relevance) (lambda () nil))
                       ((symbol-function 'sp-litnotes-meta--read-priority) (lambda () nil))
                       ((symbol-function 'vulpea-db-update-file) (lambda (f) (push f indexed))))
              (should (equal (sp-litnotes-meta-backfill-children "reuten2014book" '("doe2015chapter"))
                             '("doe2015chapter"))))
            (let ((text (with-temp-buffer
                          (insert-file-contents (expand-file-name "doe2015chapter.org" dir))
                          (buffer-string))))
              (should (string-match-p ":ID: n1" text))
              (should (string-match-p ":CREATED:" text))
              (should (string-match-p "^#\\+title: Doe (2014) A Chapter$" text))
              (should-not (string-match-p "print_bibliography" text))
              (should (string-match-p "- pub-author :: \\[\\[id:aid\\]\\[Jane Doe\\]\\]" text))
              (should (string-match-p "- pub-year :: 2014" text))
              (should (string-match-p "- bib-parent :: \\[\\[id:lit-book\\]" text)))
            ;; the file just made is in the database, whatever any cache holds
            (should (member (expand-file-name "doe2015chapter.org" dir) indexed)))
        (delete-directory dir t)))))

(defvar sp-litnotes-meta-test--made nil
  "The keys the test create function made, newest first.")

(defun sp-litnotes-meta-test--make-note (dir)
  "A create function that writes a note with ID id-KEY in DIR and records the key in `made'."
  (lambda (key)
    (let ((file (expand-file-name (concat key ".org") dir)))
      (with-temp-file file
        (insert (format ":PROPERTIES:\n:ID: id-%s\n:ROAM_REFS: @%s\n:END:\n#+title: %s\n#+filetags: :litnote:\n\n"
                        key key key)))
      (push key sp-litnotes-meta-test--made)
      file)))

(defmacro sp-litnotes-meta-test--with-parents (bib &rest body)
  "Run BODY with BIB registered, a litnotes DIR, the questions stubbed to no answer.
`sp-litnotes-meta-test--made' collects the keys that the create function made."
  (declare (indent 1))
  `(sp-litnotes-meta-test--with-bib ,bib
     (let* ((dir (make-temp-file "sp-meta-notes" t))
            (sp-author-notes-litnotes-directory dir)
            (sp-litnotes-meta-backup-directory (expand-file-name "bak/" dir))
            (sp-litnotes-meta-auto nil)
            (sp-litnotes-meta--created (make-hash-table :test #'equal))
            (sp-litnotes-meta--preset '(("bib-project") ("relevance-factor") ("read-priority")))
            (sp-litnotes-meta-create-function (sp-litnotes-meta-test--make-note dir))
            (sp-litnotes-meta-test--made nil))
       (cl-flet ((note (name text) (with-temp-file (expand-file-name name dir) (insert text))))
         (unwind-protect
             (cl-letf (((symbol-function 'sp-litnotes-meta--author-note)
                        (lambda (name) (cons "aid" name)))
                       ((symbol-function 'y-or-n-p) (lambda (&rest _) (error "Nothing should be asked")))
                       ((symbol-function 'citar-create-note)
                        (lambda (&rest _) (error "citar must not make the parent"))))
               ,@body)
           (delete-directory dir t))))))

(defun sp-litnotes-meta-test--read (dir name)
  (with-temp-buffer (insert-file-contents (expand-file-name name dir)) (buffer-string)))

(defconst sp-litnotes-meta-test--parent-bib
  "@book{bk,
  author = {Reuten, Geert},
  title = {The Book},
  year = {2014},
}
@incollection{ch1,
  author = {Doe, Jane},
  title = {One},
  crossref = {bk},
}
@incollection{ch2,
  author = {Roe, Rick},
  title = {Two},
  crossref = {bk},
}
")

(ert-deftest sp-litnotes-meta-creates-missing-parent-silently ()
  "A crossref without a note gets one, filled from BibTeX, and is linked; nobody is asked."
  (sp-litnotes-meta-test--with-parents sp-litnotes-meta-test--parent-bib
    (note "ch1.org" ":PROPERTIES:\n:ID: id-ch1\n:ROAM_REFS: @ch1\n:END:\n#+title: x\n#+filetags: :litnote:\n\n")
    (should (member "bib-parent" (sp-litnotes-meta-fill "ch1")))
    (should (equal sp-litnotes-meta-test--made '("bk")))
    (should (string-match-p "- bib-parent :: \\[\\[id:id-bk\\]\\[bk\\]\\]" (sp-litnotes-meta-test--read dir "ch1.org")))
    ;; the parent itself was filled from its BibTeX entry
    (let ((parent (sp-litnotes-meta-test--read dir "bk.org")))
      (should (string-match-p "- pub-author :: \\[\\[id:aid\\]\\[Geert Reuten\\]\\]" parent))
      (should (string-match-p "- pub-year :: 2014" parent))
      (should (string-match-p "#\\+filetags: :litnote:book:" parent)))
    ;; a second run finds the note and makes nothing
    (should-not (sp-litnotes-meta-fill "ch1"))
    (should (equal sp-litnotes-meta-test--made '("bk")))))

(ert-deftest sp-litnotes-meta-existing-parent-is-not-made ()
  (sp-litnotes-meta-test--with-parents sp-litnotes-meta-test--parent-bib
    (note "bk.org" ":PROPERTIES:\n:ID: lit-bk\n:ROAM_REFS: @bk\n:END:\n#+title: Book\n\n")
    (should (equal (sp-litnotes-meta--parent-value (sp-litnotes-meta--entry "ch1"))
                   "[[id:lit-bk][Book]]"))
    (should-not sp-litnotes-meta-test--made)))

(ert-deftest sp-litnotes-meta-create-parent-off-leaves-line-out ()
  (sp-litnotes-meta-test--with-parents sp-litnotes-meta-test--parent-bib
    (let ((sp-litnotes-meta-create-parent nil))
      (should-not (sp-litnotes-meta--parent-value (sp-litnotes-meta--entry "ch1")))
      (should-not sp-litnotes-meta-test--made))))

(ert-deftest sp-litnotes-meta-parent-of-itself-is-left-out ()
  (sp-litnotes-meta-test--with-parents "@book{self, title = {S}, crossref = {self}}\n"
    (note "self.org" ":PROPERTIES:\n:ID: id-self\n:ROAM_REFS: @self\n:END:\n#+title: S\n\n")
    (let ((sp-litnotes-meta--making '("self")))
      (should-not (sp-litnotes-meta--parent-value (sp-litnotes-meta--entry "self"))))
    (should-not sp-litnotes-meta-test--made)))

(ert-deftest sp-litnotes-meta-crossref-loop-makes-each-parent-once ()
  "ch -> b -> c -> b: b and c are made once, and c's link back to b is left out."
  (sp-litnotes-meta-test--with-parents
      "@incollection{ch, title = {Ch}, crossref = {b}}
@book{b, title = {B}, crossref = {c}}
@book{c, title = {C}, crossref = {b}}
"
    (note "ch.org" ":PROPERTIES:\n:ID: id-ch\n:ROAM_REFS: @ch\n:END:\n#+title: x\n#+filetags: :litnote:\n\n")
    ;; The batch reads the existing notes once, so b is not found while c is made.
    (let* ((covered (sp-author-notes-bibtex--covered))
           (sp-litnotes-meta--made-parents (make-hash-table :test #'equal)))
      (cl-letf (((symbol-function 'sp-author-notes-bibtex--covered) (lambda () covered)))
        (sp-litnotes-meta-fill "ch"))
      (should (equal (reverse sp-litnotes-meta-test--made) '("b" "c")))
      (should (string-match-p "- bib-parent :: \\[\\[id:id-b\\]" (sp-litnotes-meta-test--read dir "ch.org")))
      (should (string-match-p "- bib-parent :: \\[\\[id:id-c\\]" (sp-litnotes-meta-test--read dir "b.org")))
      (should-not (string-match-p "bib-parent" (sp-litnotes-meta-test--read dir "c.org"))))))

(ert-deftest sp-litnotes-meta-missing-parents-chain ()
  (sp-litnotes-meta-test--with-bib
      "@incollection{ch, crossref = {b}}
@book{b, crossref = {c}}
@book{c, crossref = {b}}
@book{d, crossref = {nokey}}
"
    (let ((covered (make-hash-table :test #'equal)))
      (should (equal (sp-litnotes-meta--missing-parents (sp-litnotes-meta--entry "ch") covered)
                     '("b" "c")))
      ;; stops at a parent that has a note, and at one without a BibTeX entry
      (puthash "c" "c.org" covered)
      (should (equal (sp-litnotes-meta--missing-parents (sp-litnotes-meta--entry "ch") covered) '("b")))
      (should-not (sp-litnotes-meta--missing-parents (sp-litnotes-meta--entry "d") covered)))))

(ert-deftest sp-litnotes-meta-batch-report-lists-each-parent-once ()
  (sp-litnotes-meta-test--with-parents sp-litnotes-meta-test--parent-bib
    (note "ch1.org" ":PROPERTIES:\n:ID: id-ch1\n:ROAM_REFS: @ch1\n:END:\n#+title: x\n#+filetags: :litnote:\n\n")
    (note "ch2.org" ":PROPERTIES:\n:ID: id-ch2\n:ROAM_REFS: @ch2\n:END:\n#+title: x\n#+filetags: :litnote:\n\n")
    (cl-letf (((symbol-function 'sp-litnotes-meta--batch-files)
               (lambda () (directory-files dir t "\\.org\\'"))))
      (let* ((plans (sp-litnotes-meta--batch-plans nil))
             (text (sp-litnotes-meta--batch-report-text plans nil)))
        (should (equal (plist-get (sp-litnotes-meta-test--plan-of plans "ch1.org") :new-parents) '("bk")))
        (should (equal (sp-litnotes-meta--planned-parents plans) '(("bk" "ch2" "ch1"))))
        (should (string-match-p "Parent notes to make: 1" text))
        (should (string-match-p "fill bib-parent :: bk (new note)" text))
        (should (string-match-p "\\* Parent notes to make[^\n]*\n- bk: Reuten (2014) The Book (linked from ch1, ch2)" text))
        (should (= 1 (with-temp-buffer (insert text) (how-many "^- bk: " (point-min)))))))))

(ert-deftest sp-litnotes-meta-batch-convert-makes-each-parent-once ()
  (sp-litnotes-meta-test--with-parents sp-litnotes-meta-test--parent-bib
    (note "ch1.org" ":PROPERTIES:\n:ID: id-ch1\n:ROAM_REFS: @ch1\n:END:\n#+title: x\n#+filetags: :litnote:\n\n")
    (note "ch2.org" ":PROPERTIES:\n:ID: id-ch2\n:ROAM_REFS: @ch2\n:END:\n#+title: x\n#+filetags: :litnote:\n\n")
    (cl-letf (((symbol-function 'sp-litnotes-meta--batch-files)
               (lambda () (directory-files dir t "\\`ch.*\\.org\\'")))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
              ((symbol-function 'completing-read) (lambda (&rest _) ""))
              ((symbol-function 'pop-to-buffer) #'ignore))
      (let ((sp-litnotes-meta--preset nil))
        (sp-litnotes-meta-fill-all-convert)))
    (should (equal sp-litnotes-meta-test--made '("bk")))
    (dolist (name '("ch1.org" "ch2.org"))
      (should (string-match-p "- bib-parent :: \\[\\[id:id-bk\\]" (sp-litnotes-meta-test--read dir name))))
    (when (get-buffer sp-litnotes-meta--batch-buffer) (kill-buffer sp-litnotes-meta--batch-buffer))))

(provide 'sp-litnotes-meta-test)
;;; sp-litnotes-meta-test.el ends here

(ert-deftest sp-litnotes-meta-new-title-uses-surname-before-comma ()
  "\"Last, First M.\" gives \"Last (Year) Title\", never \"M. Last\"."
  (sp-litnotes-meta-test--with-bib
      "@article{arthur2022,\n  author = {Arthur, Christopher J. and van der Berg, Ann},\n  year = {2022},\n  title = {Capital as Value}\n}\n"
    (let ((sp-litnotes-meta-new-title 'standard))
      (should (equal (sp-litnotes-meta--new-title (sp-litnotes-meta--entry "arthur2022"))
                     "Arthur and van der Berg (2022) Capital as Value")))))

(ert-deftest sp-litnotes-meta-table-view-uses-type-mapping ()
  (sp-litnotes-meta-test--with-bib "@mvcollection{vol2020,\n  title = {V},\n}\n@book{b2020,\n  title = {B},\n}\n"
    (should (equal (sp-litnotes-meta--table-view "vol2020") "collection-articles"))
    (should (equal (sp-litnotes-meta--table-view "b2020") "book-sections"))))

;;;; Batch

(defconst sp-litnotes-meta-test--batch-bib
  "@book{bk2014,
  author = {Reuten, Geert},
  title = {The Book},
  year = {2014},
}
@article{art2020,
  author = {Doe, Jane},
  title = {Right Title},
  year = {2020},
}
")

(defmacro sp-litnotes-meta-test--with-batch (&rest body)
  "Run BODY with notes bk, art, nokey, noentry in DIR and a .bib file."
  (declare (indent 0))
  `(sp-litnotes-meta-test--with-bib sp-litnotes-meta-test--batch-bib
     (let* ((dir (make-temp-file "sp-meta-batch" t))
            (sp-author-notes-litnotes-directory dir)
            (sp-litnotes-meta-backup-directory (expand-file-name "bak/" dir))
            (sp-litnotes-meta--created (make-hash-table :test #'equal)))
       (cl-flet ((note (name text) (with-temp-file (expand-file-name name dir) (insert text))))
         (note "bk.org" ":PROPERTIES:\n:ID: bk\n:ROAM_REFS: @bk2014\n:END:\n#+title: x\n#+filetags: :litnote:\n\n")
         (note "art.org" ":PROPERTIES:\n:ID: art\n:ROAM_REFS: @art2020\n:END:\n#+title: x\n#+filetags: :litnote:text:\n\n- pub-title :: Old Title\n- pub-year :: 2020\n\n")
         (note "nokey.org" ":PROPERTIES:\n:ID: nk\n:END:\n#+title: x\n#+filetags: :litnote:\n\n")
         (note "noentry.org" ":PROPERTIES:\n:ID: ne\n:ROAM_REFS: @missing\n:END:\n#+title: x\n#+filetags: :litnote:\n\n"))
       (unwind-protect
           (cl-letf (((symbol-function 'sp-litnotes-meta--batch-files)
                      (lambda () (directory-files dir t "\\.org\\'")))
                     ((symbol-function 'sp-litnotes-meta--author-note)
                      (lambda (name) (cons "aid" name))))
             ,@body)
         (delete-directory dir t)))))

(defun sp-litnotes-meta-test--plan-of (plans name)
  (seq-find (lambda (p) (equal (sp-litnotes-meta--name p) name)) plans))

(ert-deftest sp-litnotes-meta-batch-plan ()
  (sp-litnotes-meta-test--with-batch
    (let* ((plans (sp-litnotes-meta--batch-plans nil))
           (bk (sp-litnotes-meta-test--plan-of plans "bk.org"))
           (art (sp-litnotes-meta-test--plan-of plans "art.org")))
      (should (eq (plist-get (sp-litnotes-meta-test--plan-of plans "nokey.org") :status) 'no-key))
      (should (eq (plist-get (sp-litnotes-meta-test--plan-of plans "noentry.org") :status) 'no-entry))
      (should (equal (plist-get bk :fill)
                     '(("pub-author" . "Geert Reuten") ("pub-title" . "The Book") ("pub-year" . "2014"))))
      (should (equal (plist-get bk :tag) '(add . "book")))
      (should (member "relevance-factor" (plist-get bk :missing)))
      ;; art has title and year; only the author is to fill; its text tag is a mismatch
      (should (equal (plist-get art :fill) '(("pub-author" . "Jane Doe"))))
      (should (equal (plist-get art :tag) '(mismatch ("text") . "journalarticle")))
      (should-not (plist-get art :replace))
      ;; a prefix argument lists the differing title only
      (let ((art2 (sp-litnotes-meta-test--plan-of (sp-litnotes-meta--batch-plans t) "art.org")))
        (should (equal (plist-get art2 :replace) '(("pub-title" . "Right Title"))))))))

(ert-deftest sp-litnotes-meta-batch-report-text ()
  (sp-litnotes-meta-test--with-batch
    (let ((text (sp-litnotes-meta--batch-report-text (sp-litnotes-meta--batch-plans nil) nil)))
      (should (string-match-p "To change: 2" text))
      (should (string-match-p "Skipped: no citation key\n- \\[\\[file:[^]]*nokey\\.org\\]\\[nokey\\.org\\]\\]" text))
      (should (string-match-p "- \\[\\[file:[^]]*noentry\\.org\\]\\[noentry\\.org\\]\\] (missing)" text))
      (should (string-match-p "\\[art\\.org\\]\\]: has text, the entry type says journalarticle" text)))))

(ert-deftest sp-litnotes-meta-batch-dryrun-writes-nothing ()
  (sp-litnotes-meta-test--with-batch
    (let ((before (with-temp-buffer (insert-file-contents (expand-file-name "bk.org" dir)) (buffer-string))))
      (sp-litnotes-meta-fill-all-dryrun)
      (should (equal before (with-temp-buffer (insert-file-contents (expand-file-name "bk.org" dir))
                                              (buffer-string))))
      (should-not (file-exists-p sp-litnotes-meta-backup-directory))
      (kill-buffer sp-litnotes-meta--batch-buffer))))

(ert-deftest sp-litnotes-meta-batch-convert ()
  (sp-litnotes-meta-test--with-batch
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
              ((symbol-function 'completing-read) (lambda (&rest _) "")))
      (let ((results (sp-litnotes-meta-fill-all-convert)))
        (should (equal (cdr (assoc (expand-file-name "bk.org" dir) results))
                       '("pub-author" "pub-title" "pub-year" "tag")))
        (let ((bk (with-temp-buffer (insert-file-contents (expand-file-name "bk.org" dir)) (buffer-string)))
              (art (with-temp-buffer (insert-file-contents (expand-file-name "art.org" dir)) (buffer-string))))
          (should (string-match-p "#\\+filetags: :litnote:book:" bk))
          (should (string-match-p "pub-author :: \\[\\[id:aid\\]\\[Geert Reuten\\]\\]" bk))
          ;; nothing asked: the empty answers left the default lines out
          (should-not (string-match-p "relevance-factor" bk))
          ;; existing value kept, tag untouched
          (should (string-match-p "pub-title :: Old Title" art))
          (should (string-match-p ":litnote:text:" art)))
        (should (= 2 (length (directory-files (car (directory-files sp-litnotes-meta-backup-directory t "\\`[0-9]"))
                                              nil "\\.org\\'"))))
        ;; a second run has nothing left to do
        (should-not (sp-litnotes-meta-fill-all-convert)))
      (kill-buffer sp-litnotes-meta--batch-buffer))))

(ert-deftest sp-litnotes-meta-batch-convert-overwrite ()
  (sp-litnotes-meta-test--with-batch
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
              ((symbol-function 'completing-read) (lambda (&rest _) "")))
      (sp-litnotes-meta-fill-all-convert t)
      (should (string-match-p "pub-title :: Right Title"
                              (with-temp-buffer (insert-file-contents (expand-file-name "art.org" dir))
                                                (buffer-string))))
      (kill-buffer sp-litnotes-meta--batch-buffer))))

(ert-deftest sp-litnotes-meta-type-tag-keeps-existing ()
  (let ((entry '(("=type=" . "book"))))
    (with-temp-buffer
      (insert "#+title: T\n#+filetags: :litnote:phdthesis:\n")
      (should-not (sp-litnotes-meta--ensure-type-tag entry)))
    (with-temp-buffer
      (insert "#+title: T\n\n")
      (should (sp-litnotes-meta--ensure-type-tag entry))
      (should (string-match-p "#\\+title: T\n#\\+filetags: :litnote:book:\n" (buffer-string))))))

(ert-deftest sp-litnotes-meta-batch-report-is-a-report-buffer ()
  (sp-litnotes-meta-test--with-batch
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-litnotes-meta-fill-all-dryrun))
    (with-current-buffer sp-litnotes-meta--batch-buffer
      (should (derived-mode-p 'sp-batch-report-mode))
      (should (functionp sp-batch-report-refresh-function))
      (should (string-match-p
               (format "\\[\\[file:%s\\]\\[bk\\.org\\]\\]" (regexp-quote (expand-file-name "bk.org" dir)))
               (buffer-string))))
    (kill-buffer sp-litnotes-meta--batch-buffer)))
