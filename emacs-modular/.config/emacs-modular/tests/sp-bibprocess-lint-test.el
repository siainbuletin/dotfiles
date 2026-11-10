;;; sp-bibprocess-lint-test.el --- Tests for the .bib lint of sp-bibprocess -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'bibtex)
(require 'sp-async-work)
(require 'sp-batch-report)
(require 'sp-author-notes-bibtex)

;; sp-bibprocess needs the whole configuration; load only the lint part.
(defvar sp-bibprocess-lint-test--lint-file
  (expand-file-name "../libraries/modules/academic/sp-bibprocess.el"
                    (file-name-directory (or load-file-name buffer-file-name))))
(with-temp-buffer
  (insert-file-contents sp-bibprocess-lint-test--lint-file)
  (goto-char (point-min))
  (let ((start (search-forward ";;;; Linting the .bib files"))
        (end (progn (search-forward "(provide 'sp-bibprocess)") (match-beginning 0))))
    (eval (read (concat "(progn " (buffer-substring start end) ")")) t)))

(ert-deftest sp-bibtex-lint-test-canonical-name ()
  (should (equal "Smith, John" (sp-bibtex-canonical-name "John Smith")))
  (should (equal "Smith, John" (sp-bibtex-canonical-name "Smith,John")))
  (should (equal "Smith, J. M." (sp-bibtex-canonical-name "J. M. Smith")))
  (should (equal "van Gogh, Vincent" (sp-bibtex-canonical-name "Vincent van Gogh")))
  (should (equal "{Big Corp}" (sp-bibtex-canonical-name "{Big Corp}")))
  (should (equal "others" (sp-bibtex-canonical-name "others")))
  (should (equal "Plato" (sp-bibtex-canonical-name "Plato")))
  (should (equal "Smith, Jr, John" (sp-bibtex-canonical-name "Smith, Jr, John"))))

(ert-deftest sp-bibtex-lint-test-canonical-names ()
  (should (equal "Smith, John and Doe, Jane and {A and B Inc}"
                 (sp-bibtex-canonical-names "John Smith and Jane Doe and {A and B Inc}"))))

(ert-deftest sp-bibtex-lint-test-fields ()
  (let* ((fields '(("year" . "{2020}") ("title" . "{T}") ("author" . "{John Smith and Doe, Jane}")))
         (linted (sp-bibtex--lint-fields fields nil)))
    (should (equal (mapcar #'car (car linted)) '("author" "title" "year")))
    (should (equal (cdr (assoc "author" (car linted))) "{Smith, John and Doe, Jane}"))
    (should (= 2 (length (cdr linted))))))

(ert-deftest sp-bibtex-lint-test-suggestion ()
  (let ((people (sp-bibtex--make-people '("John Smith" "Jane Doe"))))
    (should (equal "Smith, John" (sp-bibtex--suggestion "Smyth, John" people)))
    (should-not (sp-bibtex--suggestion "Smith, John" people))
    (should-not (sp-bibtex--suggestion "Nobody, Else" people))))

(defvar sp-bibtex-files)
(defvar sp-bibtex-lint-backup-directory)
(defvar sp-bibtex-lint--excluded)

(defmacro sp-bibprocess-lint-test--with-bib (text &rest body)
  "Run BODY with FILE a .bib file holding TEXT, and the lint set up to use it."
  (declare (indent 1))
  `(let* ((dir (file-name-as-directory (make-temp-file "sp-bib" t)))
          (file (expand-file-name "a.bib" dir))
          (sp-bibtex-files (list file))
          (sp-bibtex-lint-backup-directory (expand-file-name "bk/" dir))
          (sp-async-work-synchronous t)
          (sp-bibtex-lint--excluded nil)
          (sp-bibtex--people-cache (cons (float-time) (sp-bibtex--make-people nil))))
     (unwind-protect
         (progn (with-temp-file file (insert ,text)) ,@body)
       (delete-directory dir t))))

(defun sp-bibprocess-lint-test--text (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun sp-bibprocess-lint-test--entries (n)
  "N entries whose names and fields need fixing."
  (mapconcat (lambda (i)
               (format "@article{k%d,\n  year = {2020},\n  author = {John Smith%d},\n  title = {T}}\n" i i))
             (number-sequence 1 n) "\n"))

(defun sp-bibprocess-lint-test--convert (file answers &optional command)
  "Run COMMAND (default `sp-bibtex-lint-fix-order') on FILE, giving ANSWERS to what it asks.
Batches of author names are answered with ?a, ?s or ?q; the single question of
the order and indent fixes with ?a for yes.  Return the number of entries of
each question that was asked."
  (let (sizes)
    (cl-letf (((symbol-function 'sp-bibtex-lint--ask-batch)
               (lambda (_file batch &rest _) (push (length batch) sizes) (pop answers)))
              ((symbol-function 'sp-bibtex-lint--confirm)
               (lambda (_file _kind count) (push count sizes) (eq ?a (pop answers)))))
      (funcall (or command #'sp-bibtex-lint-fix-order) file))
    (nreverse sizes)))

(ert-deftest sp-bibtex-lint-test-results ()
  (sp-bibprocess-lint-test--with-bib
      (concat "@article{a1,\n  year = {2020},\n  author = {John Smith and Jane Doe},\n  title = {T}}\n\n"
              "@article{a2,\n  % keep me\n  year = {2020},\n  author = {John Smith},\n  title = {T}}\n\n"
              "@article{a1,\n  author = {Doe, Jane},\n  title = {Dup}}\n")
    (let (results)
      (sp-bibtex-lint--job "t" (list file) '(order indent authors notes) (lambda (r) (setq results r)))
      (should (= 3 (length results)))
      ;; The second has a comment and is left alone; the third is a duplicate, and only its
      ;; indentation can be changed.
      (should (equal '(t nil t) (mapcar (lambda (r) (and (nth 4 r) t)) results)))
      (should (equal '(indent order authors) (mapcar #'car (nth 4 (car results)))))
      (should (equal '(indent) (mapcar #'car (nth 4 (nth 2 results))))))))

(ert-deftest sp-bibtex-lint-test-convert-applies ()
  (sp-bibprocess-lint-test--with-bib
      (concat "@article{a1,\n  year = {2020},\n  author = {John Smith and Jane Doe},\n  title = {T}}\n\n"
              "@article{a2,\n  % keep me\n  year = {2020},\n  author = {John Smith},\n  title = {T}}\n")
    (should (equal '(1) (sp-bibprocess-lint-test--convert file '(?a))))
    (let ((text (sp-bibprocess-lint-test--text file)))
      (should (string-match-p "author =[ \t]+{John Smith and Jane Doe}" text))
      (should (< (string-match "author =[ \t]+{John" text) (string-match "year =[ \t]+{2020}" text)))
      ;; The entry with a comment is untouched.
      (should (string-match-p "% keep me\n  year = {2020},\n  author = {John Smith}" text)))
    (should (directory-files-recursively sp-bibtex-lint-backup-directory "a\\.bib\\'"))))

(ert-deftest sp-bibtex-lint-test-order-is-not-batched ()
  (let ((sp-bibtex-lint-batch-size 2))
    (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 5)
      ;; One question for all five entries, in spite of the batch size.
      (should (equal '(5) (sp-bibprocess-lint-test--convert file '(?a))))
      (let ((text (sp-bibprocess-lint-test--text file)))
        (dotimes (i 5)
          (should (< (string-match (format "k%d," (1+ i)) text)
                     (string-match (format "author =[ \t]+{John Smith%d}" (1+ i)) text)
                     (string-match "year =[ \t]+{2020}" text (string-match (format "k%d," (1+ i)) text))))))
      (should (directory-files-recursively sp-bibtex-lint-backup-directory "a\\.bib\\'")))))

(ert-deftest sp-bibtex-lint-test-order-declined-writes-nothing ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 3)
    (let ((before (sp-bibprocess-lint-test--text file)))
      (should (equal '(3) (sp-bibprocess-lint-test--convert file '(?n))))
      (should (equal before (sp-bibprocess-lint-test--text file)))
      (should-not (file-exists-p sp-bibtex-lint-backup-directory)))))

(ert-deftest sp-bibtex-lint-test-authors-batches ()
  (let ((sp-bibtex-lint-batch-size 2))
    (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 5)
      ;; Apply the first batch, skip the second, apply the third.
      (should (equal '(2 2 1) (sp-bibprocess-lint-test--convert file '(?a ?s ?a) #'sp-bibtex-lint-fix-authors)))
      (let ((text (sp-bibprocess-lint-test--text file)))
        (should (string-match-p "author =[ \t]+{Smith1, John}" text))
        (should (string-match-p "author =[ \t]+{Smith2, John}" text))
        (should (string-match-p "author =[ \t]+{John Smith3}" text))
        (should (string-match-p "author =[ \t]+{John Smith4}" text))
        (should (string-match-p "author =[ \t]+{Smith5, John}" text))))))

(ert-deftest sp-bibtex-lint-test-convert-default-batch-size ()
  (should (= 50 (default-value 'sp-bibtex-lint-batch-size)))
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 120)
    (should (equal '(50 50 20) (sp-bibprocess-lint-test--convert file '(?s ?s ?s) #'sp-bibtex-lint-fix-authors)))))

(ert-deftest sp-bibtex-lint-test-convert-writes-nothing-unasked ()
  (let ((sp-bibtex-lint-batch-size 2))
    (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 3)
      (let ((before (sp-bibprocess-lint-test--text file)))
        ;; Skipping, then quitting: the next batch is not even shown.
        (should (equal '(2 1) (sp-bibprocess-lint-test--convert file '(?s ?q) #'sp-bibtex-lint-fix-authors)))
        (should (equal before (sp-bibprocess-lint-test--text file)))
        (should-not (file-exists-p sp-bibtex-lint-backup-directory))
        (should (equal '(2) (sp-bibprocess-lint-test--convert file '(?q) #'sp-bibtex-lint-fix-authors)))
        (should (equal before (sp-bibprocess-lint-test--text file)))))))

(ert-deftest sp-bibtex-lint-test-convert-file-changed-on-disk ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 1)
    (cl-letf (((symbol-function 'sp-bibtex-lint--confirm)
               (lambda (&rest _)
                 ;; The file changes between the lint and the answer.
                 (let ((new (replace-regexp-in-string "John" "Johnny" (sp-bibprocess-lint-test--text file)))) (sleep-for 1.1) (with-temp-file file (insert new)))
                 t)))
      (should-error (sp-bibtex-lint-fix-order file) :type 'user-error))
    ;; Neither written nor backed up.
    (should (string-match-p "author =[ \t]+{Johnny Smith1}" (sp-bibprocess-lint-test--text file)))
    (should-not (file-exists-p sp-bibtex-lint-backup-directory))))

(ert-deftest sp-bibtex-lint-test-convert-refuses-unsaved-buffer ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 1)
    (let ((buffer (find-file-noselect file)))
      (unwind-protect
          (progn
            (with-current-buffer buffer (insert "x"))
            (should-error (sp-bibtex-lint-fix-order file) :type 'user-error))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(ert-deftest sp-bibtex-lint-test-read-file ()
  (sp-bibprocess-lint-test--with-bib "@article{a,\n}\n"
    ;; In a .bib buffer the file is taken without asking.
    (with-temp-buffer
      (setq buffer-file-name file)
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (error "asked"))))
        (should (equal file (sp-bibtex-lint--read-file)))))
    ;; Elsewhere, or with ASK, it is read from the registered files.
    (with-temp-buffer
      (cl-letf (((symbol-function 'completing-read) (lambda (_prompt coll &rest _) (car coll))))
        (should (equal file (sp-bibtex-lint--read-file)))))
    (with-temp-buffer
      (setq buffer-file-name "/tmp/not-a-bib.txt")
      (cl-letf (((symbol-function 'completing-read) (lambda (_prompt coll &rest _) (car coll))))
        (should (equal file (sp-bibtex-lint--read-file t)))))))

(ert-deftest sp-bibtex-lint-test-dryrun-report ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 2)
    (let ((before (sp-bibprocess-lint-test--text file)))
      (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
        (sp-bibtex-lint-dryrun file))
      (should (equal before (sp-bibprocess-lint-test--text file)))
      (with-current-buffer sp-bibtex-lint--buffer
        (should (derived-mode-p 'sp-batch-report-mode))
        (should (string-match-p "2 entries with problems" (buffer-string)))
        ;; Each entry links to its own line.
        (should (string-match-p (format "\\[\\[file:%s::1\\]\\[k1\\]\\]" (regexp-quote file)) (buffer-string)))
        (should (string-match-p (format "\\[\\[file:%s::6\\]\\[k2\\]\\]" (regexp-quote file)) (buffer-string))))
      (kill-buffer sp-bibtex-lint--buffer))))

(ert-deftest sp-bibtex-lint-test-order-only-touches-order ()
  (sp-bibprocess-lint-test--with-bib
      (concat "@article{ok,\n  author = {Smith, John},\n  title = {T}\n}\n\n"
              "@article{bad,\n  year = {2020},\n  author = {John Smith},\n  title = {T}\n}\n")
    ;; One entry has its fields out of order; the names are not touched by this fix.
    (should (equal '(1) (sp-bibprocess-lint-test--convert file '(?a))))
    (let ((text (sp-bibprocess-lint-test--text file)))
      (should (string-match-p "author =[ \t]+{John Smith}" text))
      (should (< (string-match "author" (substring text (string-match "@article{bad" text)))
                 (string-match "year" (substring text (string-match "@article{bad" text)))))
      ;; The entry that was in order is exactly as it was.
      (should (string-prefix-p "@article{ok,\n  author = {Smith, John},\n  title = {T}\n}\n" text)))))

(ert-deftest sp-bibtex-lint-test-indent ()
  (sp-bibprocess-lint-test--with-bib
      (concat "@article{a,\nauthor   =   {Smith, John},\n      title = {T}\n}\n\n"
              "@article{b,\n  author =\t {Smith, Jane},\n  title =\t {T}\n}\n")
    (let ((fixed (with-temp-buffer
                   (delay-mode-hooks (bibtex-mode))
                   (insert "@article{a,\nauthor   =   {Smith, John},\n      title = {T}\n}")
                   (goto-char (point-min))
                   (bibtex-fill-entry)
                   (buffer-string))))
      ;; Only the first entry differs from the bibtex-mode layout.
      (should (equal '(1) (sp-bibprocess-lint-test--convert file '(?a) #'sp-bibtex-lint-fix-indent)))
      (let ((text (sp-bibprocess-lint-test--text file)))
        (should (string-prefix-p fixed text))
        ;; The order and the names are as they were.
        (should (string-match-p "author =[ \t]+{Smith, John},\n  title" text))
        (should (string-match-p "@article{b,\n  author =\t {Smith, Jane},\n  title =\t {T}\n}" text))))))

(ert-deftest sp-bibtex-lint-test-authors-form-only ()
  (sp-bibprocess-lint-test--with-bib
      "@article{a,\n  year = {2020},\n  author = {John Smith},\n  title = {T}\n}\n"
    (should (equal '(1) (sp-bibprocess-lint-test--convert file '(?a) #'sp-bibtex-lint-fix-authors)))
    (let ((text (sp-bibprocess-lint-test--text file)))
      (should (string-match-p "author =[ \t]+{Smith, John}" text))
      ;; Names are the only change: the year still comes first.
      (should (< (string-match "year" text) (string-match "author" text))))))

(defmacro sp-bibprocess-lint-test--with-notes (&rest body)
  "Run BODY with an author note for John Smith, FILE a .bib with a typo of his name.
NOTE is the note file; aliases are added by a stub that appends to ADDED."
  `(sp-bibprocess-lint-test--with-bib
       (concat "@article{a,\n  author = {Smyth, John},\n  title = {T}\n}\n\n"
               "@article{b,\n  author = {Smyth, John and Doe, Jane},\n  title = {U}\n}\n")
     (let* ((note (expand-file-name "smith.org" dir))
            (added nil)
            (sp-bibtex--people-cache
             (cons (float-time)
                   (sp-bibtex--make-people (list (list :title "John Smith" :file note))))))
       (with-temp-file note (insert ":PROPERTIES:\n:ID: x\n:END:\n#+title: John Smith\n"))
       (cl-letf (((symbol-function 'sp-bibtex-lint--add-alias)
                  (lambda (f alias) (push (cons f alias) added))))
         ,@body))))

(ert-deftest sp-bibtex-lint-test-notes-normalise ()
  (sp-bibprocess-lint-test--with-notes
   (cl-letf (((symbol-function 'sp-bibtex-lint--ask-notes) (lambda (&rest _) ?n)))
     (sp-bibtex-lint-fix-authors file))
   (let ((text (sp-bibprocess-lint-test--text file)))
     (should-not (string-match-p "Smyth" text))
     (should (string-match-p "author =[ \t]+{Smith, John}" text))
     ;; The other name of the second entry is untouched.
     (should (string-match-p "{Smith, John and Doe, Jane}" text)))
   (should-not added)
   (should (directory-files-recursively sp-bibtex-lint-backup-directory "a\\.bib\\'"))))

(ert-deftest sp-bibtex-lint-test-notes-alias ()
  (sp-bibprocess-lint-test--with-notes
   (let ((before (sp-bibprocess-lint-test--text file)))
     (cl-letf (((symbol-function 'sp-bibtex-lint--ask-notes) (lambda (&rest _) ?l)))
       (sp-bibtex-lint-fix-authors file))
     ;; An alias changes the note, not the .bib file, and needs no backup of it.
     (should (equal before (sp-bibprocess-lint-test--text file)))
     (should-not (file-exists-p sp-bibtex-lint-backup-directory))
     (should (equal (list (cons note "Smyth, John")) (delete-dups (copy-sequence added)))))))

(ert-deftest sp-bibtex-lint-test-notes-each-case ()
  (sp-bibprocess-lint-test--with-notes
   (let ((answers '(?n ?l)))
     (cl-letf (((symbol-function 'sp-bibtex-lint--ask-notes) (lambda (&rest _) ?e))
               ((symbol-function 'sp-bibtex-lint--ask-case) (lambda (_case) (pop answers))))
       (sp-bibtex-lint-fix-authors file)))
   (let ((text (sp-bibprocess-lint-test--text file)))
     ;; The first entry was normalised; the second got an alias and kept its name.
     (should (string-match-p "@article{a,\n  author =[ \t]+{Smith, John}" text))
     (should (string-match-p "{Smyth, John and Doe, Jane}" text)))
   (should (= 1 (length added)))))

(ert-deftest sp-bibtex-lint-test-notes-skip-and-quit-write-nothing ()
  (sp-bibprocess-lint-test--with-notes
   (let ((before (sp-bibprocess-lint-test--text file)))
     (dolist (answer '(?s ?q))
       (cl-letf (((symbol-function 'sp-bibtex-lint--ask-notes) (lambda (&rest _) answer)))
         (sp-bibtex-lint-fix-authors file)))
     (should (equal before (sp-bibprocess-lint-test--text file)))
     (should-not added)
     (should-not (file-exists-p sp-bibtex-lint-backup-directory)))))

(ert-deftest sp-bibtex-lint-test-notes-each-case-quit ()
  (sp-bibprocess-lint-test--with-notes
   (let ((before (sp-bibprocess-lint-test--text file)))
     (cl-letf (((symbol-function 'sp-bibtex-lint--ask-notes) (lambda (&rest _) ?e))
               ((symbol-function 'sp-bibtex-lint--ask-case) (lambda (_case) ?q)))
       (sp-bibtex-lint-fix-authors file))
     (should (equal before (sp-bibprocess-lint-test--text file)))
     (should-not added))))

(ert-deftest sp-bibtex-lint-test-given-names-compatible ()
  (let ((fits (lambda (given note) (sp-bibtex--initials-compatible-p given note))))
    ;; Initials, with or without dots and spaces, and a name written out, fit the note.
    (dolist (given '("TW" "T. W." "T" "Theodor" "Theodor W." "T W" "Theodor W. X." "TWX"))
      (should (funcall fits given "Theodor W.")))
    ;; A different first name, a wrong middle initial or too many names do not.
    (dolist (given '("W" "Michael" "M" "Theodor Ludwig" "Theodore" "TL"))
      (should-not (funcall fits given "Theodor W.")))
    (should (funcall fits "J-P" "Jean-Paul"))
    (should-not (funcall fits "" "Theodor W."))))

(ert-deftest sp-bibtex-lint-test-surname-match ()
  (let ((people (sp-bibtex--make-people '("Theodor W. Adorno" "John Smith" "Michael Smith"
                                          "Tamara Adorno"))))
    (should (equal '("Adorno, Theodor W.") (sp-bibtex--surname-match "Adorno, TW" people)))
    (should (equal '("Adorno, Theodor W.") (sp-bibtex--surname-match "Adorno, Theodor" people)))
    ;; Same surname and a T that fits two notes: ambiguous.
    (should (= 2 (length (sp-bibtex--surname-match "Adorno, T" people))))
    ;; John Smith is not Michael Smith.
    (should (equal '("Smith, John") (sp-bibtex--surname-match "Smith, J" people)))
    (should (equal '("Smith, Michael") (sp-bibtex--surname-match "Smith, Michael R." people)))
    (should-not (sp-bibtex--surname-match "Smith, M. J. X." (sp-bibtex--make-people '("John Smith"))))
    (should-not (sp-bibtex--surname-match "Smith, Peter" people))
    ;; A name of a note, a name without given names and another surname are not matches.
    (should-not (sp-bibtex--surname-match "Smith, John" people))
    (should-not (sp-bibtex--surname-match "Adorno" people))
    (should-not (sp-bibtex--surname-match "Nobody, T" people))))

(defmacro sp-bibprocess-lint-test--with-surnames (text &rest body)
  "Run BODY with notes for Theodor W. Adorno, John Smith and Michael Smith, and TEXT as the .bib."
  (declare (indent 1))
  `(sp-bibprocess-lint-test--with-bib ,text
     (let* ((adorno (expand-file-name "adorno.org" dir))
            (added nil)
            (sp-bibtex--people-cache
             (cons (float-time)
                   (sp-bibtex--make-people
                    (list (list :title "Theodor W. Adorno" :file adorno)
                          "John Smith" "Michael Smith")))))
       (with-temp-file adorno (insert "#+title: Theodor W. Adorno\n"))
       (cl-letf (((symbol-function 'sp-bibtex-lint--add-alias)
                  (lambda (f alias) (push (cons f alias) added))))
         ,@body))))

(ert-deftest sp-bibtex-lint-test-surname-normalise ()
  (sp-bibprocess-lint-test--with-surnames
      (concat "@article{a,\n  author = {TW Adorno and John Smith},\n  title = {T}\n}\n\n"
              "@article{b,\n  author = {Theodor Adorno},\n  title = {U}\n}\n")
    (cl-letf (((symbol-function 'sp-bibtex-lint--ask-batch) (lambda (&rest _) ?a))
              ((symbol-function 'sp-bibtex-lint--ask-notes) (lambda (&rest _) ?n)))
      (sp-bibtex-lint-fix-authors file))
    (let ((text (sp-bibprocess-lint-test--text file)))
      (should (string-match-p "author =[ \t]+{Adorno, Theodor W. and Smith, John}" text))
      (should (string-match-p "author =[ \t]+{Adorno, Theodor W.}" text)))
    (should-not added)))

(ert-deftest sp-bibtex-lint-test-surname-alias ()
  (sp-bibprocess-lint-test--with-surnames
      "@article{a,\n  author = {Adorno, TW},\n  title = {T}\n}\n"
    (let ((before (sp-bibprocess-lint-test--text file)))
      (cl-letf (((symbol-function 'sp-bibtex-lint--ask-notes) (lambda (&rest _) ?l)))
        (sp-bibtex-lint-fix-authors file))
      (should (equal before (sp-bibprocess-lint-test--text file)))
      (should (equal (list (cons adorno "Adorno, TW")) added)))))

(ert-deftest sp-bibtex-lint-test-surname-ambiguous-and-other-smith-untouched ()
  (sp-bibprocess-lint-test--with-surnames
      (concat "@article{a,\n  author = {Smith, Peter and Adorno, T},\n  title = {T}\n}\n")
    ;; Peter Smith matches no note; T Adorno would fit only one note here, so add another.
    (setq sp-bibtex--people-cache
          (cons (float-time)
                (sp-bibtex--make-people (list "Theodor W. Adorno" "Tamara Adorno" "John Smith"))))
    (let ((before (sp-bibprocess-lint-test--text file)))
      (cl-letf (((symbol-function 'sp-bibtex-lint--ask-notes) (lambda (&rest _) ?n)))
        (sp-bibtex-lint-fix-authors file))
      (should (equal before (sp-bibprocess-lint-test--text file)))
      (should-not added))))

(ert-deftest sp-bibtex-lint-test-report-sections ()
  (sp-bibprocess-lint-test--with-surnames
      (concat "@article{a,\n  author = {TW Adorno},\n  title = {T}\n}\n\n"
              "@article{b,\n  author = {Smyth, John},\n  title = {T}\n}\n")
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-bibtex-lint-dryrun file))
    (with-current-buffer sp-bibtex-lint--buffer
      (let ((text (buffer-string)))
        ;; The typo is in the main list; the surname match has its own section.
        (should (string-match "\\* \\[\\[[^]]*\\]\\[b\\]\\]" text))
        (should (string-match "^\\* Same surname as an author note (1)\n\\*\\* \\[\\[[^]]*\\]\\[a\\]\\]\n- author: Adorno, TW → Adorno, Theodor W. (same surname)" text))
        (should (< (string-match "\\[b\\]" text) (string-match "Same surname as" text)))
        (should-not (string-match-p "did you mean Adorno" text))))
    (kill-buffer sp-bibtex-lint--buffer)))


(defun sp-bibprocess-lint-test--keys (&rest answers)
  "Make `read-char-choice' give ANSWERS in turn; return the list of the answers given."
  (let (given)
    (cons (lambda (&rest _) (let ((a (pop answers))) (push a given) a))
          (lambda () (nreverse given)))))

(ert-deftest sp-bibtex-lint-test-drop-in-batch ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 3)
    (let* ((keys (sp-bibprocess-lint-test--keys ?d ?a))
           (shown nil))
      ;; Drop k2 for later, then apply the batch: k1 and k3 change, k2 does not.
      (cl-letf (((symbol-function 'read-char-choice) (car keys))
                ((symbol-function 'sp-bibtex-lint--choose) (lambda (_prompt candidates)
                                                               (setq shown candidates) '("k2"))))
        (sp-bibtex-lint-fix-authors file))
      (should (equal '("k1" "k2" "k3") shown))
      (let ((text (sp-bibprocess-lint-test--text file)))
        (should (string-match-p "author =[ \t]+{Smith1, John}" text))
        (should (string-match-p "author =[ \t]+{John Smith2}" text))
        (should (string-match-p "author =[ \t]+{Smith3, John}" text)))
      (should (equal (list (sp-bibtex-lint--entry-key file "k2")) sp-bibtex-lint--excluded)))))

(ert-deftest sp-bibtex-lint-test-dropped-stays-out-of-later-runs ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 3)
    (setq sp-bibtex-lint--excluded (list (sp-bibtex-lint--entry-key file "k2")))
    ;; Only two entries are asked about (and skipped here).
    (should (equal '(2) (sp-bibprocess-lint-test--convert file '(?s) #'sp-bibtex-lint-fix-authors)))
    ;; Bring k2 back with `u' while a batch is asked, then skip that batch.
    (let ((keys (sp-bibprocess-lint-test--keys ?u ?s)))
      (cl-letf (((symbol-function 'read-char-choice) (car keys))
                ((symbol-function 'sp-bibtex-lint--choose) (lambda (&rest _) '("k2"))))
        (sp-bibtex-lint-fix-authors file)))
    (should-not sp-bibtex-lint--excluded)
    ;; The next run has all three, and k2 is fixed with the others.
    (should (equal '(3) (sp-bibprocess-lint-test--convert file '(?a) #'sp-bibtex-lint-fix-authors)))
    (should (string-match-p "author =[ \t]+{Smith2, John}" (sp-bibprocess-lint-test--text file)))))

(ert-deftest sp-bibtex-lint-test-drop-everything-skips-the-batch ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 2)
    (let ((before (sp-bibprocess-lint-test--text file))
          (keys (sp-bibprocess-lint-test--keys ?d ?a)))
      (cl-letf (((symbol-function 'read-char-choice) (car keys))
                ((symbol-function 'sp-bibtex-lint--choose) (lambda (&rest _) '("k1" "k2"))))
        (sp-bibtex-lint-fix-authors file))
      (should (equal before (sp-bibprocess-lint-test--text file)))
      (should-not (file-exists-p sp-bibtex-lint-backup-directory)))))

(ert-deftest sp-bibtex-lint-test-order-ignores-dropped ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 2)
    (setq sp-bibtex-lint--excluded (list (sp-bibtex-lint--entry-key file "k1")))
    ;; Dropping is for the author fixes only: the order fix still takes both entries.
    (should (equal '(2) (sp-bibprocess-lint-test--convert file '(?a))))))

(ert-deftest sp-bibtex-lint-test-drop-in-notes-batch ()
  (sp-bibprocess-lint-test--with-notes
   (let ((keys (sp-bibprocess-lint-test--keys ?d ?n)))
     ;; Drop entry a; the typo of entry b is normalised.
     (cl-letf (((symbol-function 'read-char-choice) (car keys))
               ((symbol-function 'sp-bibtex-lint--choose) (lambda (&rest _) '("a"))))
       (sp-bibtex-lint-fix-authors file)))
   (let ((text (sp-bibprocess-lint-test--text file)))
     (should (string-match-p "@article{a,\n  author = {Smyth, John}" text))
     (should (string-match-p "@article{b,\n  author =[ \t]+{Smith, John and Doe, Jane}" text)))))

(ert-deftest sp-bibtex-lint-test-report-drop-and-restore ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 2)
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-bibtex-lint-dryrun file)
      (with-current-buffer sp-bibtex-lint--buffer
        (goto-char (point-min))
        (re-search-forward "\\[k1\\]")
        ;; `d' drops the entry at point; it moves to the dropped section.
        (sp-batch-report-drop)
        (should (equal (list (sp-bibtex-lint--entry-key file "k1")) sp-bibtex-lint--excluded))
        (let ((text (buffer-string)))
          (should (string-match "Dropped from the list (u brings one back) (1)" text))
          (should (< (string-match "\\[k2\\]" text) (string-match "Dropped from the list" text)))
          (should (string-match-p "k1 in " (substring text (string-match "Dropped from the list" text))))
          (should (string-match-p "1 entry with problems" text))
          ;; The order button still counts both.
          (should (string-match-p "field order (2)" text))
          (should (string-match-p "author names (1)" text)))
        ;; `u' on the dropped entry brings it back.
        (goto-char (point-min))
        (re-search-forward "k1 in ")
        (sp-batch-report-restore)
        (should-not sp-bibtex-lint--excluded)
        (should-not (string-match-p "Dropped from the list" (buffer-string)))
        (should (string-match-p "2 entries with problems" (buffer-string)))))
    (kill-buffer sp-bibtex-lint--buffer)))

(ert-deftest sp-bibtex-lint-test-restore-command ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 2)
    (setq sp-bibtex-lint--excluded (list (sp-bibtex-lint--entry-key file "k1")
                                         (sp-bibtex-lint--entry-key file "k2")
                                         "/elsewhere/b.bib::k1"))
    (cl-letf (((symbol-function 'sp-bibtex-lint--choose) (lambda (_p candidates) (list (car candidates)))))
      (sp-bibtex-lint-restore-dropped file))
    (should (equal (list (sp-bibtex-lint--entry-key file "k2") "/elsewhere/b.bib::k1")
                   sp-bibtex-lint--excluded))))


(ert-deftest sp-bibtex-lint-test-rename-names ()
  (should (equal '(("author" . "{Smith, John and Doe, Jane}") ("title" . "{T}"))
                 (sp-bibtex--rename-names
                  '(("author" . "{Smyth, John and Doe, Jane}") ("title" . "{T}"))
                  '(("author" "Smyth, John" "Smith, John" nil))))))

(ert-deftest sp-bibtex-lint-test-people-aliases ()
  (let* ((dir (file-name-as-directory (make-temp-file "sp-bib" t)))
         (note (expand-file-name "smith.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file note
            (insert ":PROPERTIES:\n:ID: x\n:ROAM_ALIASES: \"Smyth, John\" Jonny\n:END:\n#+title: John Smith\n"))
          (should (equal '("Smyth, John" "Jonny") (sp-bibtex--note-aliases note)))
          (let ((people (sp-bibtex--make-people (list (list :title "John Smith" :file note)))))
            ;; A name that is an alias is known, so it is not suggested to be a typo.
            (should-not (sp-bibtex--suggestion "Smyth, John" people))
            (should (equal "Smith, John" (sp-bibtex--suggestion "Smyth, Johm" people)))
            (should (equal note (gethash (sp-bibtex--name-key "Smith, John") (plist-get people :files))))
            (should (equal '("Smith, John") (plist-get people :names)))))
      (delete-directory dir t))))

(ert-deftest sp-bibtex-lint-test-report-buttons ()
  (sp-bibprocess-lint-test--with-bib
      (concat "@article{a,\n  year = {2020},\n  author = {John Smith},\n  title = {T}\n}\n\n"
              "@article{b,\n  author = {Smith, Jane},\n  title = {T}\n}\n")
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-bibtex-lint-dryrun file))
    (with-current-buffer sp-bibtex-lint--buffer
      (let ((text (buffer-string)))
        (should (string-match-p (format "\\[\\[sp-bibtex-lint:order:%s\\]\\[field order (1)\\]\\]" (regexp-quote file)) text))
        (should (string-match-p (format "\\[\\[sp-bibtex-lint:indent:%s\\]\\[[^]]*(2)\\]\\]" (regexp-quote file)) text))
        (should (string-match-p (format "\\[\\[sp-bibtex-lint:authors:%s\\]\\[author names (1)\\]\\]" (regexp-quote file)) text))))
    (kill-buffer sp-bibtex-lint--buffer)))

(ert-deftest sp-bibtex-lint-test-button-runs-its-fix ()
  (let (called)
    (cl-letf (((symbol-function 'sp-bibtex-lint-fix-order) (lambda (f) (push (list 'order f) called)))
              ((symbol-function 'sp-bibtex-lint-fix-indent) (lambda (f) (push (list 'indent f) called)))
              ((symbol-function 'sp-bibtex-lint-fix-authors) (lambda (f) (push (list 'authors f) called))))
      (dolist (kind '("order" "indent" "authors"))
        (sp-bibtex-lint--follow (concat kind ":/tmp/a b.bib")))
      (should (equal '((authors "/tmp/a b.bib") (indent "/tmp/a b.bib") (order "/tmp/a b.bib")) called))
      (should-error (sp-bibtex-lint--follow "other:/tmp/a.bib") :type 'user-error))))


;;; Attachment paths (sp-bibtex-files)

(defvar sp-bibtex-files nil)
(defvar sp-literature-dir nil)

(defun sp-bibtex-files-test--bdsk (path &optional utf16)
  "The base64 value of a BibDesk bookmark whose relativePath is PATH."
  (let* ((head "bplist00\xd2\x01\x02\x03\x04\\relativePathXbookmark")
         (tail "O\x11\x04,book,\x04\x00\x00\x00\x00\x04\x10\x30")
         (n (length path))
         (body (cond
                (utf16 (concat "o\x10" (string n) (encode-coding-string path 'utf-16be)))
                ((< n 15) (concat (string (+ #x50 n)) path))
                ((< n 256) (concat "_\x10" (string n) path))
                (t (concat "_\x11" (string (ash n -8) (logand n 255)) path)))))
    (base64-encode-string (concat head body tail) t)))

(defun sp-bibtex-files-test--library (&rest names)
  "A temp library with the files NAMES (relative paths); return its directory."
  (let ((dir (file-name-as-directory (make-temp-file "sp-lib" t))))
    (dolist (n names)
      (make-directory (file-name-directory (expand-file-name n dir)) t)
      (write-region "" nil (expand-file-name n dir)))
    dir))

(ert-deftest sp-bibtex-files-test-bdsk-path ()
  (should (equal "../literature/a1990x0.pdf"
                 (sp-bibtex-files--bdsk-path (sp-bibtex-files-test--bdsk "../literature/a1990x0.pdf"))))
  (let ((long (concat "../" (make-string 300 ?a) ".pdf")))
    (should (equal long (sp-bibtex-files--bdsk-path (sp-bibtex-files-test--bdsk long)))))
  (should (equal "../Anna’s.pdf"
                 (sp-bibtex-files--bdsk-path (sp-bibtex-files-test--bdsk "../Anna’s.pdf" t))))
  (should-not (sp-bibtex-files--bdsk-path "not a bookmark")))

(ert-deftest sp-bibtex-files-test-rewrite ()
  (let* ((dir (sp-bibtex-files-test--library "inbox/mac-bibdesk/suchman2017reconstruc0.pdf"
                                             "inbox/mac-bibdesk/a2000b0.pdf"
                                             "inbox/mac-bibdesk/a2000b1.pdf"
                                             "inbox/mac-bibdesk/other0.pdf"
                                             "plain.pdf" "elsewhere/moved.pdf"))
         (ctx (sp-bibtex-files-index dir nil))
         (b (lambda (n) (sp-bibtex-files-test--bdsk (concat "../literature/" n)))))
    (unwind-protect
        (progn
          ;; One file, last field without a comma: replaced in place.
          (let ((r (sp-bibtex-files--rewrite
                    (format "@book{k,\n  year = 2017,\n  bdsk-file-1  =\n    {%s}\n}\n"
                            (funcall b "suchman2017reconstruc0.pdf"))
                    "suchman-2017-recon-tech-soc-prac" ctx)))
            (should (equal "@book{k,\n  year = 2017,\n  file         = {inbox/mac-bibdesk/suchman2017reconstruc0.pdf}\n}\n"
                           (car r)))
            (should (eq 'change (car (car (nth 1 r))))))
          ;; Two files, trailing commas kept, the first field removed.
          (let ((r (sp-bibtex-files--rewrite
                    (format "@book{k,\n\tbdsk-file-1 = {%s},\n\tbdsk-file-2 = {%s},\n\tyear = 1}\n"
                            (funcall b "a2000b0.pdf") (funcall b "a2000b1.pdf"))
                    "zzz" ctx)))
            (should (equal "@book{k,\n\tfile        = {inbox/mac-bibdesk/a2000b0.pdf;inbox/mac-bibdesk/a2000b1.pdf},\n\tyear = 1}\n"
                           (car r))))
          ;; Merged into an existing plain file field.
          (let ((r (sp-bibtex-files--rewrite
                    (format "@book{k,\n  file = {Z:/x/y.pdf:application/pdf},\n  bdsk-file-1 = {%s}}\n"
                            (funcall b "other0.pdf"))
                    "k" ctx)))
            (should (string-match-p "file = {Z:/x/y.pdf:application/pdf;inbox/mac-bibdesk/other0.pdf}"
                                    (car r)))
            (should-not (string-match-p "bdsk" (car r))))
          ;; Unresolved: untouched and reported.
          (let* ((text (format "@book{k,\n  bdsk-file-1 = {%s}}\n" (funcall b "gone0.pdf")))
                 (r (sp-bibtex-files--rewrite text "nokey" ctx)))
            (should (equal text (car r)))
            (should (eq 'problem (car (car (nth 1 r))))))
          ;; The citekey finds the file when the bookmark's name is gone.
          (let ((r (sp-bibtex-files--rewrite
                    (format "@book{other,\n  bdsk-file-1 = {%s}}\n" (funcall b "renamed0.pdf"))
                    "other" ctx)))
            (should (string-match-p "file        = {inbox/mac-bibdesk/other0.pdf}" (car r))))
          ;; Absolute paths become relative; a moved file is found by name.
          (let ((r (sp-bibtex-files--rewrite
                    "@book{k,\n  file = {~/Docuemnts/literature/plain.pdf;~/Documents/literature/moved.pdf},\n}\n"
                    "k" ctx)))
            (should (string-match-p "file = {plain.pdf;elsewhere/moved.pdf}," (car r)))))
      (delete-directory dir t))))

(ert-deftest sp-bibtex-files-test-flatten ()
  (let* ((dir (sp-bibtex-files-test--library "inbox/x0.pdf" "inbox/clash.pdf" "clash.pdf"))
         (ctx (sp-bibtex-files-index dir t))
         (sp-bibtex-lint-backup-directory (expand-file-name "bk/" dir)))
    (unwind-protect
        (progn
          (let ((r (sp-bibtex-files--rewrite
                    (format "@a{k,\n  bdsk-file-1 = {%s}}\n" (sp-bibtex-files-test--bdsk "../x0.pdf"))
                    "k" ctx)))
            (should (string-match-p "file        = {x0.pdf}" (car r)))
            (should (equal (list (cons (expand-file-name "inbox/x0.pdf" dir) (expand-file-name "x0.pdf" dir)))
                           (nth 2 r))))
          ;; The same name at the top and below: ambiguous, so left alone.
          (let* ((text (format "@a{c,\n  bdsk-file-1 = {%s}}\n" (sp-bibtex-files-test--bdsk "../clash.pdf")))
                 (r (sp-bibtex-files--rewrite text "c" ctx)))
            (should (equal text (car r)))
            (should (string-match-p "ambiguous" (cdr (car (nth 1 r))))))
          (let ((moves (nth 2 (sp-bibtex-files--rewrite
                               (format "@a{k,\n  bdsk-file-1 = {%s}}\n" (sp-bibtex-files-test--bdsk "../x0.pdf"))
                               "k" ctx))))
            (should (= 1 (length moves)))
            (sp-bibtex-files--move moves))
          (should (file-exists-p (expand-file-name "x0.pdf" dir)))
          (should-not (file-exists-p (expand-file-name "inbox/x0.pdf" dir)))
          (should (file-exists-p (expand-file-name "inbox/clash.pdf" dir)))
          (should (directory-files sp-bibtex-lint-backup-directory nil "files-moves.*tsv")))
      (delete-directory dir t))))

(ert-deftest sp-bibtex-files-test-dryrun-and-fix ()
  (let* ((lib (sp-bibtex-files-test--library "lit/a1990x0.pdf"))
         (sp-literature-dir (expand-file-name "lit/" lib))
         (sp-bibtex-files-flatten nil))
    (unwind-protect
        (sp-bibprocess-lint-test--with-bib
            (format "@book{a1990x,\n  title = {T},\n  bdsk-file-1 = {%s}\n}\n\n@book{b,\n  file = {~/Documents/literature/a1990x0.pdf},\n  title = {U}\n}\n"
                    (sp-bibtex-files-test--bdsk "../literature/a1990x0.pdf"))
          ;; The report has a section and a button, and writes nothing.
          (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
            (sp-bibtex-lint-dryrun file))
          (with-current-buffer sp-bibtex-lint--buffer
            (let ((text (buffer-string)))
              (should (string-match-p (format "\\[\\[sp-bibtex-lint:files:%s\\]\\[attachment paths (2)\\]\\]"
                                              (regexp-quote file))
                                      text))
              (should (string-match-p "bdsk-file-1 → file = {a1990x0.pdf}" text))
              (should (string-match-p "file: ~/Documents/literature/a1990x0.pdf → a1990x0.pdf" text))))
          (kill-buffer sp-bibtex-lint--buffer)
          (should (string-match-p "bdsk-file-1" (sp-bibprocess-lint-test--text file)))
          ;; The fix: one question, a backup, the rest of the entry as it was.
          (should (equal '(2) (sp-bibprocess-lint-test--convert file '(?a) #'sp-bibtex-lint-fix-files)))
          (let ((text (sp-bibprocess-lint-test--text file)))
            (should (string-match-p "file        = {a1990x0.pdf}" text))
            (should (string-match-p "file = {a1990x0.pdf}," text))
            (should-not (string-match-p "bdsk\\|Documents" text))
            (should (string-match-p "title = {T}," text)))
          (should (directory-files-recursively sp-bibtex-lint-backup-directory "a\\.bib\\'")))
      (delete-directory lib t))))

(ert-deftest sp-bibtex-files-test-fix-needs-library ()
  (let ((sp-literature-dir "/no/such/folder/"))
    (sp-bibprocess-lint-test--with-bib "@book{a,\n  title = {T}\n}\n"
      (should-error (sp-bibtex-lint-fix-files file) :type 'user-error))))

(ert-deftest sp-bibtex-files-test-flatten-fix-moves-files ()
  (let* ((lib (sp-bibtex-files-test--library "lit/inbox/a1990x0.pdf"))
         (sp-literature-dir (expand-file-name "lit/" lib))
         (sp-bibtex-files-flatten t))
    (unwind-protect
        (sp-bibprocess-lint-test--with-bib
            (format "@book{a1990x,\n  bdsk-file-1 = {%s}\n}\n"
                    (sp-bibtex-files-test--bdsk "../literature/a1990x0.pdf"))
          (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
            (sp-bibprocess-lint-test--convert file '(?a) #'sp-bibtex-lint-fix-files))
          (should (string-match-p "file        = {a1990x0.pdf}" (sp-bibprocess-lint-test--text file)))
          (should (file-exists-p (expand-file-name "lit/a1990x0.pdf" lib)))
          (should-not (file-exists-p (expand-file-name "lit/inbox/a1990x0.pdf" lib))))
      (delete-directory lib t))))

(ert-deftest sp-bibtex-lint-test-capf ()
  (let ((sp-bibtex--people-cache (cons (float-time) (sp-bibtex--make-people '("John Smith" "Jane Doe")))))
    (with-temp-buffer
      (insert "@article{a,\n  author = {Smith, John and Do")
      (let ((capf (sp-bibtex-author-capf)))
        (should capf)
        (should (equal "Do" (buffer-substring (nth 0 capf) (nth 1 capf))))
        (should (equal '("Doe, Jane") (all-completions "Do" (nth 2 capf))))))
    (with-temp-buffer
      (insert "@article{a,\n  title = {Do")
      (should-not (sp-bibtex-author-capf)))))

(provide 'sp-bibprocess-lint-test)
;;; sp-bibprocess-lint-test.el ends here
