;;; sp-cite-open-test.el --- Tests for sp-cite-open -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-cite-open)

(defconst sp-cite-open-test--text
  "Introduction

As Smith (2020) argues, kernels matter.

References

[1] Smith, J., Jones, M., Brown, T., Lee, A. (2020). Attention Is All You
Need: A Survey of Transformers. Journal of Machine Learning, 12(3).
[2] Marx, K. (1867). Das Kapital. Hamburg: Meissner.
[3] Mueller, J. (2015a). Sociotechnical Systems in Practice. Organization Studies.
[4] Mueller, J. (2015b). Sociotechnical Systems Revisited. Organization Studies."
  "A made-up document with a numbered reference list.")

(defconst sp-cite-open-test--author-year
  "Body text.

Bibliography

Smith, John, and Maria Jones. 2020. “Attention Is All You Need.” Journal of Machine Learning 12 (3): 1–20.

Marx, Karl. 1867. Das Kapital. Hamburg: Meissner.

Zweig, Stefan. 1942. The World of Yesterday. New York: Viking.")

(ert-deftest sp-cite-open-test-references ()
  (let ((refs (sp-cite-open-references sp-cite-open-test--text)))
    (should (string-prefix-p "\n[1] Smith" refs))
    (should-not (string-match-p "Introduction" refs)))
  (should-not (sp-cite-open-references "No list here\nat all\nreally\nnone"))
  (should-not (sp-cite-open-references nil)))

(ert-deftest sp-cite-open-test-references-skips-short-tail ()
  ;; The later "References" line has too little after it: the earlier list wins.
  (let ((refs (sp-cite-open-references
               "References\n[1] A one.\n[2] B two.\n[3] C three.\n[4] D four.\nReferences\nlast")))
    (should (string-match-p "\\[1\\] A one" refs))))

(ert-deftest sp-cite-open-test-heading-variants ()
  (dolist (heading '("REFERENCES" "7. References" "Works Cited" "Bibliography:" "Literatur"))
    (should (sp-cite-open-references (concat "x\n" heading "\na\nb\nc\nd")))))

(ert-deftest sp-cite-open-test-numeric ()
  (let ((refs (sp-cite-open-references sp-cite-open-test--text)))
    (should (string-match-p "\\`\\[2\\] Marx" (sp-cite-open-entry "[2]" refs)))
    (should (string-match-p "\\`\\[1\\] Smith" (sp-cite-open-entry "(1, 2)" refs)))
    (should-not (sp-cite-open-entry "[9]" refs))))

(ert-deftest sp-cite-open-test-author-year ()
  (let ((refs (sp-cite-open-references sp-cite-open-test--author-year)))
    (should (string-match-p "Smith, John" (sp-cite-open-entry "(Smith and Jones 2020)" refs)))
    (should (string-match-p "Marx, Karl" (sp-cite-open-entry "Marx, 1867, p. 12" refs)))
    (should (string-match-p "Smith, John" (sp-cite-open-entry "Smith et al. 2020" refs)))
    ;; wrong year, or a surname that is not in the list
    (should-not (sp-cite-open-entry "Marx 1999" refs))
    (should-not (sp-cite-open-entry "Nobody 2020" refs))))

(ert-deftest sp-cite-open-test-author-year-ambiguous-asks ()
  (let ((refs (sp-cite-open-references sp-cite-open-test--text)))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_p choices &rest _) (nth 2 choices))))
      (should (string-match-p "Revisited" (sp-cite-open-entry "Mueller 2015" refs))))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "skip")))
      (should-not (sp-cite-open-entry "Mueller 2015" refs)))))

(ert-deftest sp-cite-open-test-long-text-is-its-own-entry ()
  (should-not (sp-cite-open-entry
               "Smith, John. 2020. Attention Is All You Need. Journal of Machine Learning."
               "Smith, John. 2020. Attention Is All You Need.\nb\nc\nd")))

(ert-deftest sp-cite-open-test-flow ()
  "Reference entry, then BibTeX, then litdb."
  (let ((cands (with-temp-buffer
                 (insert "@article{smith2020attention,
  author = {Smith, John and Jones, Maria},
  title = {Attention Is All You Need},
  journal = {Journal of Machine Learning},
  year = {2020},
}\n")
                 (sp-cite-match--parse-buffer)))
        opened searched)
    (cl-letf (((symbol-function 'sp-cite-match-candidates) (lambda (&rest _) cands))
              ((symbol-function 'sp-reading-open) (lambda (key &rest _) (setq opened key)))
              ((symbol-function 'sp-litdb-search) (lambda (q &rest _) (setq searched q))))
      ;; short citation -> entry of the list -> BibTeX accept
      (should (eq 'bibtex (sp-cite-open-text
                           "(Smith and Jones 2020)"
                           (sp-cite-open-references sp-cite-open-test--author-year))))
      (should (equal opened "smith2020attention"))
      ;; an entry that is not in the BibTeX files -> litdb with the entry text
      (setq opened nil)
      (should (eq 'litdb (sp-cite-open-text
                          "(Zweig 1942)"
                          (sp-cite-open-references sp-cite-open-test--author-year))))
      (should-not opened)
      (should (string-match-p "World of Yesterday" searched)))
    ;; litdb without a hit
    (cl-letf (((symbol-function 'sp-cite-match-candidates) (lambda (&rest _) nil))
              ((symbol-function 'sp-litdb-search)
               (lambda (&rest _) (user-error "No hits"))))
      (should-not (sp-cite-open-text "Nobody 1900")))))

(ert-deftest sp-cite-open-test-protocol-uses-dt-selection ()
  (let (called)
    (cl-letf (((symbol-function 'sp-cite-open--front)
               (lambda () (list :uuid "U-1" :text "Marx 1867")))
              ((symbol-function 'sp-cite-open--plain-text) (lambda (_) "x"))
              ((symbol-function 'run-with-timer) (lambda (_s _r fn) (funcall fn)))
              ((symbol-function 'raise-frame) #'ignore)
              ((symbol-function 'sp-cite-open-text) (lambda (&rest args) (setq called args))))
      (sp-cite-open-protocol '(:file "none"))
      (should (equal (car called) "Marx 1867")))))

(provide 'sp-cite-open-test)
;;; sp-cite-open-test.el ends here
