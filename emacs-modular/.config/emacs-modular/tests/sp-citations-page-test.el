;;; sp-citations-page-test.el --- Citation with a page -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'org)
(let ((file (expand-file-name "../libraries/modules/academic/sp-citations.el"
                              (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (let ((form (read (current-buffer))))
            (when (and (memq (car-safe form) '(defun))
                       (string-match-p "\\`sp-citations\\(-first-page\\|-format-locator\\|--cite-text\\|--citation-end\\|--ask-page\\|-insert-with-page\\)\\'"
                                       (symbol-name (cadr form))))
              (eval form t))))
      (end-of-file nil))))

(ert-deftest sp-citations-first-page-takes-the-first ()
  (should (equal (sp-citations-first-page "12--30") "12"))
  (should (equal (sp-citations-first-page " 12-30") "12"))
  (should (equal (sp-citations-first-page "12, 15") "12"))
  (should (equal (sp-citations-first-page "S12--S20") "S12"))
  (should (equal (sp-citations-first-page "xii") "xii"))
  (should (equal (sp-citations-first-page "{12--30}") "12"))
  (should-not (sp-citations-first-page nil))
  (should-not (sp-citations-first-page ""))
  (should-not (sp-citations-first-page "--")))

(ert-deftest sp-citations-format-locator-cases ()
  (should-not (sp-citations-format-locator ""))
  (should-not (sp-citations-format-locator "  "))
  (should-not (sp-citations-format-locator nil))
  (should (equal (sp-citations-format-locator "12") "p. 12"))
  (should (equal (sp-citations-format-locator " 12 ") "p. 12"))
  (should (equal (sp-citations-format-locator "12-14") "pp. 12-14"))
  (should (equal (sp-citations-format-locator "12--14") "pp. 12-14"))
  (should (equal (sp-citations-format-locator "12 – 14") "pp. 12-14"))
  (should (equal (sp-citations-format-locator "p. 12") "p. 12"))
  (should (equal (sp-citations-format-locator "ch. 3") "ch. 3")))

(ert-deftest sp-citations-cite-text-with-and-without-locator ()
  (should (equal (sp-citations--cite-text "key" "p. 3") "@key p. 3"))
  (should (equal (sp-citations--cite-text "key" nil) "@key")))

(defun sp-citations-page-test--run (initial keys answers &optional point-at)
  "Run the command in an Org buffer holding INITIAL; return the buffer text.
KEYS are what the selection gives, ANSWERS the replies to the page prompts, and
POINT-AT a string after which point is put (the end of the buffer when nil).
The pages field of every key is \"20--30\"."
  (let (prompts)
    (with-temp-buffer
      (org-mode)
      (insert initial)
      (when point-at
        (goto-char (point-min))
        (search-forward point-at))
      (cl-letf (((symbol-function 'citar-select-refs) (lambda (&rest _) keys))
                ((symbol-function 'citar-get-value) (lambda (_field _key) "20--30"))
                ((symbol-function 'read-string)
                 (lambda (prompt &optional initial-input &rest _)
                   (push (cons prompt initial-input) prompts)
                   (pop answers))))
        (sp-citations-insert-with-page))
      (list (buffer-string) (nreverse prompts)))))

(ert-deftest sp-citations-insert-with-page-one-key ()
  (let ((r (sp-citations-page-test--run "See " '("smith2020") '("25"))))
    (should (equal (car r) "See [cite:@smith2020 p. 25]"))
    ;; The prompt starts with the first page of the pages field.
    (should (equal (cdr (car (cadr r))) "20"))
    (should (string-match-p "smith2020" (car (car (cadr r)))))))

(ert-deftest sp-citations-insert-with-page-empty-answer-is-no-page ()
  (should (equal (car (sp-citations-page-test--run "" '("smith2020") '("")))
                 "[cite:@smith2020]")))

(ert-deftest sp-citations-insert-with-page-several-keys ()
  (should (equal (car (sp-citations-page-test--run "" '("a" "b") '("3" "")))
                 "[cite:@a p. 3; @b]")))

(ert-deftest sp-citations-insert-with-page-joins-an-existing-citation ()
  (should (equal (car (sp-citations-page-test--run "x [cite:@old] y" '("new") '("7") "[cite:@old"))
                 "x [cite:@old; @new p. 7] y")))

(ert-deftest sp-citations-insert-with-page-outside-a-citation-after-one ()
  (should (equal (car (sp-citations-page-test--run "[cite:@old] " '("new") '("7")))
                 "[cite:@old] [cite:@new p. 7]")))

(ert-deftest sp-citations-insert-with-page-only-in-org ()
  (with-temp-buffer
    (fundamental-mode)
    (should-error (sp-citations-insert-with-page) :type 'user-error)))

(ert-deftest sp-citations-insert-with-page-no-reference ()
  (with-temp-buffer
    (org-mode)
    (cl-letf (((symbol-function 'citar-select-refs) (lambda (&rest _) nil)))
      (should-error (sp-citations-insert-with-page) :type 'user-error))))

(provide 'sp-citations-page-test)
