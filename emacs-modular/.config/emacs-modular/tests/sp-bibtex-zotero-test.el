;;; sp-bibtex-zotero-test.el --- Tests for sp-bibtex-zotero -*- lexical-binding: t; -*-

;; Run from .config/emacs-modular:
;;   emacs -Q --batch -L libraries/modules/funct -L libraries/modules/academic \
;;     -l tests/sp-bibtex-zotero-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'sp-bibtex-zotero)

(defvar sp-literature-dir)
(defvar sp-bibtex-files-devonthink-tool)
(defvar sp-bibtex-lint-backup-directory)

(defvar sp-bibtex-zotero-test--running t "Whether the fake DEVONthink is running.")
(defvar sp-bibtex-zotero-test--moves nil "The move lists the fake tool was given.")
(defvar sp-bibtex-zotero-test--fail-after nil "When a number, the fake move fails after that many files.")

(defun sp-bibtex-zotero-test--write (path text)
  "Write TEXT to PATH, making its folder."
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert text)))

(defmacro sp-bibtex-zotero-test--with-library (spec bib &rest body)
  "Run BODY with a library made from SPEC and the .bib text BIB in FILE.
SPEC is a list of (KEY NAME CONTENT) for the backup, or (TOP NAME CONTENT) for
files at the top.  ROOT is the library, FILE the .bib file."
  (declare (indent 2))
  `(let* ((base (file-name-as-directory (make-temp-file "sp-zotero" t)))
          (root (expand-file-name "literature/" base))
          (file (expand-file-name "a.bib" base))
          (sp-literature-dir root)
          (sp-bibtex-lint-backup-directory (expand-file-name "bk/" base))
          (sp-bibtex-files-devonthink-tool (expand-file-name "tool.py" base))
          (sp-bibtex-zotero-test--running t)
          (sp-bibtex-zotero-test--moves nil)
          (sp-bibtex-zotero-test--fail-after nil))
     (make-directory (expand-file-name "inbox/zotero-backup/" root) t)
     (sp-bibtex-zotero-test--write sp-bibtex-files-devonthink-tool "")
     (dolist (s ,spec)
       (sp-bibtex-zotero-test--write
        (if (equal (car s) "TOP")
            (expand-file-name (nth 1 s) root)
          (expand-file-name (concat "inbox/zotero-backup/" (car s) "/" (nth 1 s)) root))
        (nth 2 s)))
     (sp-bibtex-zotero-test--write file ,bib)
     (cl-letf (((symbol-function 'sp-bibtex-zotero--devonthink-running-p)
                (lambda () sp-bibtex-zotero-test--running))
               ((symbol-function 'sp-bibtex-lint--unsaved-check) #'ignore)
               ((symbol-function 'sp-bibtex-files--call-tool)
                (lambda (_args) (cons 0 "{\"to_move\": 0, \"plain\": 0, \"blocked\": [], \"done\": 0}")))
               ((symbol-function 'sp-bibtex-lint--backup)
                (lambda (f stamp)
                  (let ((dir (expand-file-name (concat stamp "/") sp-bibtex-lint-backup-directory)))
                    (make-directory dir t)
                    (copy-file f (expand-file-name (file-name-nondirectory f) dir) t))))
               ((symbol-function 'sp-bibtex-files--move)
                (lambda (moves)
                  (push moves sp-bibtex-zotero-test--moves)
                  (let ((n 0))
                    (dolist (m moves)
                      (when (and sp-bibtex-zotero-test--fail-after
                                 (>= n sp-bibtex-zotero-test--fail-after))
                        (user-error "devonthink-move stopped: fake"))
                      (when (and (file-exists-p (car m)) (not (file-exists-p (cdr m))))
                        (rename-file (car m) (cdr m)))
                      (cl-incf n)))))
               ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
       ,@body)))

(defun sp-bibtex-zotero-test--text (file)
  "The contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun sp-bibtex-zotero-test--bib (&rest entries)
  "A .bib text of ENTRIES, each (KEY FILE-VALUE)."
  (mapconcat (lambda (e) (format "@book{%s,\n  title = {T},\n  file = {%s}\n}\n\n" (car e) (cadr e)))
             entries ""))

;;;; Reading

(ert-deftest sp-bibtex-zotero-split-respects-escapes ()
  (should (equal (sp-bibtex-zotero--split "a;b\\;c;d") '("a" "b\\;c" "d")))
  (should (equal (sp-bibtex-zotero--split "") '("")))
  (should (equal (sp-bibtex-zotero--split "x\\") '("x\\"))))

(ert-deftest sp-bibtex-zotero-parse ()
  (should (equal (sp-bibtex-zotero--parse "/Users/me/Zotero/storage/ABCD1234/Adams - 1997.pdf")
                 '(:key "ABCD1234" :name "Adams - 1997.pdf")))
  ;; Zotero's label:path:mime form, with a wrapped line and escaped punctuation.
  (should (equal (sp-bibtex-zotero--parse
                  "Full Text PDF:/Users/clb3/Zotero/storage/ABCD1234/Foo\n      bar\\; baz.pdf:application/pdf")
                 '(:key "ABCD1234" :name "Foo bar; baz.pdf")))
  (should (equal (sp-bibtex-zotero--parse "Snapshot:/Users/me/Zotero/storage/ABCD1234/x.html:text/html")
                 '(:key "ABCD1234" :name "x.html")))
  (should-not (sp-bibtex-zotero--parse "inbox/mac-bibdesk/x.pdf"))
  (should-not (sp-bibtex-zotero--parse "/Users/me/Zotero/storage/123456/x.pdf")))

(ert-deftest sp-bibtex-zotero-scan-finds-multiline-fields-and-lines ()
  (with-temp-buffer
    (insert "@article{one,\n  title = {A},\n  file = {x.pdf}\n}\n\n@book{two,\n  title = {B}\n}\n\n"
            "@book{three,\n  file = {a;\n         b {c}\n         }\n}\n")
    (let ((fields (sp-bibtex-zotero--scan)))
      (should (equal (mapcar #'car fields) '("one" "three")))
      (should (equal (mapcar #'cadr fields) '(1 10)))
      (should (equal (nth 4 (car fields)) "x.pdf"))
      (should (string-match-p "b {c}" (nth 4 (cadr fields)))))))

;;;; Names

(ert-deftest sp-bibtex-zotero-same-name ()
  (should (sp-bibtex-zotero--same-name-p "A{\"\\i}vodji et al.pdf" "Aïvodji et al.pdf"))
  (should (sp-bibtex-zotero--same-name-p "Avant--Garde.pdf" "Avant–Garde.pdf"))
  (should (sp-bibtex-zotero--same-name-p "Fiction Writer's.pdf" "Fiction Writer’s.pdf"))
  (should (sp-bibtex-zotero--same-name-p "a  b.pdf" "a b.pdf"))
  (should-not (sp-bibtex-zotero--same-name-p "a.pdf" "b.pdf"))
  ;; A name with no letters and digits has no loose key.
  (should-not (sp-bibtex-zotero--same-name-p "ΣΣ.pdf" "ΩΩ.pdf")))

;;;; Matching

(ert-deftest sp-bibtex-zotero-match-levels ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "Exact.pdf" "1") ("AAAAAAA2" "Aïvodji.pdf" "2") ("AAAAAAA3" "Other name.pdf" "3")
        ("AAAAAAA4" "one.pdf" "4") ("AAAAAAA4" "two.pdf" "5") ("AAAAAAA5" ".zotero-ft-cache" "x")
        ("BBBBBBB1" "elsewhere unique.pdf" "6") ("BBBBBBB2" "twin.pdf" "7") ("BBBBBBB3" "twin.pdf" "8"))
      ""
    (let ((ctx (sp-bibtex-zotero--context)))
      (should (eq 'exact (plist-get (sp-bibtex-zotero--match "AAAAAAA1" "Exact.pdf" ctx) :status)))
      (should (eq 'normalised (plist-get (sp-bibtex-zotero--match "AAAAAAA2" "A{\"\\i}vodji.pdf" ctx) :status)))
      (should (eq 'by-dir (plist-get (sp-bibtex-zotero--match "AAAAAAA3" "Wanted.pdf" ctx) :status)))
      (should (eq 'ambiguous (plist-get (sp-bibtex-zotero--match "AAAAAAA4" "three.pdf" ctx) :status)))
      (should (eq 'no-file (plist-get (sp-bibtex-zotero--match "AAAAAAA5" "x.pdf" ctx) :status)))
      (should (eq 'by-name (plist-get (sp-bibtex-zotero--match "CCCCCCC1" "Elsewhere Unique.pdf" ctx) :status)))
      (should (eq 'ambiguous (plist-get (sp-bibtex-zotero--match "CCCCCCC2" "twin.pdf" ctx) :status)))
      (should (eq 'no-dir (plist-get (sp-bibtex-zotero--match "CCCCCCC3" "nothing.pdf" ctx) :status))))))

;;;; Plans

(defun sp-bibtex-zotero-test--statuses (plan)
  "The (KEY . STATUS) list of the Zotero items of PLAN."
  (mapcar (lambda (i) (cons (sp-bibtex-zotero--item-entry-key i) (sp-bibtex-zotero--item-status i)))
          (sp-bibtex-zotero--items plan)))

(ert-deftest sp-bibtex-zotero-plan-classes ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1") ("AAAAAAA2" "Two.html" "<html>") ("AAAAAAA3" "Other.pdf" "3"))
      (sp-bibtex-zotero-test--bib
       '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf")
       '("snap" "Snapshot:/Users/me/Zotero/storage/AAAAAAA2/Two.html:text/html")
       '("weak" "/Users/me/Zotero/storage/AAAAAAA3/Wanted.pdf")
       '("gone" "/Users/me/Zotero/storage/ZZZZZZZ9/Nope.pdf")
       '("plain" "already.pdf"))
    (let* ((plan (sp-bibtex-zotero--plan file))
           (classes (mapcar (lambda (i) (cons (sp-bibtex-zotero--item-entry-key i) (sp-bibtex-zotero--item-class i)))
                            (sp-bibtex-zotero--items plan))))
      (should (equal classes '(("one" . move) ("snap" . skip) ("weak" . review) ("gone" . problem))))
      (should (equal (mapcar #'cdr (sp-bibtex-zotero--moves plan nil))
                     (list (expand-file-name "One.pdf" root))))
      (should (= 2 (length (sp-bibtex-zotero--moves plan t)))))))

(ert-deftest sp-bibtex-zotero-plan-existing-file-at-top ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "Same.pdf" "same") ("AAAAAAA2" "Diff.pdf" "mine") ("TOP" "Same.pdf" "same") ("TOP" "diff.pdf" "other"))
      (sp-bibtex-zotero-test--bib
       '("same" "/Users/me/Zotero/storage/AAAAAAA1/Same.pdf")
       '("diff" "/Users/me/Zotero/storage/AAAAAAA2/Diff.pdf"))
    (let ((plan (sp-bibtex-zotero--plan file)))
      (should (equal (sp-bibtex-zotero-test--statuses plan)
                     '(("same" . identical) ("diff" . collision))))
      (should-not (sp-bibtex-zotero--moves plan t)))))

(ert-deftest sp-bibtex-zotero-plan-name-clash-between-sources ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "Twin.pdf" "same") ("AAAAAAA2" "Twin.pdf" "same")
        ("AAAAAAA3" "Pair.pdf" "x") ("AAAAAAA4" "Pair.pdf" "y"))
      (sp-bibtex-zotero-test--bib
       '("t1" "/z/Zotero/storage/AAAAAAA1/Twin.pdf") '("t2" "/z/Zotero/storage/AAAAAAA2/Twin.pdf")
       '("p1" "/z/Zotero/storage/AAAAAAA3/Pair.pdf") '("p2" "/z/Zotero/storage/AAAAAAA4/Pair.pdf"))
    (let ((plan (sp-bibtex-zotero--plan file)))
      (should (equal (sp-bibtex-zotero-test--statuses plan)
                     '(("t1" . exact) ("t2" . duplicate) ("p1" . collision) ("p2" . collision))))
      (should (= 1 (length (sp-bibtex-zotero--moves plan nil)))))))

(ert-deftest sp-bibtex-zotero-plan-unsafe-name ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "a;b.pdf" "1"))
      (sp-bibtex-zotero-test--bib '("k" "/z/Zotero/storage/AAAAAAA1/a\\;b.pdf"))
    (should (equal (sp-bibtex-zotero-test--statuses (sp-bibtex-zotero--plan file)) '(("k" . unsafe-name))))))

;;;; The dry run

(ert-deftest sp-bibtex-zotero-dryrun-changes-nothing ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1") ("AAAAAAA3" "Other.pdf" "3"))
      (sp-bibtex-zotero-test--bib
       '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf")
       '("weak" "/Users/me/Zotero/storage/AAAAAAA3/Wanted.pdf")
       '("gone" "/Users/me/Zotero/storage/ZZZZZZZ9/Nope.pdf"))
    (let ((before (sp-bibtex-zotero-test--text file)) shown)
      (cl-letf (((symbol-function 'sp-batch-report-open)
                 (lambda (_name text &rest _) (setq shown text)))
                ((symbol-function 'sp-bibtex-lint--read-file) (lambda (&rest _) file))
                ((symbol-function 'sp-bibtex-files--call-tool)
                 (lambda (_args) (cons 0 "{\"to_move\": 1, \"plain\": 0, \"blocked\": [], \"done\": 0}"))))
        (sp-bibtex-zotero-dryrun file))
      (should (equal before (sp-bibtex-zotero-test--text file)))
      (should (file-exists-p (expand-file-name "inbox/zotero-backup/AAAAAAA1/One.pdf" root)))
      (should-not (file-exists-p (expand-file-name "One.pdf" root)))
      (should-not sp-bibtex-zotero-test--moves)
      (should (string-match-p "dry run, nothing changed" shown))
      (should (string-match-p "^\\* To move (1)\n| Entry" shown))
      (should (string-match-p "^\\* Review: weak matches.*(1)" shown))
      (should (string-match-p "^\\* Not matched.*(1)" shown))
      (should (string-match-p "no folder in the backup" shown))
      (should (string-match-p "1 records would be moved" shown))
      (should (string-match-p "sp-bibtex-zotero:apply:" shown)))))

(ert-deftest sp-bibtex-zotero-dryrun-says-when-devonthink-is-not-running ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1"))
      (sp-bibtex-zotero-test--bib '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf"))
    (setq sp-bibtex-zotero-test--running nil)
    (let ((text (sp-bibtex-zotero--render file (sp-bibtex-zotero--plan file))))
      (should (string-match-p "DEVONthink is not running" text)))))

;;;; Applying

(ert-deftest sp-bibtex-zotero-convert-moves-and-rewrites ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1") ("AAAAAAA2" "Two.html" "<html>") ("AAAAAAA3" "Other.pdf" "3") ("AAAAAAA6" "Six.pdf" "6"))
      (sp-bibtex-zotero-test--bib
       '("one" "One Label:/Users/me/Zotero/storage/AAAAAAA1/One.pdf:application/pdf;Snapshot:/Users/me/Zotero/storage/AAAAAAA2/Two.html:text/html")
       '("weak" "/Users/me/Zotero/storage/AAAAAAA3/Wanted.pdf")
       '("gone" "/Users/me/Zotero/storage/ZZZZZZZ9/Nope.pdf")
       '("six" "/Users/me/Zotero/storage/AAAAAAA6/Six.pdf;inbox/mac-bibdesk/keep.pdf"))
    (let ((before (sp-bibtex-zotero-test--text file)))
      (sp-bibtex-zotero-convert file)
      (let ((after (sp-bibtex-zotero-test--text file)))
        (should (string-match-p "file = {One.pdf;Snapshot:/Users/me/Zotero/storage/AAAAAAA2/Two.html:text/html}" after))
        (should (string-match-p "file = {Six.pdf;inbox/mac-bibdesk/keep.pdf}" after))
        ;; Weak and unmatched paths are untouched.
        (should (string-match-p "AAAAAAA3/Wanted.pdf" after))
        (should (string-match-p "ZZZZZZZ9/Nope.pdf" after)))
      ;; The PDFs moved, the snapshot and the weak match did not.
      (should (equal "1" (sp-bibtex-zotero-test--text (expand-file-name "One.pdf" root))))
      (should-not (file-exists-p (expand-file-name "inbox/zotero-backup/AAAAAAA1/One.pdf" root)))
      (should (file-exists-p (expand-file-name "inbox/zotero-backup/AAAAAAA2/Two.html" root)))
      (should (file-exists-p (expand-file-name "inbox/zotero-backup/AAAAAAA3/Other.pdf" root)))
      (should-not (file-exists-p (expand-file-name "Other.pdf" root)))
      ;; The copy and the manifest are there.
      (let ((runs (sp-bibtex-zotero--manifests file)))
        (should (= 1 (length runs)))
        (should (= 2 (length (plist-get (cdar runs) :moves))))
        (should (equal before (sp-bibtex-zotero-test--text
                               (expand-file-name "a.bib" (file-name-directory (caar runs))))))))))

(ert-deftest sp-bibtex-zotero-convert-with-weak-matches ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA3" "Other.pdf" "3"))
      (sp-bibtex-zotero-test--bib '("weak" "/Users/me/Zotero/storage/AAAAAAA3/Wanted.pdf"))
    (sp-bibtex-zotero-convert file t)
    (should (string-match-p "file = {Other.pdf}" (sp-bibtex-zotero-test--text file)))
    (should (file-exists-p (expand-file-name "Other.pdf" root)))))

(ert-deftest sp-bibtex-zotero-convert-never-overwrites ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "Mine.pdf" "from the backup") ("TOP" "mine.pdf" "already here"))
      (sp-bibtex-zotero-test--bib '("k" "/Users/me/Zotero/storage/AAAAAAA1/Mine.pdf"))
    (let ((before (sp-bibtex-zotero-test--text file)))
      (sp-bibtex-zotero-convert file)
      (should (equal before (sp-bibtex-zotero-test--text file)))
      (should (equal "already here" (sp-bibtex-zotero-test--text (expand-file-name "mine.pdf" root))))
      (should (equal "from the backup"
                     (sp-bibtex-zotero-test--text
                      (expand-file-name "inbox/zotero-backup/AAAAAAA1/Mine.pdf" root)))))))

(ert-deftest sp-bibtex-zotero-convert-links-an-identical-file ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "Same.pdf" "same") ("TOP" "Same.pdf" "same"))
      (sp-bibtex-zotero-test--bib '("k" "/Users/me/Zotero/storage/AAAAAAA1/Same.pdf"))
    (sp-bibtex-zotero-convert file)
    (should (string-match-p "file = {Same.pdf}" (sp-bibtex-zotero-test--text file)))
    ;; The backup copy stays: nothing is deleted.
    (should (file-exists-p (expand-file-name "inbox/zotero-backup/AAAAAAA1/Same.pdf" root)))))

(ert-deftest sp-bibtex-zotero-convert-refuses-without-devonthink ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1"))
      (sp-bibtex-zotero-test--bib '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf"))
    (let ((before (sp-bibtex-zotero-test--text file)))
      (setq sp-bibtex-zotero-test--running nil)
      (should-error (sp-bibtex-zotero-convert file) :type 'user-error)
      (setq sp-bibtex-zotero-test--running t)
      (let ((sp-bibtex-files-devonthink-tool nil))
        (should-error (sp-bibtex-zotero-convert file) :type 'user-error))
      (should (equal before (sp-bibtex-zotero-test--text file)))
      (should (file-exists-p (expand-file-name "inbox/zotero-backup/AAAAAAA1/One.pdf" root)))
      (should-not sp-bibtex-zotero-test--moves)
      (should-not (file-directory-p sp-bibtex-lint-backup-directory)))))

(ert-deftest sp-bibtex-zotero-convert-rewrites-only-what-moved ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1") ("AAAAAAA2" "Two.pdf" "2"))
      (sp-bibtex-zotero-test--bib
       '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf")
       '("two" "/Users/me/Zotero/storage/AAAAAAA2/Two.pdf"))
    (setq sp-bibtex-zotero-test--fail-after 1)
    (should-error (sp-bibtex-zotero-convert file) :type 'user-error)
    (let ((after (sp-bibtex-zotero-test--text file)))
      (should (string-match-p "file = {One.pdf}" after))
      (should (string-match-p "AAAAAAA2/Two.pdf" after)))
    ;; The run is still in the manifests, so it can be restored.
    (should (plist-get (cdar (sp-bibtex-zotero--manifests file)) :hash-after))))

(ert-deftest sp-bibtex-zotero-convert-is-idempotent-and-sees-earlier-moves ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1"))
      (sp-bibtex-zotero-test--bib '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf"))
    (sp-bibtex-zotero-convert file)
    (let ((once (sp-bibtex-zotero-test--text file)))
      (sp-bibtex-zotero-convert file)
      (should (equal once (sp-bibtex-zotero-test--text file))))
    ;; A .bib file that still has the old path (the write was lost) is fixed from the manifest.
    (let ((plan (progn
                  (sp-bibtex-zotero-test--write
                   file (sp-bibtex-zotero-test--bib '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf")))
                  (sp-bibtex-zotero--plan file))))
      (should (equal (sp-bibtex-zotero-test--statuses plan) '(("one" . moved-before)))))))

;;;; Restoring

(ert-deftest sp-bibtex-zotero-restore-round-trip ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1"))
      (sp-bibtex-zotero-test--bib '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf"))
    (let ((before (sp-bibtex-zotero-test--text file)))
      (sp-bibtex-zotero-convert file)
      (should-not (equal before (sp-bibtex-zotero-test--text file)))
      (cl-letf (((symbol-function 'sp-bibtex-lint--read-file) (lambda (&rest _) file)))
        (sp-bibtex-zotero-restore file))
      (should (equal before (sp-bibtex-zotero-test--text file)))
      (should (file-exists-p (expand-file-name "inbox/zotero-backup/AAAAAAA1/One.pdf" root)))
      (should-not (file-exists-p (expand-file-name "One.pdf" root)))
      ;; The text as it was before the restore is kept, and the run is marked.
      (should (file-exists-p (expand-file-name "before-restore.bib"
                                               (file-name-directory (caar (sp-bibtex-zotero--manifests file))))))
      (should (plist-get (cdar (sp-bibtex-zotero--manifests file)) :restored))
      (should-error (sp-bibtex-zotero-restore file) :type 'user-error))))

(ert-deftest sp-bibtex-zotero-restore-refuses-when-the-bib-changed ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1"))
      (sp-bibtex-zotero-test--bib '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf"))
    (sp-bibtex-zotero-convert file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-max))
      (insert "% my own edit\n")
      (write-region (point-min) (point-max) file nil 'silent))
    (let ((edited (sp-bibtex-zotero-test--text file)))
      (should-error (sp-bibtex-zotero-restore file) :type 'user-error)
      (should (equal edited (sp-bibtex-zotero-test--text file)))
      (should (file-exists-p (expand-file-name "One.pdf" root))))))


(ert-deftest sp-bibtex-zotero-dropped-rows-are-not-applied ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1") ("AAAAAAA2" "Two.pdf" "2"))
      (sp-bibtex-zotero-test--bib
       '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf")
       '("two" "/Users/me/Zotero/storage/AAAAAAA2/Two.pdf"))
    (let* ((first (car (sp-bibtex-zotero--items (sp-bibtex-zotero--plan file))))
           (key (sp-bibtex-zotero--item-key file first))
           (sp-bibtex-zotero--excluded (list key))
           (plan (sp-bibtex-zotero--plan file))
           (text (sp-bibtex-zotero--render file plan (list key))))
      (should (= 1 (length (sp-bibtex-zotero--moves plan nil))))
      (should (string-match-p "^\\* To move (1)" text))
      (should (string-match-p "^\\* Dropped from the list.*(1)" text))
      (sp-bibtex-zotero-convert file)
      (should (string-match-p "AAAAAAA1/One.pdf" (sp-bibtex-zotero-test--text file)))
      (should (string-match-p "file = {Two.pdf}" (sp-bibtex-zotero-test--text file)))
      (should (file-exists-p (expand-file-name "inbox/zotero-backup/AAAAAAA1/One.pdf" root))))))

(ert-deftest sp-bibtex-zotero-report-tables-are-aligned-org ()
  (sp-bibtex-zotero-test--with-library
      '(("AAAAAAA1" "One.pdf" "1") ("AAAAAAA2" "Longer name.pdf" "2"))
      (sp-bibtex-zotero-test--bib
       '("one" "/Users/me/Zotero/storage/AAAAAAA1/One.pdf")
       '("two" "/Users/me/Zotero/storage/AAAAAAA2/Longer name.pdf"))
    (let* ((text (sp-bibtex-zotero--render file (sp-bibtex-zotero--plan file)))
           (rows (seq-filter (lambda (l) (string-prefix-p "|" l)) (split-string text "\n"))))
      (should (>= (length rows) 4))
      (should (= 1 (length (delete-dups (mapcar #'string-width rows))))))))

(provide 'sp-bibtex-zotero-test)
;;; sp-bibtex-zotero-test.el ends here
