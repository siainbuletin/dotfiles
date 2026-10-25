;;; sp-org-tag-lint-test.el --- Tests for sp-org-tag-lint -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-org-tag-lint)

(defun sp-org-tag-lint-test--text (&rest lines)
  "LINES joined, with a final newline."
  (concat (string-join lines "\n") "\n"))

(defun sp-org-tag-lint-test--scan (&rest lines)
  "Scan LINES as a buffer."
  (with-temp-buffer
    (insert (apply #'sp-org-tag-lint-test--text lines))
    (sp-org-tag-lint--scan)))

(defmacro sp-org-tag-lint-test--with-registry (&rest body)
  "Run BODY with a temporary copy of the registry and the tag lists restored after."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sp-tag-test" t))
          (copy (expand-file-name "sp-org-tag-registry.el" dir))
          (sp-org-tag-lint-registry-file copy)
          (org-tag-persistent-alist org-tag-persistent-alist)
          (org-tag-alist '(("@home" . ?H))))
     (unwind-protect
         (progn
           (with-temp-file copy
             (insert "(setq org-tag-persistent-alist\n      '((\"person\")\n        (\"album\")\n"
                     "        " sp-org-tag-lint--sentinel "\n        ))\n"))
           (load-file copy)
           ,@body)
       (delete-directory dir t))))

(ert-deftest sp-org-tag-lint-test-scan-filetags ()
  (should (equal (sp-org-tag-lint-test--scan "#+title: A" "#+filetags: :person:album:")
                 '(t ("person" . 2) ("album" . 2))))
  (should (equal (sp-org-tag-lint-test--scan "#+FILETAGS: person album")
                 '(t ("person" . 1) ("album" . 1))))
  (should (equal (sp-org-tag-lint-test--scan "#+title: A") '(nil))))

(ert-deftest sp-org-tag-lint-test-scan-headings ()
  (should (equal (sp-org-tag-lint-test--scan
                  "#+title: A" "* TODO Write it :@home:deep:" "** Plain" "* :solo:")
                 '(nil ("@home" . 2) ("deep" . 2) ("solo" . 4)))))

(ert-deftest sp-org-tag-lint-test-scan-skips-blocks ()
  (should (equal (sp-org-tag-lint-test--scan
                  "#+begin_src org" "* Example :notag:" "#+end_src" "* Real :tag:")
                 '(nil ("tag" . 4)))))

(ert-deftest sp-org-tag-lint-test-closest ()
  (let ((tags '("person" "album" "project")))
    (should (equal (sp-org-tag-lint--closest "perosn" tags) "person"))
    (should (equal (sp-org-tag-lint--closest "Album" tags) "album"))
    (should-not (sp-org-tag-lint--closest "zebra" tags))))

(ert-deftest sp-org-tag-lint-test-registered-tags ()
  (let ((org-tag-alist '(:startgroup ("@home" . ?H) :endgroup ("deep" . ?d)))
        (org-tag-persistent-alist '(("person") "album")))
    (should (equal (sp-org-tag-lint-registered-tags)
                   '("@home" "deep" "person" "album")))))

(ert-deftest sp-org-tag-lint-test-run ()
  (sp-org-tag-lint-test--with-registry
    (let* ((dir (file-name-directory copy))
           (a (expand-file-name "a.org" dir))
           (b (expand-file-name "b.org" dir)))
      (with-temp-file a
        (insert (sp-org-tag-lint-test--text "#+filetags: :person:perosn:" "* Task :@home:oops:")))
      (with-temp-file b
        (insert (sp-org-tag-lint-test--text "#+title: untagged")))
      (let ((result (sp-org-tag-lint--run (list a b))))
        (should (equal (plist-get result :files) 2))
        (should (equal (plist-get result :unknown)
                       `(("oops" (,a . 2)) ("perosn" (,a . 1)))))
        (should (equal (plist-get result :untagged) (list b)))))))

(ert-deftest sp-org-tag-lint-test-add ()
  (sp-org-tag-lint-test--with-registry
    (should (equal (sp-org-tag-add "genre") "genre"))
    (should (member "genre" (sp-org-tag-lint-note-tags)))
    (with-temp-buffer
      (insert-file-contents copy)
      (should (search-forward "(\"genre\")" nil t))
      (should (search-forward sp-org-tag-lint--sentinel nil t)))
    (should-error (sp-org-tag-add "genre") :type 'user-error)
    (should-error (sp-org-tag-add "not a tag") :type 'user-error)))

(ert-deftest sp-org-tag-lint-test-add-similar-asks ()
  (sp-org-tag-lint-test--with-registry
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
      (should-error (sp-org-tag-add "perosn") :type 'user-error)
      (should-not (member "perosn" (sp-org-tag-lint-note-tags))))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (should (equal (sp-org-tag-add "perosn") "perosn"))
      (should (member "perosn" (sp-org-tag-lint-note-tags))))))

(ert-deftest sp-org-tag-lint-test-read-note-tags ()
  (sp-org-tag-lint-test--with-registry
    (cl-letf (((symbol-function 'completing-read-multiple)
               (lambda (&rest _) '("person" "" "person" "newtag")))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (should (equal (sp-org-tag-read-note-tags) '("person" "newtag")))
      (should (member "newtag" (sp-org-tag-lint-note-tags))))))

(ert-deftest sp-org-tag-lint-test-read-note-tags-declined ()
  (sp-org-tag-lint-test--with-registry
    (let ((answers (list '("unknown") '("album"))))
      (cl-letf (((symbol-function 'completing-read-multiple)
                 (lambda (&rest _) (pop answers)))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
                ((symbol-function 'sit-for) #'ignore))
        (should (equal (sp-org-tag-read-note-tags) '("album")))
        (should-not (member "unknown" (sp-org-tag-lint-note-tags)))))))

(provide 'sp-org-tag-lint-test)
;;; sp-org-tag-lint-test.el ends here
