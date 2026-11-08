;;; sp-collection-query-tables-book-test.el --- Tests for book section tables -*- lexical-binding: t; -*-

;; Run in batch with stubbed Vulpea:
;;   emacs -Q --batch -l tests/sp-collection-query-tables-book-test.el -f ert-run-tests-batch-and-exit
;; Not tested here: the vulpea-ui widget (needs vui and a sidebar).

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)

(defvar sp-collec-query-book-test-db nil
  "Alist of (ID . NOTE) the stubbed database holds.")

(provide 'vulpea)
(provide 'sp-org-id-link)
(defun vulpea-note-title (note) (plist-get note :title))
(defun vulpea-note-id (note) (plist-get note :id))
(defun vulpea-note-properties (note) (plist-get note :props))
(defun vulpea-note-tags (note) (plist-get note :tags))
(defun vulpea-db-get-by-id (id) (cdr (assoc id sp-collec-query-book-test-db)))
(defun vulpea-db-query (pred) (seq-filter pred (mapcar #'cdr sp-collec-query-book-test-db)))
(defun vulpea-note-meta-get-list (note key &optional _type)
  (cdr (assoc key (plist-get note :meta))))

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (load (expand-file-name "../libraries/modules/funct/sp-collection-query-tables-core.el" dir) nil t)
  (load (expand-file-name "../libraries/modules/funct/sp-collection-query-tables-book.el" dir) nil t))

(setq sp-collec-query-book-test-db
      (mapcar (lambda (n) (cons (plist-get n :id) n))
              '((:id "book" :title "The Book" :tags ("book"))
                (:id "c3" :title "Three" :tags ("booksection")
                     :meta (("bib-parent" "book") ("pub-pages" "pp. 100-120")))
                (:id "c1" :title "One" :tags ("booksection")
                     :meta (("bib-parent" "book") ("pub-pages" "9-30")))
                (:id "pref" :title "Preface" :tags ("booksection")
                     :meta (("bib-parent" "book") ("pub-pages" "ix-xii")))
                (:id "c2" :title "Two" :tags ("booksection")
                     :meta (("bib-parent" "book") ("pub-pages" "31-99")))
                (:id "other" :title "Elsewhere" :tags ("booksection")
                     :meta (("bib-parent" "nobook") ("pub-pages" "1-2")))
                (:id "loose" :title "Loose" :tags ("note")))))

(defun sp-collec-query-book-test--titles (notes) (mapcar #'vulpea-note-title notes))

(ert-deftest sp-collec-query-book-test-first-page ()
  (should (= (sp-collec-query-first-page "pp. 12-34") 12))
  (should (= (sp-collec-query-first-page "9") 9))
  (should-not (sp-collec-query-first-page "ix-xii"))
  (should-not (sp-collec-query-first-page nil)))

(ert-deftest sp-collec-query-book-test-columns ()
  (let ((note (vulpea-db-get-by-id "c3")))
    (should (equal (sp-collec-query-cell note :pages) "pp. 100-120"))
    (should (equal (sp-collec-query-cell note :page) "100"))
    (should (equal (sp-collec-query-cell (vulpea-db-get-by-id "pref") :page) ""))))

(ert-deftest sp-collec-query-book-test-sections-in-page-order ()
  (let ((book (vulpea-db-get-by-id "book")))
    (should (equal (sp-collec-query-book-test--titles
                    (sp-collec-query-book-sections book))
                   '("One" "Two" "Three" "Preface")))))

(ert-deftest sp-collec-query-book-test-root ()
  (should (eq (sp-collec-query-book-root (vulpea-db-get-by-id "book"))
              (vulpea-db-get-by-id "book")))
  (should (equal (vulpea-note-id (sp-collec-query-book-root (vulpea-db-get-by-id "c2")))
                 "book"))
  (should-not (sp-collec-query-book-root (vulpea-db-get-by-id "other")))
  (should-not (sp-collec-query-book-root (vulpea-db-get-by-id "loose")))
  (should-not (sp-collec-query-book-root nil)))

(ert-deftest sp-collec-query-book-test-position ()
  (let ((pos (sp-collec-query-book-position (vulpea-db-get-by-id "c2"))))
    (should (= (plist-get pos :index) 1))
    (should (equal (vulpea-note-title (plist-get pos :previous)) "One"))
    (should (equal (vulpea-note-title (plist-get pos :next)) "Three")))
  (let ((pos (sp-collec-query-book-position (vulpea-db-get-by-id "c1"))))
    (should (= (plist-get pos :index) 0))
    (should-not (plist-get pos :previous)))
  (let ((pos (sp-collec-query-book-position (vulpea-db-get-by-id "book"))))
    (should-not (plist-get pos :index))
    (should (= (length (plist-get pos :sections)) 4)))
  (should-not (sp-collec-query-book-position (vulpea-db-get-by-id "loose"))))

(ert-deftest sp-collec-query-book-test-spec ()
  (let ((spec (sp-collec-query-book-spec (vulpea-db-get-by-id "book"))))
    (should (equal (plist-get spec :parent-of) "book"))
    (should (equal (plist-get spec :parent-prop) "bib-parent"))
    (should (eq (plist-get spec :sort-by) :page))))

;;; sp-collection-query-tables-book-test.el ends here
