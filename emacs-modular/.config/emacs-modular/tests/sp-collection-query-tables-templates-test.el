;;; sp-collection-query-tables-templates-test.el --- Tests for view templates and bib-parent checks -*- lexical-binding: t; -*-

;; Batch run with stubbed Vulpea:
;;   emacs -Q --batch -l tests/sp-collection-query-tables-templates-test.el -f ert-run-tests-batch-and-exit
;; Not tested: the interactive commands that read a dynamic block in a note.

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)

(defvar sp-collec-query-templ-test-db nil)
(defvar sp-etc-dir (make-temp-file "sp-etc" t))

(provide 'vulpea)
(provide 'sp-org-id-link)
(defun vulpea-note-title (note) (plist-get note :title))
(defun vulpea-note-id (note) (plist-get note :id))
(defun vulpea-note-properties (note) (plist-get note :props))
(defun vulpea-note-tags (note) (plist-get note :tags))
(defun vulpea-db-get-by-id (id) (cdr (assoc id sp-collec-query-templ-test-db)))
(defun vulpea-db-query (pred) (seq-filter pred (mapcar #'cdr sp-collec-query-templ-test-db)))
(defun vulpea-note-meta-get-list (note key &optional _type) (cdr (assoc key (plist-get note :meta))))

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (dolist (f '("core" "views" "org"))
    (load (expand-file-name (format "../libraries/modules/funct/sp-collection-query-tables-%s.el" f) dir) nil t)))

(setq sp-collec-query-templ-test-db
      (mapcar (lambda (n) (cons (plist-get n :id) n))
              '((:id "book" :title "Book" :tags ("book"))
                (:id "coll" :title "Coll" :tags ("collection"))
                (:id "ok" :title "Ok" :tags ("booksection") :meta (("bib-parent" "book") ("pub-pages" "5")))
                (:id "untagged" :title "Untagged" :tags ("note") :meta (("bib-parent" "book") ("pub-pages" "1")))
                (:id "wrong" :title "Wrong" :tags ("booksection") :meta (("bib-parent" "coll")))
                (:id "orphan" :title "Orphan" :tags ("incollection"))
                (:id "art" :title "Art" :tags ("incollection") :meta (("bib-parent" "coll")))
                (:id "plain" :title "Plain" :tags ("note")))))

(defun sp-collec-query-templ-test--check (id)
  (sp-collec-query-check (vulpea-db-get-by-id id)))

(ert-deftest sp-collec-query-templ-test-check ()
  (should (equal (sp-collec-query-templ-test--check "ok") ""))
  (should (equal (sp-collec-query-templ-test--check "art") ""))
  (should (equal (sp-collec-query-templ-test--check "plain") ""))
  (should (string-match-p "not tagged booksection" (sp-collec-query-templ-test--check "untagged")))
  (should (string-match-p "parent is not tagged book" (sp-collec-query-templ-test--check "wrong")))
  (should (string-match-p "without bib-parent" (sp-collec-query-templ-test--check "orphan"))))

(ert-deftest sp-collec-query-templ-test-flagged-filter ()
  (let ((titles (mapcar #'vulpea-note-title
                        (sp-collec-query-query
                         (alist-get "bib-parent-mismatches" sp-collec-query-views-defaults
                                    nil nil #'string=)))))
    (should (equal (sort (copy-sequence titles) #'string<) '("Untagged" "Wrong")))))

(ert-deftest sp-collec-query-templ-test-book-sections-view-flags-untagged ()
  (let* ((spec (plist-put (copy-tree (sp-collec-query-views-get "book-sections"))
                          :parent-of "book"))
         (rows (sp-collec-query-query spec)))
    (should (equal (mapcar #'vulpea-note-title rows) '("Untagged" "Ok")))
    (should (string-empty-p (sp-collec-query-cell (cadr rows) :check)))
    (should-not (string-empty-p (sp-collec-query-cell (car rows) :check)))))

(ert-deftest sp-collec-query-templ-test-expand-view ()
  (let ((spec (sp-collec-query-expand-view '(:name "collection-query-table" :view "book-sections" :parent-of "x"))))
    (should (equal (plist-get spec :parent-of) "x"))
    (should (eq (plist-get spec :sort-by) :pages))
    (should-not (plist-member spec :view)))
  (should (equal (sp-collec-query-expand-view '(:tags ("a"))) '(:tags ("a"))))
  (should-error (sp-collec-query-expand-view '(:view "nope")) :type 'user-error))

(ert-deftest sp-collec-query-templ-test-saved-view-wins-and-persists ()
  (setq sp-collec-query-views nil sp-collec-query-views--loaded t)
  (should (member "book-sections" (sp-collec-query-views-names)))
  (sp-collec-query-views-put "mine" '(:tags ("x") :columns (:title)))
  (should (equal (plist-get (sp-collec-query-views-get "mine") :tags) '("x")))
  (sp-collec-query-views-put "book-sections" '(:tags ("y")))
  (should (equal (plist-get (sp-collec-query-views-get "book-sections") :tags) '("y")))
  (setq sp-collec-query-views--loaded nil)
  (should (equal (plist-get (sp-collec-query-views-get "mine") :tags) '("x")))
  (should-error (sp-collec-query-view-delete "collection-articles") :type 'user-error))

;;; sp-collection-query-tables-templates-test.el ends here
