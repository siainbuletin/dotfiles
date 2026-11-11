;;; sp-vulpea-meta-order-test.el --- Tests for sp-vulpea-meta-order -*- lexical-binding: t; -*-

(require 'ert)
(unless (featurep 'vulpea) (provide 'vulpea))
(unless (fboundp 'vulpea-db-query) (defun vulpea-db-query (&rest _) nil))
(require 'sp-vulpea-meta-order)

(defconst sp-vulpea-meta-order-test--note
  ":PROPERTIES:
:ID: n1
:END:
#+title: A note
#+filetags: :x:

- read-status :: 02
- pub-year :: 2014
- bib-project :: [[id:p][Thesis]]
- pub-author :: [[id:a][A]], [[id:b][B]]
- pub-year :: 2015

Text with - a :: b in it.

* Heading
- zzz :: stays
- aaa :: stays
")

(ert-deftest sp-vulpea-meta-order-keys ()
  (should (equal (sp-vulpea-meta-order-keys '("b" "C" "a" "b"))
                 '("a" "b" "b" "C")))
  (should (sp-vulpea-meta-order-sorted-p '("a" "b" "b")))
  (should-not (sp-vulpea-meta-order-sorted-p '("b" "a")))
  (should (sp-vulpea-meta-order-sorted-p nil)))

(ert-deftest sp-vulpea-meta-order-string-only-touches-the-list ()
  (let ((out (sp-vulpea-meta-order-string sp-vulpea-meta-order-test--note)))
    (should (equal out
                   ":PROPERTIES:
:ID: n1
:END:
#+title: A note
#+filetags: :x:

- bib-project :: [[id:p][Thesis]]
- pub-author :: [[id:a][A]], [[id:b][B]]
- pub-year :: 2014
- pub-year :: 2015
- read-status :: 02

Text with - a :: b in it.

* Heading
- zzz :: stays
- aaa :: stays
"))))

(ert-deftest sp-vulpea-meta-order-is-idempotent ()
  (let ((once (sp-vulpea-meta-order-string sp-vulpea-meta-order-test--note)))
    (should (equal once (sp-vulpea-meta-order-string once)))
    (with-temp-buffer
      (insert once)
      (set-buffer-modified-p nil)
      (should-not (sp-vulpea-meta-order-buffer))
      (should-not (buffer-modified-p)))))

(ert-deftest sp-vulpea-meta-order-keeps-continuation-lines ()
  (should (equal (sp-vulpea-meta-order-string
                  "#+title: x\n\n- b :: one\n  wrapped\n  - nested\n- a :: two\n\nafter\n")
                 "#+title: x\n\n- a :: two\n- b :: one\n  wrapped\n  - nested\n\nafter\n")))

(ert-deftest sp-vulpea-meta-order-edge-cases ()
  ;; no meta list, a note that ends right after the list, and a plain bullet list
  (should (equal (sp-vulpea-meta-order-string "#+title: x\n\ntext\n") "#+title: x\n\ntext\n"))
  (should (equal (sp-vulpea-meta-order-string "- b :: 1\n- a :: 2") "- a :: 2\n- b :: 1"))
  (should (equal (sp-vulpea-meta-order-string "- c :: 1\n- plain\n- b :: 1\n- a :: 2\n")
                 "- c :: 1\n- plain\n- b :: 1\n- a :: 2\n"))
  ;; an empty value, and a list below a heading only
  (should (equal (sp-vulpea-meta-order-string "- b ::\n- a :: 1\n") "- a :: 1\n- b ::\n"))
  (should (equal (sp-vulpea-meta-order-string "* H\n- b :: 1\n- a :: 2\n") "* H\n- b :: 1\n- a :: 2\n"))
  ;; a list inside a source block above the real one is skipped
  (should (equal (sp-vulpea-meta-order-string
                  "#+begin_src org\n- z :: 1\n- y :: 2\n#+end_src\n- b :: 1\n- a :: 2\n")
                 "#+begin_src org\n- z :: 1\n- y :: 2\n#+end_src\n- a :: 2\n- b :: 1\n")))

(ert-deftest sp-vulpea-meta-order-pinned-and-case ()
  (let ((sp-vulpea-meta-order-pinned '("parent")))
    (should (equal (sp-vulpea-meta-order-keys '("b" "Parent" "a")) '("Parent" "a" "b"))))
  (should (equal (sp-vulpea-meta-order-keys '("b" "A")) '("A" "b"))))

(defmacro sp-vulpea-meta-order-test--with-notes (&rest body)
  "Run BODY with DIR holding a.org (unordered), b.org (ordered) and c.org (tagged other)."
  `(let* ((dir (make-temp-file "sp-mo" t))
          (sp-vulpea-meta-order-backup-directory (expand-file-name "bak/" dir))
          (a (expand-file-name "a.org" dir))
          (b (expand-file-name "b.org" dir))
          (c (expand-file-name "c.org" dir)))
     (with-temp-file a (insert "#+title: a\n\n- y :: 1\n- x :: 2\n"))
     (with-temp-file b (insert "#+title: b\n\n- x :: 1\n- y :: 2\n"))
     (with-temp-file c (insert "#+title: c\n\n- q :: 1\n- p :: 2\n"))
     (unwind-protect
         (cl-letf (((symbol-function 'vulpea-db-query)
                    (lambda (&rest _)
                      (list (list a 0 '("keep")) (list b 0 '("keep")) (list c 0 '("other"))
                            (list a 1 nil))))
                   ((symbol-function 'vulpea-note-path) #'car)
                   ((symbol-function 'vulpea-note-level) #'cadr)
                   ((symbol-function 'vulpea-note-tags) #'caddr)
                   ((symbol-function 'pop-to-buffer) #'ignore))
           ,@body)
       (when (get-buffer sp-vulpea-meta-order--buffer) (kill-buffer sp-vulpea-meta-order--buffer))
       (delete-directory dir t))))

(defun sp-vulpea-meta-order-test--read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest sp-vulpea-meta-order-dryrun-writes-nothing ()
  (sp-vulpea-meta-order-test--with-notes
    (let ((todo (sp-vulpea-meta-order-dryrun)))
      (should (equal (mapcar (lambda (p) (plist-get p :file)) todo) (list a c)))
      (should (equal (plist-get (car todo) :before) '("y" "x")))
      (should (equal (plist-get (car todo) :after) '("x" "y"))))
    (should (equal (sp-vulpea-meta-order-test--read a) "#+title: a\n\n- y :: 1\n- x :: 2\n"))
    (should-not (file-exists-p sp-vulpea-meta-order-backup-directory))
    (with-current-buffer sp-vulpea-meta-order--buffer
      (should (derived-mode-p 'sp-batch-report-mode))
      (should (string-match-p "2 notes checked\\|3 notes checked" (buffer-string)))
      (should (string-match-p "now: y, x" (buffer-string)))
      (should (string-match-p "new: x, y" (buffer-string))))))

(ert-deftest sp-vulpea-meta-order-filter-by-tag-and-directory ()
  (sp-vulpea-meta-order-test--with-notes
    (should (equal (sp-vulpea-meta-order--files '(:tags ("other"))) (list c)))
    (should (equal (sp-vulpea-meta-order--files (list :directory (expand-file-name "nowhere/" dir))) nil))
    (should (equal (sp-vulpea-meta-order--files (list :directory dir)) (list a b c)))))

(ert-deftest sp-vulpea-meta-order-convert-backs-up-and-writes ()
  (sp-vulpea-meta-order-test--with-notes
    (let (asked)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (p) (setq asked p) t)))
        (let ((results (sp-vulpea-meta-order-convert '(:tags ("keep")))))
          (should asked)
          (should (equal results (list (cons a t))))))
      (should (equal (sp-vulpea-meta-order-test--read a) "#+title: a\n\n- x :: 2\n- y :: 1\n"))
      ;; the note with another tag is outside the filter
      (should (equal (sp-vulpea-meta-order-test--read c) "#+title: c\n\n- q :: 1\n- p :: 2\n"))
      (let ((backup (car (directory-files sp-vulpea-meta-order-backup-directory t "\\`[0-9]"))))
        (should (equal (sp-vulpea-meta-order-test--read (expand-file-name "a.org" backup))
                       "#+title: a\n\n- y :: 1\n- x :: 2\n")))
      ;; nothing is left to do
      (should-not (sp-vulpea-meta-order-convert '(:tags ("keep")))))))

(ert-deftest sp-vulpea-meta-order-convert-declined-writes-nothing ()
  (sp-vulpea-meta-order-test--with-notes
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (should-not (sp-vulpea-meta-order-convert)))
    (should (equal (sp-vulpea-meta-order-test--read a) "#+title: a\n\n- y :: 1\n- x :: 2\n"))
    (should-not (file-exists-p sp-vulpea-meta-order-backup-directory))))

(ert-deftest sp-vulpea-meta-order-convert-skips-unsaved-buffer ()
  (sp-vulpea-meta-order-test--with-notes
    (let ((buf (find-file-noselect a)))
      (unwind-protect
          (progn
            (with-current-buffer buf (goto-char (point-max)) (insert "- z :: 3\n"))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
              (let ((results (sp-vulpea-meta-order-convert '(:tags ("keep")))))
                (should (stringp (cdr (assoc a results))))
                (should (string-match-p "unsaved" (cdr (assoc a results))))))
            (should (equal (sp-vulpea-meta-order-test--read a) "#+title: a\n\n- y :: 1\n- x :: 2\n")))
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))))

(ert-deftest sp-vulpea-meta-order-drop-and-apply ()
  "A dropped note leaves the report and the convert that A runs."
  (sp-vulpea-meta-order-test--with-notes
    (sp-vulpea-meta-order-dryrun)
    (with-current-buffer sp-vulpea-meta-order--buffer
      (goto-char (point-min))
      (re-search-forward "^- \\[\\[file:[^]]*c\\.org")
      (sp-batch-report-drop)
      (should (equal sp-batch-report-excluded (list c)))
      (should (string-match-p "Dropped from the list" (buffer-string)))
      (let (applied)
        (cl-letf (((symbol-function 'sp-vulpea-meta-order-convert)
                   (lambda (&rest args) (setq applied args))))
          (sp-batch-report-apply))
        (should (equal (cadr applied) (list c)))))))

(provide 'sp-vulpea-meta-order-test)
;;; sp-vulpea-meta-order-test.el ends here
