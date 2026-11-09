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

(defmacro sp-bibprocess-lint-test--with-bib (text &rest body)
  "Run BODY with FILE a .bib file holding TEXT, and the lint set up to use it."
  (declare (indent 1))
  `(let* ((dir (file-name-as-directory (make-temp-file "sp-bib" t)))
          (file (expand-file-name "a.bib" dir))
          (sp-bibtex-files (list file))
          (sp-bibtex-lint-backup-directory (expand-file-name "bk/" dir))
          (sp-async-work-synchronous t)
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
  "Run COMMAND (default `sp-bibtex-lint-fix-order') on FILE, answering the batches with ANSWERS.
Return the sizes of the batches that were asked."
  (let (sizes)
    (cl-letf (((symbol-function 'sp-bibtex-lint--ask-batch)
               (lambda (_file batch &rest _) (push (length batch) sizes) (pop answers))))
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

(ert-deftest sp-bibtex-lint-test-convert-batches ()
  (let ((sp-bibtex-lint-batch-size 2))
    (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 5)
      ;; Apply the first batch, skip the second, apply the third.
      (should (equal '(2 2 1) (sp-bibprocess-lint-test--convert file '(?a ?s ?a))))
      (let ((text (sp-bibprocess-lint-test--text file)))
        (should (string-match-p "author =[ \t]+{John Smith1}" text))
        (should (string-match-p "author =[ \t]+{John Smith2}" text))
        (should (string-match-p "author =[ \t]+{John Smith3}" text))
        (should (string-match-p "author =[ \t]+{John Smith4}" text))
        (should (string-match-p "author =[ \t]+{John Smith5}" text))))))

(ert-deftest sp-bibtex-lint-test-convert-default-batch-size ()
  (should (= 50 (default-value 'sp-bibtex-lint-batch-size)))
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 120)
    (should (equal '(50 50 20) (sp-bibprocess-lint-test--convert file '(?s ?s ?s))))))

(ert-deftest sp-bibtex-lint-test-convert-writes-nothing-unasked ()
  (let ((sp-bibtex-lint-batch-size 2))
    (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 3)
      (let ((before (sp-bibprocess-lint-test--text file)))
        ;; Skipping, then quitting: the next batch is not even shown.
        (should (equal '(2 1) (sp-bibprocess-lint-test--convert file '(?s ?q))))
        (should (equal before (sp-bibprocess-lint-test--text file)))
        (should-not (file-exists-p sp-bibtex-lint-backup-directory))
        (should (equal '(2) (sp-bibprocess-lint-test--convert file '(?q))))
        (should (equal before (sp-bibprocess-lint-test--text file)))))))

(ert-deftest sp-bibtex-lint-test-convert-file-changed-on-disk ()
  (sp-bibprocess-lint-test--with-bib (sp-bibprocess-lint-test--entries 1)
    (cl-letf (((symbol-function 'sp-bibtex-lint--ask-batch)
               (lambda (&rest _)
                 ;; The file changes between the lint and the answer.
                 (let ((new (replace-regexp-in-string "John" "Johnny" (sp-bibprocess-lint-test--text file)))) (sleep-for 1.1) (with-temp-file file (insert new)))
                 ?a)))
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
        (should (string-match-p "2 entries to look at" (buffer-string)))
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
