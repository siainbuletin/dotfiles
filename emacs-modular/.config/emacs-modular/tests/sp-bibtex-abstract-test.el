;;; sp-bibtex-abstract-test.el --- Tests for sp-bibtex-abstract -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'bibtex)
(require 'sp-async-work)
(require 'sp-batch-report)
(require 'sp-author-notes-bibtex)

;; sp-bibprocess needs the whole configuration; load only the lint part.
(defvar sp-bibtex-abstract-test--lint-file
  (expand-file-name "../libraries/modules/academic/sp-bibprocess.el"
                    (file-name-directory (or load-file-name buffer-file-name))))
(unless (fboundp 'sp-bibtex--unwrap)
  (with-temp-buffer
    (insert-file-contents sp-bibtex-abstract-test--lint-file)
    (goto-char (point-min))
    (let ((start (search-forward ";;;; Linting the .bib files"))
          (end (progn (search-forward "(provide 'sp-bibprocess)") (match-beginning 0))))
      (eval (read (concat "(progn " (buffer-substring start end) ")")) t))))

(require 'sp-bibtex-abstract)

;;;; Helpers

(defun sp-bibtex-abstract-test--read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defconst sp-bibtex-abstract-test--bib
  "@book{one2020,
  author = {One, A.},
  title = {First},
  abstract = {A {Marx}ist study of S{\\o}ren and \\emph{value} \\& more.

  Second paragraph, $x_1$ stays.},
  year = {2020},
}

@article{two2021,
  title = {Second},
  abstract = {Already there.},
  year = {2021}
}

@article{three2022,
  title = {Third},
  abstract = {Mine, from BibTeX.},
}

@article{four2023,
  title = {No note},
  abstract = {Lost without a note.},
}

@misc{five2024,
  title = {Macro},
  abstract = \"start\" # amacro,
}

@misc{six2025,
  title = {Nothing here},
}
"
  "A .bib file for the tests.")

(defconst sp-bibtex-abstract-test--head
  ":PROPERTIES:\n:ID: id-%s\n:ROAM_REFS: @%s\n:END:\n#+title: T\n#+filetags: :litnote:\n\n- pub-year :: 2020\n")

(defmacro sp-bibtex-abstract-test--with-setup (&rest body)
  "Run BODY with a .bib file, litnotes, and backup folders; `bib', `dir' and `note' are bound."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sp-abs" t))
          (bib (expand-file-name "a.bib" dir))
          (notes (expand-file-name "notes/" dir))
          (sp-bibtex-files (list bib))
          (sp-author-notes-litnotes-directory notes)
          (sp-bibtex-abstract-backup-directory (expand-file-name "backups/" dir))
          (sp-bibtex-lint-backup-directory (expand-file-name "lintbackups/" dir))
          (sp-bibtex-abstract--excluded nil)
          (sp-batch-report-batch-size 50)
          (note (lambda (key) (expand-file-name (concat key ".org") notes))))
     (make-directory notes t)
     (with-temp-file bib (insert sp-bibtex-abstract-test--bib))
     (with-temp-file (funcall note "one2020")
       (insert (format sp-bibtex-abstract-test--head "one" "one2020") "\n* Notes\nSome notes.\n"))
     (with-temp-file (funcall note "two2021")
       (insert (format sp-bibtex-abstract-test--head "two" "two2021")
               "\n* Abstract\n\nAlready   there.\n\n* Notes\n"))
     (with-temp-file (funcall note "three2022")
       (insert (format sp-bibtex-abstract-test--head "three" "three2022")
               "\n* Abstract\n\nSomething else that I wrote.\n"))
     (with-temp-file (funcall note "five2024")
       (insert (format sp-bibtex-abstract-test--head "five" "five2024")))
     (unwind-protect
         (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                   ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
           ,@body)
       (dolist (name '("*BibTeX abstracts*"))
         (when (get-buffer name) (kill-buffer name)))
       (delete-directory dir t))))

;;;; The field

(ert-deftest sp-bibtex-abstract-fields ()
  (let* ((text "@book{k,\n  title = {A {nested} title},\n  abstract = \"q {x}\" # mac # {z},\n  year = 2020,\n}")
         (fields (sp-bibtex-abstract--fields text)))
    (should (equal (mapcar #'car fields) '("title" "abstract" "year")))
    (should (equal (sp-bibtex-abstract--value text (nth 1 fields)) "\"q {x}\" # mac # {z}"))
    (should (equal (sp-bibtex-abstract--value text (nth 2 fields)) "2020"))))

(ert-deftest sp-bibtex-abstract-remove ()
  (should (equal (sp-bibtex-abstract--remove "@a{k,\n  title = {T},\n  abstract = {A\n  two {lines}},\n  year = {1}\n}")
                 "@a{k,\n  title = {T},\n  year = {1}\n}"))
  ;; the last field, with and without a comma
  (should (equal (sp-bibtex-abstract--remove "@a{k,\n  title = {T},\n  abstract = {A},\n}")
                 "@a{k,\n  title = {T},\n}"))
  (should (equal (sp-bibtex-abstract--remove "@a{k,\n  title = {T},\n  abstract = {A}\n}")
                 "@a{k,\n  title = {T},\n}"))
  ;; several fields on a line
  (should (equal (sp-bibtex-abstract--remove "@a{k, title = {T}, ABSTRACT = \"x\", year = 1}")
                 "@a{k, title = {T}, year = 1}"))
  ;; the only field
  (should (equal (sp-bibtex-abstract--remove "@a{k,\n  abstract = {A},\n}") "@a{k,\n}"))
  (should-error (sp-bibtex-abstract--remove "@a{k,\n  title = {T},\n}")))

(ert-deftest sp-bibtex-abstract-remove-keeps-other-fields-with-braces ()
  (let ((text "@a{k,\n  abstract = {A {b} c},\n  title = {T {x} \\\"{o}},\n  note = \"q\",\n}"))
    (should (equal (sp-bibtex-abstract--other-fields (sp-bibtex-abstract--remove text))
                   (sp-bibtex-abstract--other-fields text)))))

;;;; The conversion

(ert-deftest sp-bibtex-abstract-convert ()
  (let ((done (sp-bibtex-abstract--convert
               "{A {Marx}ist study of S{\\o}ren and \\emph{value} \\textbf{now} \\& 5\\%---fine, \\\"o and \\url{x.org}.\n\n  Second\n  paragraph, $x_{1}$ and $$y$$ stay, ``q''~end.}")))
    (should (equal (car done)
                   (concat "A Marxist study of Søren and /value/ *now* & 5%—fine, ö and x.org.\n\n"
                           "Second paragraph, $x_{1}$ and $$y$$ stay, “q” end.")))
    (should (null (cdr done)))))

(ert-deftest sp-bibtex-abstract-convert-quoted-and-unknown ()
  (let ((done (sp-bibtex-abstract--convert "\"Some \\foo{bar} and \\baz text\"")))
    (should (equal (car done) "Some \\foo{bar} and \\baz text"))
    (should (equal (cdr done) '("\\foo" "\\baz")))))

(ert-deftest sp-bibtex-abstract-convert-guards-org-syntax ()
  (should (equal (car (sp-bibtex-abstract--convert "{* not a heading\n\n#+begin_src x}"))
                 ",* not a heading\n\n,#+begin_src x")))

(ert-deftest sp-bibtex-abstract-convert-macro-is-nil ()
  (should-not (sp-bibtex-abstract--convert "\"start\" # amacro"))
  (should-not (sp-bibtex-abstract--convert "mymacro")))

;;;; The note

(ert-deftest sp-bibtex-abstract-put ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID: x\n:END:\n#+title: T\n\n- pub-year :: 2020\n\n* Notes\nText\n")
    (should (eq 'added (sp-bibtex-abstract--put "The text.")))
    (should (equal (buffer-string)
                   ":PROPERTIES:\n:ID: x\n:END:\n#+title: T\n\n- pub-year :: 2020\n\n* Abstract\n\nThe text.\n\n* Notes\nText\n"))
    (should (eq 'same (sp-bibtex-abstract--put "The   text.")))
    (should-error (sp-bibtex-abstract--put "Other."))))

(ert-deftest sp-bibtex-abstract-put-without-headings-and-empty-heading ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID: x\n:END:\n#+title: T\n\n- pub-year :: 2020")
    (should (eq 'added (sp-bibtex-abstract--put "A.")))
    (should (equal (buffer-string)
                   ":PROPERTIES:\n:ID: x\n:END:\n#+title: T\n\n- pub-year :: 2020\n\n* Abstract\n\nA.\n")))
  (with-temp-buffer
    (insert "#+title: T\n\n* abstract :tag:\n:PROPERTIES:\n:X: y\n:END:\n\n* Notes\n")
    (should (eq 'filled (sp-bibtex-abstract--put "B.")))
    (should (equal (buffer-string)
                   "#+title: T\n\n* abstract :tag:\n:PROPERTIES:\n:X: y\n:END:\n\nB.\n\n* Notes\n")))
  (with-temp-buffer
    (insert "#+title: T\n")
    (should (eq 'added (sp-bibtex-abstract--put "C.")))
    (should (equal (buffer-string) "#+title: T\n\n* Abstract\n\nC.\n"))))

;;;; The plan and the report

(ert-deftest sp-bibtex-abstract-plans ()
  (sp-bibtex-abstract-test--with-setup
    (let* ((plans (sp-bibtex-abstract--plans bib))
           (state (lambda (key) (plist-get (seq-find (lambda (p) (equal (plist-get p :key) key)) plans) :state))))
      (should (equal (mapcar (lambda (p) (plist-get p :key)) plans)
                     '("one2020" "two2021" "three2022" "four2023" "five2024")))
      (should (eq (funcall state "one2020") 'create))
      (should (eq (funcall state "two2021") 'same))
      (should (eq (funcall state "three2022") 'conflict))
      (should (eq (funcall state "four2023") 'no-note))
      (should (eq (funcall state "five2024") 'problem))
      (should (equal (plist-get (car plans) :line) 1))
      (should (equal (plist-get (car plans) :left) nil)))))

(ert-deftest sp-bibtex-abstract-dryrun-report-writes-nothing ()
  (sp-bibtex-abstract-test--with-setup
    (let ((before (sp-bibtex-abstract-test--read bib))
          (notes-before (mapcar (lambda (k) (sp-bibtex-abstract-test--read (funcall note k)))
                                '("one2020" "two2021" "three2022"))))
      (sp-bibtex-lint-abstract-dryrun bib)
      (let ((text (with-current-buffer sp-bibtex-abstract--buffer (buffer-string))))
        (should (string-match-p "Abstracts to move (2)" text))
        (should (string-match-p "Different abstract in the note (not touched) (1)" text))
        (should (string-match-p "No litnote (skipped) (1)" text))
        (should (string-match-p "Problems (1)" text))
        (should (string-match-p "new Abstract heading" text))
        (should (string-match-p "already in the note; only the field goes" text))
        (should (string-match-p "Something else that I wrote" text)))
      (should (equal before (sp-bibtex-abstract-test--read bib)))
      (should (equal notes-before (mapcar (lambda (k) (sp-bibtex-abstract-test--read (funcall note k)))
                                          '("one2020" "two2021" "three2022"))))
      (should-not (file-exists-p sp-bibtex-abstract-backup-directory)))))

;;;; The fix

(ert-deftest sp-bibtex-abstract-fix-moves-and-keeps-the-rest ()
  (sp-bibtex-abstract-test--with-setup
    (sp-bibtex-lint-fix-abstract bib)
    (let ((bib-text (sp-bibtex-abstract-test--read bib))
          (one (sp-bibtex-abstract-test--read (funcall note "one2020"))))
      ;; moved: the field is gone, the rest of the entry is not
      (should-not (string-match-p "Marx" bib-text))
      (should-not (string-match-p "Already there" bib-text))
      (should (string-match-p "author = {One, A.}" bib-text))
      (should (string-match-p "year = {2020}" bib-text))
      ;; not moved: conflict, no note, macro
      (should (string-match-p "Mine, from BibTeX" bib-text))
      (should (string-match-p "Lost without a note" bib-text))
      (should (string-match-p "# amacro" bib-text))
      ;; the note has the heading as its first one, and kept everything
      (should (string-match-p "\\* Abstract\n\nA Marxist study of Søren and /value/ & more\\.\n\nSecond paragraph, \\$x_1\\$ stays\\.\n\n\\* Notes\nSome notes\\.\n" one))
      (should (string-match-p ":ROAM_REFS: @one2020" one))
      (should (string-match-p "#\\+filetags: :litnote:" one))
      ;; the conflicting note is untouched
      (should (string-match-p "Something else that I wrote"
                              (sp-bibtex-abstract-test--read (funcall note "three2022")))))
    ;; the run is backed up with its manifest
    (let* ((run (car (sp-bibtex-abstract--runs)))
           (manifest (sp-bibtex-abstract--read-manifest run)))
      (should (file-exists-p (expand-file-name "a.bib" run)))
      (should (string-match-p "Marx" (sp-bibtex-abstract-test--read (expand-file-name "a.bib" run))))
      (should (file-exists-p (expand-file-name "one2020.org" run)))
      (should-not (string-match-p "Abstract" (sp-bibtex-abstract-test--read (expand-file-name "one2020.org" run))))
      (should (equal (sort (copy-sequence (plist-get manifest :keys)) #'string<) '("one2020" "two2021")))
      (should (equal (plist-get manifest :bib-sha) (sp-bibtex-abstract--sha bib)))
      ;; only the note that was written is listed
      (should (equal (mapcar (lambda (n) (file-name-nondirectory (car n))) (plist-get manifest :notes))
                     '("one2020.org"))))))

(ert-deftest sp-bibtex-abstract-fix-is-idempotent ()
  (sp-bibtex-abstract-test--with-setup
    (sp-bibtex-lint-fix-abstract bib)
    (let ((bib-text (sp-bibtex-abstract-test--read bib))
          (n (length (sp-bibtex-abstract--runs))))
      (should-not (sp-bibtex-lint-fix-abstract bib))
      (should (equal bib-text (sp-bibtex-abstract-test--read bib)))
      (should (= n (length (sp-bibtex-abstract--runs)))))))

(ert-deftest sp-bibtex-abstract-failed-note-keeps-the-abstract ()
  (sp-bibtex-abstract-test--with-setup
    (let ((orig (symbol-function 'sp-bibtex-abstract--file-state)))
      ;; The note reads back without the text: the write is not confirmed.
      (cl-letf (((symbol-function 'sp-bibtex-abstract--file-state)
                 (lambda (file text)
                   (if (string-match-p "one2020" file)
                       (cons 'create nil)
                     (funcall orig file text)))))
        (sp-bibtex-lint-fix-abstract bib))
      (let ((bib-text (sp-bibtex-abstract-test--read bib)))
        (should (string-match-p "Marxist\\|{Marx}ist" bib-text))   ; stays in BibTeX
        (should-not (string-match-p "Already there" bib-text))))))  ; the other one moved

(ert-deftest sp-bibtex-abstract-note-with-lost-text-is-not-written ()
  (sp-bibtex-abstract-test--with-setup
    (cl-letf (((symbol-function 'sp-litnotes-meta--verify-kept)
               (lambda (&rest _) (error "would lose a line"))))
      (sp-bibtex-lint-fix-abstract bib))
    (should (string-match-p "{Marx}ist" (sp-bibtex-abstract-test--read bib)))
    (should-not (string-match-p "Abstract" (sp-bibtex-abstract-test--read (funcall note "one2020"))))))

(ert-deftest sp-bibtex-abstract-bib-changed-during-run-is-not-written ()
  (sp-bibtex-abstract-test--with-setup
    (let ((orig (symbol-function 'sp-bibtex-abstract--move-one)))
      (cl-letf (((symbol-function 'sp-bibtex-abstract--move-one)
                 (lambda (plan dir)
                   (prog1 (funcall orig plan dir)
                     (with-temp-file bib
                       (insert (sp-bibtex-abstract-test--read (expand-file-name "a.bib" dir)) "\n% edited\n"))))))
        (should-error (sp-bibtex-lint-fix-abstract bib) :type 'user-error))
      (should (string-match-p "{Marx}ist" (sp-bibtex-abstract-test--read bib)))
      ;; the notes have it, so a second run only removes the fields
      (should (string-match-p "Marxist" (sp-bibtex-abstract-test--read (funcall note "one2020"))))
      (sp-bibtex-lint-fix-abstract bib)
      (should-not (string-match-p "{Marx}ist" (sp-bibtex-abstract-test--read bib)))
      (should (string-match-p "% edited" (sp-bibtex-abstract-test--read bib))))))

(ert-deftest sp-bibtex-abstract-dropped-entries-stay ()
  (sp-bibtex-abstract-test--with-setup
    (setq sp-bibtex-abstract--excluded (list (sp-bibtex-lint--entry-key bib "one2020")))
    (sp-bibtex-lint-fix-abstract bib)
    (should (string-match-p "{Marx}ist" (sp-bibtex-abstract-test--read bib)))
    (should-not (string-match-p "Already there" (sp-bibtex-abstract-test--read bib)))))

(ert-deftest sp-bibtex-abstract-unsaved-bib-buffer-stops ()
  (sp-bibtex-abstract-test--with-setup
    (with-current-buffer (find-file-noselect bib)
      (insert "% unsaved\n")
      (unwind-protect
          (should-error (sp-bibtex-lint-fix-abstract bib) :type 'user-error)
        (set-buffer-modified-p nil)
        (kill-buffer)))))

(ert-deftest sp-bibtex-abstract-note-visited-with-changes-is-saved-after-backup ()
  (sp-bibtex-abstract-test--with-setup
    (let ((buf (find-file-noselect (funcall note "one2020"))))
      (with-current-buffer buf (goto-char (point-max)) (insert "More notes.\n"))
      (sp-bibtex-lint-fix-abstract bib)
      (should-not (string-match-p "{Marx}ist" (sp-bibtex-abstract-test--read bib)))
      (let ((text (sp-bibtex-abstract-test--read (funcall note "one2020"))))
        (should (string-match-p "More notes\\." text))
        (should (string-match-p "\\* Abstract" text)))
      ;; the backup is the text from before the write, unsaved changes included;
      ;; the text that was on disk is kept apart
      (let ((run (car (sp-bibtex-abstract--runs))))
        (should (string-match-p "More notes" (sp-bibtex-abstract-test--read (expand-file-name "one2020.org" run))))
        (should-not (string-match-p "More notes"
                                    (sp-bibtex-abstract-test--read (expand-file-name "before-save/one2020.org" run)))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;;;; The restore

(ert-deftest sp-bibtex-abstract-restore ()
  (sp-bibtex-abstract-test--with-setup
    (let ((before-bib (sp-bibtex-abstract-test--read bib))
          (before-one (sp-bibtex-abstract-test--read (funcall note "one2020"))))
      (sp-bibtex-lint-fix-abstract bib)
      (should-not (equal before-bib (sp-bibtex-abstract-test--read bib)))
      (sp-bibtex-lint-abstract-restore (car (sp-bibtex-abstract--runs)))
      (should (equal before-bib (sp-bibtex-abstract-test--read bib)))
      (should (equal before-one (sp-bibtex-abstract-test--read (funcall note "one2020")))))))

(ert-deftest sp-bibtex-abstract-restore-keeps-later-edits ()
  (sp-bibtex-abstract-test--with-setup
    (let ((before-bib (sp-bibtex-abstract-test--read bib)))
      (sp-bibtex-lint-fix-abstract bib)
      (let ((run (car (sp-bibtex-abstract--runs))))
        ;; edits made after the run: to the note, and to the .bib file
        (with-temp-buffer
          (insert-file-contents (funcall note "one2020"))
          (goto-char (point-max)) (insert "Later notes.\n")
          (write-region (point-min) (point-max) (funcall note "one2020")))
        (with-temp-buffer
          (insert-file-contents bib) (goto-char (point-max)) (insert "% later\n")
          (write-region (point-min) (point-max) bib))
        (sp-bibtex-lint-abstract-restore run)
        (should (equal before-bib (sp-bibtex-abstract-test--read bib)))
        ;; the .bib text of before the restore is kept
        (should (string-match-p "% later"
                                (sp-bibtex-abstract-test--read
                                 (expand-file-name "before-restore/a.bib" run))))
        ;; the note changed since the run, so it was left as it is
        (should (string-match-p "Later notes" (sp-bibtex-abstract-test--read (funcall note "one2020"))))
        (should (string-match-p "\\* Abstract" (sp-bibtex-abstract-test--read (funcall note "one2020"))))))))

;;;; The entry at point

(ert-deftest sp-bibtex-abstract-entry-at-point ()
  (sp-bibtex-abstract-test--with-setup
    (with-current-buffer (find-file-noselect bib)
      (unwind-protect
          (progn
            (goto-char (point-min))
            (search-forward "title = {First}")
            ;; dry run: nothing changes
            (sp-bibtex-lint-abstract-entry t)
            (should-not (buffer-modified-p))
            (sp-bibtex-lint-abstract-entry)
            (should (buffer-modified-p))
            (should-not (string-match-p "Marx" (buffer-string)))
            (should (string-match-p "Mine, from BibTeX" (buffer-string)))
            (should (string-match-p "\\* Abstract" (sp-bibtex-abstract-test--read (funcall note "one2020"))))
            ;; the disk file is not changed until it is saved, and undo brings the field back
            (should (string-match-p "Marx" (sp-bibtex-abstract-test--read bib)))
            (primitive-undo 1 buffer-undo-list)
            (should (string-match-p "{Marx}ist" (buffer-string))))
        (set-buffer-modified-p nil)
        (kill-buffer)))))

(ert-deftest sp-bibtex-abstract-entry-refuses ()
  (sp-bibtex-abstract-test--with-setup
    (with-current-buffer (find-file-noselect bib)
      (unwind-protect
          (progn
            (dolist (title '("title = {Third}" "title = {No note}" "title = {Macro}" "title = {Nothing here}"))
              (goto-char (point-min))
              (search-forward title)
              (should-error (sp-bibtex-lint-abstract-entry) :type 'user-error))
            (should-not (buffer-modified-p)))
        (kill-buffer)))))

(provide 'sp-bibtex-abstract-test)
;;; sp-bibtex-abstract-test.el ends here
