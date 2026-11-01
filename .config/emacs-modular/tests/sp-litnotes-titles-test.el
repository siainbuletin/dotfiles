;;; sp-litnotes-titles-test.el --- Tests for sp-litnotes-titles -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-litnotes-titles)

(defun sp-litnotes-titles-test--write (file &rest lines)
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert (string-join lines "\n") "\n")))

(defun sp-litnotes-titles-test--read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro sp-litnotes-titles-test--with-vault (&rest body)
  "Run BODY with a temporary vault: `dir' (litnotes) and `root'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "sp-titles" t)))
          (dir (expand-file-name "litnotes/" root))
          (sp-litnotes-titles-directory dir)
          (sp-litnotes-titles-link-directory root)
          (sp-litnotes-titles-backup-directory (expand-file-name "backups/" root)))
     (make-directory dir t)
     (unwind-protect (progn ,@body) (delete-directory root t))))

(defun sp-litnotes-titles-test--note (dir name id title &rest more)
  (apply #'sp-litnotes-titles-test--write (expand-file-name name dir)
         ":PROPERTIES:" (format ":ID:       %s" id) ":ROAM_REFS: @kant2009" ":END:"
         (format "#+title: %s" title) more))

(defun sp-litnotes-titles-test--status (plans)
  (mapcar (lambda (p) (list (file-name-nondirectory (plist-get p :file))
                            (plist-get p :title-status) (plist-get p :name-status)))
          plans))

(ert-deftest sp-litnotes-titles-slug ()
  (should (equal (sp-litnotes-titles-slug "Kritik der reinen Vernunft: Über „Zeit“" "-")
                 "kritik-der-reinen-vernunft-uber-zeit"))
  (should (equal (sp-litnotes-titles-slug "What's new?" "_") "what_s_new"))
  (should (equal (sp-litnotes-titles-slug "???" "-") ""))
  (let ((sp-litnotes-titles-max-slug-length 12))
    (should (equal (sp-litnotes-titles-slug "alpha beta gamma delta" "-") "alpha-beta"))))

