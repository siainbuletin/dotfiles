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

(ert-deftest sp-devonthink-front-script-visits-all-windows ()
  (should (string-match-p "repeat with theWindow in (every window)" sp-devonthink--front-script))
  (should-not (string-match-p "think window 1" sp-devonthink--front-script))
  (should (string-match-p "content record of theWindow" sp-devonthink--front-script))
  (should (string-match-p "exit repeat" sp-devonthink--front-script)))

(ert-deftest sp-devonthink-store-link-multiline-selection ()
  (let* ((org-stored-links nil) (kill-ring nil)
         (out (format "%s\tsmith-2017-x.pdf\t3\tline one\nline two\n" sp-devonthink-test--uuid)))
    (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) out)))
      (sp-devonthink-store-link)
      (should (equal (car kill-ring) "line one\nline two")))))

(ert-deftest sp-devonthink-first-page-parses-ranges-and-odd-values ()
  (should (= (sp-devonthink-first-page "45--67") 45))
  (should (= (sp-devonthink-first-page "45-67") 45))
  (should (= (sp-devonthink-first-page " 45 – 67 ") 45))
  (should (= (sp-devonthink-first-page "e123") 123))
  (should (= (sp-devonthink-first-page "12,15") 12))
  (should (= (sp-devonthink-first-page "7") 7))
  (should-not (sp-devonthink-first-page "xii--xv"))
  (should-not (sp-devonthink-first-page "0"))
  (should-not (sp-devonthink-first-page ""))
  (should-not (sp-devonthink-first-page nil)))

