;;; sp-litnotes-refs-test.el --- Tests for sp-litnotes-refs -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-litnotes-refs)

(defvar sp-literature-dir)
(defvar sp-bibtex-files)

(defun sp-litnotes-refs-test--write (file &rest lines)
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert (string-join lines "\n") "\n")))

(defun sp-litnotes-refs-test--read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro sp-litnotes-refs-test--with-vault (&rest body)
  "Run BODY with a temporary vault: `dir' (litnotes), `lit' (PDFs), `bib' (a .bib)."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "sp-refs" t)))
          (dir (expand-file-name "litnotes/" root))
          (lit (expand-file-name "literature/" root))
          (bib (expand-file-name "refs.bib" root))
          (sp-litnotes-refs-directory dir)
          (sp-litnotes-refs-backup-directory (expand-file-name "backups/" root))
          (sp-literature-dir lit)
          (sp-bibtex-files (list bib)))
     (make-directory lit t)
     (unwind-protect (progn ,@body) (delete-directory root t))))

(ert-deftest sp-litnotes-refs-tokens ()
  (should (equal (sp-litnotes-refs--tokens "@a1 b2 cite:c3 [cite:@d4;@e5]")
                 '(("a1" "b2" "c3" "d4" "e5"))))
  (should (equal (sp-litnotes-refs--tokens "@a1 https://doi.org/10.1/x")
                 '(("a1") "https://doi.org/10.1/x"))))

(ert-deftest sp-litnotes-refs-plan-statuses ()
  (sp-litnotes-refs-test--with-vault
    (let ((head ":PROPERTIES:\n:ID:       abc\n"))
      (sp-litnotes-refs-test--write (expand-file-name "a.org" dir)
        ":PROPERTIES:" ":ID:       abc" ":END:" "#+title: a" "#+reference:  kant2009" "body")
      (sp-litnotes-refs-test--write (expand-file-name "b.org" dir)
        ":PROPERTIES:" ":ID:       abc" ":ROAM_REFS: bare-key" ":END:" "#+title: b")
      (sp-litnotes-refs-test--write (expand-file-name "c.org" dir)
        ":PROPERTIES:" ":ID:       abc" ":ROAM_REFS: @ok" ":END:" "#+title: c")
      (sp-litnotes-refs-test--write (expand-file-name "d.org" dir)
        "#+title: d" "#+reference: nodrawer")
      (sp-litnotes-refs-test--write (expand-file-name "e.org" dir)
        ":PROPERTIES:" ":ID:       abc" ":ROAM_REFS: @x" ":END:" "#+reference: y")
      (sp-litnotes-refs-test--write (expand-file-name "f.org" dir)
        (concat head ":END:") "#+title: f")
      (let ((status (mapcar (lambda (p) (cons (file-name-nondirectory (plist-get p :file))
                                              (plist-get p :status)))
                            (sp-litnotes-refs--plans))))
        (should (equal status '(("a.org" . convert) ("b.org" . normalise) ("c.org" . ok)
                                ("d.org" . no-id) ("e.org" . merge)
                                ("f.org" . no-reference))))))))

(ert-deftest sp-litnotes-refs-convert-writes-and-is-idempotent ()
  (sp-litnotes-refs-test--with-vault
    (let ((a (expand-file-name "a.org" dir)))
      (sp-litnotes-refs-test--write a
        ":PROPERTIES:" ":ID:       abc" ":END:" "#+title: a" "#+reference:  kant2009" "body")
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'pop-to-buffer) #'ignore))
        (sp-litnotes-refs-convert)
        (let ((text (sp-litnotes-refs-test--read a)))
          (should (string-match-p "^:ROAM_REFS: @kant2009$" text))
          (should-not (string-match-p "#\\+reference" text))
          (should (string-match-p "body" text)))
        (should (file-exists-p (expand-file-name "a.org" sp-litnotes-refs-backup-directory)))
        (should (string-match-p "#\\+reference"
                                (sp-litnotes-refs-test--read
                                 (expand-file-name "a.org" sp-litnotes-refs-backup-directory))))
        (let ((once (sp-litnotes-refs-test--read a)))
          (sp-litnotes-refs-convert)
          (should (equal once (sp-litnotes-refs-test--read a))))))))

(ert-deftest sp-litnotes-refs-report-crossref-pdf ()
  (sp-litnotes-refs-test--with-vault
    (with-temp-file bib
      (insert "@book{book-1, title = {B}}\n@incollection{sec-1,\n  crossref = {book-1},\n  title = {S}}\n"
              "@comment{x, y}\n"))
    (with-temp-file (expand-file-name "book-1.pdf" lit) (insert "x"))
    (let ((index (sp-litnotes-refs--bib-index (list bib))))
      (should (equal (gethash "sec-1" index) "book-1"))
      (should (eq (gethash "book-1" index) :none))
      (should-not (gethash "x" index))
      (should (eq (sp-litnotes-refs--pdf "book-1" index) 'own))
      (should (eq (sp-litnotes-refs--pdf "sec-1" index) 'crossref))
      (should-not (sp-litnotes-refs--pdf "missing" index)))
    (sp-litnotes-refs-test--write (expand-file-name "a.org" dir)
      ":PROPERTIES:" ":ID:       abc" ":END:" "#+reference: sec-1")
    (sp-litnotes-refs-test--write (expand-file-name "b.org" dir)
      ":PROPERTIES:" ":ID:       def" ":END:" "#+reference: nowhere")
    (let ((text (sp-litnotes-refs--report-text
                 (sp-litnotes-refs--plans) (sp-litnotes-refs--bib-index (list bib)))))
      (should (string-match-p "through crossref: 1" text))
      (should (string-match-p "keys not in any registered .bib: 1" text))
      (should (string-match-p "nowhere in =b.org=" text)))))

(provide 'sp-litnotes-refs-test)
;;; sp-litnotes-refs-test.el ends here
