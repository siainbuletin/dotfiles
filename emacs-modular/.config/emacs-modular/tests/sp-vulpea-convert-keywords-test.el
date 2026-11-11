;;; sp-vulpea-convert-keywords-test.el --- Tests for sp-vulpea-convert-keywords -*- lexical-binding: t; -*-

(require 'ert)
;; The module needs `vulpea' only for the all-notes scope, not for these tests.
(unless (featurep 'vulpea) (provide 'vulpea))
(require 'sp-vulpea-convert-keywords)

(defun sp-vulpea-convert-keywords-test--run (text keys &optional keep)
  "Convert KEYS in TEXT in a temporary Org buffer; return the new text.
With KEEP, do not remove the original keyword lines."
  (with-temp-buffer
    (insert text)
    (delay-mode-hooks (org-mode))
    (let ((sp-vulpea-convert-keywords-remove-original (not keep)))
      (sp-vulpea-convert-keywords--apply keys))
    (buffer-string)))

(ert-deftest sp-vulpea-convert-keywords-collect-ignores-title-and-date ()
  (with-temp-buffer
    (insert "#+title: T\n#+date: 2026-01-01\n#+bib-project: thesis\n#+empty:\n\n* H\n#+later: x\n")
    (delay-mode-hooks (org-mode))
    (should (equal (mapcar (lambda (c) (cons (car c) (plist-get (cdr c) :example)))
                           (sp-vulpea-convert-keywords--collect (list (current-buffer))))
                   '(("bib-project" . "thesis"))))))

(ert-deftest sp-vulpea-convert-keywords-moves-keyword-to-meta ()
  (should (equal (sp-vulpea-convert-keywords-test--run
                  "#+title: T\n#+bib-project: thesis\n\nBody.\n" '("bib-project"))
                 "#+title: T\n\n- bib-project :: thesis\n\nBody.\n")))

(ert-deftest sp-vulpea-convert-keywords-after-drawer-and-keeps-others ()
  (should (equal (sp-vulpea-convert-keywords-test--run
                  ":PROPERTIES:\n:ID: abc\n:END:\n#+title: T\n#+filetags: :a:\n#+bib-project: p\n\n* Head\n"
                  '("bib-project"))
                 ":PROPERTIES:\n:ID: abc\n:END:\n#+title: T\n#+filetags: :a:\n\n- bib-project :: p\n\n* Head\n")))

(ert-deftest sp-vulpea-convert-keywords-repeated-keyword-gives-several-lines ()
  (should (equal (sp-vulpea-convert-keywords-test--run
                  "#+title: T\n#+bib-project: a\n#+bib-project: b\n" '("bib-project"))
                 "#+title: T\n\n- bib-project :: a\n- bib-project :: b\n")))

(ert-deftest sp-vulpea-convert-keywords-joins-existing-meta-block ()
  (should (equal (sp-vulpea-convert-keywords-test--run
                  "#+title: T\n#+x: 1\n\n- other :: o\n\nText.\n" '("x"))
                 "#+title: T\n\n- x :: 1\n- other :: o\n\nText.\n")))

(ert-deftest sp-vulpea-convert-keywords-is-idempotent-and-keep-works ()
  (let* ((text "#+title: T\n#+x: 1\n")
         (kept (sp-vulpea-convert-keywords-test--run text '("x") t)))
    (should (equal kept "#+title: T\n#+x: 1\n\n- x :: 1\n"))
    (should (equal (sp-vulpea-convert-keywords-test--run kept '("x") t) kept))))

(ert-deftest sp-vulpea-convert-keywords-leaves-blocks-and-headings-alone ()
  (let ((text "#+title: T\n#+begin_src text\n#+x: 1\n#+end_src\n* H\n#+x: 2\n"))
    (should (equal (sp-vulpea-convert-keywords-test--run text '("x")) text))))

(ert-deftest sp-vulpea-convert-keywords-only-chosen-keys ()
  (should (equal (sp-vulpea-convert-keywords-test--run
                  "#+title: T\n#+a: 1\n#+b: 2\n" '("a"))
                 "#+title: T\n#+b: 2\n\n- a :: 1\n")))

;;; sp-vulpea-convert-keywords-test.el ends here

(ert-deftest sp-vulpea-convert-keywords-preview-links-files ()
  "The preview is a report buffer whose file headings are links."
  (let ((buffer (save-window-excursion
                  (sp-vulpea-convert-keywords--show-preview
                   '(("/tmp/vault/a.org" ("bib-project" . "thesis")))))))
    (unwind-protect
        (with-current-buffer buffer
          (should (derived-mode-p 'sp-batch-report-mode))
          (should (string-match-p "^\\* \\[\\[file:/tmp/vault/a\\.org\\]\\[/tmp/vault/a\\.org\\]\\]$"
                                  (buffer-string)))
          (should (string-match-p "- bib-project :: thesis" (buffer-string))))
      (kill-buffer buffer))))
