;;; sp-litdb-test.el --- Tests for sp-litdb -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-litdb)

(defun sp-litdb-test--result (&optional key page)
  `((source . ,(format "x-devonthink-item://U-%s?page=%d" (or key "k") (1- (or page 6))))
    (score . 0.7)
    (snippet . "Yet as is often the case\nin Adorno")
    (extra . ((citekey . ,(or key "okane-2018")) (page . ,(or page 6)) (uuid . "U")
              (highlights . ("exchange abstraction" "value form"))))))

(ert-deftest sp-litdb-filter-parses-lines-in-pieces ()
  (let ((sp-litdb--partial "") (sp-litdb--pending nil) (sp-litdb--ready nil))
    (sp-litdb--filter nil "{\"ready\": true}\n{\"id\": 3, \"res")
    (should sp-litdb--ready)
    (should-not sp-litdb--pending)
    (sp-litdb--filter nil "ults\": [{\"source\": \"a\"}]}\n")
    (should (equal (alist-get 'results (cdr (assq 3 sp-litdb--pending)))
                   '(((source . "a")))))))

(ert-deftest sp-litdb-hit-label-and-candidates ()
  (let* ((sp-litdb--hits (make-hash-table :test 'equal))
         (hit (sp-litdb--hit (sp-litdb-test--result) "value form"))
         (same (sp-litdb--hit (sp-litdb-test--result) "value form"))
         (cands (sp-litdb--candidates (list hit same))))
    (should (string-match-p "\\`okane-2018 p. 6  Yet as is often the case in Adorno" (car cands)))
    (should-not (equal (car cands) (cadr cands)))
    (should (eq (sp-litdb--hit-for (car cands)) hit))
    (should (string-match-p "0.70  2 highlights" (sp-litdb--annotate (car cands))))
    (should-error (sp-litdb--hit-for "nope") :type 'user-error)))

(ert-deftest sp-litdb-table-metadata ()
  (let ((table (sp-litdb--table '("a" "b"))))
    (should (eq (alist-get 'category (cdr (funcall table "" nil 'metadata))) 'sp-litdb))
    (should (equal (all-completions "" table) '("a" "b")))))

(ert-deftest sp-litdb-insert-link-and-cite ()
  (let* ((sp-litdb--hits (make-hash-table :test 'equal))
         (cand (car (sp-litdb--candidates (list (sp-litdb--hit (sp-litdb-test--result) "q"))))))
    (with-temp-buffer
      (sp-litdb-insert-link cand)
      (should (equal (buffer-string)
                     "[[x-devonthink-item://U-k?page=5][okane-2018 p. 6]]")))
    (with-temp-buffer
      (sp-litdb-insert-cite cand)
      (should (equal (buffer-string) "[cite:@okane-2018 p. 6]")))))

(ert-deftest sp-litdb-collect-to-note ()
  (let* ((sp-litdb--hits (make-hash-table :test 'equal))
         (file (make-temp-file "sp-litdb" nil ".org" "#+title: n\n"))
         (cands (sp-litdb--candidates
                 (list (sp-litdb--hit (sp-litdb-test--result "a" 3) "value form")
                       (sp-litdb--hit (sp-litdb-test--result "b" 9) "value form")))))
    (unwind-protect
        (cl-letf (((symbol-function 'vulpea-select) (lambda (&rest _) 'note))
                  ((symbol-function 'vulpea-note-path) (lambda (_) file))
                  ((symbol-function 'vulpea-note-title) (lambda (_) "n")))
          (sp-litdb-collect-to-note cands)
          (let ((text (buffer-string)))
            (should (string-match-p "^\\* litdb: value form$" text))
            (should (string-match-p "^- \\[\\[x-devonthink-item://U-a\\?page=2\\]\\[a p. 3\\]\\] \\[cite:@a\\]$" text))
            (should (string-match-p "^  - exchange abstraction$" text))
            (should (string-match-p "p. 9" text))))
      (when (get-file-buffer file) (with-current-buffer (get-file-buffer file) (set-buffer-modified-p nil) (kill-buffer)))
      (delete-file file))))

(provide 'sp-litdb-test)
;;; sp-litdb-test.el ends here
