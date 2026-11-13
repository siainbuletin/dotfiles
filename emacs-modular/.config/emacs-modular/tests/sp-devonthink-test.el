;;; sp-devonthink-test.el --- Tests for sp-devonthink -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-devonthink)

(defconst sp-devonthink-test--uuid "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")

(ert-deftest sp-devonthink-uuid-p ()
  (should (sp-devonthink--uuid-p sp-devonthink-test--uuid))
  (should-not (sp-devonthink--uuid-p "nope"))
  (should-not (sp-devonthink--uuid-p nil)))

(ert-deftest sp-devonthink-path-roundtrip ()
  (let ((u sp-devonthink-test--uuid))
    (should (equal (sp-devonthink--parse-path u) (cons u nil)))
    (should (equal (sp-devonthink--parse-path (sp-devonthink-link-path u 6)) (cons u 6)))
    (should-error (sp-devonthink--parse-path "xyz::6") :type 'user-error)
    (should-error (sp-devonthink--parse-path (concat u "::0")) :type 'user-error)
    (should-error (sp-devonthink--parse-path (concat u "::six")) :type 'user-error)))

(ert-deftest sp-devonthink-url-counts-pages-from-zero ()
  (let ((u sp-devonthink-test--uuid))
    (should (equal (sp-devonthink-url (concat u "::6"))
                   (concat "x-devonthink-item://" u "?page=5")))
    (should (equal (sp-devonthink-url u) (concat "x-devonthink-item://" u)))))

(ert-deftest sp-devonthink-follow-opens-url ()
  (let (opened)
    (cl-letf (((symbol-function 'sp-reading--open-url) (lambda (url) (setq opened url))))
      (sp-devonthink-follow (concat sp-devonthink-test--uuid "::2")))
    (should (string-suffix-p "?page=1" opened))))

(ert-deftest sp-devonthink-link-is-registered-and-exports-description ()
  (should (org-link-get-parameter "devonthink" :follow))
  (should (equal (sp-devonthink-export "x" "key p. 6" 'html) "key p. 6"))
  (should (string-match-p "DEVONthink" (sp-devonthink-export "x" nil 'html))))

(ert-deftest sp-devonthink-note-citekey-forms ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID: a\n:ROAM_REFS: [cite:@smith-2017-x]\n:END:\n#+title: T\n")
    (should (equal (sp-devonthink-note-citekey) "smith-2017-x")))
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ROAM_REFS: cite:jones-2010-y https://x.org\n:END:\n")
    (should (equal (sp-devonthink-note-citekey) "jones-2010-y")))
  (with-temp-buffer
    (insert "#+title: T\n#+reference: old-1999-z\n")
    (should (equal (sp-devonthink-note-citekey) "old-1999-z")))
  (with-temp-buffer (insert "#+title: T\n") (should-not (sp-devonthink-note-citekey))))

(ert-deftest sp-devonthink-set-keyword-inserts-below-title ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID: a\n:ROAM_REFS: @k-2000-a\n:END:\n#+title: T\n\n* H\n")
    (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) sp-devonthink-test--uuid)))
      (sp-devonthink-set-keyword))
    (should (equal (sp-devonthink-note-uuid) sp-devonthink-test--uuid))
    (goto-char (point-min))
    (should (re-search-forward "#\\+title: T\n#\\+devonthink: " nil t))
    ;; second run changes nothing
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) sp-devonthink-test--uuid)))
        (sp-devonthink-set-keyword))
      (should (equal before (buffer-string))))))

(ert-deftest sp-devonthink-set-keyword-without-title-goes-below-drawer ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ROAM_REFS: @k-2000-a\n:END:\n* H\n")
    (sp-devonthink-set-keyword sp-devonthink-test--uuid)
    (should (string-match-p ":END:\n#\\+devonthink: " (buffer-string)))))

(ert-deftest sp-devonthink-set-keyword-replaces-after-confirmation ()
  (with-temp-buffer
    (insert "#+title: T\n#+reference: k-2000-a\n#+devonthink: OLD\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (sp-devonthink-set-keyword sp-devonthink-test--uuid))
    (should (equal (sp-devonthink-note-uuid) sp-devonthink-test--uuid))))

(ert-deftest sp-devonthink-open-from-note-prefers-keyword ()
  (let (opened)
    (cl-letf (((symbol-function 'sp-reading--open-url) (lambda (url) (setq opened url)))
              ((symbol-function 'sp-reading-uuid) (lambda (_) (error "should not look up"))))
      (with-temp-buffer
        (insert (format "#+title: T\n#+devonthink: %s\n" sp-devonthink-test--uuid))
        (sp-devonthink-open-from-note 3)))
    (should (string-suffix-p "?page=2" opened))))

(ert-deftest sp-devonthink-open-from-note-falls-back-to-citekey ()
  (let (opened)
    (cl-letf (((symbol-function 'sp-reading--open-url) (lambda (url) (setq opened url)))
              ((symbol-function 'sp-reading-uuid) (lambda (_) sp-devonthink-test--uuid)))
      (with-temp-buffer
        (insert "#+title: T\n#+reference: k-2000-a\n")
        (sp-devonthink-open-from-note)))
    (should (equal opened (concat "x-devonthink-item://" sp-devonthink-test--uuid)))
    (with-temp-buffer
      (insert "#+title: T\n")
      (should-error (sp-devonthink-open-from-note) :type 'user-error))))

(ert-deftest sp-devonthink-parse-front ()
  (let* ((u sp-devonthink-test--uuid)
         (front (sp-devonthink--parse-front (format "%s\tsmith-2017-x.pdf\t6\tsome\ttext\n" u))))
    (should (equal (plist-get front :key) "smith-2017-x"))
    (should (= (plist-get front :page) 6))
    (should (equal (plist-get front :text) "some\ttext"))
    (let ((sp-devonthink-store-page-offset 1))
      (should (= (plist-get (sp-devonthink--parse-front (format "%s\tk.pdf\t5\t" u)) :page) 6)))
    (should-not (plist-get (sp-devonthink--parse-front (format "%s\tk.pdf\t\t" u)) :page))
    (should-not (sp-devonthink--parse-front ""))
    (should-not (sp-devonthink--parse-front "garbage\tk.pdf"))))

(ert-deftest sp-devonthink-store-link-pushes-stored-link ()
  (let ((org-stored-links nil) (kill-ring nil))
    (cl-letf (((symbol-function 'sp-reading--osascript)
               (lambda (_) (format "%s\tsmith-2017-x.pdf\t6\tquote" sp-devonthink-test--uuid))))
      (sp-devonthink-store-link))
    (should (equal (car org-stored-links)
                   (list (concat "devonthink:" sp-devonthink-test--uuid "::6") "smith-2017-x p. 6")))
    (should (equal (car kill-ring) "quote"))
    (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "")))
      (should-error (sp-devonthink-store-link) :type 'user-error))))

(ert-deftest sp-devonthink-insert-link ()
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) sp-devonthink-test--uuid)))
    (with-temp-buffer
      (sp-devonthink-insert-link "smith-2017-x" 6)
      (should (equal (buffer-string)
                     (format "[[devonthink:%s::6][smith-2017-x p. 6]]" sp-devonthink-test--uuid))))))

(ert-deftest sp-devonthink-first-page-label-keeps-the-text-as-written ()
  (should (equal (sp-devonthink-first-page-label "45--67") "45"))
  (should (equal (sp-devonthink-first-page-label "45-67") "45"))
  (should (equal (sp-devonthink-first-page-label " 45 – 67 ") "45"))
  (should (equal (sp-devonthink-first-page-label "pp. 45--67") "45"))
  (should (equal (sp-devonthink-first-page-label "e123") "e123"))
  (should (equal (sp-devonthink-first-page-label "12,15") "12"))
  (should (equal (sp-devonthink-first-page-label "7+") "7"))
  (should (equal (sp-devonthink-first-page-label "xii--xv") "xii"))
  (should-not (sp-devonthink-first-page-label "2:45"))
  (should-not (sp-devonthink-first-page-label ""))
  (should-not (sp-devonthink-first-page-label nil)))

(ert-deftest sp-devonthink-resolve-own-record-wins ()
  (cl-letf (((symbol-function 'sp-reading-uuid)
             (lambda (k) (and (equal k "child-2001-x") "U-OWN")))
            ((symbol-function 'citar-get-value) (lambda (&rest _) "parent-2000-b")))
    (should (equal (sp-devonthink-resolve "child-2001-x") '(:uuid "U-OWN")))))

(defmacro sp-devonthink-test--with-parent (pages hit &rest body)
  "Run BODY with the entry c in the parent p (record U-P, PDF /x/p.pdf); HIT is what the reader says."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'sp-reading-uuid) (lambda (k) (and (equal k "p") "U-P")))
             ((symbol-function 'sp-reading--pdf) (lambda (k) (and (equal k "p") "/x/p.pdf")))
             ((symbol-function 'citar-get-value)
              (lambda (field _key) (pcase field ('crossref "p") ('pages ,pages))))
             ((symbol-function 'sp-devonthink-pdf-page-for-label)
              (lambda (file label) (list :asked (list file label)) ,hit)))
     ,@body))

(ert-deftest sp-devonthink-resolve-through-crossref-uses-the-pdf-labels ()
  (let (asked)
    (sp-devonthink-test--with-parent "45--67" (progn (setq asked (list file label)) '(:page 53))
      (let ((r (sp-devonthink-resolve "c")))
        (should (equal asked '("/x/p.pdf" "45")))
        (should (equal (plist-get r :uuid) "U-P"))
        (should (= (plist-get r :page) 53))
        (should (equal (plist-get r :via) "p"))))))

(ert-deftest sp-devonthink-resolve-explains-why-there-is-no-page ()
  (dolist (case '(("xii--xv" (:why no-labels) "no page labels")
                  ("xii--xv" (:why not-found) "labelled xii")
                  ("xii--xv" (:why error :message "boom") "boom")
                  ("2:45" (:page 9) "no usable pages")))
    (sp-devonthink-test--with-parent (car case) (cadr case)
      (let ((r (sp-devonthink-resolve "c")))
        (should-not (plist-get r :page))
        (should (string-match-p (nth 2 case) (plist-get r :note)))))))

(ert-deftest sp-devonthink-resolve-parent-without-pdf ()
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (k) (and (equal k "p") "U-P")))
            ((symbol-function 'sp-reading--pdf) (lambda (_) nil))
            ((symbol-function 'citar-get-value)
             (lambda (field _key) (pcase field ('crossref "p") ('pages "45--67")))))
    (let ((r (sp-devonthink-resolve "c")))
      (should-not (plist-get r :page))
      (should (string-match-p "no PDF file found" (plist-get r :note))))))

(ert-deftest sp-devonthink-no-offset-variables-left ()
  (should-not (boundp 'sp-devonthink-page-offset))
  (should-not (boundp 'sp-devonthink-parent-page-offsets)))

(ert-deftest sp-devonthink-resolve-no-parent-record ()
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) nil))
            ((symbol-function 'citar-get-value)
             (lambda (field _key) (and (eq field 'crossref) "parent-2000-b"))))
    (should-not (sp-devonthink-resolve "child-2001-x")))
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) nil))
            ((symbol-function 'citar-get-value) (lambda (&rest _) nil)))
    (should-not (sp-devonthink-resolve "alone-2001-x"))))

(ert-deftest sp-devonthink-citar-open-opens-parent-at-first-page ()
  (let (opened (current-prefix-arg nil))
    (cl-letf (((symbol-function 'sp-reading-uuid)
               (lambda (k) (and (equal k "parent-2000-b") "U-PARENT")))
              ((symbol-function 'sp-reading--pdf) (lambda (_) "/x/parent.pdf"))
              ((symbol-function 'citar-get-value)
               (lambda (field _key) (pcase field ('crossref "parent-2000-b") ('pages "45--67"))))
              ((symbol-function 'sp-devonthink-pdf-page-for-label) (lambda (&rest _) '(:page 47)))
              ((symbol-function 'sp-reading--open-url) (lambda (u) (setq opened u)))
              ((symbol-function 'message) #'ignore))
      (sp-devonthink-citar-open "child-2001-x")
      ;; PDF page 47 counted from 1; the URL counts from 0
      (should (equal opened "x-devonthink-item://U-PARENT?page=46")))))

(ert-deftest sp-devonthink-citar-open-falls-back-to-reading-open ()
  (let (called (current-prefix-arg nil))
    (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) nil))
              ((symbol-function 'citar-get-value)
               (lambda (field _key) (and (eq field 'crossref) "parent-2000-b")))
              ((symbol-function 'sp-reading-open) (lambda (k &optional p) (setq called (list k p))))
              ((symbol-function 'message) #'ignore))
      (sp-devonthink-citar-open "child-2001-x")
      (should (equal called '("child-2001-x" nil))))))

(ert-deftest sp-devonthink-insert-link-always-asks-for-a-page ()
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) sp-devonthink-test--uuid))
            ((symbol-function 'citar-select-ref) (lambda () "smith-2017-x"))
            ((symbol-function 'read-string) (lambda (&rest _) "12")))
    (with-temp-buffer
      (let ((current-prefix-arg nil))
        (call-interactively #'sp-devonthink-insert-link))
      (should (equal (buffer-string)
                     (format "[[devonthink:%s::12][smith-2017-x p. 12]]" sp-devonthink-test--uuid))))))

(ert-deftest sp-devonthink-insert-link-empty-page-links-whole-record ()
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) sp-devonthink-test--uuid))
            ((symbol-function 'citar-select-ref) (lambda () "smith-2017-x"))
            ((symbol-function 'read-string) (lambda (&rest _) "  ")))
    (with-temp-buffer
      (call-interactively #'sp-devonthink-insert-link)
      (should (equal (buffer-string)
                     (format "[[devonthink:%s][smith-2017-x]]" sp-devonthink-test--uuid))))))

(ert-deftest sp-devonthink-read-page-optional-reasks-on-bad-input ()
  (let ((answers '("abc" "0" "7")))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop answers))))
      (should (= (sp-devonthink--read-page-optional) 7))
      (should (null answers)))))


;;; sp-devonthink-test.el ends here

;;;; The real reader script

(defun sp-devonthink-test--pikepdf-p ()
  (and (executable-find "python3")
       (eq 0 (call-process "python3" nil nil nil "-c" "import pikepdf"))))

(ert-deftest sp-devonthink-pdf-page-for-label-runs-the-script ()
  (skip-unless (sp-devonthink-test--pikepdf-p))
  (let* ((tools (expand-file-name "tools" (locate-dominating-file
                                           (or load-file-name buffer-file-name default-directory)
                                           "tools")))
         (sp-devonthink-label-script (expand-file-name "pdf-labels-read.py" tools))
         (pdf (make-temp-file "sp-labels" nil ".pdf")))
    (unwind-protect
        (progn
          (should (eq 0 (call-process "python3" nil nil nil "-c"
                                      "import sys, pikepdf; p = pikepdf.new(); [p.add_blank_page() for _ in range(12)]; p.save(sys.argv[1])"
                                      pdf)))
          (should (eq 'no-labels (plist-get (sp-devonthink-pdf-page-for-label pdf "1") :why)))
          (should (eq 0 (call-process "python3" nil nil nil
                                      (expand-file-name "pdf-labels-book.py" tools)
                                      pdf "--first-page" "9" "--apply"
                                      "--library" "/nonexistent" "--bib" "/nonexistent.bib"
                                      "--backup-dir" (make-temp-file "sp-bk" t))))
          (should (equal (sp-devonthink-pdf-page-for-label pdf "1") '(:page 9)))
          (should (equal (sp-devonthink-pdf-page-for-label pdf "4") '(:page 12)))
          (should (eq 'not-found (plist-get (sp-devonthink-pdf-page-for-label pdf "5") :why))))
      (delete-file pdf))))

(ert-deftest sp-devonthink-pdf-page-for-label-reports-a-missing-program ()
  (let ((sp-devonthink-label-command '("/nonexistent/python")))
    (should (eq 'error (plist-get (sp-devonthink-pdf-page-for-label "/x.pdf" "1") :why)))))

(provide 'sp-devonthink-test)
