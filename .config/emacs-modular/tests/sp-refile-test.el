;;; sp-refile-test.el --- Tests for sp-refile -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(dolist (f '(vulpea denote))
  (unless (require f nil t) (provide f)))
(dolist (f '(sp-split-leave-parents sp-move-region-to-heading))
  (require f nil t))
(require 'sp-refile)

(defmacro sp-refile-test--with-file (var content &rest body)
  (declare (indent 2))
  `(let* ((,var (make-temp-file "sp-refile" nil ".org" ,content)))
     (unwind-protect (progn ,@body)
       (when-let* ((b (get-file-buffer ,var))) (with-current-buffer b (set-buffer-modified-p nil)) (kill-buffer b))
       (delete-file ,var))))

(ert-deftest sp-refile-test-note-as-subtree ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:ID: n1\n:END:\n#+title: My note\n#+filetags: :a:b:\n\nIntro.\n* Child\nText\n")
    (should (equal (sp-refile--note-as-subtree)
                   "* My note :a:b:\n:PROPERTIES:\n:ID:       n1\n:END:\nIntro.\n** Child\nText\n"))))

(ert-deftest sp-refile-test-move-within-file ()
  (sp-refile-test--with-file f "* A\n** A1\n* B\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (goto-char (point-min)) (search-forward "A1")
      (let ((target (save-excursion (goto-char (point-min)) (search-forward "* B")
                                    (copy-marker (line-beginning-position)))))
        (sp-refile--move-heading target (current-buffer)))
      (should (equal (buffer-string) "* A\n* B\n** A1\n")))))

(ert-deftest sp-refile-test-move-into-itself ()
  (sp-refile-test--with-file f "* A\n** A1\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (goto-char (point-min))
      (let ((target (save-excursion (search-forward "A1") (copy-marker (line-beginning-position)))))
        (should-error (sp-refile--move-heading target (current-buffer)) :type 'user-error)))))

(ert-deftest sp-refile-test-move-to-other-file-top ()
  (sp-refile-test--with-file a "* A\n** A1\n* B\n"
    (sp-refile-test--with-file b "#+title: T\n* X\n"
      (with-current-buffer (find-file-noselect a)
        (org-mode)
        (goto-char (point-min)) (search-forward "A1")
        (sp-refile--move-heading nil (find-file-noselect b))
        (should (equal (buffer-string) "* A\n* B\n")))
      (with-current-buffer (find-file-noselect b)
        (org-mode)
        (should (equal (buffer-string) "#+title: T\n* X\n* A1\n"))))))

(provide 'sp-refile-test)
;;; sp-refile-test.el ends here
