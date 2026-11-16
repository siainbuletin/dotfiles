;;; sp-devonthink-keywords-test.el --- Tests for sp-devonthink-keywords -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(unless (boundp 'sp-cache-dir) (defvar sp-cache-dir temporary-file-directory))
(unless (boundp 'sp-var-dir) (defvar sp-var-dir temporary-file-directory))
(defvar sp-bibtex-files nil)
(require 'sp-devonthink-keywords)

;;;; Pure helpers

(ert-deftest sp-devonthink-keywords-parse-and-same ()
  (should (equal (sp-devonthink-keywords-parse " a; B,, b ,c ") '("a" "B" "c")))
  (should-not (sp-devonthink-keywords-parse nil))
  (should (sp-devonthink-keywords-same-p '("A" "b") '("b" "a")))
  (should-not (sp-devonthink-keywords-same-p '("a") '("a" "b"))))

(ert-deftest sp-devonthink-keywords-merge-additions ()
  ;; added anywhere reaches everything; first spelling wins
  (should (equal (sp-devonthink-keywords-merge '("a") '("a" "b") '("a" "c")) '("a" "b" "c")))
  (should (equal (sp-devonthink-keywords-merge nil '("A") '("a" "b")) '("A" "b"))))

(ert-deftest sp-devonthink-keywords-merge-removals ()
  ;; removed in one place, untouched in the other: removed
  (should (equal (sp-devonthink-keywords-merge '("a" "b") '("a") '("a" "b")) '("a")))
  ;; removed in one, another one added in the other
  (should (equal (sp-devonthink-keywords-merge '("a" "b") '("b") '("a" "b" "c")) '("b" "c")))
  ;; everything removed
  (should-not (sp-devonthink-keywords-merge '("a") nil '("a")))
  ;; no base: union, nothing removed
  (should (equal (sp-devonthink-keywords-merge nil '("x") '("y")) '("x" "y"))))

(ert-deftest sp-devonthink-keywords-diff-string ()
  (should (equal (sp-devonthink-keywords--diff-string '("a" "b") '("b" "c")) "+c, -a")))

(ert-deftest sp-devonthink-keywords-dt-keywords-split-comma-tags ()
  (should (equal (sp-devonthink-keywords--dt-keywords '("a" "b, c" "d" "A")) '("a" "b" "c" "d"))))

;;;; State file

(ert-deftest sp-devonthink-keywords-state-roundtrip ()
  (let ((sp-devonthink-keywords-state-file (make-temp-file "sp-kw" nil ".eld"))
        (sp-devonthink-keywords--state nil))
    (unwind-protect
        (progn
          (delete-file sp-devonthink-keywords-state-file)
          (should (eq (sp-devonthink-keywords--synced "k") 'none))
          (sp-devonthink-keywords--set-synced "k" '("a" "b"))
          (sp-devonthink-keywords--set-synced "e" nil)
          (setq sp-devonthink-keywords--state nil)   ; force a re-read from disk
          (should (equal (sp-devonthink-keywords--synced "k") '("a" "b")))
          (should (equal (sp-devonthink-keywords--synced "e") nil))
          (should (eq (sp-devonthink-keywords--synced "z") 'none)))
      (ignore-errors (delete-file sp-devonthink-keywords-state-file)))))

;;;; BibTeX

(ert-deftest sp-devonthink-keywords-bib-text ()
  (should-not (sp-devonthink-keywords--bib-text "a, b" '("b" "a")))
  (should (equal (sp-devonthink-keywords--bib-text "a, b" '("a" "c")) "a, c"))
  (should (equal (sp-devonthink-keywords--bib-text "a; b" '("a" "b" "c")) "a; b; c"))
  (should (equal (sp-devonthink-keywords--bib-text nil '("x")) "x"))
  (should (equal (sp-devonthink-keywords--bib-text "a" nil) "")))

(defconst sp-devonthink-keywords-test--bib
  "@article{k1,\n  title = {T},\n  keywords = {a, b},\n  year = {2020},\n}\n\n@book{k2,\n  title = {U}\n}\n")

(defun sp-devonthink-keywords-test--bib-run (key merged)
  "Run `--bib-put' on the sample, return (RESULT . TEXT)."
  (with-temp-buffer
    (insert sp-devonthink-keywords-test--bib)
    (delay-mode-hooks (bibtex-mode))
    (let ((r (sp-devonthink-keywords--bib-put key merged)))
      (cons r (buffer-string)))))

(ert-deftest sp-devonthink-keywords-bib-put-replaces-and-removes ()
  (let ((r (sp-devonthink-keywords-test--bib-run "k1" '("b" "c"))))
    (should (equal (car r) "b, c"))
    (should (string-match-p "keywords = {b, c}" (cdr r)))
    (should-not (string-match-p "keywords = {a" (cdr r)))))

(ert-deftest sp-devonthink-keywords-bib-put-adds-field-and-skips-no-op ()
  (let ((r (sp-devonthink-keywords-test--bib-run "k2" '("x" "y"))))
    (should (equal (car r) "x, y"))
    (should (string-match-p "title = {U},\n  keywords = {x, y}" (cdr r))))
  (should-not (car (sp-devonthink-keywords-test--bib-run "k1" '("a" "b"))))
  (should-not (car (sp-devonthink-keywords-test--bib-run "k2" nil)))
  (should-not (car (sp-devonthink-keywords-test--bib-run "nope" '("a")))))

(ert-deftest sp-devonthink-keywords-write-bib-file ()
  (let ((file (make-temp-file "sp-kw" nil ".bib" sp-devonthink-keywords-test--bib)))
    (unwind-protect
        (progn
          (should (eq (sp-devonthink-keywords--write-bib file "k1" '("a")) t))
          (should (string-match-p "keywords = {a}" (with-temp-buffer (insert-file-contents file) (buffer-string))))
          (should-not (sp-devonthink-keywords--write-bib file "k1" '("a")))
          (let ((buf (find-file-noselect file)))
            (with-current-buffer buf (insert " ") (should (eq (sp-devonthink-keywords--write-bib file "k1" '("z")) 'unsaved)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf)))
      (delete-file file))))

;;;; Litnote line

(defconst sp-devonthink-keywords-test--note
  ":PROPERTIES:\n:ID: abc\n:ROAM_REFS: @k1\n:END:\n#+title: K\n\n- pub-title :: A title\n- pub-year :: 2020\n\n* Notes\nKEYWORDS: not me\n")

(defun sp-devonthink-keywords-test--with-note (text function)
  (with-temp-buffer
    (insert text)
    (delay-mode-hooks (org-mode))
    (funcall function)
    (buffer-string)))

(ert-deftest sp-devonthink-keywords-line-write-inserts-after-meta ()
  (let ((out (sp-devonthink-keywords-test--with-note
              sp-devonthink-keywords-test--note
              (lambda () (should (sp-devonthink-keywords-line-write '("a" "b c")))))))
    (should (string-match-p "- pub-year :: 2020\n\nKEYWORDS: a, b c\n\n\\* Notes" out))
    ;; the line under the heading is not ours
    (should (string-match-p "\\* Notes\nKEYWORDS: not me" out))))

(ert-deftest sp-devonthink-keywords-line-read-write-replace ()
  (sp-devonthink-keywords-test--with-note
   (concat "#+title: K\n\n- pub-year :: 2020\n\nKEYWORDS: a, b\n\n* H\n")
   (lambda ()
     (should (equal (plist-get (sp-devonthink-keywords-line-read) :keywords) '("a" "b")))
     (should-not (sp-devonthink-keywords-line-write '("a" "b")))
     (should (sp-devonthink-keywords-line-write '("c")))
     (should (equal (plist-get (sp-devonthink-keywords-line-read) :keywords) '("c")))
     (should (sp-devonthink-keywords-line-write nil))
     (should (equal (plist-get (sp-devonthink-keywords-line-read) :keywords) nil))
     (should (sp-devonthink-keywords-line-read)))))

(ert-deftest sp-devonthink-keywords-line-legacy-meta-line-is-moved ()
  (let ((out (sp-devonthink-keywords-test--with-note
              "#+title: K\n\n- keywords :: x, y\n- pub-year :: 2020\n\n* H\n"
              (lambda ()
                (let ((line (sp-devonthink-keywords-line-read)))
                  (should (plist-get line :legacy))
                  (should (equal (plist-get line :keywords) '("x" "y"))))
                (sp-devonthink-keywords-line-write '("x" "y" "z"))))))
    (should-not (string-match-p "- keywords ::" out))
    (should (string-match-p "KEYWORDS: x, y, z" out))))

(ert-deftest sp-devonthink-keywords-line-none-writes-nothing-for-no-keywords ()
  (should (equal (sp-devonthink-keywords-test--with-note
                  "#+title: K\n\n* H\n" (lambda () (should-not (sp-devonthink-keywords-line-write nil))))
                 "#+title: K\n\n* H\n"))
  (should (string-match-p "\\`KEYWORDS: a\n"
                          (sp-devonthink-keywords-test--with-note
                           "* H\n" (lambda () (sp-devonthink-keywords-line-write '("a")))))))

(ert-deftest sp-devonthink-keywords-flag-property ()
  (let ((out (sp-devonthink-keywords-test--with-note
              sp-devonthink-keywords-test--note
              (lambda () (sp-devonthink-keywords--flag t)))))
    (should (string-match-p ":SP_KEYWORDS_DRIFT: t" out))
    (should-not (string-match-p ":SP_KEYWORDS_DRIFT:"
                                (sp-devonthink-keywords-test--with-note
                                 out (lambda () (sp-devonthink-keywords--flag nil)))))))

;;;; DEVONthink

(ert-deftest sp-devonthink-keywords-write-dt ()
  (let (script)
    (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (s) (setq script s) "")))
      (should (sp-devonthink-keywords--write-dt "U1" '("a" "b" "x,y") '("b" "c")))
      (should (string-match-p "set tags of (get record with uuid \"U1\") to {\"b\", \"x,y\", \"c\"}" script))
      (setq script nil)
      (should-not (sp-devonthink-keywords--write-dt "U1" '("b" "c") '("C" "b")))
      (should-not script))))

;;;; The sync of one work (DEVONthink and files faked)

(cl-defmacro sp-devonthink-keywords-test--world ((&key bib dt note synced ask) &rest body)
  "Run BODY with fake places: BIB, DT tags, NOTE line (or nil for no litnote), base SYNCED.
Records writes in `written' (a list of (PLACE . KEYWORDS))."
  (declare (indent 1))
  `(let* ((written nil)
          (bibv ,bib) (dtv ,dt) (notev ,note)
          (sp-devonthink-keywords-state-file (make-temp-file "sp-kw"))
          (sp-devonthink-keywords--state (list (cons "k1" ,synced)))
          (,'answer ,ask))
     (unwind-protect
         (cl-letf (((symbol-function 'sp-devonthink-keywords--bib-keywords)
                    (lambda (&rest _) bibv))
                   ((symbol-function 'sp-devonthink-keywords--key-bib-file) (lambda (_) "/x.bib"))
                   ((symbol-function 'sp-devonthink-keywords--write-bib)
                    (lambda (_f _k m) (push (cons 'bib m) written) t))
                   ((symbol-function 'sp-reading--osascript)
                    (lambda (s) (push (cons 'dt s) written) ""))
                   ((symbol-function 'sp-devonthink-keywords--key-litnote)
                    (lambda (_) (and notev "/n.org")))
                   ((symbol-function 'sp-devonthink-keywords--call-in-note)
                    (lambda (_f fn &optional _save)
                      (if (functionp fn)
                          (let ((r (with-temp-buffer
                                     (delay-mode-hooks (org-mode))
                                     (insert "#+title: n\n\n"
                                             (if (eq notev 'none) "" (format "KEYWORDS: %s\n" (string-join notev ", ")))
                                             "\n* H\n")
                                     (prog1 (funcall fn)
                                       (when-let* ((l (sp-devonthink-keywords-line-read)))
                                         (push (cons 'note (plist-get l :keywords)) written))))))
                            r)
                        nil)))
                   ((symbol-function 'y-or-n-p) (lambda (_) answer))
                   ((symbol-value 'noninteractive) nil))
           ,@body)
       (ignore-errors (delete-file sp-devonthink-keywords-state-file)))))

(ert-deftest sp-devonthink-keywords-sync-first-time-is-a-union ()
  (sp-devonthink-keywords-test--world (:bib '("a") :dt '("b") :note nil :synced 'none)
    (let ((r (sp-devonthink-keywords-sync-record "k1" "U1" '("b"))))
      (should (equal (plist-get r :merged) '("a" "b")))
      (should (assq 'bib written))
      (should (assq 'dt written))
      (should (equal (sp-devonthink-keywords--synced "k1") '("a" "b"))))))

(ert-deftest sp-devonthink-keywords-sync-dt-removal-reaches-bibtex ()
  (sp-devonthink-keywords-test--world (:bib '("a" "b") :dt '("a") :note nil :synced '("a" "b"))
    (let ((r (sp-devonthink-keywords-sync-record "k1" "U1" '("a"))))
      (should (equal (plist-get r :merged) '("a")))
      (should (equal (cdr (assq 'bib written)) '("a")))
      (should-not (assq 'dt written)))))

(ert-deftest sp-devonthink-keywords-sync-bibtex-addition-reaches-dt ()
  (sp-devonthink-keywords-test--world (:bib '("a" "n") :dt '("a") :note nil :synced '("a"))
    (let ((r (sp-devonthink-keywords-sync-record "k1" "U1" '("a" "other,tag"))))
      ;; the comma-joined tag counts as two keywords; the tag itself stays in DEVONthink
      (should (equal (plist-get r :merged) '("a" "n" "other" "tag")))
      (should (string-match-p "\"a\", \"other,tag\", \"n\"" (cdr (assq 'dt written))))
      (should (equal (cdr (assq 'bib written)) '("a" "n" "other" "tag"))))))

(ert-deftest sp-devonthink-keywords-sync-litnote-is-cloned ()
  (sp-devonthink-keywords-test--world (:bib '("a" "b") :dt '("a" "b") :note '("a") :synced '("a" "b"))
    ;; the litnote lost b, which is a drift; answer no: the line is reset
    (let ((r (sp-devonthink-keywords-sync-record "k1" "U1" '("a" "b"))))
      (should (equal (plist-get r :merged) '("a" "b")))
      (should-not (assq 'bib written))
      (should (equal (cdr (assq 'note written)) '("a" "b"))))))

(ert-deftest sp-devonthink-keywords-sync-drift-yes-propagates ()
  (sp-devonthink-keywords-test--world (:bib '("a" "b") :dt '("a" "b") :note '("a" "n") :synced '("a" "b") :ask t)
    (let ((r (sp-devonthink-keywords-sync-record "k1" "U1" '("a" "b"))))
      (should (equal (plist-get r :merged) '("a" "n")))
      (should (equal (cdr (assq 'bib written)) '("a" "n")))
      (should (assq 'dt written))
      (should (equal (cdr (assq 'note written)) '("a" "n")))
      (should (eq (plist-get r :drift) 'asked)))))

(ert-deftest sp-devonthink-keywords-sync-drift-without-a-question-is-flagged ()
  (sp-devonthink-keywords-test--world (:bib '("a" "b") :dt '("a" "b") :note '("a" "n") :synced '("a" "b") :ask t)
    (let ((sp-devonthink-keywords-ask nil))
      (let ((r (sp-devonthink-keywords-sync-record "k1" "U1" '("a" "b"))))
        (should (eq (plist-get r :drift) 'flagged))
        (should (equal (plist-get r :merged) '("a" "b")))
        ;; the hand-edited line is left as it was
        (should (equal (cdr (assq 'note written)) '("a" "n")))))))

(ert-deftest sp-devonthink-keywords-sync-new-litnote-gets-the-line ()
  (sp-devonthink-keywords-test--world (:bib '("a") :dt '("a") :note 'none :synced 'none)
    (sp-devonthink-keywords-sync-record "k1" "U1" '("a"))
    (should (equal (cdr (assq 'note written)) '("a")))
    (should-not (assq 'bib written))))

(ert-deftest sp-devonthink-keywords-sync-keys-skips-chapters ()
  (let (synced)
    (cl-letf (((symbol-function 'sp-devonthink-record)
               (lambda (key) (pcase key ("a" '(:uuid "U1")) ("ch" '(:uuid "P" :via "p")))))
              ((symbol-function 'sp-devonthink-record-tags) (lambda (u) (mapcar (lambda (x) (list x "t")) u)))
              ((symbol-function 'sp-devonthink-keywords-sync-record)
               (lambda (k u tags &optional _b) (push (list k u tags) synced) (list :key k))))
      (let ((r (sp-devonthink-keywords-sync-keys '("a" "ch" "inbox"))))
        (should (equal synced '(("a" "U1" ("t")))))
        (should (equal (plist-get r :skipped) '("ch" "inbox")))))))

(provide 'sp-devonthink-keywords-test)
;;; sp-devonthink-keywords-test.el ends here

(ert-deftest sp-devonthink-keywords-line-write-adds-blank-line-after-meta ()
  ;; a line written by an earlier version sits right under the meta list
  (let ((out (sp-devonthink-keywords-test--with-note
              "#+title: K\n\n- pub-year :: 2020\nKEYWORDS: a\n\n* H\n"
              (lambda () (should (sp-devonthink-keywords-line-write '("a")))))))
    (should (string-match-p "- pub-year :: 2020\n\nKEYWORDS: a\n\n\\* H" out)))
  ;; already separated: nothing to do
  (sp-devonthink-keywords-test--with-note
   "#+title: K\n\n- pub-year :: 2020\n\nKEYWORDS: a\n\n* H\n"
   (lambda () (should-not (sp-devonthink-keywords-line-write '("a"))))))
