;;; sp-pdf-reader-test.el --- Tests for sp-pdf-reader -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(require 'sp-pdf-reader)

(defmacro sp-pdf-reader-test--with-ready (ready &rest body)
  "Run BODY with `sp-pdf-reader-ready-p' returning READY and the reader stubbed."
  (declare (indent 1))
  `(let ((file (make-temp-file "sp-pdf" nil ".pdf")) calls)
     (unwind-protect
         (cl-letf (((symbol-function 'sp-pdf-reader-ready-p) (lambda () ,ready))
                   ((symbol-function 'emureader-open-doc) (lambda (f) (push (list 'open f) calls)))
                   ((symbol-function 'emureader-goto-page) (lambda (n) (push (list 'page n) calls)))
                   ((symbol-function 'find-file) (lambda (f) (push (list 'find f) calls))))
           ,@body)
       (delete-file file))))

(ert-deftest sp-pdf-open-uses-emureader-and-goes-to-page ()
  (sp-pdf-reader-test--with-ready t
    (sp-pdf-open file 7)
    (should (equal (reverse calls) (list (list 'open file) '(page 7))))))

(ert-deftest sp-pdf-open-without-page-does-not-jump ()
  (sp-pdf-reader-test--with-ready t
    (sp-pdf-open file)
    (should (equal calls (list (list 'open file))))))

(ert-deftest sp-pdf-open-falls-back-to-find-file ()
  (sp-pdf-reader-test--with-ready nil
    (sp-pdf-open file 7)
    (should (equal calls (list (list 'find file))))))

(ert-deftest sp-pdf-open-missing-file ()
  (should-error (sp-pdf-open "/nonexistent/x.pdf") :type 'user-error))
