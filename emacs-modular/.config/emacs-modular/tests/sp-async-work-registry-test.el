;;; sp-async-work-registry-test.el --- Tests for C-g, status files and the job list -*- lexical-binding: t; -*-

;; The jobs run in slices from timers, as the commands do.  The status files
;; go to a temporary folder.

(require 'ert)
(require 'cl-lib)
(require 'sp-async-work)

(defmacro sp-async-work-registry-test--with-dir (&rest body)
  "Run BODY with the status files in a temporary folder, written at every slice."
  `(let* ((dir (make-temp-file "sp-jobs" t))
          (sp-async-work-registry-directory dir)
          (sp-async-work-registry-interval 0)
          (sp-async-work--jobs nil))
     (unwind-protect (progn ,@body)
       (dolist (job (copy-sequence sp-async-work--jobs)) (sp-async-work-cancel-job job))
       (delete-directory dir t))))

(defun sp-async-work-registry-test--wait-for (predicate)
  "Wait until PREDICATE is non-nil, for at most 10 seconds."
  (let ((limit (+ (float-time) 10)))
    (while (and (not (funcall predicate)) (< (float-time) limit))
      (sit-for 0.02))
    (should (funcall predicate))))

(defun sp-async-work-registry-test--forever (name &optional step)
  "Start a job NAME of many slow items, each handled by STEP."
  (sp-async-work-run
   name (list (list "stage" (lambda () (number-sequence 1 100000))
                    (or step (lambda (_ _) (sleep-for 0.01)))))))

(ert-deftest sp-async-work-registry-file-lives-while-the-job-runs ()
  (sp-async-work-registry-test--with-dir
   (let* ((job (sp-async-work-registry-test--forever "Registry test"))
          (file (expand-file-name (concat (sp-async-work-job-id job) ".job") dir)))
     (should (equal (sp-async-work-job-id job) (format "%d-registry-test" (emacs-pid))))
     (should (file-exists-p file))
     (sp-async-work-registry-test--wait-for
      (lambda () (> (string-to-number (cdr (assoc "done" (sp-async-work-registry-read file)))) 0)))
     (let ((record (sp-async-work-registry-read file)))
       (should (equal (cdr (assoc "name" record)) "Registry test"))
       (should (equal (cdr (assoc "stage" record)) "stage"))
       (should (equal (cdr (assoc "pid" record)) (number-to-string (emacs-pid)))))
     (sp-async-work-cancel-job job)
     (should-not (file-exists-p file)))))

(ert-deftest sp-async-work-registry-file-goes-when-the-job-finishes ()
  (sp-async-work-registry-test--with-dir
   (let ((job (sp-async-work-run "Short" (list (list "s" (lambda () '(1 2)) #'ignore)))))
     (should (eq (sp-async-work-wait job) 'finished))
     (should-not (directory-files dir nil "\\.\\(job\\|cancel\\)\\'")))))

(ert-deftest sp-async-work-registry-cancel-file-stops-the-job ()
  (sp-async-work-registry-test--with-dir
   (let ((job (sp-async-work-registry-test--forever "From outside")))
     (should (sp-async-work-registry-jobs))
     ;; Another process asks: it writes the cancel file.
     (write-region "" nil (expand-file-name (concat (sp-async-work-job-id job) ".cancel") dir))
     (should (eq (sp-async-work-wait job) 'cancelled))
     (should-not (directory-files dir nil "\\.\\(job\\|cancel\\)\\'")))))

(ert-deftest sp-async-work-registry-request-cancel-of-a-local-job-is-immediate ()
  (sp-async-work-registry-test--with-dir
   (let ((job (sp-async-work-registry-test--forever "Local")))
     (sp-async-work-request-cancel (sp-async-work-job-id job))
     (should (eq (sp-async-work-job-status job) 'cancelled)))))

(ert-deftest sp-async-work-registry-lists-and-drops-stale-files ()
  (sp-async-work-registry-test--with-dir
   (let ((job (sp-async-work-registry-test--forever "Listed"))
         (stale (expand-file-name "99999999-gone.job" dir)))
     (write-region "id=99999999-gone\npid=99999999\nname=Gone\nstarted=1\n" nil stale)
     (let ((records (sp-async-work-registry-jobs)))
       (should (equal (mapcar (lambda (r) (cdr (assoc "id" r))) records)
                      (list (sp-async-work-job-id job)))))
     (should-not (file-exists-p stale))
     (should (= 1 (length (sp-async-work--list-entries)))))))

(ert-deftest sp-async-work-quit-in-a-slice-stops-the-job ()
  "C-g during a slice: the job ends, it is not left running without a timer."
  (sp-async-work-registry-test--with-dir
   (let* ((seen 'unset)
          (job (sp-async-work-registry-test--forever
                "Quit" (lambda (_ _) (setq seen inhibit-quit) (signal 'quit nil)))))
     (should (eq (sp-async-work-wait job) 'cancelled))
     (should-not seen)
     (should-not sp-async-work--jobs))))

(ert-deftest sp-async-work-registry-double-quit-stops-the-jobs ()
  (sp-async-work-registry-test--with-dir
   (let ((job (sp-async-work-registry-test--forever "Double")))
     (let ((last-command 'self-insert-command))
       (sp-async-work--keyboard-quit))
     (should (eq (sp-async-work-job-status job) 'running))
     (let ((last-command 'keyboard-quit))
       (sp-async-work--keyboard-quit))
     (should (eq (sp-async-work-job-status job) 'cancelled)))))

(provide 'sp-async-work-registry-test)
;;; sp-async-work-registry-test.el ends here
