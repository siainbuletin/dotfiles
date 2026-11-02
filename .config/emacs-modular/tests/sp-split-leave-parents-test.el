;;; sp-split-leave-parents-test.el --- Tests for sp-split-leave-parents -*- lexical-binding: t; -*-

(require 'ert)
(dolist (f '(vulpea denote))
  (unless (require f nil t) (provide f)))
(require 'sp-refile)

(ert-deftest sp-split-test-extract-links ()
  (should (equal (sp-split--extract-id-links "Plain title")
                 '("Plain title")))
  (should (equal (sp-split--extract-id-links "Reading [[id:a1][Alpha]] notes")
                 '("Reading Alpha notes" . ("[[id:a1][Alpha]]"))))
  (should (equal (sp-split--extract-id-links "[[id:a1][Alpha]] and [[id:b2]] and [[id:a1][Alpha]]")
                 '("Alpha and and Alpha" . ("[[id:a1][Alpha]]" "[[id:b2]]")))))

(ert-deftest sp-split-test-extract-keeps-other-links ()
  (should (equal (sp-split--extract-id-links "See [[https://x.org][X]] [[id:a1][A]]")
                 '("See [[https://x.org][X]] A" . ("[[id:a1][A]]")))))

(ert-deftest sp-split-test-extract-only-links ()
  (should (equal (sp-split--extract-id-links "[[id:a1][Alpha]]")
                 '("Alpha" . ("[[id:a1][Alpha]]")))))

(ert-deftest sp-split-test-seealso-new-line ()
  (should (equal (sp-split--body-with-seealso "Text." '("[[id:a1][A]]" "[[id:b2][B]]"))
                 "- seealso :: [[id:a1][A]], [[id:b2][B]]\n\nText."))
  (should (equal (sp-split--body-with-seealso "- note :: x\nText." '("[[id:a1][A]]"))
                 "- seealso :: [[id:a1][A]]\n- note :: x\nText."))
  (should (equal (sp-split--body-with-seealso "" '("[[id:a1][A]]"))
                 "- seealso :: [[id:a1][A]]")))

(ert-deftest sp-split-test-seealso-no-links ()
  (should (equal (sp-split--body-with-seealso "Text." nil) "Text.")))

(ert-deftest sp-split-test-seealso-existing-line ()
  (should (equal (sp-split--body-with-seealso
                  "- seealso :: [[id:a1][A]]\nText." '("[[id:a1][A]]" "[[id:b2][B]]"))
                 "- seealso :: [[id:a1][A]], [[id:b2][B]]\nText."))
  (should (equal (sp-split--body-with-seealso
                  "- seealso :: [[id:a1][A]]\nText." '("[[id:a1][A]]"))
                 "- seealso :: [[id:a1][A]]\nText.")))

(ert-deftest sp-split-test-seealso-ignores-child-headings ()
  (should (equal (sp-split--body-with-seealso
                  "Text.\n** Child\n- seealso :: [[id:c3][C]]\n" '("[[id:a1][A]]"))
                 "- seealso :: [[id:a1][A]]\n\nText.\n** Child\n- seealso :: [[id:c3][C]]\n")))

(provide 'sp-split-leave-parents-test)
;;; sp-split-leave-parents-test.el ends here
