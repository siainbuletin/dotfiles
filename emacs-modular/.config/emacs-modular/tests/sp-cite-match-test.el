;;; sp-cite-match-test.el --- Tests for sp-cite-match -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-cite-match)

(defconst sp-cite-match-test--bib
  "@article{smith2020attention,
  author = {Smith, John and Jones, Maria and Brown, Tom and Lee, Ann},
  title = {Attention Is All You Need: A {Survey} of Transformers},
  journal = {Journal of Machine Learning},
  year = {2020},
  doi = {10.1234/jml.2020.55},
}
@book{marx1867capital,
  author = \"Marx, Karl\",
  title = {Das Kapital},
  year = 1867,
}
@article{mueller2015sozio,
  author = {M{\\\"u}ller, J{\\\"o}rg},
  title = {Sociotechnical Systems in Practice},
  journaltitle = {Organization Studies},
  date = {2015-03-01},
}
@article{smith2020other,
  author = {Smith, John},
  title = {Kernels for Graphs},
  journal = {Journal of Machine Learning},
  year = {2020},
}
@article{jones2019kernels,
  author = {Jones, Maria},
  title = {Kernels for Graphs},
  year = {2019},
}
@comment{ignored}
"
  "A small made-up bibliography.")

(defmacro sp-cite-match-test--with-bib (&rest body)
  "Run BODY with the candidates of the test bibliography in `cands'."
  `(let ((cands (with-temp-buffer
                  (insert sp-cite-match-test--bib)
                  (sp-cite-match--parse-buffer))))
     ,@body))

(ert-deftest sp-cite-match-test-normalise ()
  (should (equal (sp-cite-match-normalise "Müller, Jörg: ﬁnding \"Ørsted\"!")
                 "muller jorg finding orsted"))
  (should (equal (sp-cite-match-normalise "socio-\ntechnical") "sociotechnical"))
  (should (equal (sp-cite-match-normalise "  A   B ") "a b")))

(ert-deftest sp-cite-match-test-parse ()
  (sp-cite-match-test--with-bib
   (should (equal (mapcar (lambda (c) (plist-get c :key)) cands)
                  '("smith2020attention" "marx1867capital" "mueller2015sozio"
                    "smith2020other" "jones2019kernels")))
   (let ((a (car cands)))
     (should (equal (plist-get a :surnames) '("smith" "jones" "brown" "lee")))
     (should (= (plist-get a :year) 2020))
     (should (equal (plist-get a :doi) "10.1234/jml.2020.55"))
     (should (equal (plist-get a :main-title) "attention is all you need")))
   (should (= (plist-get (nth 1 cands) :year) 1867))
   (should (= (plist-get (nth 2 cands) :year) 2015))
   (should (equal (plist-get (nth 2 cands) :container) "organization studies"))))

(defun sp-cite-match-test--best (text cands)
  "The key and status of the best match of TEXT in CANDS."
  (let ((r (sp-cite-match-text text cands)))
    (cons (car r) (plist-get (cdar (cdr r)) :key))))

(ert-deftest sp-cite-match-test-styles ()
  (sp-cite-match-test--with-bib
   ;; Chicago
   (should (equal (sp-cite-match-test--best
                   "Smith, John, Maria Jones, Tom Brown, and Ann Lee. 2020. “Attention Is All You Need: A Survey of Transformers.” Journal of Machine Learning."
                   cands)
                  '(accept . "smith2020attention")))
   ;; APA
   (should (equal (sp-cite-match-test--best
                   "Smith, J., Jones, M., Brown, T., & Lee, A. (2020). Attention is all you need: A survey of transformers. Journal of Machine Learning."
                   cands)
                  '(accept . "smith2020attention")))
   ;; IEEE, with a typo in the title
   (should (equal (sp-cite-match-test--best
                   "[3] J. Smith, M. Jones, T. Brown and A. Lee, \"Attention is all you need: a survey of transformres,\" J. Mach. Learn., 2020."
                   cands)
                  '(accept . "smith2020attention")))
   ;; accents and casing
   (should (equal (sp-cite-match-test--best
                   "MULLER, Jorg (2015) SOCIOTECHNICAL SYSTEMS IN PRACTICE. Organization Studies."
                   cands)
                  '(accept . "mueller2015sozio")))
   ;; line-end hyphenation
   (should (equal (sp-cite-match-test--best
                   "Müller, J. (2015). Socio-\ntechnical systems in practice. Organization Studies."
                   cands)
                  '(accept . "mueller2015sozio")))))

(ert-deftest sp-cite-match-test-doi ()
  (sp-cite-match-test--with-bib
   (should (equal (sp-cite-match-test--best "see https://doi.org/10.1234/JML.2020.55." cands)
                  '(accept . "smith2020attention")))))

(ert-deftest sp-cite-match-test-short-never-accepted ()
  (sp-cite-match-test--with-bib
   (let ((r (sp-cite-match-text "Marx 1867" cands)))
     (should (eq (car r) 'ambiguous))
     (should (equal (plist-get (cdar (cdr r)) :key) "marx1867capital")))))

(ert-deftest sp-cite-match-test-ambiguous-same-title ()
  (sp-cite-match-test--with-bib
   ;; Same title by two authors, the text has no author that tells them apart.
   (let ((r (sp-cite-match-text "Smith, Jones. Kernels for Graphs." cands)))
     (should (memq (car r) '(ambiguous accept)))
     (should (>= (length (cdr r)) 2)))))

(ert-deftest sp-cite-match-test-no-match ()
  (sp-cite-match-test--with-bib
   (should (eq (car (sp-cite-match-text "Nobody, Unknown (1999). Something else entirely." cands))
               'none))))

(ert-deftest sp-cite-match-test-wrong-year-lowers-score ()
  (sp-cite-match-test--with-bib
   (let ((good (car (sp-cite-match-text "Marx, Karl (1867). Das Kapital." cands)))
         (bad (car (sp-cite-match-text "Marx, Karl (1900). Das Kapital." cands))))
     (should (eq good 'accept))
     (should-not (eq bad 'accept)))))

(ert-deftest sp-cite-match-test-split-entries ()
  (let ((numbered "[1] J. Smith, \"One,\" 2020.\n[2] M. Jones, \"Two\n  continued,\" 2019.")
        (apa "Smith, J. (2020). One. Journal.\nJones, M. (2019). Two that\nspans lines. Press.\n\nMarx, K. (1867). Capital.")
        (hyphen "Smith, J. (2020). A socio-\ntechnical study. Journal."))
    (should (equal (sp-cite-match-split-entries numbered)
                   '("[1] J. Smith, \"One,\" 2020."
                     "[2] M. Jones, \"Two continued,\" 2019.")))
    (should (equal (sp-cite-match-split-entries apa)
                   '("Smith, J. (2020). One. Journal."
                     "Jones, M. (2019). Two that spans lines. Press."
                     "Marx, K. (1867). Capital.")))
    (should (equal (sp-cite-match-split-entries hyphen)
                   '("Smith, J. (2020). A sociotechnical study. Journal.")))))

(ert-deftest sp-cite-match-test-section ()
  (sp-cite-match-test--with-bib
   (let ((sp-cite-match-note-function
          (lambda (key) (when (equal key "marx1867capital") "11111111-2222-3333-4444-555555555555"))))
     (with-temp-buffer
       (org-mode)
       (insert "#+title: A litnote\n\nSome text.\n")
       (sp-cite-match-write-section (list (nth 1 cands) "Unknown, X. (2000). Lost.") cands)
       (should (string-match-p "^\\* Cited works$" (buffer-string)))
       (should (string-match-p
                "\\[cite:@marx1867capital\\] .*\\[\\[id:11111111-2222-3333-4444-555555555555\\]\\[litnote\\]\\]"
                (buffer-string)))
       (should (string-match-p "TODO unmatched: Unknown, X" (buffer-string)))
       (should (string-match-p "1 cited, 1 with litnotes, 1 unmatched" (buffer-string)))
       ;; second run adds a work, keeps the old ones, no duplicates
       (sp-cite-match-write-section (list (nth 1 cands) (car cands)) cands)
       (let ((s (buffer-string)))
         (should (= 1 (with-temp-buffer (insert s) (how-many "cite:@marx1867capital" (point-min) (point-max)))))
         (should (string-match-p "cite:@smith2020attention" s))
         (should (string-match-p "TODO unmatched: Unknown" s))
         (should (string-match-p "2 cited, 1 with litnotes, 1 unmatched" s))
         (should (= 1 (with-temp-buffer (insert s) (how-many "^\\* Cited works" (point-min) (point-max))))))
       ;; text after the block is untouched
       (goto-char (point-max))
       (insert "\n* Later\nkept\n")
       (sp-cite-match-write-section (list (nth 2 cands)) cands)
       (should (string-match-p "\\* Later\nkept" (buffer-string)))))))

(ert-deftest sp-cite-match-test-protocol-text ()
  (let* ((sp-cite-match-inbox (make-temp-file "inbox" t))
         (file (expand-file-name "t1.txt" sp-cite-match-inbox)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "hello"))
          (should (equal (sp-cite-match--protocol-text (list :file "t1.txt")) "hello"))
          (should-not (file-exists-p file))
          (should-error (sp-cite-match--protocol-text (list :file "../x")) :type 'user-error)
          (should (equal (sp-cite-match--protocol-text (list :text "abc")) "abc")))
      (delete-directory sp-cite-match-inbox t))))

(ert-deftest sp-cite-match-test-candidates-cache ()
  (let* ((dir (make-temp-file "bib" t))
         (file (expand-file-name "a.bib" dir))
         (sp-cite-match--cache nil))
    (unwind-protect
        (progn
          (with-temp-file file (insert sp-cite-match-test--bib))
          (let ((a (sp-cite-match-candidates (list file))))
            (should (= (length a) 5))
            (should (eq a (sp-cite-match-candidates (list file))))))
      (delete-directory dir t))))

;;; sp-cite-match-test.el ends here
