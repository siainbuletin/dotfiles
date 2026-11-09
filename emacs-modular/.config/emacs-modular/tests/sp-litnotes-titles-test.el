;;; sp-litnotes-titles-test.el --- Tests for sp-litnotes-titles -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-async-work)
(setq sp-async-work-synchronous t)
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
                 "Reuten (2014) The value form as a social form"))
  (should (equal (sp-litnotes-titles-format '(("Lee" . "Ann") ("Roe" . "Bo")) "2000" "T")
                 "Lee and Roe (2000) T"))
  (should (equal (sp-litnotes-titles-format '(("A" . "a") ("B" . "b") ("C" . "c")) "1" "T")
                 "A, B and C (1) T"))
  (should (equal (sp-litnotes-titles-format
                  '(("A" . "a") ("B" . "b") ("C" . "c") ("D" . "d")) "1" "T")
                 "A, B et al. (1) T"))
  (should (equal (sp-litnotes-titles-format
                  '(("A" . "a") ("B" . "b") ("C" . "c") ("D" . "d") ("E" . "e")) "1" "T")
                 "A, B et al. (1) T")))

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
      "- pub-author :: Kant, Immanuel" "- pub-year :: 1781" "- pub-title :: Critique")
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
      ":PROPERTIES:" ":ID: 8" ":ROAM_REFS: @same" ":END:" "#+title: Lee (2000) T"
      "- pub-author :: Lee, Ann" "- pub-year :: 2000" "- pub-title :: T")
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
               ("nokey.org" no-year no-citekey)
               ("nopub.org" no-pub-title same-name)
               ("reuten2014value.org" change same-name)
               ("same.org" same same-name)
               ("x1.org" no-year key-clash)
               ("x2.org" no-year key-clash)
               ("x3.org" no-year exists))))))

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
          (sp-litnotes-titles-dryrun))
        (should (equal before (sp-litnotes-titles-test--read file)))
        (should-not (file-exists-p sp-litnotes-titles-backup-directory))
        (with-current-buffer "*litnote titles*"
          (should (string-match-p "file: 20240101T120000--a.org -> =reuten2014value.org="
                                  (buffer-string)))
          (should (string-match-p "title: a -> Reuten (2014) Value" (buffer-string)))
          (should (string-match-p "links to the old name in: \\[\\[file:[^]]*ref\\.org\\]\\[ref\\.org\\]\\]" (buffer-string))))))))

(ert-deftest sp-litnotes-titles-apply-writes-and-is-idempotent ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--write (expand-file-name "20240101T120000--a__litnote.org" dir)
      ":PROPERTIES:" ":ID:       1" ":END:" "#+reference:  kant2009" "#+title: kant2009"
      "- pub-author :: [[id:9][Immanuel Kant]]" "- pub-year :: 1781"
      "- pub-title :: \"Critique of pure reason\"" "body")
    (sp-litnotes-titles-test--write (expand-file-name "notitle.org" dir)
      ":PROPERTIES:" ":ID: 2" ":ROAM_REFS: @notitle" ":END:"
      "- pub-author :: Lee, Ann" "- pub-year :: 2000" "- pub-title :: No Title")
    (let ((old (expand-file-name "20240101T120000--a__litnote.org" dir))
          (new (expand-file-name "kant2009.org" dir)))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'pop-to-buffer) #'ignore))
        (sp-litnotes-titles-convert)
        (should-not (file-exists-p old))
        (let ((text (sp-litnotes-titles-test--read new)))
          (should (string-match-p "^#\\+title: Kant (1781) Critique of pure reason$" text))
          (should (string-match-p "^:ID:       1$" text))
          (should (string-match-p "^#\\+reference:  kant2009$" text))
          (should (string-match-p "^body$" text)))
        (let ((text (sp-litnotes-titles-test--read (expand-file-name "notitle.org" dir))))
          (should (string-match-p ":END:\n#\\+title: Lee (2000) No Title\n- pub-author" text)))
        (let* ((stamp (car (directory-files sp-litnotes-titles-backup-directory t "\\`[^.]")))
               (backup (expand-file-name "20240101T120000--a__litnote.org" stamp)))
          (should (string-match-p "#\\+title: kant2009$" (sp-litnotes-titles-test--read backup))))
        (should (equal (sp-litnotes-titles-test--status (sp-litnotes-titles--plans))
                       '(("kant2009.org" same same-name)
                         ("notitle.org" same same-name))))))))

