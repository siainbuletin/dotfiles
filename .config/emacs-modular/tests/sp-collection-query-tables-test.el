;;; sp-collection-query-tables-test.el --- Tests for query table sorting  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)

(when noninteractive
  (provide 'vulpea)
  (defun vulpea-note-title (note) (plist-get note :title))
  (defun vulpea-note-meta-get-list (note key) (cdr (assoc key (plist-get note :meta)))))

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

(provide 'sp-collection-query-tables-test)
;;; sp-collection-query-tables-test.el ends here
