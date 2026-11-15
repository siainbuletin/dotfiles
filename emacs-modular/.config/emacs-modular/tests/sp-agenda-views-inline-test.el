;;; sp-agenda-views-inline-test.el --- Tests for the inline keyword view  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar sp-writing-projects "/nonexistent/")
(defvar sp-notes-dir "/nonexistent-notes/")
(defvar org-agenda-custom-commands nil)
(defvar sp-agenda-views-inline-keywords)
(defvar sp-agenda-views-inline-filter nil)
(defvar sp-agenda-views-inline-extra-dirs)
(defvar sp-agenda-views-inline-exclude-regexp)

;; Load only the inline section, so the test needs neither Org nor vulpea.
(let ((file (expand-file-name
             "../libraries/modules/text/sp-agenda-views.el"
             (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((start (search-forward ";;;; Inline keywords" nil t))
          (end (search-forward ";;;; Config files" nil t)))
      (eval-region start (- end (length ";;;; Config files"))))))

(defmacro sp-agenda-views-inline-test--term (text)
  "Return non-nil when TEXT matches the regexp of the inline view."
  `(let ((re (substring (sp-agenda-views-inline-regexp) 1 -1)))
     (string-match-p re ,text)))

(ert-deftest sp-agenda-views-inline-test-matches-keywords ()
  (should (sp-agenda-views-inline-test--term "Cite this. FIXME check"))
  (should (sp-agenda-views-inline-test--term "as shown (TK)"))
  (should (sp-agenda-views-inline-test--term "XXX")))

(ert-deftest sp-agenda-views-inline-test-whole-words-only ()
  (should-not (sp-agenda-views-inline-test--term "Atkins wrote XXXL")))

(ert-deftest sp-agenda-views-inline-test-entry-key ()
  (cl-letf (((symbol-function 'sp-agenda-views-inline-files) (lambda () nil)))
    (should (equal (car (sp-agenda-views--inline-entry)) "x"))))

(ert-deftest sp-agenda-views-inline-test-sourcerefs-keyword ()
  (should (member "SOURCEREFS" sp-agenda-views-inline-keywords))
  (should (sp-agenda-views-inline-test--term "SOURCEREFS p. 12 Smith 1999"))
  (should-not (sp-agenda-views-inline-test--term "MYSOURCEREFS")))

(ert-deftest sp-agenda-views-inline-test-filter-narrows ()
  (let ((sp-agenda-views-inline-filter "SOURCEREFS"))
    (should (sp-agenda-views-inline-test--term "SOURCEREFS Smith"))
    (should-not (sp-agenda-views-inline-test--term "FIXME this"))
    (should-not (sp-agenda-views-inline-test--term "CITE this"))))

(ert-deftest sp-agenda-views-inline-test-filter-nil-means-all ()
  (let ((sp-agenda-views-inline-filter nil))
    (should (sp-agenda-views-inline-test--term "FIXME this"))
    (should (sp-agenda-views-inline-test--term "SOURCEREFS Smith"))))

(ert-deftest sp-agenda-views-inline-test-unknown-filter-is-ignored ()
  (let ((sp-agenda-views-inline-filter "NOPE"))
    (should (sp-agenda-views-inline-test--term "FIXME this"))))

(ert-deftest sp-agenda-views-inline-test-filter-set-rejects-unknown ()
  (should-error (sp-agenda-views-inline-filter-set "NOPE") :type 'user-error)
  (should-not sp-agenda-views-inline-filter))

(ert-deftest sp-agenda-views-inline-test-filter-clear ()
  (cl-letf (((symbol-function 'sp-agenda-views-inline) #'ignore))
    (let ((sp-agenda-views-inline-filter "CITE"))
      (sp-agenda-views-inline-filter-clear)
      (should-not sp-agenda-views-inline-filter))))

(defmacro sp-agenda-views-inline-test--with-notes (&rest body)
  "Run BODY with `root' bound to a temporary notes folder with some files."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "sp-inline" t))))
     (unwind-protect
         (progn
           (dolist (spec '(("a.org" . "* H\nSOURCEREFS Smith\n")
                           ("sub/b.org" . "* H\nnothing\n")
                           ("archive/c.org" . "* H\nFIXME\n")
                           (".hidden/d.org" . "* H\nFIXME\n")
                           ("e.org_archive" . "* H\nFIXME\n")
                           (".#lock.org" . "x")
                           ("f.org~" . "x")
                           ("g.txt" . "FIXME")))
             (let ((file (expand-file-name (car spec) root)))
               (make-directory (file-name-directory file) t)
               (with-temp-file file (insert (cdr spec)))))
           ,@body)
       (delete-directory root t))))

(ert-deftest sp-agenda-views-inline-test-default-dirs-have-litnotes ()
  (should (seq-some (lambda (d) (string-suffix-p "litnotes/" d))
                    (default-value 'sp-agenda-views-inline-extra-dirs))))

(ert-deftest sp-agenda-views-inline-test-org-files-excludes ()
  (sp-agenda-views-inline-test--with-notes
    (should (equal (sort (mapcar (lambda (f) (file-relative-name f root))
                                 (sp-agenda-views-inline--org-files root))
                         #'string<)
                   '("a.org" "sub/b.org")))))

(ert-deftest sp-agenda-views-inline-test-org-files-single-file ()
  (sp-agenda-views-inline-test--with-notes
    (should (equal (sp-agenda-views-inline--org-files (expand-file-name "a.org" root))
                   (list (expand-file-name "a.org" root))))
    (should-not (sp-agenda-views-inline--org-files "/nonexistent/x"))))

(ert-deftest sp-agenda-views-inline-test-prefilter-keeps-matching-files ()
  (skip-unless (executable-find "rg"))
  (sp-agenda-views-inline-test--with-notes
    (let ((files (sp-agenda-views-inline--org-files root)))
      (should (equal (mapcar (lambda (f) (file-relative-name f root))
                             (sp-agenda-views-inline--prefilter files))
                     '("a.org")))
      (let ((sp-agenda-views-inline-filter "FIXME"))
        (should-not (sp-agenda-views-inline--prefilter files))))))

(ert-deftest sp-agenda-views-inline-test-prefilter-without-rg ()
  (sp-agenda-views-inline-test--with-notes
    (let ((files (sp-agenda-views-inline--org-files root)))
      (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil)))
        (should (equal (sp-agenda-views-inline--prefilter files) files))))))

(ert-deftest sp-agenda-views-inline-test-files-union ()
  (skip-unless (executable-find "rg"))
  (sp-agenda-views-inline-test--with-notes
    (let ((sp-agenda-views-inline-extra-dirs (list root)))
      (cl-letf (((symbol-function 'org-agenda-files)
                 (lambda () (list (expand-file-name "sub/b.org" root)))))
        (should (equal (mapcar (lambda (f) (file-relative-name f root))
                               (sp-agenda-views-inline-files))
                       '("sub/b.org" "a.org")))))))

(provide 'sp-agenda-views-inline-test)
;;; sp-agenda-views-inline-test.el ends here
