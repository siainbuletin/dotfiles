;;; sp-author-notes-test.el --- Tests for sp-author-notes -*- lexical-binding: t; -*-

(require 'ert)
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
      (should (string-match-p "#\\+title: X\n\n\\* Basics\n\n\\* Works\n\n#\\+BEGIN: collection-query-table :parent-of \"self\" :parent-prop \"pub-author\" :fold-tag \"booksection\" :fold-prop \"bib-parent\" :columns (:title :sections \"read-status\" \"read-priority\" \"pub-year\" \"relevance-factor\") :sort-by \"pub-year\"\n#\\+END:\n\n\\* Bio\ntext\n" text))
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
    (should (equal (sp-author-notes--person-pass) '(moved-works table)))
    (let ((text (buffer-string)))
      (should (string-match-p "\\* Bio\n\n?\\* Basics\nb\n\n\\* Works\nmine\n\n#\\+BEGIN: [^\n]*\n#\\+END:\n\n\\*\\* Sub\n\n\\* After\n" text))
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
      (let ((sp-author-notes-redirect-function (lambda (&rest _) nil)))
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
