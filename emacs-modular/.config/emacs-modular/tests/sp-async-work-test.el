;;; sp-async-work-test.el --- Tests for sp-async-work and the async commands -*- lexical-binding: t; -*-

;; These run the jobs the way the commands do: in slices, from timers.  The
;; other test files set `sp-async-work-synchronous' and test what the
;; commands compute; this one tests that Emacs stays usable and the
;; safety checks hold while a job runs.

(require 'ert)
(require 'cl-lib)
(require 'sp-async-work)
(require 'sp-litnotes-refs)
(require 'sp-litnotes-titles)
(require 'sp-author-notes-bibtex)

(defvar sp-bibtex-files)

;; The jobs write status files; keep them out of the real var folder.
(setq sp-async-work-registry-directory (make-temp-file "sp-jobs" t))
(defvar sp-literature-dir)

(defun sp-async-work-test--wait ()
  "Wait until no job runs."
  (let ((limit (+ (float-time) 30)))
    (while (and sp-async-work--jobs (< (float-time) limit))
      (sit-for 0.02))
    (should-not sp-async-work--jobs)))

(defun sp-async-work-test--write (file &rest lines)
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert (string-join lines "\n") "\n")))

(defun sp-async-work-test--read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest sp-async-work-stages-and-push ()
  (let ((sp-async-work-synchronous t) log)
    (sp-async-work-run
     "T"
     (list (list "a" (lambda () '(1 2))
                 (lambda (i job) (push i log) (when (= i 1) (sp-async-work-push job 10))))
           (list "b" (lambda () (list (length log))) (lambda (i _) (push (* 100 i) log))))
     :done (lambda (_) (push 'done log)))
    (should (equal (reverse log) '(1 10 2 300 done)))
    (should-not sp-async-work--jobs)))

(ert-deftest sp-async-work-yields-to-timers ()
  "A probe timer runs between the slices of a job, and the job finishes."
  (let* ((sp-async-work-synchronous nil)
         (sp-async-work-slice 0.005)
         (ticks 0) (handled 0)
         (probe (run-with-timer 0 0.001 (lambda () (cl-incf ticks)))))
    (unwind-protect
        (progn
          (sp-async-work-run "T" (list (list "x" (lambda () (number-sequence 1 40))
                                             (lambda (_i _job) (sleep-for 0.003) (cl-incf handled)))))
          (should (sp-async-work-find "T"))
          (sit-for 0.03)
          (should (string-match-p "\\[T x [0-9]+/40\\]" (sp-async-work--mode-line)))
          (sp-async-work-test--wait)
          (should (= handled 40))
          (should (> ticks 5)))
      (cancel-timer probe))))

(ert-deftest sp-async-work-cancel-and-cleanup ()
  (let ((sp-async-work-synchronous nil) (handled 0) cleaned)
    (let ((job (sp-async-work-run "T" (list (list "x" (lambda () (number-sequence 1 1000))
                                                  (lambda (_i job)
                                                    (sp-async-work-on-cleanup job (lambda () (setq cleaned t)))
                                                    (cl-incf handled)
                                                    (sleep-for 0.001)))))))
      (sit-for 0.05)
      (sp-async-work-cancel-job job)
      (should (eq (sp-async-work-job-status job) 'cancelled))
      (should cleaned)
      (let ((n handled))
        (sit-for 0.1)
        (should (= n handled)))
      (should-not sp-async-work--jobs))))

(ert-deftest sp-async-work-error-stops-the-job ()
  (let ((sp-async-work-synchronous nil) err cleaned)
    (let ((job (sp-async-work-run
                "T" (list (list "x" (lambda () '(1 2 3))
                                (lambda (i job)
                                  (sp-async-work-on-cleanup job (lambda () (setq cleaned t)))
                                  (when (= i 2) (error "boom")))))
                :on-error (lambda (e _job) (setq err (error-message-string e))))))
      (sp-async-work-test--wait)
      (should (equal err "boom"))
      (should cleaned)
      (should (eq (sp-async-work-job-status job) 'failed)))))

(ert-deftest sp-async-work-one-job-per-name ()
  (let ((sp-async-work-synchronous nil))
    (let ((job (sp-async-work-run "T" (list (list "x" (lambda () '(1)) #'ignore)))))
      (should-error (sp-async-work-run "T" nil) :type 'user-error)
      (sp-async-work-cancel-job job))))

(ert-deftest sp-async-work-waits-for-the-minibuffer ()
  (let ((sp-async-work-synchronous nil) (handled 0))
    (cl-letf (((symbol-function 'minibuffer-depth) (lambda () 1)))
      (let ((job (sp-async-work-run "T" (list (list "x" (lambda () '(1 2)) (lambda (_i _j) (cl-incf handled)))))))
        (sit-for 0.1)
        (should (= handled 0))
        (sp-async-work-cancel-job job)))))

(ert-deftest sp-async-work-titles-apply-in-slices ()
  "The whole apply flow, with its questions, runs from timers and writes the notes."
  (let* ((sp-async-work-synchronous nil)
         (sp-async-work-slice 0.002)
         (root (file-name-as-directory (make-temp-file "sp-async" t)))
         (dir (expand-file-name "litnotes/" root))
         (sp-litnotes-titles-directory dir)
         (sp-litnotes-titles-link-directory root)
         (sp-litnotes-titles-backup-directory (expand-file-name "backups/" root))
         (asked 0))
    (unwind-protect
        (progn
          (dotimes (i 30)
            (sp-async-work-test--write
             (expand-file-name (format "n%d.org" i) dir)
             ":PROPERTIES:" (format ":ID: %d" i) (format ":ROAM_REFS: @n%d" i) ":END:"
             "#+title: old" "- pub-author :: Lee, Ann" "- pub-year :: 2000" "- pub-title :: T"))
          (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (cl-incf asked) t))
                    ((symbol-function 'pop-to-buffer) #'ignore))
            (sp-litnotes-titles-convert)
            ;; The command returned before anything was read.
            (should (sp-async-work-find "Litnote titles"))
            (should (string-match-p "old" (sp-async-work-test--read (expand-file-name "n0.org" dir))))
            (sp-async-work-test--wait))
          (should (= asked 1))
          (dotimes (i 30)
            (should (string-match-p "^#\\+title: Lee (2000) T$"
                                    (sp-async-work-test--read
                                     (expand-file-name (format "n%d.org" i) dir))))))
      (delete-directory root t))))

(ert-deftest sp-async-work-titles-skips-a-note-edited-meanwhile ()
  "A note that changes between the report and the write is not written."
  (let* ((sp-async-work-synchronous nil)
         (root (file-name-as-directory (make-temp-file "sp-async" t)))
         (dir (expand-file-name "litnotes/" root))
         (sp-litnotes-titles-directory dir)
         (sp-litnotes-titles-link-directory root)
         (sp-litnotes-titles-backup-directory (expand-file-name "backups/" root))
         (a (expand-file-name "a.org" dir))
         (b (expand-file-name "b.org" dir)))
    (unwind-protect
        (progn
          (dolist (f (list a b))
            (sp-async-work-test--write
             f ":PROPERTIES:" (format ":ID: %s" (file-name-base f))
             (format ":ROAM_REFS: @%s" (file-name-base f)) ":END:" "#+title: old"
             "- pub-author :: Lee, Ann" "- pub-year :: 2000" "- pub-title :: T"))
          (cl-letf (((symbol-function 'yes-or-no-p)
                     (lambda (&rest _)
                       ;; the author is corrected while the question is open
                       (sp-async-work-test--write
                        b ":PROPERTIES:" ":ID: b" ":ROAM_REFS: @b" ":END:" "#+title: old"
                        "- pub-author :: Roe, Bo" "- pub-year :: 2000" "- pub-title :: T")
                       t))
                    ((symbol-function 'pop-to-buffer) #'ignore))
            (sp-litnotes-titles-convert)
            (sp-async-work-test--wait))
          (should (string-match-p "^#\\+title: Lee (2000) T$" (sp-async-work-test--read a)))
          (should (string-match-p "^#\\+title: old$" (sp-async-work-test--read b)))
          (should (file-exists-p b)))
      (delete-directory root t))))

(ert-deftest sp-async-work-refs-convert-skips-edited-and-open-notes ()
  (let* ((sp-async-work-synchronous nil)
         (root (file-name-as-directory (make-temp-file "sp-async" t)))
         (dir (expand-file-name "litnotes/" root))
         (sp-litnotes-refs-directory dir)
         (sp-litnotes-refs-backup-directory (expand-file-name "backups/" root))
         (sp-litnotes-refs-inbox-bib (expand-file-name "master.bib" root))
         (sp-literature-dir (expand-file-name "lit/" root))
         (sp-bibtex-files nil)
         (names '("a" "b" "c"))
         buffer)
    (unwind-protect
        (progn
          (dolist (n names)
            (sp-async-work-test--write
             (expand-file-name (concat n ".org") dir)
             ":PROPERTIES:" ":ID: x" ":END:" "#+title: t" (format "#+reference: %s2000" n)))
          (setq buffer (find-file-noselect (expand-file-name "c.org" dir)))
          (cl-letf (((symbol-function 'yes-or-no-p)
                     (lambda (&rest _)
                       ;; b is edited by someone else, c has unsaved changes in Emacs
                       (sp-async-work-test--write (expand-file-name "b.org" dir)
                                                  ":PROPERTIES:" ":ID: x" ":END:" "#+title: t"
                                                  "#+reference: other2000")
                       (with-current-buffer buffer (insert "typed"))
                       t))
                    ((symbol-function 'pop-to-buffer) #'ignore))
            (sp-litnotes-refs-convert)
            (sp-async-work-test--wait))
          (should (string-match-p "ROAM_REFS: @a2000" (sp-async-work-test--read (expand-file-name "a.org" dir))))
          (should-not (string-match-p "ROAM_REFS" (sp-async-work-test--read (expand-file-name "b.org" dir))))
          (should-not (string-match-p "ROAM_REFS" (sp-async-work-test--read (expand-file-name "c.org" dir)))))
      (when buffer (with-current-buffer buffer (set-buffer-modified-p nil)) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest sp-async-work-bibtex-splits-big-files ()
  "A .bib file of more entries than a slice reads gives the same works as a small one."
  (let* ((sp-async-work-synchronous nil)
         (sp-async-work-slice 0.002)
         (vault (file-name-as-directory (make-temp-file "sp-async" t)))
         (sp-author-notes-directory vault)
         (sp-author-notes-litnotes-directory (expand-file-name "litnotes/" vault))
         (bib (expand-file-name "refs.bib" vault))
         (sp-bibtex-files (list bib))
         groups)
    (unwind-protect
        (progn
          (make-directory sp-author-notes-litnotes-directory t)
          (with-temp-file bib
            (dotimes (i 450)
              (insert (format "@article{smith%d,\n  author = {Smith, John},\n  title = {T%d},\n  year = {2020}}\n" i i))))
          (sp-async-work-test--write (expand-file-name "p1.org" vault)
                                     ":PROPERTIES:" ":ID: p-smith" ":END:" "#+title: John Smith"
                                     "#+filetags: :person:" "")
          (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
            (sp-author-notes-bibtex)
            (should (sp-async-work-find "Author works"))
            (sp-async-work-test--wait))
          (with-current-buffer sp-author-notes-bibtex--buffer-name
            (should (string-match-p "John Smith  (450)" (buffer-string)))
            (kill-buffer))
          (setq groups (let ((sp-async-work-synchronous t)) (sp-author-notes-bibtex--compute)))
          (should (= 450 (length (cdar groups)))))
      (delete-directory vault t))))

(provide 'sp-async-work-test)
;;; sp-async-work-test.el ends here
