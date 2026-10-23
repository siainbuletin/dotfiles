;;; sp-org-keywords-test.el --- Tests for sp-org-keywords  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)

(load (expand-file-name
       "../libraries/modules/text/sp-org-keywords.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(ert-deftest sp-org-keywords-test-tasks-first ()
  (should (equal (car org-todo-keywords) (car sp-org-keywords-tasks))))

(ert-deftest sp-org-keywords-test-every-use-case-is-joined ()
  (dolist (seq (append sp-org-keywords-tasks sp-org-keywords-legacy
                       sp-org-keywords-trails sp-org-keywords-questions))
    (should (member seq org-todo-keywords))))

(ert-deftest sp-org-keywords-test-done-keywords ()
  (let ((done (sp-org-keywords-done)))
    (dolist (word '("DONE" "CNCL" "CANCELLED" "ANSWERED" "ARCHIVED" "READ"
                    "STABLE" "SKIPPED"))
      (should (member word done)))
    (dolist (word '("TODO" "NEXT" "PROG" "WAIT" "DOING" "WAITING"))
      (should-not (member word done)))
    (should-not (seq-find (lambda (w) (string-match-p "(" w)) done))))
