;;; sp-globals-test.el --- Tests for sp-globals defaults -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-globals)

(ert-deftest sp-globals-bib-notes-is-a-directory-string ()
  "`sp-bib-notes' must be evaluated: citar rejects an unevaluated form."
  (should (stringp (default-value 'sp-bib-notes)))
  (should (string-suffix-p "litnotes/" (default-value 'sp-bib-notes))))

(ert-deftest sp-globals-citar-notes-paths-shape ()
  "The list built for `citar-notes-paths' holds only directory strings."
  (let ((paths (list (or sp-bib-notes sp-notes-dir))))
    (should (seq-every-p #'stringp paths))))

(provide 'sp-globals-test)
;;; sp-globals-test.el ends here
