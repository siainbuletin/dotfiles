;;; sp-batch-report-test.el --- Tests for sp-batch-report -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-batch-report)

(defun sp-batch-report-test--link-at (text)
  "The (TYPE PATH DESCRIPTION) of the first link in the Org TEXT."
  (with-temp-buffer
    (org-mode)
    (insert text)
    (goto-char (point-min))
    (re-search-forward "\\[\\[")
    (goto-char (match-beginning 0))
    (let ((link (org-element-link-parser)))
      (list (org-element-property :type link)
            (org-element-property :path link)
            (buffer-substring-no-properties
             (org-element-property :contents-begin link)
             (org-element-property :contents-end link))))))

(ert-deftest sp-batch-report-file-link ()
  (should (equal (sp-batch-report-file-link "/tmp/notes/kant2009.org")
                 "[[file:/tmp/notes/kant2009.org][kant2009.org]]"))
  (should (equal (sp-batch-report-file-link "/tmp/a.org" "the note")
                 "[[file:/tmp/a.org][the note]]"))
  (should (equal (sp-batch-report-file-link "/tmp/a.org" nil 12)
                 "[[file:/tmp/a.org::12][a.org]]")))

(ert-deftest sp-batch-report-file-link-is-absolute ()
  (let ((default-directory "/tmp/vault/"))
    (should (equal (sp-batch-report-file-link "note.org")
                   "[[file:/tmp/vault/note.org][note.org]]"))))

(ert-deftest sp-batch-report-file-link-brackets ()
  "A bracket in the name does not break the link."
  (let ((link (sp-batch-report-file-link "/tmp/a [draft].org")))
    (should (equal (cl-subseq (sp-batch-report-test--link-at link) 0 2)
                   '("file" "/tmp/a [draft].org")))))

(ert-deftest sp-batch-report-file-links ()
  (should (equal (sp-batch-report-file-links '("/tmp/a.org" "/tmp/b.org"))
                 "[[file:/tmp/a.org][a.org]], [[file:/tmp/b.org][b.org]]"))
  (should (equal (sp-batch-report-file-links '("/tmp/a.org" "/tmp/b.org") "; ")
                 "[[file:/tmp/a.org][a.org]]; [[file:/tmp/b.org][b.org]]"))
  (should (equal (sp-batch-report-file-links nil) "")))

(ert-deftest sp-batch-report-note-link ()
  (should (equal (sp-batch-report-note-link "abc-123" "Kant (2009) Title")
                 "[[id:abc-123][Kant (2009) Title]]")))

(ert-deftest sp-batch-report-show ()
  (let ((buffer (save-window-excursion
                  (sp-batch-report-show "*sp-batch-report-test*"
                                        "#+title: T\n* One\n- [[file:/tmp/a.org][a.org]]\n"))))
    (unwind-protect
        (with-current-buffer buffer
          (should (derived-mode-p 'sp-batch-report-mode))
          (should buffer-read-only)
          (should (= (point) (point-min)))
          (should (string-match-p "a\\.org" (buffer-string)))
          (should-error (sp-batch-report-refresh) :type 'user-error)
          (goto-char (point-min))
          (org-next-link)
          (should (looking-at "\\[\\[file:/tmp/a.org")))
      (kill-buffer buffer))))

(ert-deftest sp-batch-report-show-refresh ()
  "The refresh function is called by the refresh command, and survives a re-show."
  (let* ((calls 0)
         (refresh (lambda () (cl-incf calls)))
         (buffer (save-window-excursion
                   (sp-batch-report-show "*sp-batch-report-test*" "x\n" refresh))))
    (unwind-protect
        (with-current-buffer buffer
          (sp-batch-report-refresh)
          (should (= calls 1))
          (save-window-excursion (sp-batch-report-show "*sp-batch-report-test*" "y\n" refresh))
          (sp-batch-report-refresh)
          (should (= calls 2))
          (should (equal (buffer-string) "y\n")))
      (kill-buffer buffer))))

(ert-deftest sp-batch-report-show-mode ()
  "A mode derived from the report mode can be passed."
  (define-derived-mode sp-batch-report-test-mode sp-batch-report-mode "T")
  (let ((buffer (save-window-excursion
                  (sp-batch-report-show "*sp-batch-report-test*" "x\n" nil
                                        #'sp-batch-report-test-mode))))
    (unwind-protect
        (with-current-buffer buffer
          (should (derived-mode-p 'sp-batch-report-mode))
          (should (eq major-mode 'sp-batch-report-test-mode)))
      (kill-buffer buffer))))

(provide 'sp-batch-report-test)
;;; sp-batch-report-test.el ends here
