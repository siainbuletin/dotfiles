;;; sp-devonthink-bibsync-test.el --- Tests for sp-devonthink-bibsync -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(defvar sp-bibtex-files nil)
(require 'sp-devonthink-bibsync)

(defconst sp-devonthink-bibsync-test--bib
  "@article{smith2020,
  author = {Smith, Jane and {van der Berg}, Piet and Doe, A.},
  title = {Attention {Is} \\& More\n    Than You Need},
  keywords = {Marx; value form,  Reading},
  year = {2020},
}
@book{doe2019,
  title = {Only Title},
}
")

(ert-deftest sp-devonthink-bibsync-clean-and-lists ()
  (should (equal (sp-devonthink-bibsync--clean " {A}\n  \\&  b ") "A & b"))
  (should-not (sp-devonthink-bibsync--clean "  "))
  (should-not (sp-devonthink-bibsync--clean nil))
  (should (equal (sp-devonthink-bibsync--authors "A, B and C, D  and others") "A, B; C, D; others"))
  (should (equal (sp-devonthink-bibsync--keywords "a, b; B ,, c") '("a" "b" "c"))))

(ert-deftest sp-devonthink-bibsync-entry-fields ()
  (let ((f (sp-devonthink-bibsync-entry-fields sp-devonthink-bibsync-test--bib)))
    (should (equal (plist-get f :key) "smith2020"))
    (should (equal (plist-get f :author) "Smith, Jane; van der Berg, Piet; Doe, A."))
    (should (equal (plist-get f :title) "Attention Is & More Than You Need"))
    (should (equal (plist-get f :keywords) '("Marx" "value form" "Reading")))))

(ert-deftest sp-devonthink-bibsync-read-files-one-pass ()
  (let ((file (make-temp-file "sp-bs" nil ".bib" sp-devonthink-bibsync-test--bib)))
    (unwind-protect
        (let ((r (sp-devonthink-bibsync--read-files '("doe2019" "smith2020" "nope") (list file))))
          (should (equal (mapcar #'car r) '("smith2020" "doe2019")))
          (should-not (plist-get (cdr (assoc "doe2019" r)) :author))
          (should-not (plist-get (cdr (assoc "doe2019" r)) :keywords))
          (should (equal (plist-get (cdr (assoc "doe2019" r)) :title) "Only Title")))
      (delete-file file))))

(ert-deftest sp-devonthink-bibsync-metadata-script ()
  (let ((script (sp-devonthink-bibsync--metadata-script
                 '(("U1" . (:author "A \"q\"" :title "T"))
                   ("U2" . (:author nil :title "T2"))))))
    (should (string-match-p "get record with uuid \"U1\"" script))
    (should (string-match-p "add custom meta data \"A \\\\\"q\\\\\"\" for \"bibauthor\" to r" script))
    (should (string-match-p "add custom meta data \"T2\" for \"bibtitle\" to r" script))
    (should (= (with-temp-buffer (insert script) (goto-char (point-min)) (count-matches "bibauthor")) 1))))

(ert-deftest sp-devonthink-bibsync-parse-result ()
  (should (equal (sp-devonthink-bibsync--parse-result "ok\tU1\nerror\tU2\tbad field\n")
                 '(("U2" . "bad field")))))

(ert-deftest sp-devonthink-bibsync-apply-hands-the-keywords-to-the-sync ()
  (let (scripts synced)
    (cl-letf (((symbol-function 'sp-reading--osascript)
               (lambda (s) (push s scripts) "ok\tU1\nerror\tU2\tno field"))
              ((symbol-function 'sp-devonthink-keywords-sync-items)
               (lambda (items) (setq synced items) 1)))
      (let ((r (sp-devonthink-bibsync-apply
                '(("U1" . (:key "k1" :keywords ("Marx" "new")))
                  ("U2" . (:key "k2" :keywords ("x")))))))
        (should (= (plist-get r :records) 2))
        (should (equal (plist-get r :failed) '(("U2" . "no field"))))
        (should (= (plist-get r :tagged) 1))
        (should (= (length synced) 2))
        (should (= (length scripts) 1))))))

(ert-deftest sp-devonthink-bibsync-keywords-off ()
  (let ((sp-devonthink-bibsync-keywords nil) (called nil))
    (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "ok\tU1"))
              ((symbol-function 'sp-devonthink-keywords-sync-items) (lambda (_) (setq called t) 1)))
      (should (= (plist-get (sp-devonthink-bibsync-apply '(("U1" . (:keywords ("a"))))) :tagged) 0))
      (should-not called))))

(ert-deftest sp-devonthink-bibsync-keys ()
  (let ((file (make-temp-file "sp-bs" nil ".bib" sp-devonthink-bibsync-test--bib)) applied)
    (unwind-protect
        (let ((sp-bibtex-files (list file)))
          (cl-letf (((symbol-function 'sp-devonthink-record)
                     (lambda (key) (pcase key
                                     ("smith2020" '(:uuid "U1" :supplier "smith2020"))
                                     ("doe2019" '(:uuid "P" :supplier "p" :via "p")))))
                    ((symbol-function 'sp-devonthink-bibsync-apply)
                     (lambda (items) (setq applied items) (list :records (length items) :tagged 0 :failed nil))))
            (let ((r (sp-devonthink-bibsync-keys '("smith2020" "doe2019" "nope"))))
              (should (equal (mapcar #'car applied) '("U1")))
              (should (equal (plist-get r :no-entry) '("nope")))
              (should (equal (plist-get r :no-record) '("doe2019"))))
            ))
      (delete-file file))))

(provide 'sp-devonthink-bibsync-test)
;;; sp-devonthink-bibsync-test.el ends here
