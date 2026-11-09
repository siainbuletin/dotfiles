;;; sp-backup-lookup-test.el --- Tests for sp-backup-lookup -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-backup-lookup)

(defmacro sp-backup-lookup-test--with-folder (var &rest body)
  "Run BODY with VAR bound to a fresh temporary folder."
  (declare (indent 1))
  `(let ((,var (file-name-as-directory (make-temp-file "sp-backup-lookup" t))))
     (unwind-protect (progn ,@body)
       (delete-directory ,var t))))

(defun sp-backup-lookup-test--touch (root &rest parts)
  "Create the file made of the PARTS below ROOT and return its path."
  (let ((path (expand-file-name (mapconcat #'identity parts "/") root)))
    (make-directory (file-name-directory path) t)
    (write-region "backup\n" nil path)
    path))

(ert-deftest sp-backup-lookup-stamp-time ()
  (should (equal (sp-backup-lookup--stamp-time "20261109T225317")
                 (sp-backup-lookup--stamp-time "20261109-225317")))
  (should (equal (format-time-string "%F %T" (sp-backup-lookup--stamp-time "20261109T225317"))
                 "2026-11-09 22:53:17"))
  (should-not (sp-backup-lookup--stamp-time "files"))
  (should-not (sp-backup-lookup--stamp-time nil)))

(ert-deftest sp-backup-lookup-stamp-folder-layout ()
  "STAMP/name, as the titles, meta, meta-order and BibTeX commands write it."
  (sp-backup-lookup-test--with-folder root
    (let* ((old (sp-backup-lookup-test--touch root "20261101T100000" "kant.org"))
           (new (sp-backup-lookup-test--touch root "20261105T100000" "kant.org"))
           (sp-backup-lookup-directories `(("Titles" . ,root))))
      (sp-backup-lookup-test--touch root "20261105T100000" "hegel.org")
      (should (equal (mapcar (lambda (e) (plist-get e :path))
                             (sp-backup-lookup-list "/notes/kant.org"))
                     (list new old))))))

(ert-deftest sp-backup-lookup-suffix-layout ()
  "name and name.STAMP, as the references command writes it."
  (sp-backup-lookup-test--with-folder root
    (let* ((first (sp-backup-lookup-test--touch root "kant.org"))
           (second (sp-backup-lookup-test--touch root "kant.org.20261105T100000"))
           (_ (set-file-times first (encode-time 0 0 0 1 11 2026)))
           (sp-backup-lookup-directories `(("Refs" . ,root)))
           (found (sp-backup-lookup-list "/notes/kant.org")))
      (should (equal (mapcar (lambda (e) (plist-get e :path)) found)
                     (list second first)))
      (should (equal (plist-get (car found) :stamp) "20261105T100000"))
      (should-not (plist-get (cadr found) :stamp)))))

(ert-deftest sp-backup-lookup-path-layout ()
  "STAMP/path/of/the/file: only the backup of that very path matches."
  (sp-backup-lookup-test--with-folder root
    (let* ((file (sp-backup-lookup-test--touch root "notes" "a" "kant.org"))
           (mine (sp-backup-lookup-test--touch
                  root "20261105-100000"
                  (string-remove-prefix "/" (file-truename file))))
           (other (sp-backup-lookup-test--touch root "20261105-100000" "elsewhere" "kant.org"))
           (sp-backup-lookup-directories `(("Footnotes" . ,root)))
           (paths (mapcar (lambda (e) (plist-get e :path)) (sp-backup-lookup-list file))))
      (should (member mine paths))
      (should-not (member other paths)))))

(ert-deftest sp-backup-lookup-notes-filing-layout ()
  "STAMP/files/path-in-root, written by the notes filing."
  (sp-backup-lookup-test--with-folder root
    (let* ((backup (sp-backup-lookup-test--touch root "20261105-100000" "files" "sub" "kant.org"))
           (sp-backup-lookup-directories `(("Filing" . ,root))))
      (should (equal (mapcar (lambda (e) (plist-get e :path))
                             (sp-backup-lookup-list "/notes/sub/kant.org"))
                     (list backup)))
      (should-not (sp-backup-lookup-list "/notes/other/kant.org")))))

(ert-deftest sp-backup-lookup-skips-unbound-and-missing ()
  (let ((sp-backup-lookup-directories
         '(("Nothing" . sp-backup-lookup-test--unbound-variable)
           ("Missing" . "/nonexistent/backups/"))))
    (should-not (sp-backup-lookup-list "/notes/kant.org"))))

(ert-deftest sp-backup-lookup-link-file ()
  "The file of a report line is read from its Org link."
  (with-temp-buffer
    (insert "- [[file:/notes/kant.org::12][kant.org]] changed\n")
    (goto-char (point-min))
    (should (equal (sp-backup-lookup--link-file) "/notes/kant.org")))
  (with-temp-buffer
    (insert "- no link here\n")
    (should-not (sp-backup-lookup--link-file))))

(provide 'sp-backup-lookup-test)
;;; sp-backup-lookup-test.el ends here
