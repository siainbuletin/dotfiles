;;; sp-author-notes-bibtex-test.el --- Tests for sp-author-notes-bibtex -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-author-notes-bibtex)

(defvar sp-bibtex-files)

(defun sp-an-bib-test--write (file &rest lines)
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert (string-join lines "\n") "\n")))

(defmacro sp-an-bib-test--with-vault (&rest body)
  "Run BODY with a vault and a .bib file; `create-fn' makes a litnote."
  (declare (indent 0))
  `(let* ((vault (file-name-as-directory (make-temp-file "sp-bib" t)))
          (sp-author-notes-directory vault)
          (sp-author-notes-litnotes-directory (expand-file-name "litnotes/" vault))
          (bib (expand-file-name "refs.bib" vault))
          (sp-bibtex-files (list bib))
          (sp-author-notes-bibtex-create-function
           (lambda (key)
             (sp-an-bib-test--write
              (expand-file-name (format "litnotes/%s.org" key) vault)
              ":PROPERTIES:" (format ":ID: lit-%s" key) ":END:"
              (format "#+title: %s" key) "#+filetags: :litnote:" ""
              "- pub-year :: 2020" "" "* Notes" "text"))))
     (unwind-protect
         (progn
           (sp-an-bib-test--write bib
            "@article{smith2020attention,"
            "  author = {Smith, John and Doe, Jane},"
            "  title = {{Attention} is something},"
            "  year = {2020}}"
            "@book{smith2018other,"
            "  author = \"J. Smith\","
            "  title = {Other},"
            "  year = {2018}}"
            "@article{doe2019covered,"
            "  author = {Doe, Jane}, title = {Covered}, year = {2019}}")
           (sp-an-bib-test--write
            (expand-file-name "p1.org" vault)
            ":PROPERTIES:" ":ID: p-smith" ":END:" "#+title: John Smith" "#+filetags: :person:" "")
           (sp-an-bib-test--write
            (expand-file-name "p2.org" vault)
            ":PROPERTIES:" ":ID: p-doe" ":END:" "#+title: Jane Doe" "#+filetags: :person:" "")
           (sp-an-bib-test--write
            (expand-file-name "litnotes/doe.org" vault)
            ":PROPERTIES:" ":ID: lit-doe" ":REFERENCES: @doe2019covered" ":END:"
            "#+title: Covered" "")
           ,@body)
       (delete-directory vault t))))

(ert-deftest sp-an-bib-test-match ()
  (should (eq 'exact (sp-author-notes-bibtex--match "John Smith" "John Smith")))
  (should (eq 'possible (sp-author-notes-bibtex--match "John Smith" "J. Smith")))
  (should-not (sp-author-notes-bibtex--match "John Smith" "Mary Smith"))
  (should-not (sp-author-notes-bibtex--match "John Smith" "John Smithers")))

(ert-deftest sp-an-bib-test-compute ()
  (sp-an-bib-test--with-vault
    (let* ((groups (sp-author-notes-bibtex--compute))
           (titles (mapcar (lambda (g) (plist-get (car g) :title)) groups)))
      ;; Jane Doe's own entry has a litnote, but she co-wrote the other one.
      (should (equal titles '("John Smith" "Jane Doe")))
      (should (equal (mapcar (lambda (m) (plist-get (car m) :key)) (cdr (cadr groups)))
                     '("smith2020attention")))
      (should (equal (mapcar (lambda (m) (cons (plist-get (car m) :key) (cdr m)))
                             (cdar groups))
                     '(("smith2018other" . possible) ("smith2020attention" . exact)))))))

(ert-deftest sp-an-bib-test-create-and-link ()
  (sp-an-bib-test--with-vault
    (let* ((groups (sp-author-notes-bibtex--compute))
           (person (caar groups))
           (entry (car (nth 1 (cdar groups))))
           (file (sp-author-notes-bibtex--create person entry))
           (text (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (should (string-match-p "^- pub-author :: \\[\\[id:p-smith\\]\\[John Smith\\]\\]$" text))
      (should (< (string-match "pub-year" text) (string-match "pub-author" text)))
      (should (< (string-match "pub-author" text) (string-match "\\* Notes" text)))
      ;; The entry is covered now.
      (should (equal (mapcar (lambda (m) (plist-get (car m) :key)) (cdar (sp-author-notes-bibtex--compute)))
                     '("smith2018other"))))))

(ert-deftest sp-an-bib-test-report ()
  (sp-an-bib-test--with-vault
    (save-window-excursion
      (sp-author-notes-bibtex)
      (with-current-buffer sp-author-notes-bibtex--buffer-name
        (should (string-match-p "John Smith  (2)" (buffer-string)))
        (should (string-match-p "exact +smith2020attention" (buffer-string)))
        (goto-char (point-min))
        (search-forward "smith2020attention")
        (should (plist-get (sp-author-notes-bibtex--at-point) :key))
        (kill-buffer)))))

(provide 'sp-author-notes-bibtex-test)
;;; sp-author-notes-bibtex-test.el ends here
