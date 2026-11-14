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

(defun sp-batch-report-test--file (text)
  (let ((file (make-temp-file "sp-br-" nil ".org")))
    (with-temp-file file (insert text))
    file))

(ert-deftest sp-batch-report-close-file-saves-then-kills ()
  (let ((file (sp-batch-report-test--file "one\n")))
    (unwind-protect
        (let ((buffer (find-file-noselect file)))
          (with-current-buffer buffer (insert "unsaved "))
          (should (null (sp-batch-report-close-file file)))
          (should-not (buffer-live-p buffer))
          (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                         "unsaved one\n")))
      (delete-file file))))

(ert-deftest sp-batch-report-close-file-off-leaves-the-buffer ()
  (let ((file (sp-batch-report-test--file "one\n"))
        (sp-batch-report-save-and-kill nil))
    (unwind-protect
        (let ((buffer (find-file-noselect file)))
          (with-current-buffer buffer (insert "unsaved "))
          (should (null (sp-batch-report-close-file file)))
          (should (buffer-live-p buffer))
          (should (buffer-modified-p buffer))
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer))
      (delete-file file))))

(ert-deftest sp-batch-report-flush-file-backs-up-the-disk-text-first ()
  (let ((file (sp-batch-report-test--file "disk\n")) seen)
    (unwind-protect
        (let ((buffer (find-file-noselect file)))
          (with-current-buffer buffer (insert "edit "))
          (sp-batch-report-flush-file
           file (lambda (f) (setq seen (with-temp-buffer (insert-file-contents f) (buffer-string)))))
          (should (equal seen "disk\n"))
          (should-not (buffer-modified-p buffer))
          (kill-buffer buffer))
      (delete-file file))))

(ert-deftest sp-batch-report-flush-file-reverts-a-stale-buffer ()
  (let ((file (sp-batch-report-test--file "old\n")))
    (unwind-protect
        (let ((buffer (find-file-noselect file)))
          (sleep-for 1.1)
          (with-temp-file file (insert "new\n"))
          (should-not (verify-visited-file-modtime buffer))
          (should (null (sp-batch-report-flush-file file)))
          (should (equal (with-current-buffer buffer (buffer-string)) "new\n"))
          (kill-buffer buffer))
      (delete-file file))))

(ert-deftest sp-batch-report-edited-buffer-wins-over-a-changed-file ()
  (let ((file (sp-batch-report-test--file "old\n")))
    (unwind-protect
        (let ((buffer (find-file-noselect file)))
          (with-current-buffer buffer (insert "mine "))
          (sleep-for 1.1)
          (with-temp-file file (insert "theirs\n"))
          (should (null (sp-batch-report-close-file file)))
          (should-not (buffer-live-p buffer))
          (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                         "mine old\n")))
      (delete-file file))))

(ert-deftest sp-batch-report-with-file-opens-and-closes ()
  (let ((file (sp-batch-report-test--file "x\n")))
    (unwind-protect
        (progn
          (should (equal (sp-batch-report-with-file
                          file (lambda () (insert "y") (buffer-string)))
                         "yx\n"))
          (should-not (find-buffer-visiting file))
          (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                         "yx\n")))
      (delete-file file))))

(ert-deftest sp-batch-report-with-file-keeps-the-buffer-in-use ()
  (let ((file (sp-batch-report-test--file "x\n")))
    (unwind-protect
        (let ((buffer (find-file-noselect file)))
          (with-current-buffer buffer
            (sp-batch-report-with-file file (lambda () (insert "y")))
            (should (buffer-live-p buffer))
            (should-not (buffer-modified-p buffer))
            (should (equal (buffer-string) "yx\n")))
          (kill-buffer buffer))
      (delete-file file))))