(ert-deftest sp-devonthink-resolve-own-record-wins ()
  (cl-letf (((symbol-function 'sp-reading-uuid)
             (lambda (k) (and (equal k "child-2001-x") "U-OWN")))
            ((symbol-function 'citar-get-value) (lambda (&rest _) "parent-2000-b")))
    (should (equal (sp-devonthink-resolve "child-2001-x")
                   '(:uuid "U-OWN" :supplier "child-2001-x")))))

(ert-deftest sp-devonthink-resolve-through-crossref-with-offset ()
  (let ((sp-devonthink-page-offset 0)
        (sp-devonthink-parent-page-offsets '(("parent-2000-b" . 8))))
    (cl-letf (((symbol-function 'sp-reading-uuid)
               (lambda (k) (and (equal k "parent-2000-b") "U-PARENT")))
              ((symbol-function 'citar-get-value)
               (lambda (field _key)
                 (pcase field ('crossref "parent-2000-b") ('pages "45--67")))))
      (let ((r (sp-devonthink-resolve "child-2001-x")))
        (should (equal (plist-get r :uuid) "U-PARENT"))
        (should (= (plist-get r :page) 53))
        (should (equal (plist-get r :via) "parent-2000-b"))))
    (let ((sp-devonthink-parent-page-offsets nil))
      (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (k) (and (equal k "p") "U-P")))
                ((symbol-function 'citar-get-value)
                 (lambda (field _key) (pcase field ('crossref "p") ('pages "xii--xv")))))
        (let ((r (sp-devonthink-resolve "c")))
          (should (null (plist-get r :page)))
          (should (string-match-p "no usable pages" (plist-get r :note))))))))

(ert-deftest sp-devonthink-resolve-no-parent-record ()
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) nil))
            ((symbol-function 'citar-get-value)
             (lambda (field _key) (and (eq field 'crossref) "parent-2000-b"))))
    (should-not (sp-devonthink-resolve "child-2001-x")))
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) nil))
            ((symbol-function 'citar-get-value) (lambda (&rest _) nil)))
    (should-not (sp-devonthink-resolve "alone-2001-x"))))

(ert-deftest sp-devonthink-citar-open-opens-parent-at-first-page ()
  (let (opened (sp-devonthink-page-offset 2) (current-prefix-arg nil))
    (cl-letf (((symbol-function 'sp-reading-uuid)
               (lambda (k) (and (equal k "parent-2000-b") "U-PARENT")))
              ((symbol-function 'citar-get-value)
               (lambda (field _key) (pcase field ('crossref "parent-2000-b") ('pages "45--67"))))
              ((symbol-function 'sp-reading--open-url) (lambda (u) (setq opened u)))
              ((symbol-function 'message) #'ignore))
      (sp-devonthink-citar-open "child-2001-x")
      ;; printed 45 + offset 2 = PDF page 47, URL counts from 0
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

(defmacro sp-devonthink-test--with-crossref (&rest body)
  "Run BODY with an entry child-2001-x that has no record but a parent with one."
  `(cl-letf (((symbol-function 'sp-reading-uuid)
              (lambda (k) (and (equal k "parent-2000-b") sp-devonthink-test--uuid)))
             ((symbol-function 'citar-get-value)
              (lambda (field _key)
                (pcase field ('crossref "parent-2000-b") ('pages "45--67"))))
             ((symbol-function 'citar-select-ref) (lambda () "child-2001-x")))
     (let ((sp-devonthink-page-offset 2) (sp-devonthink-parent-page-offsets nil)
           (current-prefix-arg nil))
       ,@body)))

(ert-deftest sp-devonthink-record-is-the-one-resolver ()
  (sp-devonthink-test--with-crossref
   (let ((r (sp-devonthink-record "child-2001-x")))
     (should (equal (plist-get r :uuid) sp-devonthink-test--uuid))
     (should (equal (plist-get r :via) "parent-2000-b"))
     (should (equal (plist-get r :supplier) "parent-2000-b"))))
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) nil))
            ((symbol-function 'citar-get-value) (lambda (&rest _) nil)))
    (should-not (sp-devonthink-record "alone-2001-z"))))

(ert-deftest sp-devonthink-field-falls-back-to-citar-get-entry ()
  (cl-letf (((symbol-function 'citar-get-value) (lambda (&rest _) nil))
            ((symbol-function 'citar-get-entry)
             (lambda (_) '(("Crossref" . " parent-2000-b ") ("pages" . "")))))
    (should (equal (sp-devonthink--parent-key "k") "parent-2000-b"))
    (should-not (sp-devonthink--field 'pages "k"))))

(ert-deftest sp-devonthink-insert-link-for-an-entry-with-only-a-crossref ()
  ;; The real interactive path: citar picks the entry, the page prompt starts
  ;; with the chapter's first page (45 + offset 2), and the answer is taken as is.
  (sp-devonthink-test--with-crossref
   (let (initial)
     (cl-letf (((symbol-function 'message) #'ignore)
               ((symbol-function 'read-string)
                (lambda (_prompt &optional init &rest _) (setq initial init) init)))
       (with-temp-buffer
         (call-interactively #'sp-devonthink-insert-link)
         (should (equal initial "47"))
         (should (equal (buffer-string)
                        (format "[[devonthink:%s::47][child-2001-x p. 47]]"
                                sp-devonthink-test--uuid))))))))

(ert-deftest sp-devonthink-insert-link-crossref-page-can-be-cleared ()
  (sp-devonthink-test--with-crossref
   (cl-letf (((symbol-function 'message) #'ignore)
             ((symbol-function 'read-string) (lambda (&rest _) "")))
     (with-temp-buffer
       (call-interactively #'sp-devonthink-insert-link)
       (should (equal (buffer-string)
                      (format "[[devonthink:%s][child-2001-x]]" sp-devonthink-test--uuid)))))))

(ert-deftest sp-devonthink-insert-link-no-record-anywhere ()
  (cl-letf (((symbol-function 'sp-reading-uuid) (lambda (_) nil))
            ((symbol-function 'citar-get-value) (lambda (&rest _) nil)))
    (with-temp-buffer
      (should-error (sp-devonthink-insert-link "alone-2001-z" nil) :type 'user-error))))

(ert-deftest sp-devonthink-open-from-note-uses-crossref-parent ()
  (sp-devonthink-test--with-crossref
   (let (opened)
     (cl-letf (((symbol-function 'sp-reading--open-url) (lambda (u) (setq opened u)))
               ((symbol-function 'message) #'ignore))
       (with-temp-buffer
         (insert ":PROPERTIES:\n:ROAM_REFS: @child-2001-x\n:END:\n#+title: x\n")
         (sp-devonthink-open-from-note)
         ;; page 47 (from 1) is ?page=46 in DEVONthink's URL
         (should (string-match-p "\\?page=46\\'" opened))
         (should (string-match-p sp-devonthink-test--uuid opened)))))))

(ert-deftest sp-devonthink-set-keyword-asks-before-using-the-parents-record ()
  (sp-devonthink-test--with-crossref
   (with-temp-buffer
     (insert ":PROPERTIES:\n:ROAM_REFS: @child-2001-x\n:END:\n#+title: x\n")
     (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
       (should-error (sp-devonthink-set-keyword) :type 'user-error))
     (should-not (sp-devonthink-note-uuid))
     (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
       (sp-devonthink-set-keyword))
     (should (equal (sp-devonthink-note-uuid) sp-devonthink-test--uuid)))))

(ert-deftest sp-devonthink-note-record-uuid-follows-crossref-and-asks ()
  (sp-devonthink-test--with-crossref
   (with-temp-buffer
     (insert ":PROPERTIES:\n:ROAM_REFS: @child-2001-x\n:END:\n#+title: x\n")
     (let (said)
       (cl-letf (((symbol-function 'message) (lambda (fmt &rest a) (setq said (apply #'format fmt a)))))
         (should (equal (sp-devonthink-note-record-uuid) sp-devonthink-test--uuid))
         (should (string-match-p "using the record of parent-2000-b" said)))
       (cl-letf (((symbol-function 'y-or-n-p) (lambda (p) (setq said p) nil)))
         (should-error (sp-devonthink-note-record-uuid "tag") :type 'user-error)
         (should (string-match-p "Tag the record of parent-2000-b (the whole book)" said)))
       (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
         (should (equal (sp-devonthink-note-record-uuid "tag") sp-devonthink-test--uuid)))))))

(provide 'sp-devonthink-test)
;;; sp-devonthink-test.el ends here
