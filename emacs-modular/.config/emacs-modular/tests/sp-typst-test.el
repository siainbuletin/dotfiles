;;; sp-typst-test.el --- Tests for the note handling of sp-typst -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -L libraries/modules/text -l tests/sp-typst-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org)

;; The module installs ox-typst with use-package; nothing is installed here.
(defmacro use-package (&rest _))

(load (expand-file-name
       "../libraries/modules/text/sp-typst.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(ert-deftest sp-typst-test-note-label-keeps-the-prefix-first ()
  (should (equal (sp-typst--note-label "doc-x" "see-1") "see-doc-x-1"))
  (should (equal (sp-typst--note-label "doc-x" "end-12") "end-doc-x-12"))
  (should (equal (sp-typst--note-label "doc-x" "3") "doc-x-3"))
  ;; The kind survives.
  (should (eq (sp-note-kind (sp-typst--note-label "doc-x" "see-1")) 'see-also))
  (should (eq (sp-note-kind (sp-typst--note-label "doc-x" "end-1")) 'endnote)))

(ert-deftest sp-typst-test-prefix-footnotes-keeps-the-kind ()
  (with-temp-buffer
    (insert "A[fn:see-1] b[fn:end-1] c[fn:1] d[fn:see-9]\n\n[fn:see-1] x\n\n[fn:end-1] y\n\n[fn:1] z\n")
    (sp-typst--prefix-footnotes "doc-x")
    (should (equal (buffer-string)
                   (concat "A[fn:see-doc-x-1] b[fn:end-doc-x-1] c[fn:doc-x-1] d[fn\u200b:see-9]\n\n"
                           "[fn:see-doc-x-1] x\n\n[fn:end-doc-x-1] y\n\n[fn:doc-x-1] z\n")))))

(ert-deftest sp-typst-test-notes-in-blocks-do-not-count ()
  (with-temp-buffer
    (insert "Text\n#+begin_src org\nx[fn:see-1]\n#+end_src\n")
    (should-not (sp-typst--has-notes-p 'see-also)))
  (with-temp-buffer
    (insert "Text[fn:see-1]\n")
    (should (sp-typst--has-notes-p 'see-also))
    (should-not (sp-typst--has-notes-p 'endnote))))

(ert-deftest sp-typst-test-features-follow-the-style ()
  (let ((sp-typst-see-also-style 'margin))
    (should (equal (sp-typst--features "A[fn:see-1]\n") '(see-also)))
    (should-not (sp-typst--features "A[fn:1]\n")))
  (let ((sp-typst-see-also-style 'footnote))
    (should-not (sp-typst--features "A[fn:see-1]\n"))))

(ert-deftest sp-typst-test-preamble-imports-the-sidenotes-only-when-asked ()
  (should-not (string-match-p "sidenotes.typ" (sp-typst--preamble "T")))
  (let ((text (sp-typst--preamble "T" '(see-also))))
    (should (string-match-p "import \"sidenotes.typ\": see-also, sidenote-layout" text))
    ;; After the book show rule, so the title page keeps its margins.
    (should (< (string-match "show: book" text) (string-match "show: sidenote-layout" text)))))

(ert-deftest sp-typst-test-endnotes-section-is-added-once ()
  (with-temp-buffer
    (insert "* Doc\nText[fn:end-1]\n\n[fn:end-1] y\n")
    (sp-typst--add-endnotes-section 1)
    (should (string-match-p "\n\\*\\* Notes\n#\\+begin_export typst\n#endnotes()\n" (buffer-string)))
    (let ((once (buffer-string)))
      (sp-typst--add-endnotes-section 1)
      (should (equal once (buffer-string))))))

(ert-deftest sp-typst-test-no-endnotes-section-without-endnotes ()
  (with-temp-buffer
    (insert "* Doc\nText[fn:1]\n\n[fn:1] y\n")
    (let ((before (buffer-string)))
      (sp-typst--add-endnotes-section 1)
      (should (equal before (buffer-string))))))

(provide 'sp-typst-test)
;;; sp-typst-test.el ends here