(ert-deftest sp-batch-report-with-file-off-keeps-an-open-buffer ()
  (let ((file (sp-batch-report-test--file "x\n"))
        (sp-batch-report-save-and-kill nil))
    (unwind-protect
        (let ((buffer (find-file-noselect file)))
          (sp-batch-report-with-file file (lambda () nil))
          (should (buffer-live-p buffer))
          (kill-buffer buffer)
          (sp-batch-report-with-file file (lambda () nil))
          (should-not (find-buffer-visiting file)))
      (delete-file file))))

(ert-deftest sp-batch-report-failed-kill-is-reported-quietly ()
  (let ((file (sp-batch-report-test--file "x\n")))
    (unwind-protect
        (let ((buffer (find-file-noselect file)))
          (with-current-buffer buffer
            (add-hook 'kill-buffer-query-functions #'ignore nil t)) ; ignored: bound to nil
          (cl-letf (((symbol-function 'kill-buffer) (lambda (&rest _) nil)))
            (should (equal (sp-batch-report-close-file file) "the buffer was not killed")))
          (kill-buffer buffer))
      (delete-file file))))

(ert-deftest sp-batch-report-hints-follow-the-functions ()
  (with-temp-buffer
    (sp-batch-report-mode)
    (let ((keys (mapcar #'car (sp-batch-report--hints))))
      (should-not (member "d" keys))
      (should-not (member "A" keys)))
    (setq sp-batch-report-refresh-function #'ignore
          sp-batch-report-apply-function #'ignore)
    (let ((keys (mapcar #'car (sp-batch-report--hints))))
      (should (member "d" keys))
      (should (member "A" keys))
      (should (member "g" keys)))
    (sp-batch-report--set-hints)
    (should (equal sp-echo-help--hints (sp-batch-report--hints)))
    (should-not header-line-format)))

(ert-deftest sp-batch-report-open-shows-hints-in-the-real-path ()
  "The path every batch command takes: hints shown at once, keys not in the header."
  (let (shown buffer)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) shown))))
      (save-window-excursion
        (unwind-protect
            (progn
              (setq buffer (sp-batch-report-open "*sp-batch-report-hints-test*"
                                                 "#+title: T\n* One\n"
                                                 :refresh #'ignore :apply #'ignore))
              (with-current-buffer buffer
                (should-not header-line-format)
                (should sp-echo-help-mode)
                (should (member #'sp-echo-help-show post-command-hook))
                (should (equal sp-echo-help--hints (sp-batch-report--hints))))
              (should (string-match-p "Apply" (car shown)))
              (should (string-match-p "Quit" (car shown))))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest sp-batch-report-hints-survive-a-lingering-message ()
  "A job's last message does not hide the hints for good: the idle show wins."
  (let (shown buffer)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) shown)))
              ((symbol-function 'current-message) (lambda () "Author notes: done")))
      (save-window-excursion
        (unwind-protect
            (progn
              (setq buffer (sp-batch-report-open "*sp-batch-report-hints-test*" "#+title: T\n"))
              (setq shown nil)
              (with-current-buffer buffer (sp-echo-help-show))
              (should-not shown)        ; the polite show leaves the message alone
              (sp-echo-help--idle-show)
              (should (string-match-p "Quit" (car shown))))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest sp-batch-report-no-key-lines-in-header-code ()
  "No converted report puts its key list in the header line any more."
  (let ((dir (file-name-directory (locate-library "sp-batch-report"))))
    (dolist (file '("sp-author-notes.el" "sp-author-notes-bibtex.el" "sp-org-tag-lint.el"
                    "sp-org-lint-footnotes.el"))
      (let ((path (expand-file-name file dir)))
        (when (file-exists-p path)
          (with-temp-buffer
            (insert-file-contents path)
            (goto-char (point-min))
            (should-not (re-search-forward "header-line-format[^\n]*\\(\\[\\|RET\\|\\bq\\b[^a-z]*\\(quit\\|Quit\\)\\)" nil t))))))))

(provide 'sp-batch-report-test)
;;; sp-batch-report-test.el ends here
