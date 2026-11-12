;;; sp-devonthink-search-test.el --- Tests for sp-devonthink-search -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-devonthink-search)

(defconst sp-devonthink-search-test--text
  "U1\t/A/\tsmith-2017-x.pdf\tPDF Document\t12\nU2\t/B/\tnote.txt\tPlain Text\t0\n")

(ert-deftest sp-devonthink-search-script-quotes-the-query ()
  (let ((script (sp-devonthink-search--script "\"value form\" kind:pdf")))
    (should (string-match-p "search \"\\\\\"value form\\\\\" kind:pdf\" in root of database \"literature\"" script))
    (should (string-match-p "items 1 thru 50" script))))

(ert-deftest sp-devonthink-search-parse-and-annotate ()
  (let* ((records (sp-devonthink-browse--parse sp-devonthink-search-test--text))
         (cands (sp-devonthink-browse--make-candidates records)))
    (should (equal (plist-get (car records) :pages) "12"))
    (should (equal (sp-devonthink-search--annotate (car cands)) "  PDF Document, 12 pages"))
    (should (equal (sp-devonthink-search--annotate (cadr cands)) "  Plain Text"))
    (should-not (sp-devonthink-search--annotate "unknown"))))

(ert-deftest sp-devonthink-search-table-keeps-rank-order ()
  (let ((table (sp-devonthink-search--table '("b" "a"))))
    (should (eq (alist-get 'category (cdr (funcall table "" nil 'metadata))) 'sp-devonthink-record))
    (should (eq (alist-get 'display-sort-function (cdr (funcall table "" nil 'metadata))) 'identity))
    (should (equal (all-completions "" table) '("b" "a")))))

(ert-deftest sp-devonthink-search-choose-opens-the-hit ()
  (let (opened)
    (cl-letf (((symbol-function 'sp-reading--osascript)
               (lambda (_) sp-devonthink-search-test--text))
              ((symbol-function 'completing-read) (lambda (&rest _) "smith-2017-x.pdf"))
              ((symbol-function 'sp-reading--open-url) (lambda (url) (setq opened url))))
      (sp-devonthink-search--choose "script" "p: "))
    (should (equal opened "x-devonthink-item://U1"))
    (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "")))
      (should-error (sp-devonthink-search--choose "script" "p: ") :type 'user-error))))

(ert-deftest sp-devonthink-search-engine-litdb-sets-mode ()
  (let (mode query)
    (defvar sp-litdb-default-mode)
    (cl-letf (((symbol-function 'sp-litdb-search)
               (lambda (q &optional _) (setq query q mode sp-litdb-default-mode)))
              ((symbol-function 'require) (lambda (&rest _) t)))
      (sp-devonthink-search "value form" 'vector))
    (should (equal query "value form"))
    (should (eq mode 'vector))))

(ert-deftest sp-devonthink-search-similar-and-preview-scripts ()
  (should (string-match-p "compare record theRecord to database \"literature\""
                          (sp-devonthink-search--similar-script "U1")))
  (should (string-match-p "get record with uuid \"U1\"" (sp-devonthink-search--preview-script "U1")))
  (should (string-match-p "text 1 thru 3000" (sp-devonthink-search--preview-script "U1"))))

(ert-deftest sp-devonthink-search-preview-buffer ()
  (sp-devonthink-browse--make-candidates (sp-devonthink-browse--parse sp-devonthink-search-test--text))
  (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "Some text"))
            ((symbol-function 'display-buffer) #'ignore))
    (sp-devonthink-preview "smith-2017-x.pdf"))
  (with-current-buffer "*devonthink preview*"
    (should (string-match-p "smith-2017-x.pdf\n\nSome text" (buffer-string)))))

(provide 'sp-devonthink-search-test)
;;; sp-devonthink-search-test.el ends here
