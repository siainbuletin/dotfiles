;;; sp-collection-query-tables-test.el --- Tests for query table sorting  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(when noninteractive
  (provide 'vulpea)
  (defun vulpea-note-title (note) (plist-get note :title))
  (defun vulpea-note-id (note) (plist-get note :id))
  (defun vulpea-note-properties (note) (plist-get note :props))
  (defun vulpea-note-tags (note) (plist-get note :tags))
  (defun vulpea-db-get-by-id (id) (cdr (assoc id sp-collec-query-test-db)))
  (defun vulpea-note-meta-get-list (note key &optional _type) (cdr (assoc key (plist-get note :meta)))))

(load (expand-file-name
       "../libraries/modules/funct/sp-collection-query-tables-core.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defvar sp-collec-query-test-notes
  '((:title "d" :meta (("rating" "5") ("year" "2020")))
    (:title "a" :meta (("rating" "3") ("year" "2021")))
    (:title "c" :meta (("rating" "5") ("year" "2022")))
    (:title "b" :meta (("rating" "5") ("year" "2020")))
    (:title "e" :meta (("year" "2019")))))

(defun sp-collec-query-test--titles (sort-by &optional descending)
  (mapcar (lambda (n) (plist-get n :title))
          (sp-collec-query-sort sp-collec-query-test-notes sort-by descending)))

(ert-deftest sp-collec-query-test-single-key-still-works ()
  (should (equal (sp-collec-query-test--titles "rating") '("a" "d" "c" "b" "e")))
  (should (equal (sp-collec-query-test--titles :title t) '("e" "d" "c" "b" "a"))))

(ert-deftest sp-collec-query-test-second-key-breaks-ties ()
  (should (equal (sp-collec-query-test--titles '("rating" :title)) '("a" "b" "c" "d" "e")))
  (should (equal (sp-collec-query-test--titles '("rating" "year" :title)) '("a" "b" "d" "c" "e"))))

(ert-deftest sp-collec-query-test-keys-have-their-own-direction ()
  (should (equal (sp-collec-query-test--titles '("rating" (:title . desc)))
                 '("a" "d" "c" "b" "e")))
  (should (equal (sp-collec-query-test--titles '(("rating" . desc) (:title . asc)))
                 '("e" "b" "c" "d" "a"))))

(ert-deftest sp-collec-query-test-default-direction-applies-to-plain-keys ()
  (should (equal (sp-collec-query-test--titles '("rating" (:title . asc)) t)
                 '("e" "b" "c" "d" "a"))))

(ert-deftest sp-collec-query-test-sort-keys-are-idempotent ()
  (let ((keys (sp-collec-query-sort-keys '("rating" (:title . desc)))))
    (should (equal keys '(("rating") (:title . t))))
    (should (equal (sp-collec-query-sort-keys keys) keys))))

(ert-deftest sp-collec-query-test-no-key-keeps-the-order ()
  (should (equal (sp-collec-query-test--titles nil) '("d" "a" "c" "b" "e"))))

;;;; Folding notes into their parent

(defvar sp-collec-query-test-db
  '(("b2" . (:id "b2" :title "Other book" :tags ("book")))
    ("c9" . (:id "c9" :title "Essays on X" :tags ("collection")))))

(ert-deftest sp-collec-query-test-fold-counts-sections-on-the-book ()
  (let* ((book (list :id "b1" :title "Book" :tags '("book")))
         (s1 (list :id "s1" :title "Ch 1" :tags '("booksection") :meta '(("bib-parent" "b1"))))
         (s2 (list :id "s2" :title "Ch 2" :tags '("booksection") :meta '(("bib-parent" "b1" "b2"))))
         (paper (list :id "p" :title "Paper" :tags '("journalarticle")))
         (spec '(:fold-tag "booksection" :fold-prop "bib-parent"))
         (out (sp-collec-query--fold (list book s1 s2 paper) spec)))
    ;; sections leave; the missing book b2 is added from the database
    (should (equal (sort (mapcar (lambda (n) (plist-get n :id)) out) #'string<)
                   '("b1" "b2" "p")))
    (should (equal (sp-collec-query-cell book :sections) "2"))
    (should (equal (sp-collec-query-cell (cdr (assoc "b2" sp-collec-query-test-db)) :sections) "1"))
    (should (equal (sp-collec-query-cell paper :sections) ""))))

(ert-deftest sp-collec-query-test-fold-list-of-tags ()
  (let* ((s1 (list :id "s1" :title "Ch 1" :tags '("booksection") :meta '(("bib-parent" "b1"))))
         (c1 (list :id "c1" :title "Chapter" :tags '("incollection") :meta '(("bib-parent" "b2"))))
         (spec '(:fold-tag ("booksection" "incollection")))
         (out (sp-collec-query--fold (list s1 c1) spec)))
    ;; both leave the table; only b2 is in the stubbed database
    (should (equal (mapcar (lambda (n) (plist-get n :id)) out) '("b2")))
    (should (equal (sp-collec-query-cell (car out) :sections) "1"))))

(ert-deftest sp-collec-query-test-collection-column-shows-parent-title ()
  (let ((chapter (list :id "i1" :title "Chapter" :tags '("incollection")
                       :meta '(("bib-parent" "c9"))))
        (loose (list :id "i2" :title "Loose" :tags '("incollection"))))
    (should (equal (sp-collec-query-cell chapter :collection) "Essays on X"))
    (should (equal (sp-collec-query-display-cell chapter :collection)
                   "[[id:c9][Essays on X]]"))
    (should (equal (sp-collec-query-cell loose :collection) ""))))

(ert-deftest sp-collec-query-test-parent-of-matches-every-link-of-a-value ()
  (let ((note (list :id "x" :tags '("incollection")
                    :meta '(("pub-author" "[[id:a1][Ann]], [[id:a2][Bob]]")))))
    (should (equal (sp-collec-query--link-ids note "pub-author") '("a1" "a2")))
    (should (sp-collec-query-note-matches-p note '(:parent-of "a2" :parent-prop "pub-author")))
    (should-not (sp-collec-query-note-matches-p note '(:parent-of "a3" :parent-prop "pub-author")))
    (should-not (sp-collec-query-note-matches-p
                 note '(:parent-of "a2" :parent-prop "pub-author" :except-prop "pub-author")))))

(ert-deftest sp-collec-query-test-no-fold-tag-changes-nothing ()
  (let ((notes (list (list :id "s1" :tags '("booksection")))))
    (should (eq (sp-collec-query--fold notes nil) notes))))

;;;; Dynamic blocks kept up to date

(when noninteractive
  (unless (fboundp 'vulpea-db-query) (defun vulpea-db-query (&rest _) nil))
  (load (expand-file-name
         "../libraries/modules/funct/sp-collection-query-tables-org.el"
         (file-name-directory (or load-file-name buffer-file-name)))
        nil t))

(defvar sp-collec-query-test--table "| a |"
  "What the stubbed block writer inserts.")

(defmacro sp-collec-query-test--with-note (text &rest body)
  "Run BODY in an Org file buffer holding TEXT, saved and unmodified."
  `(let* ((file (make-temp-file "dblock" nil ".org" ,text))
          (buffer (find-file-noselect file)))
     (unwind-protect
         (with-current-buffer buffer
           (cl-letf (((symbol-function 'org-dblock-write:collection-query-table)
                      (lambda (_params) (insert sp-collec-query-test--table))))
             ,@body))
       (kill-buffer buffer)
       (delete-file file))))

(defconst sp-collec-query-test--note
  "* A\n#+BEGIN: collection-query-table :tags (\"x\")\n| a |\n#+END:\n\n#+BEGIN: clocktable\nkeep\n#+END:\n")

(ert-deftest sp-collec-query-test-dblock-same-result-leaves-buffer-unmodified ()
  (sp-collec-query-test--with-note sp-collec-query-test--note
    (let ((sp-collec-query-test--table "| a |"))
      (should-not (sp-collec-query-dblock-update-buffer))
      (should-not (buffer-modified-p)))))

(ert-deftest sp-collec-query-test-dblock-new-result-is-written ()
  (sp-collec-query-test--with-note sp-collec-query-test--note
    (let ((sp-collec-query-test--table "| b |"))
      (should (sp-collec-query-dblock-update-buffer))
      (should (buffer-modified-p))
      (should (string-match-p "| b |" (buffer-string)))
      (should (string-match-p "clocktable\nkeep" (buffer-string))))))

(ert-deftest sp-collec-query-test-dblock-saves-only-when-asked ()
  (sp-collec-query-test--with-note sp-collec-query-test--note
    (let ((sp-collec-query-test--table "| b |"))
      (let ((sp-collec-query-dblock-save t))
        (should (sp-collec-query-dblock-update-buffer))
        (should-not (buffer-modified-p))
        (should (string-match-p "| b |" (with-temp-buffer (insert-file-contents file) (buffer-string))))))))

(ert-deftest sp-collec-query-test-dblock-never-saves-edited-buffer ()
  (sp-collec-query-test--with-note sp-collec-query-test--note
    (let ((sp-collec-query-test--table "| b |")
          (sp-collec-query-dblock-save t))
      (goto-char (point-max))
      (insert "my edit\n")
      (should (sp-collec-query-dblock-update-buffer))
      (should (buffer-modified-p)))))

(ert-deftest sp-collec-query-test-dblock-buffer-without-block-is-skipped ()
  (sp-collec-query-test--with-note "* A\nnothing here\n"
    (should-not (sp-collec-query-dblock-has-block-p))
    (should-not (sp-collec-query-dblock-update-buffer))))

(ert-deftest sp-collec-query-test-dblock-old-block-name-is-updated ()
  (sp-collec-query-test--with-note "* A\n#+BEGIN: vulpea-table\nold\n#+END:\n"
    (let ((sp-collec-query-test--table "| a |"))
      (cl-letf (((symbol-function 'org-dblock-write:vulpea-table)
                 #'org-dblock-write:collection-query-table))
        (should (sp-collec-query-dblock-update-buffer))
        (should (string-match-p "| a |" (buffer-string)))))))

(ert-deftest sp-collec-query-test-dblock-mode-hooks-come-and-go ()
  (sp-collec-query-dblock-auto-mode 1)
  (should (memq #'sp-collec-query-dblock--after-save after-save-hook))
  (sp-collec-query-dblock-auto-mode -1)
  (should-not (memq #'sp-collec-query-dblock--after-save after-save-hook))
  (should-not (memq #'sp-collec-query-dblock--on-open find-file-hook)))

(defvar sp-collec-query-test-bib
  '(("chap1" ("crossref" . "book1"))
    ("chap2" ("crossref" . "book1"))
    ("book1" ("file" . "/lib/book 1.pdf"))
    ("loop1" ("crossref" . "loop2"))
    ("loop2" ("crossref" . "loop1"))
    ("lone" ("crossref" . "missing"))))

(defun citar-get-entry (key) (cdr (assoc key sp-collec-query-test-bib)))

(defun citar-get-files (key)
  (let ((h (make-hash-table :test 'equal)))
    (when (equal key "book1") (puthash key '("/lib/book 1.pdf") h))
    h))

(ert-deftest sp-collec-query-test-crossref-root ()
  (should (equal (sp-collec-query--crossref-root "chap1") "book1"))
  (should (equal (sp-collec-query--crossref-root "book1") "book1"))
  (should (equal (sp-collec-query--crossref-root "lone") "lone"))
  (should (member (sp-collec-query--crossref-root "loop1") '("loop1" "loop2"))))

(ert-deftest sp-collec-query-test-refs-and-pdf-columns ()
  (let ((note '(:title "x" :props (("ROAM_REFS" . "@chap1 @chap2 @book1 @lone https://x.org")))))
    (should (equal (sp-collec-query-cell note :refs)
                   "@chap1 @chap2 @book1 @lone https://x.org"))
    (should (equal (sp-collec-query--citekeys note) '("chap1" "chap2" "book1" "lone")))
    (should (equal (sp-collec-query--root-keys note) '("book1" "lone")))
    (should (equal (sp-collec-query-cell note :pdf)
                   "[[sp-open:/lib/book 1.pdf][book 1.pdf]]"))
    (should (equal (sp-collec-query-cell '(:title "y") :pdf) ""))))

(ert-deftest sp-collec-query-test-devonthink-column ()
  (let ((note '(:title "x" :props (("ROAM_REFS" . "@chap1 @chap2")))))
    (cl-letf (((symbol-function 'sp-collec-query--dt-running-p) (lambda () nil)))
      (should (equal (sp-collec-query-cell note :devonthink) "")))
    (puthash "book 1.pdf" "UUID-1" sp-collec-query--dt-uuids)
    (should (equal (sp-collec-query-cell note :devonthink)
                   "[[x-devonthink-item://UUID-1][x]]"))))

(ert-deftest sp-collec-query-test-devonthink-header-is-short ()
  (should (equal (sp-collec-query-header-label :devonthink) "DT"))
  (should (equal (sp-collec-query-header-label :pdf) "Pdf")))

(ert-deftest sp-collec-query-test-refs-keys-link-to-bibtex ()
  (let ((note '(:title "x" :props (("ROAM_REFS" . "@smith2020 cite:jones2021 https://x.org")))))
    (should (equal (sp-collec-query-display-cell note :refs)
                   "[[sp-bib:smith2020][@smith2020]] [[sp-bib:jones2021][@jones2021]] https://x.org"))
    (should (equal (sp-collec-query-cell note :refs)
                   "@smith2020 cite:jones2021 https://x.org"))))

(ert-deftest sp-collec-query-test-pub-title-links-to-the-note ()
  (let ((note '(:title "x" :id "ID-1" :meta (("pub-title" "A [odd] title")))))
    (should (equal (sp-collec-query-display-cell note "pub-title")
                   "[[id:ID-1][A odd title]]"))
    (should (equal (sp-collec-query-display-cell '(:id "ID-2" :meta nil) "pub-title") ""))))

(ert-deftest sp-collec-query-test-except-prop-leaves-out-authored-works ()
  (let ((spec '(:parent-of "p" :parent-prop "pub-editor" :except-prop "pub-author"))
        (edited-only '(:meta (("pub-editor" "p"))))
        (both '(:meta (("pub-editor" "p") ("pub-author" "p"))))
        (other '(:meta (("pub-editor" "q")))))
    (should (sp-collec-query-note-matches-p edited-only spec))
    (should-not (sp-collec-query-note-matches-p both spec))
    (should-not (sp-collec-query-note-matches-p other spec))
    ;; without :except-prop both match
    (should (sp-collec-query-note-matches-p both (list :parent-of "p" :parent-prop "pub-editor")))))

;;;; :bibtex and :dt-page

(ert-deftest sp-collec-query-test-bibtex-column ()
  (let ((note '(:title "x" :props (("ROAM_REFS" . "@smith2020 cite:jones2021 https://x.org")))))
    (should (equal (sp-collec-query-cell note :bibtex) "@smith2020 @jones2021"))
    (should (equal (sp-collec-query-display-cell note :bibtex)
                   "[[sp-bib:smith2020][@smith2020]] [[sp-bib:jones2021][@jones2021]]"))
    (should (equal (sp-collec-query-cell '(:title "y") :bibtex) ""))
    (should (equal (sp-collec-query-header-label :bibtex) "BibTeX"))))

(ert-deftest sp-collec-query-test-bib-key-at-point ()
  (with-temp-buffer
    (insert (propertize "@k" 'sp-org-link "sp-bib:a b"))
    (goto-char 1)
    (should (equal (sp-collec-query--bib-key-at-point) '(citar-key . "a b"))))
  (with-temp-buffer
    (insert (propertize "x" 'sp-org-link "id:1"))
    (goto-char 1)
    (should-not (sp-collec-query--bib-key-at-point))))

(ert-deftest sp-collec-query-test-dt-page-column ()
  (let ((note '(:title "x" :props (("ROAM_REFS" . "@chap1"))
                :meta (("pub-pages" "pp. 41-60"))))
        (preface '(:title "p" :props (("ROAM_REFS" . "@chap1")) :meta (("pub-pages" "ix-xii")))))
    (puthash "book 1.pdf" "UUID-1" sp-collec-query--dt-uuids)
    (should (equal (sp-collec-query-header-label :dt-page) "DT page"))
    (should (equal (sp-collec-query-cell note :dt-page)
                   "[[x-devonthink-item://UUID-1?page=40][p. 41]]"))
    (should (equal (sp-collec-query-cell preface :dt-page)
                   "[[x-devonthink-item://UUID-1][open]]"))
    (let ((sp-collec-query-dt-page-offset 12))
      (should (equal (sp-collec-query-cell note :dt-page)
                     "[[x-devonthink-item://UUID-1?page=52][p. 41]]")))
    (should (equal (sp-collec-query-cell '(:title "y" :meta (("pub-pages" "3"))) :dt-page) ""))))

(ert-deftest sp-collec-query-test-dt-page-offset-from-parent ()
  (let ((note '(:title "x" :props (("ROAM_REFS" . "@chap1"))
                :meta (("pub-pages" "10") ("bib-parent" "PARENT"))))
        (sp-collec-query-test-db '(("PARENT" . (:title "b" :meta (("pdf-offset" "7")))))))
    (puthash "book 1.pdf" "UUID-1" sp-collec-query--dt-uuids)
    (should (equal (sp-collec-query-cell note :dt-page)
                   "[[x-devonthink-item://UUID-1?page=16][p. 10]]"))))

(ert-deftest sp-collec-query-test-bib-key-at-point-in-org-buffer ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "| [[sp-bib:smith2020][@smith2020]] |")
    (goto-char 8)
    (should (equal (sp-collec-query--bib-key-at-point) '(citar-key . "smith2020")))
    (erase-buffer)
    (insert "[[id:1][x]]")
    (goto-char 5)
    (should-not (sp-collec-query--bib-key-at-point))))

;;;; Check rules

(defun sp-collec-query-test--check (tags parent-tags)
  "The check of a note with TAGS whose parent has PARENT-TAGS (nil: no parent)."
  (let ((sp-collec-query-test-db
         (and parent-tags `(("pid" . (:id "pid" :tags ,parent-tags))))))
    (sp-collec-query-check
     (list :id "n" :tags tags :meta (and parent-tags '(("bib-parent" "pid")))))))

(ert-deftest sp-collec-query-test-check-keeps-book-and-collection-rules ()
  (should (equal (sp-collec-query-test--check '("booksection") '("book")) ""))
  (should (equal (sp-collec-query-test--check '("incollection") '("collection")) ""))
  (should (string-match-p "booksection but the parent is not tagged book"
                          (sp-collec-query-test--check '("booksection") '("collection"))))
  (should (string-match-p "booksection without bib-parent"
                          (sp-collec-query-test--check '("booksection") nil)))
  (should (string-match-p "the parent is a book but this is not tagged booksection"
                          (sp-collec-query-test--check '("text") '("book")))))

(ert-deftest sp-collec-query-test-check-reference-and-encyclopedia ()
  ;; inreference: parent reference or book
  (should (equal (sp-collec-query-test--check '("inreference") '("reference")) ""))
  (should (equal (sp-collec-query-test--check '("inreference") '("book")) ""))
  (should (string-match-p "inreference but the parent is not tagged reference or book"
                          (sp-collec-query-test--check '("inreference") '("collection"))))
  ;; encyclopedia article: parent encyclopedia or collection
  (should (equal (sp-collec-query-test--check '("encyclopedia") '("encyclopedia")) ""))
  (should (equal (sp-collec-query-test--check '("encyclopedia") '("collection")) ""))
  ;; an incollection and an encyclopedia article both fit a collection
  (should (equal (sp-collec-query-test--check '("incollection") '("collection")) ""))
  ;; a note in an encyclopedia must be an encyclopedia article
  (should (string-match-p "the parent is a encyclopedia but this is not tagged encyclopedia"
                          (sp-collec-query-test--check '("text") '("encyclopedia")))))