(ert-deftest sp-litnotes-titles-apply-skips-unsaved-buffer ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--note dir "alpha.org" "1" "- pub-author :: Lee, Ann" "- pub-year :: 2000" "- pub-title :: Alpha")
    (let* ((file (expand-file-name "alpha.org" dir))
           (buffer (find-file-noselect file)))
      (unwind-protect
          (progn
            (with-current-buffer buffer (insert "unsaved"))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                      ((symbol-function 'pop-to-buffer) #'ignore))
              (let ((results (sp-litnotes-titles-convert)))
                (should (eq (plist-get (car results) :status) 'skipped))
                (should (string-match-p "#\\+title: old$" (sp-litnotes-titles-test--read file))))))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(ert-deftest sp-litnotes-titles-apply-asks-for-missing-values ()
  (sp-litnotes-titles-test--with-vault
    (sp-litnotes-titles-test--note dir "noyear.org" "1" "- pub-author :: Lee, Ann" "- pub-title :: T")
    (sp-litnotes-titles-test--note dir "amb.org" "2" "- pub-author :: A B, C D, E F"
                                   "- pub-year :: 1999" "- pub-title :: U")
    (sp-litnotes-titles-test--note dir "skip.org" "3" "- pub-title :: V")
    (let ((asked nil))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'pop-to-buffer) #'ignore)
                ((symbol-function 'read-string)
                 (lambda (prompt &rest _)
                   (push prompt asked)
                   (cond ((string-match-p "\\`noyear" prompt) "2001")
                         ((string-match-p "\\`amb" prompt) "Ann Bo; Cy Di")
                         (t "")))))
        (sp-litnotes-titles-convert)
        (should (string-match-p "^#\\+title: Lee (2001) T$"
                                (sp-litnotes-titles-test--read (expand-file-name "noyear.org" dir))))
        (should (string-match-p "^#\\+title: Bo and Di (1999) U$"
                                (sp-litnotes-titles-test--read (expand-file-name "amb.org" dir))))
        ;; skip.org: author skipped by an empty answer, nothing written
        (should (string-match-p "^#\\+title: old$"
                                (sp-litnotes-titles-test--read (expand-file-name "skip.org" dir))))
        (should (= 3 (length asked)))
        ;; the report lists the failure
        (sp-litnotes-titles-dryrun)
        (with-current-buffer "*litnote titles*"
          (should (string-match-p "Failed: No pub-author" (buffer-string))))))))

(defvar sp-bibtex-files)

(defconst sp-litnotes-titles-test--bib
  "@book{reuten2014value,
  author = {Reuten, Geert},
  title = {The {Value} Form},
  year = {2014},
}
@incollection{moller2020chapter,
  author = {M{\\\"o}ller, Jan and van der Berg, Ann and {World Bank} and others},
  title = {A Chapter},
  crossref = {reuten2014value},
}
")

(defmacro sp-litnotes-titles-test--with-bib (&rest body)
  "Run BODY with a registered .bib file and a clean BibTeX state."
  (declare (indent 0))
  `(let* ((bibdir (make-temp-file "sp-titles-bib" t))
          (bib (expand-file-name "a.bib" bibdir))
          (sp-bibtex-files (list bib))
          (sp-litnotes-titles-bibtex nil))
     (with-temp-file bib (insert sp-litnotes-titles-test--bib))
     (unwind-protect (progn ,@body)
       (setq sp-litnotes-titles--bibtex-mode nil sp-litnotes-meta--index nil)
       (delete-directory bibdir t))))

(ert-deftest sp-litnotes-titles-bibtex-missing-fills-only-gaps ()
  (sp-litnotes-titles-test--with-bib
    (sp-litnotes-titles-test--with-vault
      (sp-litnotes-titles-test--note dir "reuten2014value.org" "1")
      (sp-litnotes-titles-test--note dir "moller2020chapter.org" "2"
                                     "- pub-author :: Lee, Ann" "- pub-year :: 1999")
      (sp-litnotes-titles-test--note dir "nobib.org" "3")
      ;; without BibTeX nothing can be done
      (sp-litnotes-titles-dryrun)
      (should (equal (mapcar (lambda (p) (plist-get p :title-status))
                             (sp-litnotes-titles--plans))
                     '(no-pub-title no-pub-title no-pub-title)))
      (sp-litnotes-titles-dryrun 'missing)
      (let ((plans (sp-litnotes-titles--plans)))
        (should (equal (mapcar (lambda (p) (plist-get p :new-title)) plans)
                       '("Lee (1999) A Chapter" nil "Reuten (2014) The Value Form")))
        (should (equal (plist-get (nth 2 plans) :inferred) '(:author :year :pub)))
        (should (equal (plist-get (nth 1 plans) :bib) 'no-entry)))
      (with-current-buffer "*litnote titles*"
        (should (string-match-p "from BibTeX: authors, year, title" (buffer-string)))
        (should (string-match-p "No BibTeX entry for the citekey (1)" (buffer-string)))
        (should (string-match-p "Reuten (2014) The Value Form" (buffer-string)))))))

(ert-deftest sp-litnotes-titles-bibtex-always-wins-and-reads-names ()
  (sp-litnotes-titles-test--with-bib
    (sp-litnotes-titles-test--with-vault
      (sp-litnotes-titles-test--note dir "moller2020chapter.org" "2"
                                     "- pub-author :: Lee, Ann" "- pub-year :: 1999"
                                     "- pub-title :: Mine")
      (sp-litnotes-titles-dryrun 'always)
      (let ((plan (car (sp-litnotes-titles--plans))))
        ;; accents in Unicode, particles kept, a braced name is one name,
        ;; `and others' dropped, year from the crossref
        (should (equal (plist-get plan :new-title)
                       "Möller, van der Berg and World Bank (2014) A Chapter"))))))

