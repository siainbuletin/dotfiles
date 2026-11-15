;;; sp-note-kinds-test.el --- Tests for sp-note-kinds -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-note-kinds-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org)

(load (expand-file-name
       "../libraries/modules/text/sp-note-kinds.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro sp-note-kinds-test--in-org (text &rest body)
  "Run BODY in an Org buffer holding TEXT, point at the end of the first line."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (delay-mode-hooks (org-mode))
     (goto-char (point-min))
     (end-of-line)
     ,@body))

(ert-deftest sp-note-kinds-test-kind ()
  (should (eq (sp-note-kind "see-1") 'see-also))
  (should (eq (sp-note-kind "see-concept") 'see-also))
  (should (eq (sp-note-kind "end-12") 'endnote))
  (should (eq (sp-note-kind "1") 'footnote))
  (should (eq (sp-note-kind "seen") 'footnote))
  (should (eq (sp-note-kind "see-") 'footnote))
  (should (eq (sp-note-kind nil) 'footnote)))

(ert-deftest sp-note-kinds-test-prefixes-are-options ()
  (let ((sp-note-see-also-prefix "sa:")
        (sp-note-endnote-prefix "en_"))
    (should (eq (sp-note-kind "sa:1") 'see-also))
    (should (eq (sp-note-kind "en_1") 'endnote))
    (should (eq (sp-note-kind "see-1") 'footnote)))
  (let ((sp-note-see-also-prefix ""))
    (should (eq (sp-note-kind "1") 'footnote))))

(ert-deftest sp-note-kinds-test-next-label ()
  (sp-note-kinds-test--in-org "A[fn:see-1] b[fn:see-4] c[fn:end-2] d[fn:7]\n"
    (should (equal (sp-note-next-label 'see-also) "see-5"))
    (should (equal (sp-note-next-label 'endnote) "end-3")))
  (sp-note-kinds-test--in-org "Nothing here\n"
    (should (equal (sp-note-next-label 'see-also) "see-1"))))

(ert-deftest sp-note-kinds-test-new-makes-the-section ()
  (sp-note-kinds-test--in-org "Some text\n"
    (let ((label (sp-note-new 'see-also "[[id:x][X]]")))
      (should (equal label "see-1"))
      (should (equal (buffer-string)
                     "Some text[fn:see-1]\n\n* Footnotes\n\n[fn:see-1] [[id:x][X]]")))))

(ert-deftest sp-note-kinds-test-new-appends-to-the-section ()
  (sp-note-kinds-test--in-org "Some text\n\n* Next\ntext\n\n* Footnotes\n\n[fn:1] plain\n"
    (goto-char (point-min))
    (end-of-line)
    (sp-note-new 'endnote "later")
    (should (string-match-p
             "\\[fn:1\\] plain\n\n\\[fn:end-1\\] later\n?\\'" (buffer-string)))
    (should (string-prefix-p "Some text[fn:end-1]" (buffer-string)))
    ;; The mark was left at the reference, and point is in the definition.
    (should (looking-back "\\[fn:end-1\\] later" (line-beginning-position)))))

(ert-deftest sp-note-kinds-test-new-numbers-count-up ()
  (sp-note-kinds-test--in-org "One\n"
    (sp-note-new 'see-also "a")
    (goto-char (point-min))
    (end-of-line)
    (should (equal (sp-note-new 'see-also "b") "see-2"))
    (should (string-match-p "\\[fn:see-1\\] a\n\n\\[fn:see-2\\] b" (buffer-string)))))

(ert-deftest sp-note-kinds-test-endnotes-template ()
  (sp-note-kinds-test--in-org "Text\n"
    (forward-line 1)
    (sp-note-insert-endnotes-section)
    (should (string-match-p
             "^\\* Notes\n#\\+begin_export typst\n#endnotes()\n#\\+end_export\n"
             (buffer-string)))
    (should-error (sp-note-insert-endnotes-section) :type 'user-error)))

(ert-deftest sp-note-kinds-test-renumber-follows-the-text ()
  (sp-note-kinds-test--in-org
      "A[fn:see-2] b[fn:see-1] c[fn:end-5] d[fn:see-2] e[fn:3]\n\n* Footnotes\n\n[fn:see-1] one\n\n[fn:see-2] two\n\n[fn:end-5] five\n\n[fn:3] plain\n"
    (should (equal (sort (sp-note-renumber) (lambda (a b) (string< (car a) (car b))))
                   '(("end-5" . "end-1") ("see-1" . "see-2") ("see-2" . "see-1"))))
    (should (equal (buffer-string)
                   "A[fn:see-1] b[fn:see-2] c[fn:end-1] d[fn:see-1] e[fn:3]\n\n* Footnotes\n\n[fn:see-2] one\n\n[fn:see-1] two\n\n[fn:end-1] five\n\n[fn:3] plain\n"))
    ;; Nothing left to change.
    (should-not (sp-note-renumber))))

(ert-deftest sp-note-kinds-test-renumber-orphans-names-and-blocks ()
  (sp-note-kinds-test--in-org
      "A[fn:see-4] b[fn:see-kant]\n\n#+begin_src org\nx[fn:see-9]\n#+end_src\n\n[fn:see-4] four\n\n[fn:see-kant] named\n\n[fn:see-7] orphan\n"
    (sp-note-renumber)
    (should (equal (buffer-string)
                   "A[fn:see-1] b[fn:see-kant]\n\n#+begin_src org\nx[fn:see-9]\n#+end_src\n\n[fn:see-1] four\n\n[fn:see-kant] named\n\n[fn:see-2] orphan\n"))))

(ert-deftest sp-note-kinds-test-new-note-before-an-older-one-is-renumbered ()
  (sp-note-kinds-test--in-org "First line\nSecond line[fn:see-1]\n\n* Footnotes\n\n[fn:see-1] old\n"
    ;; A note inserted in the first line gets see-2 from the counter, and
    ;; then see-1, as it comes first in the text.
    (should (equal (sp-note-new 'see-also "new") "see-1"))
    (should (string-match-p "First line\\[fn:see-1\\]\nSecond line\\[fn:see-2\\]"
                            (buffer-string)))
    (should (string-match-p "\\[fn:see-2\\] old" (buffer-string)))
    (should (looking-back "\\[fn:see-1\\] new" (line-beginning-position)))))

(ert-deftest sp-note-kinds-test-normalize-leaves-the-notes ()
  (sp-note-kinds-test--in-org
      "A[fn:see-2] b[fn:x] c[fn::inline] d[fn:see-1] e[fn:end-3]\n\n* Footnotes\n\n[fn:see-1] one\n\n[fn:see-2] two\n\n[fn:x] ex\n\n[fn:end-3] end\n"
    (let ((org-footnote-section nil))
      (org-footnote-normalize))
    (let ((text (buffer-string)))
      ;; The plain ones are numbered by Org; the notes keep their kind and are
      ;; renumbered in the order of the text.
      (should (string-match-p "\\`A\\[fn:see-1\\] b\\[fn:1\\] c\\[fn:2\\] d\\[fn:see-2\\] e\\[fn:end-1\\]" text))
      (should (string-match-p "^\\[fn:see-2\\] one$" text))
      (should (string-match-p "^\\[fn:see-1\\] two$" text))
      (should (string-match-p "^\\[fn:end-1\\] end$" text))
      (should (string-match-p "^\\[fn:1\\] ex$" text))
      (should (string-match-p "^\\[fn:2\\] inline$" text))
      ;; No mask is left behind.
      (should-not (string-match-p "​" text)))))

(ert-deftest sp-note-kinds-test-guard-unmasks-after-an-error ()
  (sp-note-kinds-test--in-org "A[fn:see-1]\n\n[fn:see-1] one\n"
    (should-error (sp-note--guarded (lambda () (error "boom"))))
    (should (equal (buffer-string) "A[fn:see-1]\n\n[fn:see-1] one\n"))))

(ert-deftest sp-note-kinds-test-guard-refuses-with-a-footnote-section ()
  (sp-note-kinds-test--in-org "A[fn:see-1]\n\n[fn:see-1] one\n"
    (let ((org-footnote-section "Footnotes"))
      (should-error (org-footnote-normalize) :type 'user-error))
    (should (equal (buffer-string) "A[fn:see-1]\n\n[fn:see-1] one\n"))))

(ert-deftest sp-note-kinds-test-auto-adjust-keeps-and-renumbers ()
  (sp-note-kinds-test--in-org "A[fn:see-2] b[fn:see-1]\n\n[fn:see-1] one\n\n[fn:see-2] two\n"
    (let ((org-footnote-auto-adjust t) (org-footnote-section nil))
      (org-footnote-auto-adjust-maybe))
    (should (string-prefix-p "A[fn:see-1] b[fn:see-2]\n" (buffer-string)))))

(provide 'sp-note-kinds-test)
;;; sp-note-kinds-test.el ends here
