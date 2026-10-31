;;; sp-dashboard-entries-test.el --- Tests for the dashboard entry cache  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'org)

(defvar sp-cache-dir temporary-file-directory)

(load (expand-file-name
       "../libraries/modules/tooling/sp-dashboard.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro sp-dashboard-entries-test--with-files (bindings &rest body)
  "Run BODY with each (VAR CONTENT) of BINDINGS a temporary Org file and a clean cache."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "sp-dashboard-test" t))
          (sp-dashboard-entries-cache-file (expand-file-name "entries.eld" dir))
          (sp-dashboard--file-entries nil)
          (sp-dashboard--entries-signature nil)
          (sp-dashboard--entries-cache nil)
          (org-todo-keywords '((sequence "TODO" "|" "DONE")))
          ,@(mapcar (lambda (b)
                      `(,(car b) (let ((f (expand-file-name ,(format "%s.org" (car b)) dir)))
                                   (with-temp-file f (insert ,(cadr b)))
                                   f)))
                    bindings))
     (unwind-protect (progn ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (string-prefix-p dir (buffer-file-name buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory dir t))))

(defun sp-dashboard-entries-test--messages (thunk)
  "Return the dashboard message THUNK printed."
  (let (seen)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) seen))))
      (funcall thunk))
    (car seen)))

(ert-deftest sp-dashboard-entries-test-hit-after-first-read ()
  (sp-dashboard-entries-test--with-files ((a "* TODO one\n* DONE two\n* TODO three\n"))
    (should (= 2 (length (sp-dashboard--read-entries (list a)))))
    (should (string-match-p "1 cached.*0 re-read"
                            (progn (setq sp-dashboard--file-entries nil)
                                   (sp-dashboard-entries-test--messages
                                    (lambda () (sp-dashboard--read-entries (list a)))))))
    (should (string-match-p "0 cached, 1 re-read"
                            (progn (delete-file sp-dashboard-entries-cache-file)
                                   (setq sp-dashboard--file-entries nil)
                                   (sp-dashboard-entries-test--messages
                                    (lambda () (sp-dashboard--read-entries (list a)))))))))

(ert-deftest sp-dashboard-entries-test-persists-in-file ()
  (sp-dashboard-entries-test--with-files ((a "* TODO one\n"))
    (sp-dashboard--read-entries (list a))
    (setq sp-dashboard--file-entries nil)
    (should (string-match-p "1 cached, 0 re-read"
                            (sp-dashboard-entries-test--messages
                             (lambda () (sp-dashboard--read-entries (list a))))))))

(ert-deftest sp-dashboard-entries-test-rereads-changed-file ()
  (sp-dashboard-entries-test--with-files ((a "* TODO one\n"))
    (sp-dashboard--read-entries (list a))
    (with-temp-file a (insert "* TODO one\n* TODO a longer second heading\n"))
    (let (entries)
      (should (string-match-p "0 cached, 1 re-read"
                              (sp-dashboard-entries-test--messages
                               (lambda () (setq entries (sp-dashboard--read-entries (list a)))))))
      (should (= 2 (length entries))))))

(ert-deftest sp-dashboard-entries-test-drops-deleted-file ()
  (sp-dashboard-entries-test--with-files ((a "* TODO one\n") (b "* TODO two\n"))
    (sp-dashboard--read-entries (list a b))
    (delete-file b)
    (should (string-match-p "1 dropped"
                            (sp-dashboard-entries-test--messages
                             (lambda () (sp-dashboard--read-entries (list a))))))
    (should-not (gethash b sp-dashboard--file-entries))
    (should (gethash a sp-dashboard--file-entries))))

(ert-deftest sp-dashboard-entries-test-keywords-invalidate ()
  (sp-dashboard-entries-test--with-files ((a "* TODO one\n* WAIT two\n"))
    (should (= 1 (length (sp-dashboard--read-entries (list a)))))
    (let ((org-todo-keywords '((sequence "TODO" "WAIT" "|" "DONE"))))
      (should (string-match-p "0 cached, 1 re-read"
                              (sp-dashboard-entries-test--messages
                               (lambda () (sp-dashboard--read-entries (list a))))))
      (should (= 2 (length (sp-dashboard--read-entries (list a))))))))

(ert-deftest sp-dashboard-entries-test-days-stay-relative-to-today ()
  (sp-dashboard-entries-test--with-files ((a "* TODO due\nDEADLINE: <2030-01-10 Thu>\n"))
    (let ((day (org-time-string-to-absolute "<2030-01-10 Thu>")))
      (cl-letf (((symbol-function 'org-today) (lambda () (- day 3))))
        (should (= 3 (plist-get (car (sp-dashboard--read-entries (list a))) :deadline))))
      (cl-letf (((symbol-function 'org-today) (lambda () (- day 1))))
        ;; The second read comes from the cache and still counts from the new day.
        (should (= 1 (plist-get (car (sp-dashboard--read-entries (list a))) :deadline)))))))

(ert-deftest sp-dashboard-entries-test-skips-archived-and-unsaved-state ()
  (sp-dashboard-entries-test--with-files ((a "* TODO live\n* Old :ARCHIVE:\n** TODO hidden\n"))
    (should (equal '("live")
                   (mapcar (lambda (e) (plist-get e :heading))
                           (sp-dashboard--read-entries (list a)))))
    ;; An unsaved edit shows at once and is not cached.
    (with-current-buffer (find-file-noselect a)
      (goto-char (point-max))
      (insert "* TODO typed\n"))
    (should (= 2 (length (sp-dashboard--read-entries (list a)))))
    (with-current-buffer (find-file-noselect a) (set-buffer-modified-p nil))
    (should (= 1 (length (nth 2 (gethash a sp-dashboard--file-entries)))))))

(provide 'sp-dashboard-entries-test)
;;; sp-dashboard-entries-test.el ends here