(ert-deftest sp-litnotes-titles-bibtex-typed-values-win ()
  (sp-litnotes-titles-test--with-bib
    (sp-litnotes-titles-test--with-vault
      (sp-litnotes-titles-test--note dir "reuten2014value.org" "1")
      (sp-litnotes-titles-dryrun 'missing)
      (let ((file (expand-file-name "reuten2014value.org" dir)))
        (puthash file '(:author "Doe, Jo") sp-litnotes-titles--overrides)
        (should (equal (plist-get (car (sp-litnotes-titles--plans)) :new-title)
                       "Doe (2014) The Value Form"))))))

(ert-deftest sp-litnotes-titles-bibtex-prefix-argument ()
  (let ((sp-litnotes-titles-bibtex 'missing))
    (should (eq (sp-litnotes-titles--bibtex-from-prefix nil) 'missing))
    (should (eq (sp-litnotes-titles--bibtex-from-prefix '(4)) 'missing))
    (should (eq (sp-litnotes-titles--bibtex-from-prefix '(16)) 'always))))

(ert-deftest sp-litnotes-titles-bibtex-convert-writes-inferred-title ()
  (sp-litnotes-titles-test--with-bib
    (sp-litnotes-titles-test--with-vault
      (sp-litnotes-titles-test--note dir "reuten2014value.org" "1")
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
                ((symbol-function 'pop-to-buffer) #'ignore))
        (sp-litnotes-titles-convert 'missing))
      (should (string-match-p "^#\\+title: Reuten (2014) The Value Form$"
                              (sp-litnotes-titles-test--read
                               (expand-file-name "reuten2014value.org" dir)))))))

(ert-deftest sp-litnotes-titles-report-drop-and-apply ()
  "A note dropped from the report is excluded from what A applies."
  (sp-litnotes-titles-test--with-vault
    (let ((file (expand-file-name "20240101T120000--a.org" dir)) seen)
      (sp-litnotes-titles-test--write file
        ":PROPERTIES:" ":ID: 1" ":ROAM_REFS: @reuten2014value" ":END:" "#+title: a"
        "- pub-author :: Reuten, Geert" "- pub-year :: 2014" "- pub-title :: Value")
      (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
        (sp-litnotes-titles-dryrun)
        (with-current-buffer "*litnote titles*"
          (goto-char (point-min))
          (re-search-forward "^\\*\\* \\[\\[file:")
          (sp-batch-report-drop)
          (should (equal sp-batch-report-excluded (list file)))
          (should (string-match-p "Dropped from the list" (buffer-string)))
          (cl-letf (((symbol-function 'sp-litnotes-titles-convert)
                     (lambda (&optional _b excl) (setq seen excl))))
            (sp-batch-report-apply))
          (should (equal seen (list file))))))))

(provide 'sp-litnotes-titles-test)
;; sp-litnotes-titles-test.el ends here

(ert-deftest sp-litnotes-titles-split-name-surname ()
  "The surname is found in every common BibTeX name form."
  (dolist (case '(("Arthur, Christopher J." "Arthur")
                  ("Christopher J. Arthur" "Arthur")
                  ("J. Arthur" "Arthur")
                  ("von Neumann, John" "von Neumann")
                  ("John von Neumann" "von Neumann")
                  ("Ludwig van der Berg" "van der Berg")
                  ("King, Jr., Martin L." "King")
                  ("{Smith, Jones}, Ann" "Smith, Jones")
                  ("{World Bank}" "World Bank")
                  ("Madonna" "Madonna")))
    (should (equal (car (sp-litnotes-titles--split-name (car case))) (cadr case)))))

(ert-deftest sp-litnotes-titles-split-name-ignores-case-fold ()
  "Initials are never particles, whatever `case-fold-search' is."
  (dolist (fold '(t nil))
    (let ((case-fold-search fold))
      (should (equal (sp-litnotes-titles--split-name "Christopher J. Arthur")
                     '("Arthur" . "Christopher J."))))))

(ert-deftest sp-litnotes-titles-bib-authors-surname ()
  (should (equal (sp-litnotes-titles--bib-authors
                  '(("author" . "Arthur, Christopher J. and Smith, Ann")))
                 '(("Arthur" . "Christopher J.") ("Smith" . "Ann")))))

(ert-deftest sp-litnotes-titles-format-first-name-comma ()
  (should (equal (sp-litnotes-titles-format
                  (list (sp-litnotes-titles--split-name "Arthur, Christopher J.")) "2022" "Capital as")
                 "Arthur (2022) Capital as")))

(ert-deftest sp-litnotes-titles-report-is-a-report-buffer-with-file-links ()
  "The dry run opens a report buffer where each note is a link to its file."
  (sp-litnotes-titles-test--with-vault
    (let ((file (expand-file-name "20240101T120000--a.org" dir)))
      (sp-litnotes-titles-test--write file
        ":PROPERTIES:" ":ID: 1" ":ROAM_REFS: @reuten2014value" ":END:" "#+title: a"
        "- pub-author :: Reuten, Geert" "- pub-year :: 2014" "- pub-title :: Value")
      (sp-litnotes-titles-test--write (expand-file-name "nokey.org" dir)
        ":PROPERTIES:" ":ID: 2" ":END:" "#+title: b" "- pub-author :: Lee, Ann" "- pub-title :: T")
      (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
        (sp-litnotes-titles-dryrun))
      (with-current-buffer "*litnote titles*"
        (should (derived-mode-p 'sp-batch-report-mode))
        (should buffer-read-only)
        (should (functionp sp-batch-report-refresh-function))
        (should (string-match-p
                 (format "^\\*\\* \\[\\[file:%s\\]\\[20240101T120000--a\\.org\\]\\]$"
                         (regexp-quote file))
                 (buffer-string)))
        ;; a failed note is listed with a link too
        (should (string-match-p "Failed:.*\n- \\[\\[file:[^]]*nokey\\.org\\]\\[nokey\\.org\\]\\]: "
                                (buffer-string)))))))
