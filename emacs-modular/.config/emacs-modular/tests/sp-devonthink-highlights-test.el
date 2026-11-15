;;; sp-devonthink-highlights-test.el --- Tests for sp-devonthink-highlights -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-devonthink-highlights)

(defconst sp-devonthink-highlights-test--uuid "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")

(defconst sp-devonthink-highlights-test--pages
  '((2 "exchange abstraction") (6 "value  form" "the third")))

(ert-deftest sp-devonthink-highlights-parse ()
  (should (equal (sp-devonthink-highlights--parse
                  "[{\"page\": 6, \"highlights\": [\"a\", \"b\"]}]")
                 '((6 "a" "b")))))

(ert-deftest sp-devonthink-highlights-item ()
  (should (equal (sp-devonthink-highlights--item sp-devonthink-highlights-test--uuid "k-2000-a" 6 "two\nlines ")
                 (format "- two lines [[devonthink:%s::6][k-2000-a p. 6]]\n"
                         sp-devonthink-highlights-test--uuid))))

(ert-deftest sp-devonthink-highlights-creates-heading-at-the-end ()
  (with-temp-buffer
    (insert "#+title: T\n\nMy notes.")
    (let ((items (sp-devonthink-highlights--missing
                  sp-devonthink-highlights-test--pages sp-devonthink-highlights-test--uuid "k")))
      (should (= (length items) 3))
      (sp-devonthink-highlights--insert items))
    (should (string-match-p "\\`#\\+title: T\n\nMy notes\\.\n\n\\* Highlights\n- exchange abstraction " (buffer-string)))
    (should (= (length (split-string (buffer-string) "^- " t)) 4))))

(ert-deftest sp-devonthink-highlights-adds-only-new-ones ()
  (with-temp-buffer
    (insert "#+title: T\n* Highlights\n- Exchange  Abstraction (my edit)\n\n* Other\ntext\n")
    (let ((items (sp-devonthink-highlights--missing
                  sp-devonthink-highlights-test--pages sp-devonthink-highlights-test--uuid "k")))
      (should (= (length items) 2))
      (sp-devonthink-highlights--insert items))
    (let ((s (buffer-string)))
      (should (string-match-p "my edit)\n- value form " s))
      (should (string-match-p "the third .*\n\n\\* Other\ntext\n\\'" s)))
    ;; a second run finds nothing new
    (should-not (sp-devonthink-highlights--missing
                 sp-devonthink-highlights-test--pages sp-devonthink-highlights-test--uuid "k"))))

(ert-deftest sp-devonthink-highlights-text-outside-section-does-not-count ()
  (with-temp-buffer
    (insert "* Other\nexchange abstraction\n* Highlights\n")
    (should (= (length (sp-devonthink-highlights--missing
                        '((1 "exchange abstraction")) sp-devonthink-highlights-test--uuid "k"))
               1))))

(ert-deftest sp-devonthink-highlights-import-command ()
  (with-temp-buffer
    (insert (format "#+title: T\n#+devonthink: %s\n" sp-devonthink-highlights-test--uuid))
    (cl-letf (((symbol-function 'sp-devonthink-highlights--fetch)
               (lambda (_) '((6 "value form")))))
      (sp-devonthink-highlights-import)
      (should (string-match-p "\\* Highlights\n- value form \\[\\[devonthink:.*::6\\]" (buffer-string)))
      (let ((before (buffer-string)))
        (sp-devonthink-highlights-import)
        (should (equal before (buffer-string)))))
    (cl-letf (((symbol-function 'sp-devonthink-highlights--fetch) (lambda (_) nil)))
      (sp-devonthink-highlights-import))))

(ert-deftest sp-devonthink-highlights-fetch-needs-a-file ()
  (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "/no/such.pdf")))
    (should-error (sp-devonthink-highlights--fetch "U") :type 'user-error)))

(ert-deftest sp-devonthink-highlights-import-asks-before-using-the-parent ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ROAM_REFS: @child-2001-x\n:END:\n#+title: T\n")
    (let (asked)
      (cl-letf (((symbol-function 'sp-reading-uuid)
                 (lambda (k) (and (equal k "parent-2000-b") sp-devonthink-highlights-test--uuid)))
                ((symbol-function 'citar-get-value)
                 (lambda (field _) (and (eq field 'crossref) "parent-2000-b")))
                ((symbol-function 'sp-devonthink-highlights--fetch) (lambda (_) '((6 "value form"))))
                ((symbol-function 'y-or-n-p) (lambda (p) (setq asked p) nil))
                ((symbol-function 'message) #'ignore))
        (should-error (sp-devonthink-highlights-import) :type 'user-error)
        (should (string-match-p "Import highlights from the record of parent-2000-b" asked))
        (should-not (string-match-p "value form" (buffer-string))))
      (cl-letf (((symbol-function 'sp-reading-uuid)
                 (lambda (k) (and (equal k "parent-2000-b") sp-devonthink-highlights-test--uuid)))
                ((symbol-function 'citar-get-value)
                 (lambda (field _) (and (eq field 'crossref) "parent-2000-b")))
                ((symbol-function 'sp-devonthink-highlights--fetch) (lambda (_) '((6 "value form"))))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'message) #'ignore))
        (sp-devonthink-highlights-import)
        (should (string-match-p "value form \\[\\[devonthink:.*::6\\]" (buffer-string)))))))

(provide 'sp-devonthink-highlights-test)
;;; sp-devonthink-highlights-test.el ends here
