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

(provide 'sp-devonthink-test)
;;; sp-devonthink-test.el ends here
