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

(defun sp-litnotes-titles-test--note (dir name id &rest more)
  "Write the note NAME in DIR with ID, ROAM_REFS from the name, and the MORE lines."
  (apply #'sp-litnotes-titles-test--write (expand-file-name name dir)
         ":PROPERTIES:" (format ":ID:       %s" id)
         (format ":ROAM_REFS: @%s" (file-name-sans-extension (file-name-nondirectory name)))
         ":END:" "#+title: old" more))

(defun sp-litnotes-titles-test--status (plans)
  (mapcar (lambda (p) (list (file-name-nondirectory (plist-get p :file))
                            (plist-get p :title-status) (plist-get p :name-status)))
          plans))

(ert-deftest sp-litnotes-titles-authors ()
  (should (equal (sp-litnotes-titles--authors "Reuten, Geert") '(("Reuten" . "Geert"))))
  (should (equal (sp-litnotes-titles--authors "Geert Reuten") '(("Reuten" . "Geert"))))
  (should (equal (sp-litnotes-titles--authors "Ludwig van Beethoven") '(("van Beethoven" . "Ludwig"))))
  (should (equal (sp-litnotes-titles--authors "[[id:1][Geert Reuten]], [[id:2][Peter Thomas]]")
                 '(("Reuten" . "Geert") ("Thomas" . "Peter"))))
  (should (equal (sp-litnotes-titles--authors "\"Ann Lee\", \"Bo Roe\"")
                 '(("Lee" . "Ann") ("Roe" . "Bo"))))
  (should (equal (sp-litnotes-titles--authors "Lee, Ann; Roe, Bo and Cy Poe")
                 '(("Lee" . "Ann") ("Roe" . "Bo") ("Poe" . "Cy"))))
  (should (eq (sp-litnotes-titles--authors "Ann Lee, Bo Roe, Cy Poe") 'ambiguous)))

(ert-deftest sp-litnotes-titles-format ()
  (should (equal (sp-litnotes-titles-format '(("Reuten" . "Geert")) "2014"
                                            "The value form as a social form")
                 "Reuten, Geert (2014) The value form as a social form"))
  (should (equal (sp-litnotes-titles-format '(("Lee" . "Ann") ("Roe" . "Bo")) nil "T")
                 "Lee, Ann, and Bo Roe (n.d.) T"))
  (should (equal (sp-litnotes-titles-format '(("A" . "a") ("B" . "b") ("C" . "c")) "1" "T")
                 "A, a, b B, and c C (1) T"))
  (let ((sp-litnotes-titles-et-al-threshold 2))
    (should (equal (sp-litnotes-titles-format
                    (mapcar (lambda (n) (cons n "x")) '("A" "B" "C" "D" "E" "F" "G" "H")) "1" "T")
                   "A, x, x B, x C, x D, x E, x F, x G, et al. (1) T"))))

(ert-deftest sp-litnotes-titles-keys ()
  (should (equal (sp-litnotes-titles--keys "@a1 b2 cite:c3 [cite:@d4;@e5] https://x/y") '("a1" "b2" "c3" "d4" "e5")))
  (should (null (sp-litnotes-titles--keys nil))))

(ert-deftest sp-litnotes-titles-plan-statuses ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--note dir "reuten2014value.org" "1"
                                   "- pub-author :: Reuten, Geert" "- pub-year :: 2014"
                                   "- pub-title :: The value form as a social form")
    (sp-litnotes-titles-test--write (expand-file-name "20240102T120000--b__litnote.org" dir)
      ":PROPERTIES:" ":ID: 2" ":END:" "#+reference: kant2009" "#+title: kant2009"
      "- pub-author :: Kant, Immanuel" "- pub-title :: Critique")
    (sp-litnotes-titles-test--note dir "nopub.org" "3" "- pub-author :: Lee, Ann")
    (sp-litnotes-titles-test--note dir "noauthor.org" "4" "- pub-title :: Alone")
    (sp-litnotes-titles-test--note dir "amb.org" "5" "- pub-author :: A B, C D, E F"
                                   "- pub-title :: Amb")
    (sp-litnotes-titles-test--write (expand-file-name "noid.org" dir)
      "#+title: x" "- pub-author :: Lee, Ann" "- pub-title :: T")
    (sp-litnotes-titles-test--write (expand-file-name "nokey.org" dir)
      ":PROPERTIES:" ":ID: 7" ":END:" "- pub-author :: Lee, Ann" "- pub-title :: T")
    ;; already right
    (sp-litnotes-titles-test--write (expand-file-name "same.org" dir)
      ":PROPERTIES:" ":ID: 8" ":ROAM_REFS: @same" ":END:" "#+title: Lee, Ann (n.d.) T"
      "- pub-author :: Lee, Ann" "- pub-title :: T")
    ;; two notes with one key, and a key whose file exists
    (sp-litnotes-titles-test--write (expand-file-name "x1.org" dir)
      ":PROPERTIES:" ":ID: 9" ":ROAM_REFS: @dup" ":END:" "- pub-author :: Lee, Ann" "- pub-title :: T")
    (sp-litnotes-titles-test--write (expand-file-name "x2.org" dir)
      ":PROPERTIES:" ":ID: 10" ":ROAM_REFS: @dup" ":END:" "- pub-author :: Lee, Ann" "- pub-title :: T")
    (sp-litnotes-titles-test--write (expand-file-name "x3.org" dir)
      ":PROPERTIES:" ":ID: 11" ":ROAM_REFS: @amb" ":END:" "- pub-author :: Lee, Ann" "- pub-title :: T")
    (should (equal
             (sp-litnotes-titles-test--status (sp-litnotes-titles--plans))
             '(("20240102T120000--b__litnote.org" change rename)
               ("amb.org" ambiguous-author same-name)
               ("noauthor.org" no-author same-name)
               ("noid.org" no-id nil)
               ("nokey.org" change no-citekey)
               ("nopub.org" no-pub-title same-name)
               ("reuten2014value.org" change same-name)
               ("same.org" same same-name)
               ("x1.org" change key-clash)
               ("x2.org" change key-clash)
               ("x3.org" change exists))))))

(ert-deftest sp-litnotes-titles-report-writes-nothing ()
  (sp-litnotes-titles-test--with-vault
    (let ((file (expand-file-name "20240101T120000--a.org" dir))
          (other (expand-file-name "ref.org" root)))
      (sp-litnotes-titles-test--write file
        ":PROPERTIES:" ":ID: 1" ":ROAM_REFS: @reuten2014value" ":END:" "#+title: a"
        "- pub-author :: Reuten, Geert" "- pub-year :: 2014" "- pub-title :: Value")
      (sp-litnotes-titles-test--write other "see [[file:litnotes/20240101T120000--a.org][a]]")
      (let ((before (sp-litnotes-titles-test--read file)))
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (sp-litnotes-titles-report))
        (should (equal before (sp-litnotes-titles-test--read file)))
        (should-not (file-exists-p sp-litnotes-titles-backup-directory))
        (with-current-buffer "*litnote titles*"
          (should (string-match-p "file: 20240101T120000--a.org -> =reuten2014value.org="
                                  (buffer-string)))
          (should (string-match-p "title: a -> Reuten, Geert (2014) Value" (buffer-string)))
          (should (string-match-p "links to the old name in: =ref.org=" (buffer-string))))))))

(ert-deftest sp-litnotes-titles-apply-writes-and-is-idempotent ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--write (expand-file-name "20240101T120000--a__litnote.org" dir)
      ":PROPERTIES:" ":ID:       1" ":END:" "#+reference:  kant2009" "#+title: kant2009"
      "- pub-author :: [[id:9][Immanuel Kant]]" "- pub-year :: 1781"
      "- pub-title :: \"Critique of pure reason\"" "body")
    (sp-litnotes-titles-test--write (expand-file-name "notitle.org" dir)
      ":PROPERTIES:" ":ID: 2" ":ROAM_REFS: @notitle" ":END:"
      "- pub-author :: Lee, Ann" "- pub-title :: No Title")
    (let ((old (expand-file-name "20240101T120000--a__litnote.org" dir))
          (new (expand-file-name "kant2009.org" dir)))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'pop-to-buffer) #'ignore))
        (sp-litnotes-titles-apply)
        (should-not (file-exists-p old))
        (let ((text (sp-litnotes-titles-test--read new)))
          (should (string-match-p "^#\\+title: Kant, Immanuel (1781) Critique of pure reason$" text))
          (should (string-match-p "^:ID:       1$" text))
          (should (string-match-p "^#\\+reference:  kant2009$" text))
          (should (string-match-p "^body$" text)))
        (let ((text (sp-litnotes-titles-test--read (expand-file-name "notitle.org" dir))))
          (should (string-match-p ":END:\n#\\+title: Lee, Ann (n.d.) No Title\n- pub-author" text)))
        (let* ((stamp (car (directory-files sp-litnotes-titles-backup-directory t "\\`[^.]")))
               (backup (expand-file-name "20240101T120000--a__litnote.org" stamp)))
          (should (string-match-p "#\\+title: kant2009$" (sp-litnotes-titles-test--read backup))))
        (should (equal (sp-litnotes-titles-test--status (sp-litnotes-titles--plans))
                       '(("kant2009.org" same same-name)
                         ("notitle.org" same same-name))))))))

(ert-deftest sp-litnotes-titles-apply-skips-unsaved-buffer ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--note dir "alpha.org" "1" "- pub-author :: Lee, Ann" "- pub-title :: Alpha")
    (let* ((file (expand-file-name "alpha.org" dir))
           (buffer (find-file-noselect file)))
      (unwind-protect
          (progn
            (with-current-buffer buffer (insert "unsaved"))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                      ((symbol-function 'pop-to-buffer) #'ignore))
              (let ((results (sp-litnotes-titles-apply)))
                (should (eq (plist-get (car results) :status) 'skipped))
                (should (string-match-p "#\\+title: old$" (sp-litnotes-titles-test--read file))))))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(provide 'sp-litnotes-titles-test)
;; sp-litnotes-titles-test.el ends here