(ert-deftest sp-litnotes-titles-names ()
  (should (equal (sp-litnotes-titles--new-name
                  "20240101T120000--kant2009__litnote_book.org" "A Title")
                 "20240101T120000--a-title__litnote_book.org"))
  (should (equal (sp-litnotes-titles--new-name "20240101120000_kant2009.org" "A Title")
                 "20240101120000_a_title.org"))
  (should (eq (sp-litnotes-titles--new-name "kant2009.org" "A Title") 'odd-name))
  (should (eq (sp-litnotes-titles--new-name "20240101T120000--x.org" "???") 'no-slug)))

(ert-deftest sp-litnotes-titles-plan-statuses ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--note dir "20240101T120000--a__litnote.org" "1" "a"
                                   "- pub-title :: Alpha Study")
    (sp-litnotes-titles-test--note dir "20240102T120000--b__litnote.org" "2" "b")
    (sp-litnotes-titles-test--note dir "20240103T120000--c__litnote.org" "3" "c"
                                   "- pub-title ::")
    (sp-litnotes-titles-test--note dir "20240104T120000--gamma.org" "4" "Gamma"
                                   "- pub-title :: Gamma")
    (sp-litnotes-titles-test--write (expand-file-name "20240105T120000--d.org" dir)
                                    "#+title: d" "- pub-title :: Delta")
    (sp-litnotes-titles-test--note dir "odd.org" "6" "odd" "- pub-title :: Odd One")
    ;; two notes with the same slug, and one that meets an existing file
    (sp-litnotes-titles-test--note dir "20240107T120000--e.org" "7" "e" "- pub-title :: Same Name")
    (sp-litnotes-titles-test--note dir "20240107T120000--f.org" "8" "f" "- pub-title :: Same, Name!")
    (sp-litnotes-titles-test--note dir "20240109T120000--g.org" "9" "g" "- pub-title :: Taken")
    (sp-litnotes-titles-test--write (expand-file-name "20240109T120000--taken.org" dir) "x")
    (should (equal
             (sp-litnotes-titles-test--status (sp-litnotes-titles--plans))
             '(("20240101T120000--a__litnote.org" change rename)
               ("20240102T120000--b__litnote.org" no-pub-title nil)
               ("20240103T120000--c__litnote.org" empty-title nil)
               ("20240104T120000--gamma.org" same same-name)
               ("20240105T120000--d.org" no-id nil)
               ("20240107T120000--e.org" change slug-clash)
               ("20240107T120000--f.org" change slug-clash)
               ("20240109T120000--g.org" change exists)
               ("20240109T120000--taken.org" no-id nil)
               ("odd.org" change odd-name))))))

(ert-deftest sp-litnotes-titles-report-writes-nothing ()
  (sp-litnotes-titles-test--with-vault
    (let ((file (expand-file-name "20240101T120000--a.org" dir))
          (other (expand-file-name "ref.org" root)))
      (sp-litnotes-titles-test--note dir "20240101T120000--a.org" "1" "a"
                                     "- pub-title :: Alpha")
      (sp-litnotes-titles-test--write other "see [[file:litnotes/20240101T120000--a.org][a]]")
      (let ((before (sp-litnotes-titles-test--read file)))
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (sp-litnotes-titles-report))
        (should (equal before (sp-litnotes-titles-test--read file)))
        (should (file-exists-p file))
        (should-not (file-exists-p sp-litnotes-titles-backup-directory))
        (with-current-buffer "*litnote titles*"
          (should (string-match-p "20240101T120000--a.org -> =20240101T120000--alpha.org="
                                  (buffer-string)))
          (should (string-match-p "title: a -> Alpha" (buffer-string)))
          (should (string-match-p "links to the old name in: =ref.org=" (buffer-string))))))))

(ert-deftest sp-litnotes-titles-apply-writes-and-is-idempotent ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--note dir "20240101T120000--a__litnote.org" "1" "a"
                                   "- pub-title :: \"Alpha [[id:9][Study]]\"" "body")
    (sp-litnotes-titles-test--write (expand-file-name "20240102T120000--n.org" dir)
                                    ":PROPERTIES:" ":ID: 2" ":END:" "- pub-title :: No Title")
    (let ((old (expand-file-name "20240101T120000--a__litnote.org" dir))
          (new (expand-file-name "20240101T120000--alpha-study__litnote.org" dir)))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'pop-to-buffer) #'ignore))
        (sp-litnotes-titles-apply)
        (should-not (file-exists-p old))
        (let ((text (sp-litnotes-titles-test--read new)))
          (should (string-match-p "^#\\+title: Alpha Study$" text))
          (should (string-match-p "^:ID:       1$" text))
          (should (string-match-p "^:ROAM_REFS: @kant2009$" text))
          (should (string-match-p "^body$" text)))
        ;; a note without #+title gets one after the drawer
        (let ((text (sp-litnotes-titles-test--read
                     (expand-file-name "20240102T120000--no-title.org" dir))))
          (should (string-match-p ":END:\n#\\+title: No Title\n- pub-title" text)))
        ;; the old text is in a time-stamped backup
        (let* ((stamp (car (directory-files sp-litnotes-titles-backup-directory t "\\`[^.]")))
               (backup (expand-file-name "20240101T120000--a__litnote.org" stamp)))
          (should (string-match-p "#\\+title: a$" (sp-litnotes-titles-test--read backup))))
        (should (equal (sp-litnotes-titles-test--status (sp-litnotes-titles--plans))
                       '(("20240101T120000--alpha-study__litnote.org" same same-name)
                         ("20240102T120000--no-title.org" same same-name))))))))

(ert-deftest sp-litnotes-titles-apply-skips-unsaved-buffer ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--note dir "20240101T120000--a.org" "1" "a" "- pub-title :: Alpha")
    (let* ((file (expand-file-name "20240101T120000--a.org" dir))
           (buffer (find-file-noselect file)))
      (unwind-protect
          (progn
            (with-current-buffer buffer (insert "unsaved"))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                      ((symbol-function 'pop-to-buffer) #'ignore))
              (let ((results (sp-litnotes-titles-apply)))
                (should (eq (plist-get (car results) :status) 'skipped))
                (should (file-exists-p file))
                (should (string-match-p "#\\+title: a$" (sp-litnotes-titles-test--read file))))))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(provide 'sp-litnotes-titles-test)
;; sp-litnotes-titles-test.el ends here
