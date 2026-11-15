;;; sp-split-leave-parents-test.el --- Tests for sp-split-leave-parents -*- lexical-binding: t; -*-

(require 'ert)
(unless (require 'vulpea nil t) (provide 'vulpea))
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

(ert-deftest sp-split-test-notes-go-to-one-section-renumbered ()
  (pcase-let ((`(,body ,copied ,dangling)
               (sp-split--notes-fix-body
                "Text[fn:end-2] more[fn:see-3] and[fn:4] and[fn:see-9]."
                '(("see-3" . "[fn:see-3] Kant")
                  ("end-2" . "[fn:end-2] long remark")
                  ("4" . "[fn:4] plain")
                  ("see-1" . "[fn:see-1] not cited")))))
    (should (= copied 3))
    (should (equal dangling '("see-9")))
    (should (equal body
                   (concat "Text[fn:end-1] more[fn:see-1] and[fn:1] and[fn:see-2].\n\n"
                           "* Notes / Appendix\n\n[fn:end-1] long remark\n\n"
                           "[fn:see-1] Kant\n\n[fn:1] plain")))))

(ert-deftest sp-split-test-notes-keep-the-bodys-own-definitions ()
  (pcase-let ((`(,body ,copied ,_)
               (sp-split--notes-fix-body
                "Text[fn:see-1].\n\n[fn:see-1] mine\n"
                '(("see-1" . "[fn:see-1] the source's")))))
    (should (= copied 0))
    (should (equal body "Text[fn:see-1].\n\n[fn:see-1] mine"))))

(ert-deftest sp-split-test-notes-only-cited-inside-are-taken-out ()
  (with-temp-buffer
    (insert (concat "* Keep\nStays[fn:see-2] and[fn:end-1].\n\n"
                    "* Move\nGoes[fn:see-1] and[fn:end-1] and[fn:3].\n\n"
                    "* Notes / Appendix\n\n[fn:end-1] shared\n\n[fn:see-1] only moved\n\n"
                    "[fn:see-2] stays\n\n[fn:3] plain moved\n"))
    (delay-mode-hooks (org-mode))
    (let* ((beg (save-excursion (goto-char (point-min)) (search-forward "* Move") (line-beginning-position)))
           (end (save-excursion (goto-char beg) (search-forward "* Notes / Appendix") (line-beginning-position)))
           (labels (sp-split--notes-cited-only-inside beg end)))
      ;; end-1 is cited from the part that stays.
      (should (equal (sort (copy-sequence labels) #'string<) '("3" "see-1")))
      ;; The subtree is cut, then the definitions go and the rest is renumbered.
      (delete-region beg end)
      (should (= (sp-split--notes-drop-definitions labels) 2))
      (sp-split--notes-tidy)
      (should (equal (buffer-string)
                     (concat "* Keep\nStays[fn:see-1] and[fn:end-1].\n\n"
                             "* Notes / Appendix\n\n[fn:end-1] shared\n\n[fn:see-1] stays\n"))))))

(provide 'sp-split-leave-parents-test)
;;; sp-split-leave-parents-test.el ends here
