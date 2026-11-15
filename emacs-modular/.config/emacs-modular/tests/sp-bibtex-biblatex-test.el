;;; sp-bibtex-biblatex-test.el --- Tests for sp-bibtex-biblatex -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'bibtex)
(require 'sp-author-notes)
(require 'sp-bibtex-biblatex)

(defun sp-bibtex-biblatex-test--convert (text)
  "Convert TEXT in a `bibtex-mode' buffer; return (NEW-TEXT . RESULTS)."
  (with-temp-buffer
    (insert text)
    (delay-mode-hooks (bibtex-mode))
    (let ((results (sp-bibtex-biblatex--convert-buffer)))
      (cons (buffer-string) results))))

(ert-deftest sp-bibtex-biblatex-test-renames ()
  (let* ((out (sp-bibtex-biblatex-test--convert
               "@article{a2020,\n  author = {A, B},\n  journal = {Mind},\n  address = {Cham},\n  place = {Oxford},\n  year = 2020,\n}\n"))
         (text (car out)))
    (should (string-match-p "journaltitle = {Mind}" text))
    (should (string-match-p "journaltitle    = {X}"
                            (car (sp-bibtex-biblatex-test--convert "@article{b,\n  journal         = {X},\n}\n"))))
    (should-not (string-match-p "^ *journal =" text))
    (should (string-match-p "location = {Cham}" text))
    ;; place differs from location: left, reported
    (should (string-match-p "place = {Oxford}" text))
    (should (cl-some (lambda (p) (string-match-p "differ" p)) (nth 2 (car (cdr out)))))
    (should (string-match-p "year = 2020" text))))

(ert-deftest sp-bibtex-biblatex-test-same-value-dropped ()
  (let ((text (car (sp-bibtex-biblatex-test--convert
                    "@thesis{t1,\n  title = {T},\n  school = {Leeds},\n  institution = {Leeds},\n}\n"))))
    (should (string-match-p "institution = {Leeds}" text))
    (should-not (string-match-p "school" text))))

(ert-deftest sp-bibtex-biblatex-test-unicode ()
  (let ((text (car (sp-bibtex-biblatex-test--convert
                    "@article{a2020,\n  title = {Zeitschrift f{\\\"u}r {M}arx and S{\\o}ren, Est{\\'e}tica},\n  author = {Bulat{\\u a}, Ion},\n  url = {http://x.org/a{\\'e}},\n}\n"))))
    (should (string-match-p "für {M}arx and Søren, Estética" text))
    (should (string-match-p "Bulată" text))
    ;; urls are never decoded
    (should (string-match-p "a{\\\\'e}" text))))

(ert-deftest sp-bibtex-biblatex-test-keeps-turkish-s ()
  (let ((text (car (sp-bibtex-biblatex-test--convert
                    "@article{a,\n  title = {Şişli and f{\\\"u}r},\n}\n"))))
    (should (string-match-p "Şişli and für" text))))

(ert-deftest sp-bibtex-biblatex-test-escapes-stay ()
  (let ((text (car (sp-bibtex-biblatex-test--convert
                    "@article{a,\n  title = {Rock \\& Roll {\\'e}},\n}\n"))))
    (should (string-match-p "Rock \\\\& Roll é" text))))

(ert-deftest sp-bibtex-biblatex-test-keys-files-dates-untouched ()
  (let* ((src "@article{fränkel-1975,\n  title = {T},\n  date = {2022-02-07T09:40:19+00:00},\n  year = {2020},\n  month = {jan},\n  file = {Kłosiński - 2021 - {\\'e}.pdf},\n}\n")
         (out (sp-bibtex-biblatex-test--convert src)))
    (should (equal (car out) src))
    (let ((problems (nth 2 (car (cdr out)))))
      (should (cl-some (lambda (p) (string-match-p "citekey" p)) problems))
      (should (cl-some (lambda (p) (string-match-p "file name" p)) problems))
      (should (cl-some (lambda (p) (string-match-p "has a time" p)) problems)))))

(ert-deftest sp-bibtex-biblatex-test-html-entity ()
  (let ((out (sp-bibtex-biblatex-test--convert "@article{a,\n  journal = {Philosophy &amp; Rhetoric},\n}\n")))
    (should (cl-some (lambda (p) (string-match-p "HTML entity" p)) (nth 2 (car (cdr out)))))))

(ert-deftest sp-bibtex-biblatex-test-idempotent ()
  (let* ((once (car (sp-bibtex-biblatex-test--convert
                     "@article{a,\n  journal = {M{\\'e}},\n  address = {X},\n  year = 2000,\n}\n\n@book{b,\n  title = {T},\n}\n")))
         (twice (car (sp-bibtex-biblatex-test--convert once))))
    (should (equal once twice))))

(ert-deftest sp-bibtex-biblatex-test-file-roundtrip ()
  (let* ((dir (make-temp-file "biblatex" t))
         (file (expand-file-name "x.bib" dir))
         (sp-bibtex-biblatex-backup-directory (expand-file-name "bk/" dir)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "@article{a,\n  journal = {Mind},\n}\n\n@comment{x}\n\n@string{s = \"y\"}\n"))
          (let ((run (sp-bibtex-biblatex--convert-file file)))
            (should (plist-get run :changed))
            (should (string-match-p "journaltitle" (plist-get run :text)))
            (should (string-match-p "@string{s" (plist-get run :text)))
            ;; the file itself is untouched by the conversion
            (should (string-match-p "journal = " (with-temp-buffer (insert-file-contents file) (buffer-string))))))
      (delete-directory dir t))))

(ert-deftest sp-bibtex-biblatex-test-skips-binary-and-invalid-utf8 ()
  (let* ((dir (make-temp-file "biblatex" t))
         (alias (expand-file-name "alias.bib" dir))
         (latin (expand-file-name "latin.bib" dir)))
    (unwind-protect
        (progn
          (let ((coding-system-for-write 'binary))
            (with-temp-file alias (insert "book\0\0mark"))
            (with-temp-file latin (insert "@article{a,\n  journal = {Caf\351},\n}\n")))
          (should (string-match-p "binary" (plist-get (sp-bibtex-biblatex--convert-file alias) :skipped)))
          (should (string-match-p "UTF-8" (plist-get (sp-bibtex-biblatex--convert-file latin) :skipped)))
          (should-not (plist-get (sp-bibtex-biblatex--convert-file latin) :changed)))
      (delete-directory dir t))))

(ert-deftest sp-bibtex-biblatex-test-types ()
  (let* ((out (sp-bibtex-biblatex-test--convert
               "@webpage{w,\n  title = {Caf{\\'e}},\n  journal = {X},\n}\n\n@video{v,\n  title = {V {\\\"u}},\n}\n\n@news{n,\n  title = {N},\n}\n"))
         (text (car out)))
    (should (string-match-p "@online{w," text))
    (should (string-match-p "journaltitle = {X}" text))
    (should (string-match-p "Café" text))
    ;; types the dialect lacks are readable, and decoded
    (should (string-match-p "V ü" text))
    (should (string-match-p "@video{v," text))
    (should (cl-some (lambda (r) (and (equal (car r) "n") (string-match-p "not a BibLaTeX type" (car (nth 2 r)))))
                     (cdr out)))
    (should-not (cl-some (lambda (r) (equal (car r) "v") ) (seq-filter (lambda (r) (nth 2 r)) (cdr out))))))

(provide 'sp-bibtex-biblatex-test)
;;; sp-bibtex-biblatex-test.el ends here
