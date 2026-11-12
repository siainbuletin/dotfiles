;;; sp-devonthink-browse-test.el --- Tests for sp-devonthink-browse -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-devonthink-browse)

(defconst sp-devonthink-browse-test--text
  "U1\t/Inbox/\tsmith-2017-x.pdf\nU2\t/A/\tdup.pdf\nU3\t/B/\tdup.pdf\nbad line\n")

(ert-deftest sp-devonthink-browse-parse ()
  (let ((records (sp-devonthink-browse--parse sp-devonthink-browse-test--text)))
    (should (= (length records) 3))
    (should (equal (plist-get (car records) :location) "/Inbox/"))))

(ert-deftest sp-devonthink-browse-candidates-are-unique ()
  (let* ((records (sp-devonthink-browse--parse sp-devonthink-browse-test--text))
         (cands (sp-devonthink-browse--make-candidates records)))
    (should (equal cands '("smith-2017-x.pdf" "dup.pdf [/A/]" "dup.pdf [/B/]")))
    (should (equal (plist-get (sp-devonthink-browse--record "dup.pdf [/B/]") :uuid) "U3"))
    (should-error (sp-devonthink-browse--record "nope") :type 'user-error)))

(ert-deftest sp-devonthink-browse-table-groups-by-location ()
  (let* ((cands (sp-devonthink-browse--make-candidates
                 (sp-devonthink-browse--parse sp-devonthink-browse-test--text)))
         (table (sp-devonthink-browse--table cands))
         (meta (cdr (funcall table "" nil 'metadata)))
         (group (alist-get 'group-function meta)))
    (should (eq (alist-get 'category meta) 'sp-devonthink-record))
    (should (equal (funcall group "smith-2017-x.pdf" nil) "/Inbox/"))
    (should (equal (funcall group "smith-2017-x.pdf" t) "smith-2017-x.pdf"))))

(ert-deftest sp-devonthink-browse-record-open-and-link ()
  (sp-devonthink-browse--make-candidates
   (sp-devonthink-browse--parse sp-devonthink-browse-test--text))
  (let (opened)
    (cl-letf (((symbol-function 'sp-reading--open-url) (lambda (url) (setq opened url))))
      (sp-devonthink-record-open "smith-2017-x.pdf"))
    (should (equal opened "x-devonthink-item://U1")))
  (with-temp-buffer
    (cl-letf (((symbol-function 'sp-devonthink--uuid-p) (lambda (_) t)))
      (sp-devonthink-record-link "smith-2017-x.pdf"))
    (should (equal (buffer-string) "[[devonthink:U1][smith-2017-x]]"))))

(ert-deftest sp-devonthink-browse-record-tag-multiple ()
  (sp-devonthink-browse--make-candidates
   (sp-devonthink-browse--parse sp-devonthink-browse-test--text))
  (let (args)
    (cl-letf (((symbol-function 'sp-devonthink-read-tags) (lambda (&rest _) '("t1")))
              ((symbol-function 'sp-devonthink-apply-tags)
               (lambda (uuids tags mode) (setq args (list uuids tags mode)) 2)))
      (sp-devonthink-record-tag '("dup.pdf [/A/]" "dup.pdf [/B/]")))
    (should (equal args '(("U2" "U3") ("t1") add)))))

(ert-deftest sp-devonthink-browse-record-pdf-needs-a-file ()
  (sp-devonthink-browse--make-candidates
   (sp-devonthink-browse--parse sp-devonthink-browse-test--text))
  (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "/no/such/file.pdf")))
    (should-error (sp-devonthink-record-pdf "smith-2017-x.pdf") :type 'user-error)))

(provide 'sp-devonthink-browse-test)
;;; sp-devonthink-browse-test.el ends here
