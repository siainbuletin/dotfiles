;;; sp-author-notes-test.el --- Tests for sp-author-notes -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-author-notes)

(defvar sp-author-notes-test--n 0)

(defun sp-author-notes-test--write (file &rest lines)
  "Write LINES to FILE, creating its folder."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert (string-join lines "\n") "\n")))

(defun sp-author-notes-test--read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro sp-author-notes-test--with-vault (&rest body)
  "Run BODY with a temporary vault in `vault', and `write-note' stubbed."
  (declare (indent 0))
  `(let* ((vault (file-name-as-directory (make-temp-file "sp-authors" t)))
          (sp-author-notes-directory vault)
          (sp-author-notes-litnotes-directory (expand-file-name "litnotes/" vault))
          (sp-author-notes-backup-directory (expand-file-name "backups/" vault))
          (sp-author-notes--stub-ids nil))
     (unwind-protect
         (cl-letf (((symbol-function 'sp-org--write-note)
                    (lambda (title tags)
                      (let* ((id (format "new-%d" (cl-incf sp-author-notes-test--n)))
                             (file (expand-file-name (format "%s.org" id) vault)))
                        (sp-author-notes-test--write
                         file ":PROPERTIES:" (format ":ID:       %s" id) ":END:"
                         (format "#+title: %s" title)
                         (format "#+filetags: :%s:" (string-join tags ":")) "")
                        (push (cons id file) sp-author-notes--stub-ids)
                        id)))
                   ((symbol-function 'org-id-find)
                    (lambda (id &rest _) (when-let* ((f (cdr (assoc id sp-author-notes--stub-ids)))) (cons f 1))))
                   ((symbol-function 'require)
                    (let ((orig (symbol-function 'require)))
                      (lambda (feature &rest args)
                        (if (eq feature 'sp-org-link-conversion) t (apply orig feature args))))))
           ,@body)
       (delete-directory vault t))))

(defvar sp-author-notes--stub-ids nil)

(defun sp-author-notes-test--person (vault name id &rest extra)
  (apply #'sp-author-notes-test--write
         (expand-file-name (format "%s.org" id) vault)
         ":PROPERTIES:" (format ":ID: %s" id) ":END:" (format "#+title: %s" name)
         "#+filetags: :person:" "" extra))

(ert-deftest sp-author-notes-test-typo-states ()
  (should (equal (sp-author-notes--key-state "pub-authro") '(fix . "pub-author")))
  (should (equal (sp-author-notes--key-state "pub-autor") '(fix . "pub-author")))
  (should (equal (sp-author-notes--key-state "Pub_Author") '(fix . "pub-author")))
  (should (equal (sp-author-notes--key-state "pub-auhtro") '(suspect . "pub-author")))
  (should-not (sp-author-notes--key-state "pub-author"))
  (should-not (sp-author-notes--key-state "pub-editor"))
  (should (equal (sp-author-notes--key-state "bib-author") '(suspect . "pub-author")))
  (should-not (sp-author-notes--key-state "bib-parent"))
  (should-not (sp-author-notes--key-state "read-status")))

(ert-deftest sp-author-notes-test-parse-value ()
  (should (equal (sp-author-notes--parse-value "Smith, John and Doe, Jane")
                 '((:name "John Smith") (:name "Jane Doe"))))
  (should (equal (sp-author-notes--parse-value "{van Gogh}; Ann Lee")
                 '((:name "van Gogh") (:name "Ann Lee"))))
  (should (equal (sp-author-notes--parse-value "[[id:a][A]], [[id:b]]")
                 '((:link "a" "[[id:a][A]]") (:link "b" "[[id:b]]"))))
  (should (eq (sp-author-notes--parse-value "Dr. [[id:a][A]]") 'unparsed)))

(ert-deftest sp-author-notes-test-person-pass ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID: x\n:END:\n#+title: X\n\n* Bio\ntext\n")
    (should (equal (sp-author-notes--person-pass) '(basics works table)))
    (let ((text (buffer-string)))
      (should (string-match-p "#\\+title: X\n\n\\* Basics\n\n\\* Works\n\n#\\+BEGIN: collection-query-table :parent-of \"self\" :parent-prop \"pub-author\" :columns (:title \"read-status\" \"read-priority\" \"pub-year\" \"relevance-factor\") :sort-by \"pub-year\"\n#\\+END:\n\n\\* Bio\ntext\n" text))
      ;; idempotent
      (should (null (sp-author-notes--person-pass)))
      (should (equal text (buffer-string))))))

(ert-deftest sp-author-notes-test-person-pass-keeps-existing ()
  (with-temp-buffer
    (insert "#+title: X\n\n* Basics\nmine\n** Sub\n* Works\nold text\n** Child\nc\n* Other\n")
    (should (equal (sp-author-notes--person-pass) '(table)))
    (should (string-match-p "\\* Works\nold text\n\n#\\+BEGIN: .*\n#\\+END:\n\n\\*\\* Child\nc\n\\* Other\n"
                            (buffer-string)))
    (should (string-match-p "\\* Basics\nmine\n\\*\\* Sub\n" (buffer-string)))))

(ert-deftest sp-author-notes-test-person-pass-existing-table-elsewhere ()
  (with-temp-buffer
    (insert "#+title: X\n\n* Basics\n#+BEGIN: vulpea-table :parent-of \"self\" :parent-prop \"pub-author\"\n#+END:\n")
    (should (equal (sp-author-notes--person-pass) '(works)))))

(ert-deftest sp-author-notes-test-full-run ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--person vault "Ann Lee" "ann"
                                  "* Basics" "bio")
    (sp-author-notes-test--write
     (expand-file-name "litnotes/a.org" vault)
     ":PROPERTIES:" ":ID: l1" ":END:" "#+title: lee2020x" ""
     "- pub-authro :: [[id:ann][Ann Lee]]" "- pub-year :: 2020" "")
    (sp-author-notes-test--write
     (expand-file-name "litnotes/b.org" vault)
     ":PROPERTIES:" ":ID: l2" ":END:" "#+title: roe2021y" ""
     "- pub-author :: Lee, Ann; Roe, Richard" "- pub-year :: 2021" "")
    (sp-author-notes-test--write
     (expand-file-name "litnotes/c.org" vault)
     ":PROPERTIES:" ":ID: l3" ":END:" "#+title: odd" ""
     "- pub-author :: [[id:ghost][Ghost]]" "- pub-auhtro :: x" "")
    (sp-author-notes-test--write
     (expand-file-name "other.org" vault)
     ":PROPERTIES:" ":ID: o" ":END:" "#+title: Richard Roe" "")
    (let ((before-a (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault))))
      ;; preview writes nothing
      (let ((run (sp-author-notes--run nil)))
        (should (null (sp-author-notes--run-pending run)))
        (should (null (sp-author-notes--run-created run)))
        (should (equal before-a (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault))))
        (should-not (file-exists-p (expand-file-name "new-1.org" vault)))
        (with-temp-buffer (sp-author-notes--render run)
                          (should (string-match-p "PREVIEW" (buffer-string)))))
      ;; "Richard Roe" exists but is not a person: nothing is created for it
      (let ((run (sp-author-notes--run t)))
        (should (null (sp-author-notes--run-created run)))
        (should (seq-some (lambda (p) (string-match-p "not tagged person" (nth 2 p)))
                          (sp-author-notes--run-problems run)))
        (should (seq-some (lambda (p) (string-match-p "no note in" (nth 2 p)))
                          (sp-author-notes--run-problems run))))
      (should (string-match-p "- pub-author :: \\[\\[id:ann\\]\\[Ann Lee\\]\\]"
                              (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault))))
      ;; b: Ann linked, Roe left plain
      (should (string-match-p "- pub-author :: \\[\\[id:ann\\]\\[Ann Lee\\]\\], Richard Roe"
                              (sp-author-notes-test--read (expand-file-name "litnotes/b.org" vault))))
      ;; c: suspect key untouched
      (should (string-match-p "- pub-auhtro :: x"
                              (sp-author-notes-test--read (expand-file-name "litnotes/c.org" vault))))
      (let ((ann (sp-author-notes-test--read (expand-file-name "ann.org" vault))))
        (should (string-match-p "\\* Basics\nbio\n\n\\* Works\n\n#\\+BEGIN: collection-query-table" ann)))
      (should (file-exists-p (expand-file-name "backups/" vault)))
      ;; second run: only the unfixable remains, no changes
      (let ((run (sp-author-notes--run t)))
        (should (= 0 (sp-author-notes--change-count run)))))))

(ert-deftest sp-author-notes-test-creates-person-notes ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--write
     (expand-file-name "litnotes/a.org" vault)
     ":PROPERTIES:" ":ID: l1" ":END:" "#+title: x" ""
     "- pub-author :: Arendt, Hannah" "")
    (sp-author-notes-test--write
     (expand-file-name "litnotes/b.org" vault)
     ":PROPERTIES:" ":ID: l2" ":END:" "#+title: y" ""
     "- pub-author :: Hannah Arendt" "")
    (let ((run (sp-author-notes--run nil)))
      (should (equal (sp-author-notes--run-pending run) '("Hannah Arendt")))
      (should (equal (nth 3 (car (sp-author-notes--run-people run))) '(basics works table))))
    (let ((run (sp-author-notes--run t)))
      (should (= 1 (length (sp-author-notes--run-created run))))
      (let* ((id (nth 1 (car (sp-author-notes--run-created run))))
             (a (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault)))
             (note (sp-author-notes-test--read (expand-file-name (format "%s.org" id) vault))))
        (should (string-match-p (format "- pub-author :: \\[\\[id:%s\\]\\[Hannah Arendt\\]\\]" id) a))
        (should (string-match-p "#\\+filetags: :person:" note))
        (should (string-match-p "\\* Basics\n\n\\* Works" note))))
    (should (= 0 (sp-author-notes--change-count (sp-author-notes--run t))))))

(ert-deftest sp-author-notes-test-unsaved-buffer-skipped ()
  (sp-author-notes-test--with-vault
    (let ((file (expand-file-name "litnotes/a.org" vault)))
      (sp-author-notes-test--write file "#+title: x" "" "- pub-authro :: Z" "")
      (let ((buf (find-file-noselect file)))
        (unwind-protect
            (progn (with-current-buffer buf (insert "edit"))
                   (let ((run (sp-author-notes--run t)))
                     (should (string-match-p "pub-authro" (sp-author-notes-test--read file)))
                     (should (seq-some (lambda (p) (string-match-p "Unsaved" (nth 2 p)))
                                       (sp-author-notes--run-problems run)))))
          (with-current-buffer buf (set-buffer-modified-p nil))
          (kill-buffer buf))))))
