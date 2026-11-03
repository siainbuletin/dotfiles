;;; sp-bibprocess-lint-test.el --- Tests for the .bib lint of sp-bibprocess -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'bibtex)
(require 'sp-async-work)
(require 'sp-author-notes-bibtex)

;; sp-bibprocess needs the whole configuration; load only the lint part.
(defvar sp-bibprocess-lint-test--lint-file
  (expand-file-name "../libraries/modules/academic/sp-bibprocess.el"
                    (file-name-directory (or load-file-name buffer-file-name))))
(with-temp-buffer
  (insert-file-contents sp-bibprocess-lint-test--lint-file)
  (goto-char (point-min))
  (let ((start (search-forward ";;;; Linting the .bib files"))
        (end (progn (search-forward "(provide 'sp-bibprocess)") (match-beginning 0))))
    (eval (read (concat "(progn " (buffer-substring start end) ")")) t)))

(ert-deftest sp-bibtex-lint-test-canonical-name ()
  (should (equal "Smith, John" (sp-bibtex-canonical-name "John Smith")))
  (should (equal "Smith, John" (sp-bibtex-canonical-name "Smith,John")))
  (should (equal "Smith, J. M." (sp-bibtex-canonical-name "J. M. Smith")))
  (should (equal "van Gogh, Vincent" (sp-bibtex-canonical-name "Vincent van Gogh")))
  (should (equal "{Big Corp}" (sp-bibtex-canonical-name "{Big Corp}")))
  (should (equal "others" (sp-bibtex-canonical-name "others")))
  (should (equal "Plato" (sp-bibtex-canonical-name "Plato")))
  (should (equal "Smith, Jr, John" (sp-bibtex-canonical-name "Smith, Jr, John"))))

(ert-deftest sp-bibtex-lint-test-canonical-names ()
  (should (equal "Smith, John and Doe, Jane and {A and B Inc}"
                 (sp-bibtex-canonical-names "John Smith and Jane Doe and {A and B Inc}"))))

(ert-deftest sp-bibtex-lint-test-fields ()
  (let* ((fields '(("year" . "{2020}") ("title" . "{T}") ("author" . "{John Smith and Doe, Jane}")))
         (linted (sp-bibtex--lint-fields fields nil)))
    (should (equal (mapcar #'car (car linted)) '("author" "title" "year")))
    (should (equal (cdr (assoc "author" (car linted))) "{Smith, John and Doe, Jane}"))
    (should (= 2 (length (cdr linted))))))

(ert-deftest sp-bibtex-lint-test-suggestion ()
  (let ((people (sp-bibtex--make-people '("John Smith" "Jane Doe"))))
    (should (equal "Smith, John" (sp-bibtex--suggestion "Smyth, John" people)))
    (should-not (sp-bibtex--suggestion "Smith, John" people))
    (should-not (sp-bibtex--suggestion "Nobody, Else" people))))

(ert-deftest sp-bibtex-lint-test-apply ()
  (let* ((dir (file-name-as-directory (make-temp-file "sp-bib" t)))
         (file (expand-file-name "a.bib" dir))
         (sp-bibtex-files (list file))
         (sp-bibtex-lint-backup-directory (expand-file-name "bk/" dir))
         (sp-async-work-synchronous t)
         (sp-bibtex--people-cache (cons (float-time) (sp-bibtex--make-people nil))))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "@article{a1,\n  year = {2020},\n  author = {John Smith and Jane Doe},\n  title = {T}}\n\n"
                    "@article{a2,\n  % keep me\n  year = {2020},\n  author = {John Smith},\n  title = {T}}\n\n"
                    "@article{a1,\n  author = {Doe, Jane},\n  title = {Dup}}\n"))
          (let (results)
            (sp-bibtex-lint--job "t" (list file) nil (lambda (r) (setq results r)))
            (should (= 3 (length results))))
          (sp-bibtex-lint--job "t" (list file) t #'ignore)
          (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
            (should (string-match-p "author = {Smith, John and Doe, Jane}" text))
            (should (< (string-match "author = {Smith" text) (string-match "year = {2020}" text)))
            ;; The entry with a comment is untouched.
            (should (string-match-p "% keep me\n  year = {2020},\n  author = {John Smith}" text)))
          (should (directory-files-recursively (expand-file-name "bk/" dir) "a\\.bib\\'")))
      (delete-directory dir t))))

(ert-deftest sp-bibtex-lint-test-capf ()
  (let ((sp-bibtex--people-cache (cons (float-time) (sp-bibtex--make-people '("John Smith" "Jane Doe")))))
    (with-temp-buffer
      (insert "@article{a,\n  author = {Smith, John and Do")
      (let ((capf (sp-bibtex-author-capf)))
        (should capf)
        (should (equal "Do" (buffer-substring (nth 0 capf) (nth 1 capf))))
        (should (equal '("Doe, Jane") (all-completions "Do" (nth 2 capf))))))
    (with-temp-buffer
      (insert "@article{a,\n  title = {Do")
      (should-not (sp-bibtex-author-capf)))))

(provide 'sp-bibprocess-lint-test)
;;; sp-bibprocess-lint-test.el ends here
