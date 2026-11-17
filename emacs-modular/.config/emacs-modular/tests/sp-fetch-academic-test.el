;;; sp-fetch-academic-test.el --- Tests for the sp-fetch-academic follow-up -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(defvar sp-literature-dir (make-temp-file "lit" t))
(defvar sp-bibliography-dir (make-temp-file "bib" t))
(defvar sp-bibtex-files nil)
(require 'sp-fetch-academic)
(require 'sp-reading)
(require 'sp-devonthink-bibsync)

(defconst sp-fetch-academic-test--bib
  "@article{smith2020,\n  author = {Smith, Jane},\n  title = {Attention},\n  year = {2020},\n}\n")

(defmacro sp-fetch-academic-test--with-env (&rest body)
  "Run BODY with fresh literature and bibliography folders."
  `(let ((sp-literature-dir (make-temp-file "lit" t))
         (sp-bibliography-dir (make-temp-file "bib" t))
         (sp-bibtex-files nil))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (string-prefix-p sp-bibliography-dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b))))))

(defun sp-fetch-academic-test--setup ()
  "A bib file with one entry, registered; return it."
  (let ((bib (expand-file-name "t.bib" sp-bibliography-dir)))
    (write-region sp-fetch-academic-test--bib nil bib)
    (setq sp-bibtex-files (list bib))
    bib))

(defun sp-fetch-academic-test--pdf (name)
  (let ((f (expand-file-name name (make-temp-file "dl" t))))
    (write-region "%PDF-1.4" nil f)
    f))

(ert-deftest sp-fetch-academic-file-field-value ()
  (sp-fetch-academic-test--with-env
   (should (equal (sp-fetch-academic-file-field-value
                   (expand-file-name "a.pdf" sp-literature-dir))
                  "a.pdf"))
   (should (equal (sp-fetch-academic-file-field-value
                   (expand-file-name "inbox/x.pdf" sp-literature-dir))
                  "inbox/x.pdf"))
   (should (equal (sp-fetch-academic-file-field-value
                   "/elsewhere/a.pdf" (expand-file-name "t.bib" sp-bibliography-dir))
                  (file-relative-name "/elsewhere/a.pdf" sp-bibliography-dir)))))

(ert-deftest sp-fetch-academic-file-moves-attaches-and-saves ()
  (sp-fetch-academic-test--with-env
   (let* ((bib (sp-fetch-academic-test--setup))
          (pdf (sp-fetch-academic-test--pdf "dl.pdf"))
          (sp-fetch-academic-devonthink nil)
          (result (sp-fetch-academic-file "smith2020" pdf)))
     (should (equal (plist-get result :file)
                    (expand-file-name "smith2020.pdf" sp-literature-dir)))
     (should (file-exists-p (plist-get result :file)))
     (should-not (file-exists-p pdf))
     (should (plist-get result :attached))
     (with-temp-buffer
       (insert-file-contents bib)
       (should (search-forward "file = {smith2020.pdf}" nil t))))))

(ert-deftest sp-fetch-academic-file-is-idempotent ()
  (sp-fetch-academic-test--with-env
   (let* ((bib (sp-fetch-academic-test--setup))
          (sp-fetch-academic-devonthink nil)
          (pdf (sp-fetch-academic-test--pdf "dl.pdf")))
     (sp-fetch-academic-file "smith2020" pdf)
     (let ((again (sp-fetch-academic-file
                   "smith2020" (expand-file-name "smith2020.pdf" sp-literature-dir))))
       (should-not (plist-get again :attached)))
     (with-temp-buffer
       (insert-file-contents bib)
       (should (= 1 (how-many "smith2020\\.pdf" (point-min) (point-max))))))))

(ert-deftest sp-fetch-academic-file-appends-second-file ()
  (sp-fetch-academic-test--with-env
   (let* ((bib (sp-fetch-academic-test--setup))
          (sp-fetch-academic-devonthink nil))
     (with-current-buffer (find-file-noselect bib)
       (goto-char (point-min))
       (bibtex-find-entry "smith2020")
       (should (sp--fetch-academic-attach (expand-file-name "x.pdf" sp-literature-dir) bib))
       (should (sp--fetch-academic-attach (expand-file-name "y.pdf" sp-literature-dir) bib))
       (should-not (sp--fetch-academic-attach (expand-file-name "y.pdf" sp-literature-dir) bib))
       (goto-char (point-min))
       (should (search-forward "file = {x.pdf; y.pdf}" nil t))))))

(ert-deftest sp-fetch-academic-file-refuses-overwrite-and-unknown-key ()
  (sp-fetch-academic-test--with-env
   (sp-fetch-academic-test--setup)
   (let ((sp-fetch-academic-devonthink nil))
     (write-region "x" nil (expand-file-name "smith2020.pdf" sp-literature-dir))
     (should-error (sp-fetch-academic-file "smith2020" (sp-fetch-academic-test--pdf "o.pdf"))
                   :type 'user-error)
     (should-error (sp-fetch-academic-file "nobody1999" (sp-fetch-academic-test--pdf "p.pdf"))
                   :type 'user-error))))

(ert-deftest sp-fetch-academic-file-calls-devonthink-once ()
  (sp-fetch-academic-test--with-env
   (sp-fetch-academic-test--setup)
   (let (calls)
     (cl-letf (((symbol-function 'sp--fetch-academic-devonthink)
		(lambda (key file) (push (list key file) calls) 'indexed)))
       (let ((result (sp-fetch-academic-file "smith2020" (sp-fetch-academic-test--pdf "q.pdf"))))
         (should (eq (plist-get result :dt) 'indexed))
         (should (= (length calls) 1)))))))

(ert-deftest sp-fetch-academic-devonthink-skips-known-record ()
  (sp-fetch-academic-test--with-env
   (let ((sp-fetch-academic-devonthink t) indexed synced)
     (cl-letf (((symbol-function 'sp--fetch-academic-dt-p) (lambda () t))
               ((symbol-function 'sp-reading-uuid) (lambda (_) "U1"))
               ((symbol-function 'sp-reading-records-at) (lambda (_) nil))
               ((symbol-function 'sp-reading-index-file)
		(lambda (&rest a) (setq indexed a) "U2"))
               ((symbol-function 'sp-devonthink-bibsync-keys)
		(lambda (keys) (setq synced keys))))
       (should (eq (sp--fetch-academic-devonthink "smith2020" "/x/smith2020.pdf") 'known))
       (should-not indexed)
       (should (equal synced '("smith2020")))))))

(ert-deftest sp-fetch-academic-devonthink-failure-does-not-signal ()
  (sp-fetch-academic-test--with-env
   (let ((sp-fetch-academic-devonthink t))
     (cl-letf (((symbol-function 'sp--fetch-academic-dt-p) (lambda () t))
               ((symbol-function 'sp-reading-uuid) (lambda (_) (error "boom"))))
       (should-not (sp--fetch-academic-devonthink "smith2020" "/x/smith2020.pdf"))))))

(provide 'sp-fetch-academic-test)
;;; sp-fetch-academic-test.el ends here
