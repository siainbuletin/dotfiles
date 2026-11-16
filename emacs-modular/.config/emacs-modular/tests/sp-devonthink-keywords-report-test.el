;;; sp-devonthink-keywords-report-test.el --- Tests for sp-devonthink-keywords-report -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(unless (boundp 'sp-cache-dir) (defvar sp-cache-dir temporary-file-directory))
(unless (boundp 'sp-var-dir) (defvar sp-var-dir temporary-file-directory))
(require 'sp-devonthink-keywords-report)

(defmacro sp-devonthink-keywords-report-test--world (spec &rest body)
  "Run BODY with the litnote text, the base and the writers faked; SPEC is (:note TEXT :synced SYNCED)."
  (declare (indent 1))
  `(let* ((text (plist-get ',spec :note))
          (synced ,(plist-get spec :synced))
          (file (make-temp-file "kwr" nil ".org" (or text "")))
          (sp-devonthink-keywords-litnote t)
          written)
     (unwind-protect
         (cl-letf (((symbol-function 'sp-devonthink-keywords--key-litnote) (lambda (_) file))
                   ((symbol-function 'sp-devonthink-keywords--synced) (lambda (_) synced))
                   ((symbol-function 'sp-reading--osascript) (lambda (s) (push s written) ""))
                   ((symbol-function 'save-buffer) (lambda (&rest _) (push 'save written))))
           ,@body)
       (delete-file file))))

(ert-deftest sp-devonthink-keywords-report-plan-lists-edits-and-writes-nothing ()
  (sp-devonthink-keywords-report-test--world
      (:note "#+title: K\n\n- pub-year :: 2020\n\nKEYWORDS: a\n\n* H\n" :synced '("a"))
    (let ((plan (sp-devonthink-keywords-report--plan "k1" "U1" '("a" "b") '("a" "c"))))
      (should (equal (plist-get plan :merged) '("a" "c" "b")))
      (should (equal (plist-get plan :bib) "+b"))
      (should (equal (plist-get plan :dt) "+c"))
      (should (equal (plist-get plan :note) "+c, +b"))
      (should (eq (plist-get plan :state) 'ok))
      (should-not written))))

(ert-deftest sp-devonthink-keywords-report-plan-nothing-to-change ()
  (sp-devonthink-keywords-report-test--world
      (:note "#+title: K\n\nKEYWORDS: a\n\n* H\n" :synced '("a"))
    (let ((plan (sp-devonthink-keywords-report--plan "k1" "U1" '("a") '("a"))))
      (should-not (sp-devonthink-keywords-report--changed-p plan)))))

(ert-deftest sp-devonthink-keywords-report-plan-flags-an-edited-litnote ()
  (sp-devonthink-keywords-report-test--world
      (:note "#+title: K\n\nKEYWORDS: a, z\n\n* H\n" :synced '("a"))
    (let ((plan (sp-devonthink-keywords-report--plan "k1" "U1" '("a" "b") '("a"))))
      (should (eq (plist-get plan :state) 'flag))
      ;; BibTeX and DEVONthink are still compared with each other; the litnote edit is not merged
      (should (equal (plist-get plan :merged) '("a" "b")))
      (should-not (plist-get plan :note)))))

(ert-deftest sp-devonthink-keywords-report-plan-comma-joined-tag-counts-as-several ()
  (sp-devonthink-keywords-report-test--world
      (:note "#+title: K\n\n* H\n" :synced 'none)
    (let ((plan (sp-devonthink-keywords-report--plan "k1" "U1" '("x,y") 'none)))
      (should (equal (plist-get plan :merged) '("x" "y")))
      (should (eq (plist-get plan :state) 'none)))))

(ert-deftest sp-devonthink-keywords-report-collect-skips-chapters-and-reads-tags-once ()
  (let (reads)
    (cl-letf (((symbol-function 'sp-devonthink-record)
               (lambda (key) (pcase key ("ch" '(:uuid "UC" :via "parent")) (_ (list :uuid (upcase key))))))
              ((symbol-function 'sp-devonthink-record-tags)
               (lambda (uuids) (push uuids reads) (mapcar (lambda (u) (cons u '("t"))) uuids)))
              ((symbol-function 'sp-devonthink-bibsync--read-files) (lambda (_) nil))
              ((symbol-function 'sp-devonthink-keywords-report--plan)
               (lambda (key _uuid tags bib) (list :key key :tags tags :bib bib))))
      (let ((data (sp-devonthink-keywords-report--collect '("a" "ch" "b"))))
        (should (equal (plist-get data :skipped) '("ch")))
        (should (equal (mapcar (lambda (p) (plist-get p :key)) (plist-get data :plans)) '("a" "b")))
        (should (= (length reads) 1))
        (should (equal (plist-get (car (plist-get data :plans)) :tags) '("t")))))))

(ert-deftest sp-devonthink-keywords-report-apply-syncs-only-the-rows-left ()
  (let (synced)
    (cl-letf (((symbol-function 'sp-devonthink-keywords-sync-keys)
               (lambda (keys &optional _bibs) (setq synced keys) (list :results nil :skipped nil)))
              ((symbol-function 'sp-devonthink-keywords--summary) #'ignore)
              ((symbol-function 'sp-devonthink-keywords-report) #'ignore))
      (sp-devonthink-keywords-report--apply
       (list :plans (list (list :key "a" :bib "+x" :state 'ok)
                          (list :key "b" :dt "+y" :state 'ok)
                          (list :key "c" :dt "+y" :state 'flag)
                          (list :key "d" :state 'ok)))
       '("b"))
      (should (equal synced '("a"))))))

(ert-deftest sp-devonthink-keywords-report-text-has-a-row-for-each-change ()
  (let* ((sp-batch-report-display 'org)
         (text (sp-devonthink-keywords-report--text
                (list :plans (list (list :key "a" :bib "+x" :dt nil :note "+x" :state 'ok)
                                   (list :key "b" :state 'ok)
                                   (list :key "c" :state 'flag)))
                nil)))
    (should (string-match-p "| a " text))
    (should-not (string-match-p "| b " text))
    (should (string-match-p "Litnote edited by hand" text))))

(provide 'sp-devonthink-keywords-report-test)
;;; sp-devonthink-keywords-report-test.el ends here
