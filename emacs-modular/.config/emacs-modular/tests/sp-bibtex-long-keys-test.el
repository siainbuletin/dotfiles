;;; sp-bibtex-long-keys-test.el --- Tests for the long citation key fix -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'bibtex)
(require 'sp-async-work)
(require 'sp-batch-report)
(require 'sp-author-notes-bibtex)

;; The module's variables, special here so the tests can bind them.
(defvar sp-notes-dir)
(defvar sp-literature-dir)
(defvar sp-bibtex-files)
(defvar sp-bibtex-lint-backup-directory)
(defvar sp-bibtex-files-flatten)
(defvar sp-bibtex-files-devonthink-tool)

;; sp-bibprocess needs the whole configuration; load only the key and lint parts.
(defvar sp-bibtex-long-keys-test--file
  (expand-file-name "../libraries/modules/academic/sp-bibprocess.el"
                    (file-name-directory (or load-file-name buffer-file-name))))
(with-temp-buffer
  (insert-file-contents sp-bibtex-long-keys-test--file)
  (goto-char (point-min))
  (let* ((start (search-forward ";;;; Long citation keys"))
         (end (progn (search-forward "(use-package bibtex") (match-beginning 0))))
    (eval (read (concat "(progn " (buffer-substring start end) ")")) t))
  (goto-char (point-min))
  (let ((start (search-forward ";;;; Linting the .bib files"))
        (end (progn (search-forward "(provide 'sp-bibprocess)") (match-beginning 0))))
    (eval (read (concat "(progn " (buffer-substring start end) ")")) t)))

(defconst sp-bibtex-long-keys-test--long
  "smithjonesunderstandingneoliberalismandthestateofthings2023")

(defconst sp-bibtex-long-keys-test--bib
  (concat "@comment{ignored-because-it-is-a-comment-and-very-long-indeed-yes}
@string{averyveryverylongstringnamethatisnotanentryatall = \"x\"}
@book{short2020,
  author = {Short, Ann},
  title = {Short}, year = {2020}}
@article{" sp-bibtex-long-keys-test--long ",
  author = {Smith, John and Jones, Mary},
  title = {Understanding {Neoliberalism} and the State of Things},
  year = {2023},
  file = {inbox/" sp-bibtex-long-keys-test--long ".pdf;inbox/" sp-bibtex-long-keys-test--long "-extra.pdf;inbox/other.pdf}}
@incollection{chapter2023,
  title = {A chapter},
  crossref = {" sp-bibtex-long-keys-test--long "},
  year = {2023}}
"))

(defmacro sp-bibtex-long-keys-test--with-world (&rest body)
  "Run BODY with a temp bib file, notes, library and backup folder.
Binds `bib', `notes', `library' and `backups'."
  (declare (indent 0))
  `(let* ((root (make-temp-file "long-keys" t))
          (bib (expand-file-name "refs.bib" root))
          (notes (expand-file-name "notes/" root))
          (library (expand-file-name "library/" root))
          (backups (expand-file-name "backups/" root))
          (sp-bibtex-files (list bib))
          (sp-notes-dir notes)
          (sp-literature-dir library)
          (sp-bibtex-files-flatten nil)
          (sp-bibtex-files-devonthink-tool nil)
          (sp-bibtex-lint-backup-directory backups)
          (sp-bibtex-key-notes-directory nil))
     (unwind-protect
         (progn
           (make-directory notes t)
           (make-directory (expand-file-name "inbox/" library) t)
           (with-temp-file bib (insert sp-bibtex-long-keys-test--bib))
           (dolist (name (list (concat sp-bibtex-long-keys-test--long ".pdf")
                               (concat sp-bibtex-long-keys-test--long "-extra.pdf")
                               "other.pdf"))
             (with-temp-file (expand-file-name name (expand-file-name "inbox/" library))
               (insert name)))
           (with-temp-file (expand-file-name "lit.org" notes)
             (insert ":PROPERTIES:\n:ID: x\n:END:\n#+title: A\n#+reference: "
                     sp-bibtex-long-keys-test--long "\n\nSee [cite:@" sp-bibtex-long-keys-test--long
                     "] and [cite/t:@short2020; @" sp-bibtex-long-keys-test--long "]; also cite:"
                     sp-bibtex-long-keys-test--long ".\nNot @" sp-bibtex-long-keys-test--long
                     "extra here.\n"))
           (with-temp-file (expand-file-name "other.org" notes)
             (insert "#+reference: short2020\n"))
           ,@body)
       (delete-directory root t))))

(ert-deftest sp-bibtex-long-keys-test-find ()
  (with-temp-buffer
    (insert sp-bibtex-long-keys-test--bib)
    (should (equal (list "short2020" sp-bibtex-long-keys-test--long "chapter2023")
                   (mapcar #'car (sp-bibtex-entry-keys))))
    (let ((long (sp-bibtex-long-keys)))
      (should (equal (mapcar #'car long) (list sp-bibtex-long-keys-test--long)))
      (should (equal (buffer-substring (nth 1 (car long)) (nth 2 (car long)))
                     (car (car long)))))
    (should (null (sp-bibtex-long-keys 100)))
    (should (= 3 (length (sp-bibtex-long-keys 5))))))

(ert-deftest sp-bibtex-long-keys-test-problem ()
  (let ((table (make-hash-table :test #'equal)))
    (puthash "taken" t table)
    (should (null (sp-bibtex--key-problem "fine-2020" 45 table)))
    (should (sp-bibtex--key-problem "" 45 table))
    (should (sp-bibtex--key-problem (make-string 46 ?a) 45 table))
    (should (sp-bibtex--key-problem "has space" 45 table))
    (should (sp-bibtex--key-problem "a,b" 45 table))
    (should (sp-bibtex--key-problem "taken" 45 table))))

(ert-deftest sp-bibtex-long-keys-test-suggestion ()
  (let* ((text "@article{aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,
  author = {Smith, John},
  title = {Understanding Neoliberalism and the State},
  year = {2023}}")
         (suggestion (sp-bibtex--suggest-key text 45 (make-hash-table :test #'equal))))
    (should (<= 1 (length suggestion) 45))
    (should (equal "Understanding Neoliberalism and the State" (sp-bibtex--text-title text)))))

(ert-deftest sp-bibtex-long-keys-test-read-asks-again ()
  (let ((table (make-hash-table :test #'equal))
        (answers (list (make-string 50 ?x) "has space" "ok-2023")))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop answers)))
              ((symbol-function 'sit-for) #'ignore))
      (should (equal "ok-2023" (sp-bibtex--read-short-key "old" "s" "T" 45 table)))
      (should (null answers)))))

(ert-deftest sp-bibtex-long-keys-test-read-empty-keeps ()
  (let ((table (make-hash-table :test #'equal)))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "")))
      (should (null (sp-bibtex--read-short-key "old" "s" "T" 45 table))))))

(ert-deftest sp-bibtex-long-keys-test-note-edits ()
  (with-temp-buffer
    (insert "#+reference: oldkey\n:ROAM_REFS: @oldkey cite:oldkey\n"
            "[cite:@oldkey] [cite/t:@a; @oldkey]. oldkey @oldkey. @oldkey-2 @oldkeyx @oldkey\n"
            "plain oldkey text\n")
    (let ((edits (sp-bibtex-keys--note-edits '(("oldkey" . "new")))))
      (should (equal (mapcar (lambda (e) (nth 3 e)) (reverse edits))
                     '(ref ref ref cite cite cite cite)))
      (should (equal (mapcar (lambda (e) (nth 2 e)) edits) (make-list 7 "new")))
      (should (apply #'> (mapcar #'car edits)))
      (dolist (e edits)
        (delete-region (nth 0 e) (nth 1 e))
        (goto-char (nth 0 e))
        (insert (nth 2 e)))
      (should (string-match-p "plain oldkey text" (buffer-string)))
      (should (string-match-p "@oldkey-2 @oldkeyx" (buffer-string)))
      (should (string-match-p "#\\+reference: new" (buffer-string)))
      (should (string-match-p "\\[cite/t:@a; @new\\]\\." (buffer-string))))))

(ert-deftest sp-bibtex-long-keys-test-rewrite-entry ()
  (let ((text (concat "@article{" sp-bibtex-long-keys-test--long ",\n  title = {T},\n  file = {inbox/"
                      sp-bibtex-long-keys-test--long ".pdf;inbox/other.pdf}}")))
    (should (equal (concat "@article{new,\n  title = {T},\n  file = {inbox/new.pdf;inbox/other.pdf}}")
                   (sp-bibtex-keys--rewrite-entry
                    text sp-bibtex-long-keys-test--long "new"
                    (list (cons (concat "/lib/inbox/" sp-bibtex-long-keys-test--long ".pdf")
                                "/lib/inbox/new.pdf")))))
    (should (equal "@article{new,\n  title = {T}}"
                   (sp-bibtex-keys--rewrite-entry "@article{old,\n  title = {T}}" "old" "new" nil)))
    (should (equal "@article{other,\n  title = {T}}"
                   (sp-bibtex-keys--rewrite-entry "@article{other,\n  title = {T}}" "old" "new" nil)))))

(ert-deftest sp-bibtex-long-keys-test-pdf-moves ()
  (sp-bibtex-long-keys-test--with-world
    (let* ((long sp-bibtex-long-keys-test--long)
           (moves (sp-bibtex-keys--pdf-moves (list (cons long "new")))))
      (should (equal (list long) (mapcar #'car moves)))
      (should (equal (list (expand-file-name "inbox/new-extra.pdf" library)
                           (expand-file-name "inbox/new.pdf" library))
                     (sort (mapcar #'cdr (cdr (car moves))) #'string<)))
      (with-temp-file (expand-file-name "inbox/new.pdf" library) (insert "x"))
      (should (= 1 (length (cdr (car (sp-bibtex-keys--pdf-moves (list (cons long "new")))))))))))

(ert-deftest sp-bibtex-long-keys-test-update-notes-and-refs ()
  (sp-bibtex-long-keys-test--with-world
    (let* ((long sp-bibtex-long-keys-test--long)
           (renames (list (cons long "new")))
           (scan (sp-bibtex-keys--scan-notes renames)))
      (should (equal (list (expand-file-name "lit.org" notes)) (mapcar #'car scan)))
      (should (equal '(1 3) (cdr (car scan))))
      (let ((done (sp-bibtex-keys--update-notes renames (mapcar #'car scan) "stamp")))
        (should (= 1 (car done)))
        (should (null (cdr done))))
      (let ((text (with-temp-buffer (insert-file-contents (expand-file-name "lit.org" notes))
                                    (buffer-string))))
        (should (string-match-p "#\\+reference: new\n" text))
        (should (string-match-p "\\[cite:@new\\]" text))
        (should (string-match-p "cite:new\\." text))
        (should (string-match-p (concat "@" long "extra here") text)))
      (should (file-exists-p (expand-file-name "key-renames-stamp/lit.org" backups)))
      (should (equal (list (cons bib 1)) (sp-bibtex-keys--bib-refs renames bib)))
      (with-temp-buffer
        (insert-file-contents bib)
        (should (= 1 (sp-bibtex-keys--replace-refs renames)))
        (should (string-match-p "crossref = {new}" (buffer-string)))))))

(ert-deftest sp-bibtex-long-keys-test-lint-fix ()
  (sp-bibtex-long-keys-test--with-world
    (let* ((long sp-bibtex-long-keys-test--long)
           (answers (list ?p ?y))
           (work (generate-new-buffer " *work*"))
           (results (with-temp-buffer
                      (insert-file-contents bib)
                      (delay-mode-hooks (bibtex-mode))
                      (goto-char (point-min))
                      (seq-filter (lambda (r) (alist-get 'keys (nth 4 r)))
                                  (car (sp-bibtex--lint-chunk bib 100 nil (make-hash-table :test #'equal)
                                                              '(keys))))))
           batch)
      (unwind-protect
          (progn
            (should (= 1 (length results)))
            (should (equal long (nth 1 (car results))))
            (with-current-buffer work
              (insert-file-contents bib)
              (delay-mode-hooks (bibtex-mode)))
            (setq batch (mapcar (lambda (r)
                                  (let ((rewrite (alist-get 'keys (nth 4 r))))
                                    (list r
                                          (with-current-buffer work
                                            (copy-marker (plist-get rewrite :start)))
                                          (with-current-buffer work
                                            (copy-marker (plist-get rewrite :end))))))
                                results))
            (let ((sp-bibtex-lint--key-table (sp-bibtex--key-table bib))
                  answer)
              (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) (pop answers)))
                        ((symbol-function 'read-string) (lambda (&rest _) "smithjones-2023-understanding"))
                        ((symbol-function 'sp-bibtex-lint--show-batch) #'ignore)
                        ((symbol-function 'display-buffer) #'ignore))
                (setq answer (sp-bibtex-lint--ask-keys bib batch 1 1 1)))
              (should (listp answer))
              (should (= 1 (length (plist-get answer :decisions))))
              (let ((counts (sp-bibtex-keys--plan-counts (plist-get answer :plan))))
                (should (equal '(1 1 3 2 1) counts)))
              (cl-letf (((symbol-function 'citar-refresh) #'ignore))
                (should (equal '(1 0 t) (sp-bibtex-lint--apply-keys work batch answer)))))
            (with-current-buffer work
              (let ((text (buffer-string)))
                (should (string-match-p "@article{smithjones-2023-understanding," text))
                (should (string-match-p "inbox/smithjones-2023-understanding.pdf;inbox/smithjones-2023-understanding-extra.pdf;inbox/other.pdf" text))
                (should (string-match-p "crossref = {smithjones-2023-understanding}" text))))
            (should (file-exists-p (expand-file-name "inbox/smithjones-2023-understanding.pdf" library)))
            (should (file-exists-p (expand-file-name "inbox/smithjones-2023-understanding-extra.pdf" library)))
            (should-not (file-exists-p (expand-file-name (concat "inbox/" long ".pdf") library)))
            (should (file-exists-p (expand-file-name "inbox/other.pdf" library)))
            (with-temp-buffer
              (insert-file-contents (expand-file-name "lit.org" notes))
              (should (string-match-p "#\\+reference: smithjones-2023-understanding" (buffer-string)))))
        (kill-buffer work)))))

(ert-deftest sp-bibtex-long-keys-test-bib-only ()
  (sp-bibtex-long-keys-test--with-world
    (let* ((long sp-bibtex-long-keys-test--long)
           (plan (sp-bibtex-keys-plan (list (cons long "new")) bib nil)))
      (should (equal '(0 0 0 0 0) (sp-bibtex-keys--plan-counts plan)))
      (should (null (plist-get plan :bibrefs))))))

(provide 'sp-bibtex-long-keys-test)
;;; sp-bibtex-long-keys-test.el ends here
