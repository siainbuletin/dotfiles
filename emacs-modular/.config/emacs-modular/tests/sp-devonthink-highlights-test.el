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

;;;; Links to single annotations

(defvar sp-litdb-python)

(defconst sp-devonthink-highlights-test--json
  "[{\"page\": 2, \"text\": \"first one\", \"note\": \"\", \"created\": \"2026-11-01T10:00:00Z\", \"modified\": null},
    {\"page\": 9, \"text\": \"the newest\\nhighlight\", \"note\": \"check this\", \"created\": \"2026-11-12T08:30:00Z\", \"modified\": null},
    {\"page\": 5, \"text\": \"in between\", \"note\": \"\", \"created\": null, \"modified\": \"2026-11-05T00:00:00Z\"}]")

(defun sp-devonthink-highlights-test--annotations ()
  (sp-devonthink-annotations--parse sp-devonthink-highlights-test--json))

(ert-deftest sp-devonthink-annotations-parse ()
  (let ((all (sp-devonthink-highlights-test--annotations)))
    (should (= (length all) 3))
    (should (equal (plist-get (nth 1 all) :page) 9))
    (should (equal (plist-get (nth 1 all) :note) "check this"))
    (should (null (plist-get (nth 2 all) :created)))
    (should (equal (plist-get (nth 2 all) :modified) "2026-11-05T00:00:00Z"))))

(ert-deftest sp-devonthink-annotations-latest-by-date ()
  (should (equal (plist-get (sp-devonthink-annotations--latest
                             (sp-devonthink-highlights-test--annotations))
                            :page)
                 9))
  ;; the modification date stands in for a missing creation date
  (should (equal (sp-devonthink-annotations--date (nth 2 (sp-devonthink-highlights-test--annotations)))
                 "2026-11-05T00:00:00Z")))

(ert-deftest sp-devonthink-annotations-latest-without-dates-is-last-in-file ()
  (should (equal (plist-get (sp-devonthink-annotations--latest
                             '((:page 1 :text "a") (:page 7 :text "b") (:page 3 :text "c")))
                            :page)
                 3))
  (should-not (sp-devonthink-annotations--latest nil)))

(ert-deftest sp-devonthink-annotations-label ()
  (let ((label (sp-devonthink-annotations--label (nth 1 (sp-devonthink-highlights-test--annotations)))))
    (should (string-match-p "\\`p\\. 9 +2026-11-12  the newest highlight  \\[check this\\]\\'" label)))
  (should (string-match-p "----------" (sp-devonthink-annotations--label '(:page 1 :text "x" :note "")))))

(defmacro sp-devonthink-highlights-test--with-annotations (&rest body)
  "Run BODY with a record for citekey \"k-2000-a\" whose PDF has the test annotations."
  `(cl-letf (((symbol-function 'sp-reading-uuid)
              (lambda (k) (and (equal k "k-2000-a") sp-devonthink-highlights-test--uuid)))
             ((symbol-function 'citar-get-value) (lambda (&rest _) nil))
             ((symbol-function 'sp-devonthink-annotations--fetch)
              (lambda (_) (sp-devonthink-highlights-test--annotations)))
             ((symbol-function 'message) #'ignore))
     ,@body))

(ert-deftest sp-devonthink-annotations-insert-latest ()
  (sp-devonthink-highlights-test--with-annotations
   (with-temp-buffer
     (sp-devonthink-insert-annotation-link "k-2000-a" 'latest)
     (should (equal (buffer-string)
                    (format "[[devonthink:%s::9][k-2000-a p. 9]]" sp-devonthink-highlights-test--uuid))))))

(ert-deftest sp-devonthink-annotations-insert-chosen ()
  (sp-devonthink-highlights-test--with-annotations
   (let (seen)
     (cl-letf (((symbol-function 'completing-read)
                (lambda (_prompt collection &rest _)
                  (setq seen (all-completions "" collection))
                  (nth 2 seen))))
       (with-temp-buffer
         (sp-devonthink-insert-annotation-link "k-2000-a" 'choose)
         (should (equal (buffer-string)
                        (format "[[devonthink:%s::5][k-2000-a p. 5]]" sp-devonthink-highlights-test--uuid)))
         ;; the list keeps the order of the file
         (should (string-match-p "\\`p\\. 2 " (nth 0 seen)))
         (should (string-match-p "\\`p\\. 9 " (nth 1 seen))))))))

(ert-deftest sp-devonthink-annotations-prefix-takes-the-other-mode ()
  (let ((sp-devonthink-annotation-default 'choose))
    (should (eq (sp-devonthink-annotations--mode nil) 'choose))
    (should (eq (sp-devonthink-annotations--mode '(4)) 'latest)))
  (let ((sp-devonthink-annotation-default 'latest))
    (should (eq (sp-devonthink-annotations--mode nil) 'latest))
    (should (eq (sp-devonthink-annotations--mode '(4)) 'choose))))

(ert-deftest sp-devonthink-annotations-chapter-uses-the-parent-record ()
  (let (messages)
   (cl-letf (((symbol-function 'sp-reading-uuid)
             (lambda (k) (and (equal k "book-2000-b") sp-devonthink-highlights-test--uuid)))
            ((symbol-function 'citar-get-value)
             (lambda (field _) (and (eq field 'crossref) "book-2000-b")))
            ((symbol-function 'sp-devonthink-annotations--fetch)
             (lambda (uuid) (should (equal uuid sp-devonthink-highlights-test--uuid))
               (sp-devonthink-highlights-test--annotations)))
            ((symbol-function 'message) (lambda (&rest args) (push (apply #'format args) messages))))
    (progn
      (with-temp-buffer
        (sp-devonthink-insert-annotation-link "chapter-2001-c" 'latest)
        (should (string-match-p (format "devonthink:%s::9\\]\\[chapter-2001-c p. 9" sp-devonthink-highlights-test--uuid)
                                (buffer-string))))
      (should (string-match-p "no record of its own.*book-2000-b" (car messages)))))))

(ert-deftest sp-devonthink-annotations-errors ()
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) nil))
            ((symbol-function 'citar-get-value) (lambda (&rest _) nil)))
    (should-error (sp-devonthink-insert-annotation-link "nope-2000-z" 'latest) :type 'user-error))
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) sp-devonthink-highlights-test--uuid))
            ((symbol-function 'citar-get-value) (lambda (&rest _) nil))
            ((symbol-function 'sp-devonthink-annotations--fetch) (lambda (_) nil)))
    (should-error (sp-devonthink-insert-annotation-link "k-2000-a" 'latest) :type 'user-error)))

(ert-deftest sp-devonthink-annotations-fetch-runs-the-script-with-the-flag ()
  (let (args)
    (cl-letf (((symbol-function 'sp-devonthink-highlights--file) (lambda (_) "/tmp/some.pdf"))
              (features (cons 'sp-litdb features))
              ((symbol-function 'call-process)
               (lambda (program _in dest _display &rest rest)
                 (setq args (cons program rest))
                 (with-current-buffer (car dest) (insert sp-devonthink-highlights-test--json))
                 0)))
      (let ((sp-litdb-python "/py") (sp-devonthink-highlights-script "/tools/h.py"))
        (should (= (length (sp-devonthink-annotations--fetch sp-devonthink-highlights-test--uuid)) 3))
        (should (equal args '("/py" "/tools/h.py" "--annotations" "/tmp/some.pdf")))))))

(ert-deftest sp-devonthink-annotations-keys ()
  (should (eq (keymap-lookup sp-devonthink-map "A") #'sp-devonthink-insert-annotation-link))
  (should (eq (keymap-lookup sp-devonthink-map "L") #'sp-devonthink-insert-latest-annotation-link)))

(provide 'sp-devonthink-highlights-test)
;;; sp-devonthink-highlights-test.el ends here
