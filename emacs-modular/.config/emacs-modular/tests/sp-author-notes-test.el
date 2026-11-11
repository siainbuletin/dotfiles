;;; sp-author-notes-test.el --- Tests for sp-author-notes -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-async-work)
(setq sp-async-work-synchronous t)
(require 'sp-author-notes)

(defvar sp-author-notes-test--n 0)

(defun org-dblock-write:collection-query-table (_params)
  "Stand-in for the real block writer, which needs vulpea."
  (insert "FILLED"))

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
          (sp-author-notes-redirect-function (lambda (&rest _) nil))
          (sp-author-notes-disambiguate-function (lambda (&rest _) nil))
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
                   ((symbol-function 'vulpea-db-query) #'ignore)
                   ((symbol-function 'org-id-find)
                    (lambda (id &rest _) (when-let* ((f (cdr (assoc id sp-author-notes--stub-ids)))) (cons f 1))))
                   ((symbol-function 'require)
                    (let ((orig (symbol-function 'require)))
                      (lambda (feature &rest args)
                        (if (memq feature '(sp-org-link-conversion sp-collection-query-tables)) t (apply orig feature args))))))
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
  (should (equal (sp-author-notes--key-state "pub-editro") '(fix . "pub-editor")))
  (should (equal (sp-author-notes--key-state "Pub_Editor") '(fix . "pub-editor")))
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
    (should (equal (sp-author-notes--person-pass t) '(basics works table edited-heading edited-table)))
    (let ((text (buffer-string)))
      (should (string-match-p "#\\+title: X\n\n\\* Basics\n\n\\* Works\n\n#\\+BEGIN: collection-query-table :parent-of \"self\" :parent-prop \"pub-author\" :fold-tag (\"booksection\" \"incollection\") :fold-prop \"bib-parent\" :columns (:title :sections \"read-status\" \"read-priority\" \"pub-year\" \"relevance-factor\") :sort-by \"pub-year\"\n#\\+END:\n\n\\* Edited works\n\n#\\+BEGIN: [^\n]*:parent-prop \"pub-editor\" :except-prop \"pub-author\"[^\n]*\n#\\+END:\n\n\\* Bio\ntext\n" text))
      ;; idempotent
      (should (null (sp-author-notes--person-pass)))
      (should (equal text (buffer-string))))))

(ert-deftest sp-author-notes-test-person-pass-keeps-existing ()
  (with-temp-buffer
    (insert "#+title: X\n\n* Basics\nmine\n** Sub\n* Works\nold text\n** Child\nc\n* Other\n")
    (should (equal (sp-author-notes--person-pass t) '(table edited-heading edited-table)))
    (should (string-match-p "\\* Works\nold text\n\n#\\+BEGIN: .*\n#\\+END:\n\n\\*\\* Child\nc\n\n\\* Edited works\n\n#\\+BEGIN: [^\n]*:parent-prop \"pub-editor\" :except-prop \"pub-author\"[^\n]*\n#\\+END:\n\n\\* Other\n"
                            (buffer-string)))
    (should (string-match-p "\\* Basics\nmine\n\\*\\* Sub\n" (buffer-string)))))

(ert-deftest sp-author-notes-test-person-pass-existing-table-elsewhere ()
  (with-temp-buffer
    (insert "#+title: X\n\n* Basics\n#+BEGIN: vulpea-table :parent-of \"self\" :parent-prop \"pub-author\"\n#+END:\n")
    (should (equal (sp-author-notes--person-pass t) '(works edited-heading edited-table)))))

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
      ;; "Richard Roe" exists but is not a person: it gets tagged
      (let ((run (sp-author-notes--run t)))
        (should (null (sp-author-notes--run-created run)))
        (should (equal (mapcar #'car (sp-author-notes--run-tagged run)) '("Richard Roe")))
        (should (= 1 (length (sp-author-notes--run-orphans run)))))
      (should (string-match-p "#\\+filetags: :person:" (sp-author-notes-test--read (expand-file-name "other.org" vault))))
      (should (string-match-p "- pub-author :: \\[\\[id:ann\\]\\[Ann Lee\\]\\]"
                              (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault))))
      ;; b: Ann and Roe linked
      (should (string-match-p "- pub-author :: \\[\\[id:ann\\]\\[Ann Lee\\]\\], \\[\\[id:o\\]\\[Richard Roe\\]\\]"
                              (sp-author-notes-test--read (expand-file-name "litnotes/b.org" vault))))
      ;; c: suspect key untouched
      (should (string-match-p "- pub-auhtro :: x"
                              (sp-author-notes-test--read (expand-file-name "litnotes/c.org" vault))))
      (let ((ann (sp-author-notes-test--read (expand-file-name "ann.org" vault))))
        (should (string-match-p "\\* Basics\nbio\n\n\\* Works\n\n#\\+BEGIN: collection-query-table[^\n]*\nFILLED\n#\\+END:" ann)))
      (should (file-exists-p (expand-file-name "backups/" vault)))
      ;; second run: nothing left to change
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

(ert-deftest sp-author-notes-test-pub-editor-linked-like-author ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--write
     (expand-file-name "litnotes/a.org" vault)
     ":PROPERTIES:" ":ID: l1" ":END:" "#+title: x" ""
     "- pub-author :: Arendt, Hannah" "- pub-editro :: Kohn, Jerome" "")
    (let ((run (sp-author-notes--run t)))
      (should (= 2 (length (sp-author-notes--run-created run))))
      (let ((a (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault))))
        (should (string-match-p "- pub-author :: \\[\\[id:[^]]+\\]\\[Hannah Arendt\\]\\]" a))
        (should (string-match-p "- pub-editor :: \\[\\[id:[^]]+\\]\\[Jerome Kohn\\]\\]" a))))
    (should (= 0 (sp-author-notes--change-count (sp-author-notes--run t))))))

(ert-deftest sp-author-notes-test-unsaved-buffer-saved ()
  (sp-author-notes-test--with-vault
    (let ((file (expand-file-name "litnotes/a.org" vault)))
      (sp-author-notes-test--write file "#+title: x" "" "- pub-authro :: [[id:q][Q]]" "")
      (let ((buf (find-file-noselect file)))
        (unwind-protect
            (progn (with-current-buffer buf (goto-char (point-max)) (insert "my edit\n"))
                   (let ((run (sp-author-notes--run nil)))
                     (should (equal (sp-author-notes--run-saved run) (list file)))
                     (should-not (string-match-p "my edit" (sp-author-notes-test--read file))))
                   (let ((run (sp-author-notes--run t)))
                     (should (equal (sp-author-notes--run-saved run) (list file)))
                     (should-not (buffer-modified-p buf))
                     (let ((text (sp-author-notes-test--read file)))
                       (should (string-match-p "my edit" text))
                       (should (string-match-p "- pub-author :: " text)))))
          (set-buffer-modified-p nil)
          (kill-buffer buf))))))

(ert-deftest sp-author-notes-test-moves-works-above-basics ()
  (with-temp-buffer
    (insert "#+title: X\n\n* Works\nmine\n** Sub\n* Bio\n* Basics\nb\n* After\n")
    (should (equal (sp-author-notes--person-pass t) '(moved-works table edited-heading edited-table)))
    (let ((text (buffer-string)))
      (should (string-match-p "\\* Bio\n\n?\\* Basics\nb\n\n\\* Works\nmine\n\n#\\+BEGIN: [^\n]*\n#\\+END:\n\n\\*\\* Sub\n\n\\* Edited works\n\n#\\+BEGIN: [^\n]*:parent-prop \"pub-editor\" :except-prop \"pub-author\"[^\n]*\n#\\+END:\n\n\\* After\n" text))
      (should (null (sp-author-notes--person-pass)))
      (should (equal text (buffer-string))))))

(ert-deftest sp-author-notes-test-tag-pass ()
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID: a\n:END:\n#+title: A\n#+filetags: :music:\n")
    (sp-author-notes--tag-pass)
    (should (string-match-p "#\\+filetags: :music:person:\n" (buffer-string))))
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID: a\n:END:\n#+title: A\n\ntext\n")
    (sp-author-notes--tag-pass)
    (should (string-match-p "#\\+title: A\n#\\+filetags: :person:\n\ntext" (buffer-string)))))

(ert-deftest sp-author-notes-test-orphan-redirect ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--person vault "Ann Lee" "ann")
    (let ((file (expand-file-name "litnotes/a.org" vault))
          (asked nil))
      (sp-author-notes-test--write file "#+title: x" "" "- pub-author :: [[id:gone][Ann Lee]]" "")
      (let ((run (sp-author-notes--run nil)))
        (should (equal (car (last (car (sp-author-notes--run-orphans run)))) "Ann Lee"))
        (should (string-match-p "id:gone" (sp-author-notes-test--read file))))
      (let ((sp-author-notes-redirect-function
             (lambda (id desc suggestion candidates)
               (setq asked (list id desc suggestion (mapcar #'car candidates)))
               (cdr (assoc suggestion candidates)))))
        (sp-author-notes--run t))
      (should (equal asked '("gone" "Ann Lee" "Ann Lee" ("Ann Lee"))))
      (should (string-match-p "pub-author :: \\[\\[id:ann\\]\\[Ann Lee\\]\\]$"
                              (string-trim-right (sp-author-notes-test--read file))))
      ;; declined: left alone
      (sp-author-notes-test--write file "#+title: x" "" "- pub-author :: [[id:gone][Zed]]" "")
      (let ((sp-author-notes-redirect-function (lambda (&rest _) nil))
          (sp-author-notes-disambiguate-function (lambda (&rest _) nil)))
        (sp-author-notes--run t))
      (should (string-match-p "id:gone" (sp-author-notes-test--read file))))))

(ert-deftest sp-author-notes-test-parse-quoted ()
  (should (equal (sp-author-notes--parse-value
                  "\"Frederick Conrad\", \"Jason Corey\", \"Samantha Goldstein\", \"Joseph Ostrow\", \"Michael Sadowsky\"")
                 '((:name "Frederick Conrad") (:name "Jason Corey") (:name "Samantha Goldstein")
                   (:name "Joseph Ostrow") (:name "Michael Sadowsky"))))
  (should (equal (sp-author-notes--parse-value "\"J. N. Wright\" \"Peter G. Lucas\"")
                 '((:name "J. N. Wright") (:name "Peter G. Lucas"))))
  (should (equal (sp-author-notes--parse-value "\"Tim Wildschut")
                 '((:name "Tim Wildschut"))))
  (should (equal (sp-author-notes--parse-value "\"Ann Lee\", \"Bo Roe")
                 '((:name "Ann Lee") (:name "Bo Roe"))))
  (should (equal (sp-author-notes--parse-value "\"Lee, Ann\"")
                 '((:name "Ann Lee"))))
  (should (equal (sp-author-notes--parse-value "[[denote:20251213T235944][Leigh Claire La Berge]], \"Bo Roe\"")
                 '((:denote "20251213T235944" "[[denote:20251213T235944][Leigh Claire La Berge]]")
                   (:name "Bo Roe"))))
  (should (eq (sp-author-notes--parse-value "Dr. [[denote:1][A]]") 'unparsed)))

(ert-deftest sp-author-notes-test-quoted-and-denote-run ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--write
     (expand-file-name "20251213T235944--leigh__person.org" vault)
     ":PROPERTIES:" ":ID: leigh" ":END:" "#+title: Leigh Claire La Berge" "#+filetags: :person:" "")
    (let ((file (expand-file-name "litnotes/a.org" vault)))
      (sp-author-notes-test--write
       file "#+title: x" ""
       "- pub-author :: [[denote:20251213T235944][Leigh Claire La Berge]], \"Tim Wildschut\", \"Bo Roe\""
       "- pub-author :: [[denote:19990101T000000][Nobody]]" "")
      (let ((run (sp-author-notes--run nil)))
        (should (equal (sp-author-notes--run-pending run) '("Tim Wildschut" "Bo Roe")))
        (should (string-match-p "denote:2025" (sp-author-notes-test--read file))))
      (let* ((run (sp-author-notes--run t))
             (text (sp-author-notes-test--read file)))
        (should (= 2 (length (sp-author-notes--run-created run))))
        (should (string-match-p "pub-author :: \\[\\[id:leigh\\]\\[Leigh Claire La Berge\\]\\], \\[\\[id:new-[0-9]+\\]\\[Tim Wildschut\\]\\], \\[\\[id:new-[0-9]+\\]\\[Bo Roe\\]\\]" text))
        ;; unknown identifier stays, reported
        (should (string-match-p "denote:19990101T000000" text))
        (should (seq-some (lambda (p) (string-match-p "Denote identifier 19990101" (nth 2 p)))
                          (sp-author-notes--run-problems run))))
      (should (= 0 (sp-author-notes--change-count (sp-author-notes--run t)))))))

(ert-deftest sp-author-notes-test-parse-comma-lists ()
  (should (equal (sp-author-notes--parse-value
                  "Francisco López-Muñoz, Gabriel Rubio, Juan D. Molina, Cecilio Alam")
                 '((:ambiguous "Francisco López-Muñoz, Gabriel Rubio, Juan D. Molina, Cecilio Alam"
                               ("Francisco López-Muñoz" "Gabriel Rubio" "Juan D. Molina" "Cecilio Alam")))))
  (should (equal (sp-author-notes--parse-value "Smith, John, Doe, Jane")
                 '((:ambiguous "Smith, John, Doe, Jane" ("John Smith" "Jane Doe")))))
  (should (equal (sp-author-notes--parse-value "Smith, John, Doe")
                 '((:ambiguous "Smith, John, Doe" nil))))
  ;; one comma stays one name; "and" still splits
  (should (equal (sp-author-notes--parse-value "Smith, John and Ann Lee, Bo Roe, Cy Poe")
                 '((:name "John Smith")
                   (:ambiguous "Ann Lee, Bo Roe, Cy Poe" ("Ann Lee" "Bo Roe" "Cy Poe"))))))

(ert-deftest sp-author-notes-test-comma-list-run ()
  (sp-author-notes-test--with-vault
    (let ((file (expand-file-name "litnotes/a.org" vault))
          (raw "Ann Lee, Bo Roe, Cy Poe"))
      (sp-author-notes-test--write file "#+title: x" "" (concat "- pub-author :: " raw) "")
      ;; preview: a case, nothing pending, nothing written
      (let ((run (sp-author-notes--run nil)))
        (should (null (sp-author-notes--run-pending run)))
        (should (equal (nth 1 (car (plist-get (cdar (sp-author-notes--run-litnotes run)) :ambiguous)))
                       '("Ann Lee" "Bo Roe" "Cy Poe")))
        (with-temp-buffer (sp-author-notes--render run)
                          (should (string-match-p "to disambiguate (1)" (buffer-string)))))
      ;; declined: left as it is
      (let ((run (sp-author-notes--run t)))
        (should (null (sp-author-notes--run-created run)))
        (should (string-match-p (regexp-quote raw) (sp-author-notes-test--read file))))
      ;; accepted: one note each
      (let* ((sp-author-notes-disambiguate-function (lambda (_raw names) names))
             (run (sp-author-notes--run t))
             (text (sp-author-notes-test--read file)))
        (should (= 3 (length (sp-author-notes--run-created run))))
        (should (string-match-p "Ann Lee\\]\\], \\[\\[id:new-[0-9]+\\]\\[Bo Roe\\]\\], \\[\\[id:new-[0-9]+\\]\\[Cy Poe\\]\\]$"
                                (string-trim-right text)))))))

(ert-deftest sp-author-notes-test-parse-and-lists ()
  ;; BibTeX forms stay as they were
  (should (equal (sp-author-notes--parse-value "Smith, John and Doe, Jane")
                 '((:name "John Smith") (:name "Jane Doe"))))
  (should (equal (sp-author-notes--parse-value "Smith, John and Ann Lee")
                 '((:name "John Smith") (:name "Ann Lee"))))
  (should (equal (sp-author-notes--parse-value "Ann Lee and Bo Roe and Cy Poe")
                 '((:name "Ann Lee") (:name "Bo Roe") (:name "Cy Poe"))))
  ;; a list with commas that ends in "and" is one case
  (should (equal (sp-author-notes--parse-value "Ann Lee, Bo Roe, and Cy Poe")
                 '((:ambiguous "Ann Lee, Bo Roe, and Cy Poe" ("Ann Lee" "Bo Roe" "Cy Poe")))))
  (should (equal (sp-author-notes--parse-value "Ann Lee, Bo Roe and Cy Poe; Di Fay")
                 '((:ambiguous "Ann Lee, Bo Roe and Cy Poe" ("Ann Lee" "Bo Roe" "Cy Poe"))
                   (:name "Di Fay")))))

(ert-deftest sp-author-notes-test-exclude ()
  (sp-author-notes-test--with-vault
    (let ((a (expand-file-name "litnotes/a.org" vault))
          (b (expand-file-name "litnotes/b.org" vault)))
      (sp-author-notes-test--write a "#+title: x" "" "- pub-authro :: Ann Lee" "")
      (sp-author-notes-test--write b "#+title: y" "" "- pub-author :: Bo Roe" "")
      ;; dropping a name: no note, the name stays
      (let ((sp-author-notes--excluded (list "name:ann lee")))
        (let ((run (sp-author-notes--run t)))
          (should (equal (mapcar #'car (sp-author-notes--run-created run)) '("Bo Roe")))
          (should (string-match-p "pub-author :: Ann Lee" (sp-author-notes-test--read a)))))
      ;; dropping a file: not read or changed
      (sp-author-notes-test--write a "#+title: x" "" "- pub-authro :: Cy Poe" "")
      (let ((sp-author-notes--excluded (list a)))
        (let ((run (sp-author-notes--run nil)))
          (should (null (sp-author-notes--run-pending run)))
          (should (null (sp-author-notes--run-litnotes run)))
          (with-temp-buffer
            (sp-author-notes--render run)
            (should (string-match-p "Dropped from the list (u brings one back) (1)" (buffer-string)))))))))

(ert-deftest sp-author-notes-test-report-keys ()
  "The old view: d, u and RET work on the report lines."
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--write (expand-file-name "litnotes/a.org" vault)
                                 "#+title: x" "" "- pub-author :: Ann Lee" "")
    (let ((sp-author-notes--excluded nil) (sp-batch-report-interface 'old))
      (sp-author-notes-dryrun)
      (with-current-buffer sp-author-notes--buffer-name
        (goto-char (point-min))
        (re-search-forward "^  Ann Lee$")
        (sp-author-notes-exclude)
        (should (equal sp-author-notes--excluded '("name:ann lee")))
        (goto-char (point-min))
        (re-search-forward "^  author ann lee$")
        (sp-author-notes-restore)
        (should (null sp-author-notes--excluded))))))

(ert-deftest sp-author-notes-test-apply-in-slices ()
  "The commands read and write from timers, and the result equals the one-go run."
  (sp-author-notes-test--with-vault
    (let ((sp-async-work-synchronous nil) (sp-async-work-slice 0.001))
      (dotimes (i 25)
        (sp-author-notes-test--write
         (expand-file-name (format "litnotes/l%d.org" i) vault)
         ":PROPERTIES:" (format ":ID: l%d" i) ":END:" "#+title: x" ""
         (format "- pub-author :: Author%d Name" i) ""))
      (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
        (sp-author-notes-dryrun)
        (should (sp-async-work-find "Author notes"))
        (let ((limit (+ (float-time) 30)))
          (while (and sp-async-work--jobs (< (float-time) limit)) (sit-for 0.02)))
        (with-current-buffer sp-author-notes--buffer-name
          (should (string-match-p "Author7 Name" (buffer-string))))
        (should-not (file-exists-p (expand-file-name "new-1.org" vault)))
        (sp-author-notes-convert)
        (let ((limit (+ (float-time) 30)))
          (while (and sp-async-work--jobs (< (float-time) limit)) (sit-for 0.02)))
        (should (string-match-p "pub-author :: \\[\\[id:new-"
                                (sp-author-notes-test--read (expand-file-name "litnotes/l24.org" vault))))
        (let ((sp-async-work-synchronous t))
          (should (= 0 (sp-author-notes--change-count (sp-author-notes--run nil)))))))))


(ert-deftest sp-author-notes-test-fold-and-latex ()
  (should (equal (sp-author-notes-fold-diacritics "Søren Bulată Ștefan Țepeș Lund") "Soren Bulata Stefan Tepes Lund"))
  (should (equal (sp-author-notes-fold-diacritics "Łukasz Straße Æsop") "Lukasz Strasse AEsop"))
  (should (equal (sp-author-notes--title-key "  Soren   KIERKEGAARD ") (sp-author-notes--title-key "Søren Kierkegaard")))
  (should (equal (sp-author-notes--title-key "Ștefan Țepeș") (sp-author-notes--title-key "Stefan Tepes")))
  (should (equal (sp-author-notes-latex-to-unicode "S{\\o}ren") "S{ø}ren"))
  (should (equal (sp-author-notes-latex-to-unicode "Bulat{\\u a}") "Bulat{ă}"))
  (should (equal (sp-author-notes-latex-to-unicode "\\c{S}tefan \\c t") "Ștefan ț"))
  (should (equal (sp-author-notes-latex-to-unicode "\\'{\\i}\\^a G\\\"odel \\aa") "íâ Gödel å"))
  (should (equal (sp-author-notes--clean-name "Kierkegaard, S{\\o}ren") "Søren Kierkegaard"))
  ;; the cedilla s and t become the comma-below ones
  (should (equal (sp-author-notes-latex-to-unicode "Ştefan Ţepeş") "Ștefan Țepeș")))

(ert-deftest sp-author-notes-test-accent-insensitive-link ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--person vault "Søren Kierkegaard" "p1")
    (sp-author-notes-test--write
     (expand-file-name "litnotes/a.org" vault)
     ":PROPERTIES:" ":ID: l1" ":END:" "#+title: x" ""
     "- pub-author :: Soren Kierkegaard" "")
    (let ((run (sp-author-notes--run t)))
      (should-not (sp-author-notes--run-created run))
      (should (string-match-p "\\[\\[id:p1\\]\\[Soren Kierkegaard\\]\\]"
                              (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault)))))))

(ert-deftest sp-author-notes-test-duplicate-spellings-ask ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--person vault "Søren Kierkegaard" "p1")
    (sp-author-notes-test--person vault "Soren Kierkegaard" "p2")
    (sp-author-notes-test--write
     (expand-file-name "litnotes/a.org" vault)
     ":PROPERTIES:" ":ID: l1" ":END:" "#+title: x" ""
     "- pub-author :: S{\\o}ren Kierkegaard" "")
    ;; the preview only reports
    (let ((run (sp-author-notes--run nil)))
      (should (seq-some (lambda (p) (string-match-p "titled alike" (nth 2 p)))
                        (sp-author-notes--run-problems run))))
    (let ((sp-author-notes-duplicate-function
           (lambda (entries) (seq-find (lambda (e) (equal (plist-get e :id) "p1")) entries))))
      (sp-author-notes--run t)
      (should (string-match-p "\\[\\[id:p1\\]\\[Søren Kierkegaard\\]\\]"
                              (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault)))))))

(ert-deftest sp-author-notes-test-normalize-duplicates ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--person vault "Søren Kierkegaard" "p1")
    (sp-author-notes-test--person vault "Soren Kierkegaard" "p2")
    (sp-author-notes-test--write
     (expand-file-name "litnotes/a.org" vault)
     ":PROPERTIES:" ":ID: l1" ":END:" "#+title: x" ""
     "- pub-author :: [[id:p2][Soren Kierkegaard]]"
     "- pub-editor :: [[id:p2][Soren Kierkegaard]], [[id:other][Other]]" "")
    (let ((sp-author-notes-duplicate-function
           (lambda (entries) (seq-find (lambda (e) (equal (plist-get e :id) "p1")) entries))))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
        (sp-author-notes-normalize-duplicates))
      (let ((text (sp-author-notes-test--read (expand-file-name "litnotes/a.org" vault))))
        (should (string-match-p "- pub-author :: \\[\\[id:p1\\]\\[Søren Kierkegaard\\]\\]\n" text))
        (should (string-match-p "- pub-editor :: \\[\\[id:p1\\]\\[Søren Kierkegaard\\]\\], \\[\\[id:other\\]\\[Other\\]\\]" text))))))

;;;; Works table of one author note

(ert-deftest sp-author-notes-test-works-convert ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--person vault "Ann Lee" "ann" "* Basics" "bio")
    (let ((file (expand-file-name "ann.org" vault)))
      (with-current-buffer (find-file-noselect file)
        (unwind-protect
            (progn
              ;; the dry run writes nothing and says what would be added
              (let ((msg (sp-author-notes--works-run nil)))
                (should (string-match-p "would add the Works heading, the table" msg)))
              (should-not (string-match-p "BEGIN" (sp-author-notes-test--read file)))
              ;; convert adds the lint's heading and block, fills it, backs up
              (let ((msg (sp-author-notes--works-run t)))
                (should (string-match-p "added the Works heading, the table" msg)))
              (should (string-match-p
                       "\\* Basics\nbio\n\n\\* Works\n\n#\\+BEGIN: collection-query-table :parent-of \"self\" :parent-prop \"pub-author\"[^\n]*\nFILLED\n#\\+END:"
                       (sp-author-notes-test--read file)))
              (should (file-exists-p (expand-file-name "backups/" vault)))
              ;; idempotent
              (let ((text (sp-author-notes-test--read file)))
                (should (string-match-p "headings and tables are there"
                                        (sp-author-notes--works-run t)))
                (should (equal text (sp-author-notes-test--read file)))))
          (kill-buffer))))))

(ert-deftest sp-author-notes-test-works-needs-author-note ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--write
     (expand-file-name "x.org" vault)
     ":PROPERTIES:" ":ID: x" ":END:" "#+title: X" "")
    (with-current-buffer (find-file-noselect (expand-file-name "x.org" vault))
      (unwind-protect
          (should-error (sp-author-notes--works-run t) :type 'user-error)
        (kill-buffer)))))

(ert-deftest sp-author-notes-test-edited-table-only-for-editors ()
  (with-temp-buffer
    (insert "#+title: X\n")
    (should (equal (sp-author-notes--person-pass) '(basics works table)))
    (should-not (sp-author-notes--has-table-p "pub-editor")))
  (with-temp-buffer
    (insert "#+title: X\n")
    (should (equal (sp-author-notes--person-pass t)
                   '(basics works table edited-heading edited-table)))
    (should (string-match-p ":parent-prop \"pub-editor\" :except-prop \"pub-author\""
                            (buffer-string)))
    (should (sp-author-notes--has-table-p "pub-editor"))
    (should (null (sp-author-notes--person-pass t)))))

(ert-deftest sp-author-notes-test-lint-edited-table-follows-pub-editor ()
  (sp-author-notes-test--with-vault
    (sp-author-notes-test--person vault "Ann Lee" "ann")
    (sp-author-notes-test--person vault "Bo Roe" "bo")
    (sp-author-notes-test--write
     (expand-file-name "litnotes/a.org" vault)
     ":PROPERTIES:" ":ID: l1" ":END:" "#+title: a" ""
     "- pub-author :: [[id:ann][Ann Lee]]"
     "- pub-editro :: [[id:bo][Bo Roe]]" "")
    (sp-author-notes--run t)
    (should-not (string-match-p "pub-editor"
                                (sp-author-notes-test--read (expand-file-name "ann.org" vault))))
    (should (string-match-p "\\* Edited works"
                            (sp-author-notes-test--read (expand-file-name "bo.org" vault))))))

(ert-deftest sp-author-notes-test-batch-report-keys ()
  "The shared view: entries are links, d drops by key, u restores, A applies the rest."
  (sp-author-notes-test--with-vault
    (let ((file (expand-file-name "litnotes/a.org" vault)))
      (sp-author-notes-test--write file "#+title: x" "" "- pub-authro :: Ann Lee" "")
      (let ((sp-author-notes--excluded nil) (sp-batch-report-interface 'new))
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (sp-author-notes-dryrun))
        (with-current-buffer sp-author-notes--buffer-name
          (should (derived-mode-p 'sp-batch-report-mode))
          (should (functionp sp-batch-report-apply-function))
          (should (string-match-p (format "\\[\\[file:%s::3\\]\\[litnotes/a\\.org:3\\]\\]  pub-authro"
                                          (regexp-quote file))
                                  (buffer-string)))
          ;; a candidate author is dropped by name
          (goto-char (point-min))
          (re-search-forward "^- Ann Lee")
          (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
            (sp-batch-report-drop))
          (should (equal sp-author-notes--excluded '("name:ann lee")))
          (with-current-buffer sp-author-notes--buffer-name
            (should (string-match-p "Dropped from the list (u brings one back) (1)" (buffer-string)))
            (should (string-match-p "^- author ann lee" (buffer-string)))
            (goto-char (point-min))
            (re-search-forward "^- author ann lee")
            (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
              (sp-batch-report-restore))
            (should (null sp-author-notes--excluded))))))))
