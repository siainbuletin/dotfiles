;;; sp-quick-capture-test.el --- Tests for sp-quick-capture  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-quick-capture-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(load (expand-file-name
       "../libraries/modules/text/sp-quick-capture.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

;; Friday 2026-10-23, noon.
(defvar sp-quick-capture-test--now (encode-time '(0 0 12 23 10 2026 nil -1 nil)))

(defmacro sp-quick-capture-test--with-tags (&rest body)
  `(let ((org-tag-alist '(("@home" . ?H) ("@errands" . ?e) ("@email" . ?m) ("deep" . ?d)))
         (org-tag-persistent-alist '(("area") ("project"))))
     ,@body))

(defun sp-quick-capture-test--date (word)
  (let ((time (sp-quick-capture-parse-date word sp-quick-capture-test--now)))
    (and time (format-time-string "%Y-%m-%d" time))))

(ert-deftest sp-quick-capture-test-dates ()
  (should (equal (sp-quick-capture-test--date "today") "2026-10-23"))
  (should (equal (sp-quick-capture-test--date "tom") "2026-10-24"))
  (should (equal (sp-quick-capture-test--date "mon") "2026-10-26"))
  (should (equal (sp-quick-capture-test--date "fri") "2026-10-30"))
  (should (equal (sp-quick-capture-test--date "Friday") "2026-10-30"))
  (should (equal (sp-quick-capture-test--date "+3d") "2026-10-26"))
  (should (equal (sp-quick-capture-test--date "2w") "2026-11-06"))
  (should (equal (sp-quick-capture-test--date "+1m") "2026-11-23"))
  (should (equal (sp-quick-capture-test--date "2026-12-01") "2026-12-01"))
  (should (equal (sp-quick-capture-test--date "3nov") "2026-11-03"))
  (should (equal (sp-quick-capture-test--date "nov3") "2026-11-03"))
  (should (equal (sp-quick-capture-test--date "11-03") "2026-11-03"))
  (should (equal (sp-quick-capture-test--date "3jan") "2027-01-03"))
  (should-not (sp-quick-capture-test--date "31-02"))
  (should-not (sp-quick-capture-test--date "soon")))

(ert-deftest sp-quick-capture-test-month-end-clamped ()
  (let ((jan31 (encode-time '(0 0 12 31 1 2027 nil -1 nil))))
    (should (equal (format-time-string
                    "%Y-%m-%d" (sp-quick-capture-parse-date "+1m" jan31))
                   "2027-02-28"))))

(ert-deftest sp-quick-capture-test-parse-full-line ()
  (sp-quick-capture-test--with-tags
   (let ((p (sp-quick-capture-parse "Buy milk #errands !fri ^tom" sp-quick-capture-test--now)))
     (should (equal (plist-get p :title) "Buy milk"))
     (should (equal (plist-get p :tags) '("@errands")))
     (should (equal (plist-get p :deadline) "<2026-10-30 Fri>"))
     (should (equal (plist-get p :scheduled) "<2026-10-24 Sat>"))
     (should-not (plist-get p :warnings)))))

(ert-deftest sp-quick-capture-test-tag-matching ()
  (sp-quick-capture-test--with-tags
   ;; prefix, exact with @, unique
   (should (equal (plist-get (sp-quick-capture-parse "x #err") :tags) '("@errands")))
   (should (equal (plist-get (sp-quick-capture-parse "x #@home") :tags) '("@home")))
   (should (equal (plist-get (sp-quick-capture-parse "x #deep") :tags) '("deep")))
   ;; ambiguous: "e" matches errands and email, word stays in the title
   (let ((p (sp-quick-capture-parse "x #e")))
     (should (equal (plist-get p :title) "x #e"))
     (should-not (plist-get p :tags))
     (should (plist-get p :warnings)))
   ;; unknown: kept, with a warning
   (let ((p (sp-quick-capture-parse "x #zzz")))
     (should (equal (plist-get p :tags) '("zzz")))
     (should (plist-get p :warnings)))))

(ert-deftest sp-quick-capture-test-plain-words-survive ()
  (sp-quick-capture-test--with-tags
   (let ((p (sp-quick-capture-parse "Call mum! 100% sure #" sp-quick-capture-test--now)))
     (should (equal (plist-get p :title) "Call mum! 100% sure #")))
   (let ((p (sp-quick-capture-parse "Fix it !whenever" sp-quick-capture-test--now)))
     (should (equal (plist-get p :title) "Fix it !whenever"))
     (should (plist-get p :warnings)))))

(ert-deftest sp-quick-capture-test-insert-creates-heading-and-entry ()
  (sp-quick-capture-test--with-tags
   (let* ((dir (make-temp-file "sp-qc" t))
          (file (expand-file-name "inbox.org" dir))
          (sp-quick-capture-file file))
     (unwind-protect
         (progn
           (sp-quick-capture-insert
            (sp-quick-capture-parse "Buy 50% milk #errands !fri" sp-quick-capture-test--now))
           (sp-quick-capture-insert
            (sp-quick-capture-parse "Second ^tom" sp-quick-capture-test--now))
           (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
             (should (string-match-p "^\\* Tasks$" text))
             (should (string-match-p "^\\*\\* TODO Buy 50% milk +:@errands:$" text))
             (should (string-match-p "^DEADLINE: <2026-10-30 Fri>$" text))
             (should (string-match-p "^SCHEDULED: <2026-10-24 Sat>$" text))
             (should (string-match-p "^:ID: " text))
             (should (string-match-p "^:CREATED: " text))))
       (when-let* ((buf (get-file-buffer file))) (kill-buffer buf))
       (delete-directory dir t)))))

(ert-deftest sp-quick-capture-test-insert-into-existing-heading ()
  (sp-quick-capture-test--with-tags
   (let* ((dir (make-temp-file "sp-qc" t))
          (file (expand-file-name "inbox.org" dir))
          (sp-quick-capture-file file))
     (with-temp-file file
       (insert "* Thoughts\n** idea\n* Tasks\n** TODO old\n* After\n"))
     (unwind-protect
         (progn
           (sp-quick-capture-insert (sp-quick-capture-parse "new one"))
           (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
             (should (string-match-p "\\*\\* TODO old\n\\*\\* TODO new one\n" text))
             (should (< (string-match "TODO new one" text) (string-match "^\\* After" text)))))
       (when-let* ((buf (get-file-buffer file))) (kill-buffer buf))
       (delete-directory dir t)))))

(ert-deftest sp-quick-capture-test-empty-title-is-an-error ()
  (should-error (sp-quick-capture-insert (sp-quick-capture-parse "#deep !fri"))
                :type 'user-error))

(ert-deftest sp-quick-capture-test-returns-preview ()
  (sp-quick-capture-test--with-tags
   (let* ((dir (make-temp-file "sp-qc" t))
          (file (expand-file-name "inbox.org" dir))
          (sp-quick-capture-file file))
     (unwind-protect
         (should (equal (sp-quick-capture "Buy milk #errands")
                        "→ Buy milk  :@errands:"))
       (when-let* ((buf (get-file-buffer file))) (kill-buffer buf))
       (delete-directory dir t)))))

(defmacro sp-quick-capture-test--with-spool (&rest body)
  "Run BODY with a temporary inbox and spool; bind `dir', `file' and `spool'."
  `(let* ((dir (make-temp-file "sp-qc" t))
          (file (expand-file-name "inbox.org" dir))
          (spool (expand-file-name "spool" dir))
          (sp-quick-capture-file file)
          (sp-quick-capture-spool-dir spool))
     (make-directory spool)
     (unwind-protect (progn ,@body)
       (when-let* ((buf (get-file-buffer file))) (kill-buffer buf))
       (delete-directory dir t))))

(defun sp-quick-capture-test--spool (spool name line time)
  (let ((f (expand-file-name name spool)))
    (with-temp-file f (insert line "\n"))
    (set-file-times f time)
    f))

(ert-deftest sp-quick-capture-test-drain-uses-capture-time ()
  (sp-quick-capture-test--with-tags
   (sp-quick-capture-test--with-spool
    ;; Captured Friday 2026-10-23, filed whenever: "!tom" is the 24th.
    (sp-quick-capture-test--spool spool "1-a.txt" "Buy milk #errands !tom"
                                  sp-quick-capture-test--now)
    (should (= (sp-quick-capture-drain) 1))
    (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (should (string-match-p "TODO Buy milk +:@errands:" text))
      (should (string-match-p "DEADLINE: <2026-10-24 Sat>" text))
      (should (string-match-p ":CREATED:  \\[2026-10-23 12:00\\]" text)))
    (should-not (sp-quick-capture-pending)))))

(ert-deftest sp-quick-capture-test-drain-keeps-order-and-ignores-partial ()
  (sp-quick-capture-test--with-spool
   (sp-quick-capture-test--spool spool "2-b.txt" "second" sp-quick-capture-test--now)
   (sp-quick-capture-test--spool spool "1-a.txt" "first" sp-quick-capture-test--now)
   (sp-quick-capture-test--spool spool ".new.XYZ" "half written" sp-quick-capture-test--now)
   (should (= (sp-quick-capture-drain) 2))
   (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
     (should (< (string-match "first" text) (string-match "second" text)))
     (should-not (string-match-p "half written" text)))
   (should (file-exists-p (expand-file-name ".new.XYZ" spool)))))

(ert-deftest sp-quick-capture-test-drain-parks-failures ()
  (sp-quick-capture-test--with-spool
   (sp-quick-capture-test--spool spool "1-a.txt" "#deep" sp-quick-capture-test--now)
   (sp-quick-capture-test--spool spool "2-b.txt" "fine" sp-quick-capture-test--now)
   (should (= (sp-quick-capture-drain) 1))
   (should (file-exists-p (expand-file-name "failed/1-a.txt" spool)))
   (should-not (sp-quick-capture-pending))))

(ert-deftest sp-quick-capture-test-drain-without-spool ()
  (let ((sp-quick-capture-spool-dir "/nonexistent/sp-qc-spool"))
    (should (= (sp-quick-capture-drain) 0))))

(provide 'sp-quick-capture-test)
;;; sp-quick-capture-test.el ends here
