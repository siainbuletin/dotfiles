;;; sp-author-notes-bibtex-test.el --- Tests for sp-author-notes-bibtex -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-async-work)
(setq sp-async-work-synchronous t)
(require 'sp-author-notes-bibtex)

(defvar sp-bibtex-files)

(defun sp-an-bib-test--write (file &rest lines)
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert (string-join lines "\n") "\n")))

(defmacro sp-an-bib-test--with-vault (&rest body)
  "Run BODY with a vault and a .bib file; `create-fn' makes a litnote."
  (declare (indent 0))
  `(let* ((vault (file-name-as-directory (make-temp-file "sp-bib" t)))
          (sp-author-notes-directory vault)
          (sp-author-notes-litnotes-directory (expand-file-name "litnotes/" vault))
          (bib (expand-file-name "refs.bib" vault))
          (sp-bibtex-files (list bib))
          (sp-author-notes-bibtex-create-function
           (lambda (key)
             (sp-an-bib-test--write
              (expand-file-name (format "litnotes/%s.org" key) vault)
              ":PROPERTIES:" (format ":ID: lit-%s" key) ":END:"
              (format "#+title: %s" key) "#+filetags: :litnote:" ""
              "- pub-year :: 2020" "" "* Notes" "text"))))
     (unwind-protect
         (progn
           (sp-an-bib-test--write bib
            "@article{smith2020attention,"
            "  author = {Smith, John and Doe, Jane},"
            "  title = {{Attention} is something},"
            "  year = {2020}}"
            "@book{smith2018other,"
            "  author = \"J. Smith\","
            "  title = {Other},"
            "  year = {2018}}"
            "@article{doe2019covered,"
            "  author = {Doe, Jane}, title = {Covered}, year = {2019}}")
           (sp-an-bib-test--write
            (expand-file-name "p1.org" vault)
            ":PROPERTIES:" ":ID: p-smith" ":END:" "#+title: John Smith" "#+filetags: :person:" "")
           (sp-an-bib-test--write
            (expand-file-name "p2.org" vault)
            ":PROPERTIES:" ":ID: p-doe" ":END:" "#+title: Jane Doe" "#+filetags: :person:" "")
           (sp-an-bib-test--write
            (expand-file-name "litnotes/doe.org" vault)
            ":PROPERTIES:" ":ID: lit-doe" ":REFERENCES: @doe2019covered" ":END:"
            "#+title: Covered" "")
           ,@body)
       (delete-directory vault t))))

(ert-deftest sp-an-bib-test-match ()
  (should (eq 'exact (sp-author-notes-bibtex--match "John Smith" "John Smith")))
  (should (eq 'possible (sp-author-notes-bibtex--match "John Smith" "J. Smith")))
  (should-not (sp-author-notes-bibtex--match "John Smith" "Mary Smith"))
  (should-not (sp-author-notes-bibtex--match "John Smith" "John Smithers")))

(ert-deftest sp-an-bib-test-compute ()
  (sp-an-bib-test--with-vault
    (let* ((groups (sp-author-notes-bibtex--compute))
           (titles (mapcar (lambda (g) (plist-get (car g) :title)) groups)))
      ;; Jane Doe's own entry has a litnote, but she co-wrote the other one.
      (should (equal titles '("John Smith" "Jane Doe")))
      (should (equal (mapcar (lambda (m) (plist-get (car m) :key)) (cdr (cadr groups)))
                     '("smith2020attention")))
      (should (equal (mapcar (lambda (m) (cons (plist-get (car m) :key) (cdr m)))
                             (cdar groups))
                     '(("smith2018other" . possible) ("smith2020attention" . exact)))))))

(ert-deftest sp-an-bib-test-create-and-link ()
  (sp-an-bib-test--with-vault
    (let* ((groups (sp-author-notes-bibtex--compute))
           (person (caar groups))
           (entry (car (nth 1 (cdar groups))))
           (file (sp-author-notes-bibtex--create person entry))
           (text (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (should (string-match-p "^- pub-author :: \\[\\[id:p-smith\\]\\[John Smith\\]\\]$" text))
      (should (< (string-match "pub-year" text) (string-match "pub-author" text)))
      (should (< (string-match "pub-author" text) (string-match "\\* Notes" text)))
      ;; The entry is covered now.
      (should (equal (mapcar (lambda (m) (plist-get (car m) :key)) (cdar (sp-author-notes-bibtex--compute)))
                     '("smith2018other"))))))

(ert-deftest sp-an-bib-test-report ()
  (sp-an-bib-test--with-vault
    (save-window-excursion
      (sp-author-notes-bibtex)
      (with-current-buffer sp-author-notes-bibtex--buffer-name
        (should (string-match-p "John Smith  (2)" (buffer-string)))
        (should (string-match-p "exact +smith2020attention" (buffer-string)))
        (goto-char (point-min))
        (search-forward "smith2020attention")
        (should (plist-get (sp-author-notes-bibtex--at-point) :key))
        (kill-buffer)))))

(ert-deftest sp-an-bib-test-no-files ()
  (let ((sp-bibtex-files nil) (sp-bibliography-dir "/nonexistent/bib/"))
    (should-error (sp-author-notes-bibtex--files) :type 'user-error))
  (let ((sp-bibtex-files '("/nonexistent/master.bib")))
    (let ((err (should-error (sp-author-notes-bibtex--files) :type 'user-error)))
      (should (string-match-p "master.bib" (cadr err))))))

(ert-deftest sp-an-bib-test-missing-file-skipped ()
  (sp-an-bib-test--with-vault
    (let ((sp-bibtex-files (list "/nonexistent/master.bib" bib)))
      (should (equal (sp-author-notes-bibtex--files) (list bib)))
      (should (= 2 (length (sp-author-notes-bibtex--compute)))))))

(ert-deftest sp-an-bib-test-many-people-is-fast ()
  "Thousands of people against thousands of entries must not be quadratic."
  (sp-an-bib-test--with-vault
    (with-temp-file bib
      (dotimes (i 3000)
        (insert (format "@article{k%d,\n  author = {Last%d, First%d},\n  title = {T},\n  year = {2000}}\n" i i i))))
    (dotimes (i 1500)
      (sp-an-bib-test--write (expand-file-name (format "q%d.org" i) vault)
                             ":PROPERTIES:" (format ":ID: q%d" i) ":END:"
                             (format "#+title: First%d Last%d" i i) "#+filetags: :person:" ""))
    (let* ((start (float-time))
           (groups (sp-author-notes-bibtex--compute)))
      (should (= 1500 (length groups)))
      (should (< (- (float-time) start) 20)))))

(provide 'sp-author-notes-bibtex-test)
;;; sp-author-notes-bibtex-test.el ends here

(ert-deftest sp-an-bib-test-editor-only-entry ()
  (sp-an-bib-test--with-vault
    (with-temp-file bib
      (insert "@book{smith2021volume,\n  editor = {Smith, John}, title = {Volume}, year = {2021}}\n"))
    (let* ((groups (sp-author-notes-bibtex--compute))
           (smith (assoc "John Smith" groups
                         (lambda (g n) (equal (plist-get g :title) n))))
           (entry (car (car (cdr smith)))))
      (should (equal (plist-get entry :key) "smith2021volume"))
      (should (equal (sp-author-notes-bibtex--role-key (car smith) entry) "pub-editor")))))

;;; One author

(require 'sp-batch-report)

(defun sp-an-bib-test--person (vault name &rest aliases)
  "The person plist of the note NAME written in VAULT, with ALIASES."
  (let ((file (expand-file-name "me.org" vault)))
    (apply #'sp-an-bib-test--write
           file ":PROPERTIES:" ":ID: p-me"
           (append (when aliases
                     (list (format ":ROAM_ALIASES: %s"
                                   (mapconcat (lambda (a) (format "%S" a)) aliases " "))))
                   (list ":END:" (format "#+title: %s" name) "#+filetags: :person:" "")))
    (with-current-buffer (find-file-noselect file)
      (org-mode)
      (sp-author-notes-bibtex--current-person))))

(defun sp-an-bib-test--results (person)
  (sort (mapcar (lambda (r) (list (plist-get (plist-get r :entry) :key)
                                  (plist-get r :conf) (plist-get r :role) (plist-get r :status)))
                (sp-author-notes-bibtex--author-compute person))
        (lambda (a b) (string< (car a) (car b)))))

(ert-deftest sp-an-bib-test-author-needs-an-author-note ()
  (with-temp-buffer
    (org-mode)
    (should-error (sp-author-notes-bibtex--current-person) :type 'user-error)))

(ert-deftest sp-an-bib-test-author-forms-and-statuses ()
  (sp-an-bib-test--with-vault
    (let ((person (sp-an-bib-test--person vault "Jane Doe" "J. Doe-Smith")))
      (should (equal (plist-get person :forms) '("Jane Doe" "J. Doe-Smith")))
      ;; doe2019covered has a litnote that does not link to Jane yet.
      (should (equal (sp-an-bib-test--results person)
                     '(("doe2019covered" exact "pub-author" unlinked)
                       ("smith2020attention" exact "pub-author" new))))
      ;; Once the litnote links to her, the work is already in the note.
      (sp-an-bib-test--write
       (expand-file-name "litnotes/doe.org" vault)
       ":PROPERTIES:" ":ID: lit-doe" ":REFERENCES: @doe2019covered" ":END:"
       "#+title: Covered" "" "- pub-author :: [[id:p-me][Jane Doe]]" "")
      (should (eq 'linked (nth 3 (assoc "doe2019covered" (sp-an-bib-test--results person))))))))

(ert-deftest sp-an-bib-test-author-alias-and-editor ()
  (sp-an-bib-test--with-vault
    (with-temp-file bib
      (insert "@book{x2021volume,\n  editor = {Doe-Smith, J.}, title = {Volume}, year = {2021}}\n"
              "@book{y2021other,\n  author = {Doe, Mary}, title = {Other}, year = {2021}}\n"))
    (let ((person (sp-an-bib-test--person vault "Jane Doe" "J. Doe-Smith")))
      (should (equal (sp-an-bib-test--results person)
                     '(("x2021volume" exact "pub-editor" new)))))))

(ert-deftest sp-an-bib-test-author-report-order ()
  (sp-an-bib-test--with-vault
    (let* ((person (sp-an-bib-test--person vault "John Smith"))
           (results (sp-author-notes-bibtex--author-compute person))
           (text (sp-author-notes-bibtex--author-text person results nil)))
      (should (string-match "No litnote yet (exact name) (1)" text))
      (should (string-match "possible: surname and initials) (1)" text))
      (should (< (string-match "smith2020attention" text) (string-match "smith2018other" text)))
      (should (string-match "Already in this note (0)" text))
      (with-current-buffer (sp-author-notes-bibtex--author-show person results nil)
        (should (derived-mode-p 'sp-batch-report-mode))
        (goto-char (point-min))
        (search-forward "smith2020attention")
        (sp-batch-report-drop)
        (should (equal sp-batch-report-excluded '("smith2020attention")))
        (should (string-match-p "Dropped from the list" (buffer-string)))))))

(ert-deftest sp-an-bib-test-author-apply-adds-exact-only ()
  (sp-an-bib-test--with-vault
    (let* ((sp-author-notes-backup-directory (expand-file-name "backup/" vault))
           (person (sp-an-bib-test--person vault "John Smith"))
           (results (sp-author-notes-bibtex--author-compute person)))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
        ;; The possible match smith2018other is left out.
        (should (= 1 (sp-author-notes-bibtex--author-apply person results nil)))
        (let ((file (expand-file-name "litnotes/smith2020attention.org" vault)))
          (should (file-exists-p file))
          (should (string-match-p "- pub-author :: \\[\\[id:p-me\\]\\[John Smith\\]\\]"
                                  (with-temp-buffer (insert-file-contents file) (buffer-string)))))
        (should-not (file-exists-p (expand-file-name "litnotes/smith2018other.org" vault)))
        ;; The note got its Works heading.
        (should (string-match-p "^\\* Works"
                                (with-temp-buffer
                                  (insert-file-contents (expand-file-name "me.org" vault))
                                  (buffer-string))))
        ;; A dropped key is not added, even when the possible ones are allowed.
        (let ((sp-author-notes-bibtex-apply-possible t))
          (should (= 0 (sp-author-notes-bibtex--author-apply
                        person (sp-author-notes-bibtex--author-compute person)
                        '("smith2018other" "smith2020attention")))))))))
