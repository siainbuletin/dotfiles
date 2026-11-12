;;; sp-bibtex-long-keys-test.el --- Tests for the long citation key check -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'bibtex)

;; sp-bibprocess needs the whole configuration; load only the long-key part.
(defvar sp-bibtex-long-keys-test--file
  (expand-file-name "../libraries/modules/academic/sp-bibprocess.el"
                    (file-name-directory (or load-file-name buffer-file-name))))
(defvar sp-bibtex-lint-backup-directory)
(defvar sp-bibtex-files nil)
(defvar sp-bibtex-long-keys-test--backups nil)
(defun sp-bibtex-lint--read-file (&optional _ask) nil)
(defun sp-bibtex-lint--unsaved-check (_file) nil)
(defun sp-bibtex-lint--backup (file _stamp) (push file sp-bibtex-long-keys-test--backups))
(with-temp-buffer
  (insert-file-contents sp-bibtex-long-keys-test--file)
  (goto-char (point-min))
  (let ((start (search-forward ";;;; Long citation keys"))
        (end (progn (search-forward "(use-package bibtex") (match-beginning 0))))
    (eval (read (concat "(progn " (buffer-substring start end) ")")) t)))

(defconst sp-bibtex-long-keys-test--bib
  "@comment{ignored-because-it-is-a-comment-and-very-long-indeed-yes}
@string{averyveryverylongstringnamethatisnotanentryatall = \"x\"}
@book{short2020,
  author = {Short, Ann},
  title = {Short}, year = {2020}}
@article{smithjonesunderstandingneoliberalismandthestateofthings2023,
  author = {Smith, John and Jones, Mary},
  title = {Understanding {Neoliberalism} and the State of Things},
  year = {2023}}
")

(ert-deftest sp-bibtex-long-keys-test-find ()
  (with-temp-buffer
    (insert sp-bibtex-long-keys-test--bib)
    (should (equal '("short2020" "smithjonesunderstandingneoliberalismandthestateofthings2023")
                   (mapcar #'car (sp-bibtex-entry-keys))))
    (let ((long (sp-bibtex-long-keys)))
      (should (equal (mapcar #'car long)
                     '("smithjonesunderstandingneoliberalismandthestateofthings2023")))
      (should (equal (buffer-substring (nth 1 (car long)) (nth 2 (car long)))
                     (car (car long)))))
    (should (null (sp-bibtex-long-keys 100)))
    (should (= 2 (length (sp-bibtex-long-keys 5))))))

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
  (with-temp-buffer
    (insert sp-bibtex-long-keys-test--bib)
    (delay-mode-hooks (bibtex-mode))
    (let* ((long (car (sp-bibtex-long-keys)))
           (table (sp-bibtex--key-table))
           (suggestion (sp-bibtex--short-key (nth 1 long) 45 table)))
      (should (<= 1 (length suggestion) 45))
      (should-not (equal suggestion (car long)))
      (should (equal "Understanding Neoliberalism and the State of Things"
                     (sp-bibtex--entry-title (nth 1 long)))))))

(ert-deftest sp-bibtex-long-keys-test-read-asks-again ()
  (let ((table (make-hash-table :test #'equal))
        (answers (list (make-string 50 ?x) "has space" "ok-2023"))
        asked)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) (push t asked) (pop answers)))
              ((symbol-function 'sit-for) #'ignore))
      (should (equal "ok-2023" (sp-bibtex--read-short-key "old" "s" "T" 45 table)))
      (should (= 3 (length asked))))))

(ert-deftest sp-bibtex-long-keys-test-read-empty-keeps ()
  (let ((table (make-hash-table :test #'equal)))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "")))
      (should (null (sp-bibtex--read-short-key "old" "s" "T" 45 table))))))

(ert-deftest sp-bibtex-long-keys-test-fix ()
  (let* ((file (make-temp-file "long-keys" nil ".bib" sp-bibtex-long-keys-test--bib))
         (sp-bibtex-files nil)
         (sp-bibtex-long-keys-test--backups nil))
    (unwind-protect
        (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "smithjones-2023-understanding"))
                  ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                  ((symbol-function 'display-buffer) #'ignore))
          (sp-bibtex-fix-long-keys file)
          (with-temp-buffer
            (insert-file-contents file)
            (should (equal (mapcar #'car (sp-bibtex-entry-keys))
                           '("short2020" "smithjones-2023-understanding"))))
          (should (equal sp-bibtex-long-keys-test--backups (list file)))
          (with-current-buffer "*BibTeX key renames*"
            (should (string-match-p "smithjones-2023-understanding" (buffer-string)))))
      (when-let* ((buffer (find-buffer-visiting file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-file file))))

(provide 'sp-bibtex-long-keys-test)
;;; sp-bibtex-long-keys-test.el ends here
