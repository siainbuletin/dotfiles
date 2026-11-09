;;; sp-see-also-test.el --- Tests for sp-see-also -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-see-also-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(defvar sp-org-keywords-research)

(load (expand-file-name
       "../libraries/modules/academic/sp-see-also.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defun sp-see-also-test--text (&rest lines)
  "Return LINES joined with newlines."
  (concat (mapconcat #'identity lines "\n") "\n"))

(defconst sp-see-also-test--note
  (sp-see-also-test--text
   ":PROPERTIES:"
   ":ID: file-id"
   ":END:"
   "#+title: Litnote on X"
   "Intro with a reminder[fn::[[id:c-one][Concept one]]] in prose."
   "#+begin_quote"
   "A quoted passage[fn:q1:[[id:c-two][Concept two]] and [[id:c-three][three]]] here."
   "#+end_quote"
   "* QUESTION What is Y?"
   ":PROPERTIES:"
   ":ID: q-id"
   ":END:"
   "Prose under a question[fn::[[id:c-one][Concept one]]]."
   "** Sub heading"
   "Nested[fn::[[id:c-two][Two]]]."
   "* STABLE Closed one"
   "Answered[fn::[[id:c-three][three]]]."
   "* Plain"
   "Reference [fn:1] and a note[fn::no links here] are ignored."
   "#+begin_src emacs-lisp"
   "(message \"[fn::[[id:c-skip][Skip]]]\")"
   "#+end_src"
   "# a comment with [fn::[[id:c-skip][Skip]]]"
   "* Footnotes"
   "[fn:1] A definition."))

(defmacro sp-see-also-test--with-vault (&rest body)
  "Run BODY with a temporary folder in `root', the cache and the files there."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "sp-see-also" t)))
          (sp-see-also-cache-file (expand-file-name "cache.eld" root))
          (sp-see-also-directory (expand-file-name "litnotes/" root))
          (sp-see-also-files-function #'sp-see-also-default-files)
          (sp-see-also-use-db nil)
          (sp-see-also--files nil)
          (sp-see-also--signature nil)
          (sp-see-also--dirty nil)
          (sp-see-also--save-timer nil)
          (sp-see-also--index nil))
     (make-directory sp-see-also-directory t)
     (unwind-protect (progn ,@body)
       (delete-directory root t))))

(defun sp-see-also-test--write (root name text)
  "Write TEXT to the litnote NAME below ROOT and return its path."
  (let ((path (expand-file-name name (expand-file-name "litnotes/" root))))
    (with-temp-file path (insert text))
    path))

(defun sp-see-also-test--summary (mentions)
  "Return (ID WHERE QUESTION OPEN) for each of MENTIONS."
  (mapcar (lambda (m) (list (plist-get m :id) (plist-get m :where)
                            (plist-get m :question) (plist-get m :open)))
          mentions))

(ert-deftest sp-see-also-parse-context ()
  (with-temp-buffer
    (insert sp-see-also-test--note)
    (should (equal (sp-see-also-test--summary (sp-see-also-mentions-in-buffer))
                   '(("c-one" prose nil nil)
                     ("c-two" quote nil nil)
                     ("c-three" quote nil nil)
                     ("c-one" prose "QUESTION" t)
                     ("c-two" prose "QUESTION" t)
                     ("c-three" prose "STABLE" nil))))))

(ert-deftest sp-see-also-parse-details ()
  (with-temp-buffer
    (insert sp-see-also-test--note)
    (let* ((footnotes (sp-see-also-parse-buffer))
           (quoted (nth 1 footnotes))
           (nested (nth 3 footnotes)))
      (should (= (length footnotes) 5))
      (should (equal (plist-get quoted :label) "q1"))
      (should (equal (plist-get quoted :links) '(("c-two" . "Concept two") ("c-three" . "three"))))
      (should (equal (plist-get nested :heading) "Sub heading"))
      (should (equal (plist-get nested :heading-id) "q-id"))
      (should (equal (plist-get nested :question-title) "What is Y?"))
      (should (string-match-p "\\`Nested" (plist-get nested :snippet)))
      (should-not (string-match-p "\\[" (plist-get nested :snippet))))))

(ert-deftest sp-see-also-parse-leaves-the-buffer-alone ()
  (with-temp-buffer
    (insert sp-see-also-test--note)
    (goto-char 20)
    (narrow-to-region 10 40)
    (sp-see-also-parse-buffer)
    (should (= (point) 20))
    (should (= (point-min) 10))
    (should (= (point-max) 40))))

(ert-deftest sp-see-also-parse-agrees-with-org-element ()
  (with-temp-buffer
    (insert sp-see-also-test--note)
    (let ((ours (mapcar (lambda (f) (cons (plist-get f :beg) (plist-get f :end)))
                        (sp-see-also--footnotes-raw
                         (car (sp-see-also--block-ranges)))))
          theirs)
      (delay-mode-hooks (org-mode))
      (org-element-map (org-element-parse-buffer) 'footnote-reference
        (lambda (ref)
          (when (eq (org-element-property :type ref) 'inline)
            (push (cons (org-element-property :begin ref)
                        (- (org-element-property :end ref)
                           (org-element-property :post-blank ref)))
                  theirs))))
      (should (= (length ours) 6))
      (should (equal ours (nreverse theirs))))))

(ert-deftest sp-see-also-parse-needs-no-org-mode ()
  (with-temp-buffer
    (insert sp-see-also-test--note)
    (should-not (derived-mode-p 'org-mode))
    (sp-see-also-parse-buffer)
    (should-not (derived-mode-p 'org-mode))))

(ert-deftest sp-see-also-parse-skips-unbalanced-and-blank-line ()
  (with-temp-buffer
    (insert (sp-see-also-test--text
             "An open one[fn::[[id:a][A]] with no end"
             ""
             "next paragraph] and =[fn::[[id:b][B]]]= verbatim"
             "Fine[fn::[[id:c][C]]]."))
    (should (equal (mapcar (lambda (m) (plist-get m :id)) (sp-see-also-mentions-in-buffer))
                   '("c")))))

(ert-deftest sp-see-also-states-follow-the-keywords ()
  (let ((sp-org-keywords-research '((sequence "ASK" "DIG(d)" "|" "DONE")
                                    (sequence "ACTIVE" "|" "ARCHIVED"))))
    (should (equal (sp-see-also--states) '(("ASK" "DIG") . ("DONE"))))
    (with-temp-buffer
      (insert (sp-see-also-test--text "* DIG a question" "Text[fn::[[id:a][A]]]"))
      (should (equal (plist-get (car (sp-see-also-mentions-in-buffer)) :question) "DIG"))
      (should (plist-get (car (sp-see-also-mentions-in-buffer)) :open)))))

(ert-deftest sp-see-also-file-data-is-cached ()
  (sp-see-also-test--with-vault
    (let* ((file (sp-see-also-test--write root "a.org" sp-see-also-test--note))
           (reads 0))
      (cl-letf* ((original (symbol-function 'sp-see-also--scan-file))
                 ((symbol-function 'sp-see-also--scan-file)
                  (lambda (&rest args) (setq reads (1+ reads)) (apply original args))))
        (should (equal (plist-get (sp-see-also-file-data file) :title) "Litnote on X"))
        (should (equal (plist-get (sp-see-also-file-data file) :id) "file-id"))
        (sp-see-also-file-data file)
        (should (= reads 1))
        ;; A new process reads the cache file instead of the note.
        (sp-see-also--save-if-dirty)
        (setq sp-see-also--files nil sp-see-also--signature nil)
        (sp-see-also-file-data file)
        (should (= reads 1))
        ;; A changed file is read again.
        (with-temp-file file (insert (sp-see-also-test--text "Now[fn::[[id:z][Z]]]")))
        (sp-see-also-file-data file)
        (should (= reads 2))
        (should (equal (mapcar (lambda (m) (plist-get m :id))
                               (plist-get (sp-see-also-file-data file) :mentions))
                       '("z")))))))

(ert-deftest sp-see-also-file-data-reads-no-buffer ()
  (sp-see-also-test--with-vault
    (let ((file (sp-see-also-test--write root "a.org" sp-see-also-test--note))
          (before (buffer-list)))
      (sp-see-also-file-data file)
      (should (equal (buffer-list) before))
      (should-not (get-file-buffer file)))))

(ert-deftest sp-see-also-file-data-prefers-unsaved-buffer ()
  (sp-see-also-test--with-vault
    (let* ((file (sp-see-also-test--write root "a.org" (sp-see-also-test--text "Nothing")))
           (buffer (find-file-noselect file)))
      (unwind-protect
          (progn
            (with-current-buffer buffer (insert "Typed[fn::[[id:t][T]]]\n"))
            (should (equal (mapcar (lambda (m) (plist-get m :id))
                                   (plist-get (sp-see-also-file-data file) :mentions))
                           '("t")))
            (should-not (gethash file sp-see-also--files)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(ert-deftest sp-see-also-cache-resets-when-keywords-change ()
  (sp-see-also-test--with-vault
    (let ((file (sp-see-also-test--write root "a.org" sp-see-also-test--note)))
      (let ((sp-org-keywords-research '((sequence "QUESTION" "|" "STABLE"))))
        (sp-see-also-file-data file)
        (should (= (hash-table-count sp-see-also--files) 1)))
      (let ((sp-org-keywords-research '((sequence "ASK" "|" "STABLE"))))
        (sp-see-also-file-data file)
        (should (= (hash-table-count sp-see-also--files) 1))
        (should-not (plist-get (car (plist-get (sp-see-also-file-data file) :mentions))
                               :open))))))

(ert-deftest sp-see-also-concepts-rank-by-weight ()
  (sp-see-also-test--with-vault
    (let* ((file (sp-see-also-test--write root "a.org" sp-see-also-test--note))
           (concepts (sp-see-also-concepts-for-file file)))
      ;; c-one: prose 1 + (prose 1 + QUESTION 3) = 5; c-two: quote 2 + (prose 1 + 3) = 6;
      ;; c-three: quote 2 + closed prose 1 = 3.
      (should (equal (mapcar (lambda (c) (plist-get c :id)) concepts)
                     '("c-two" "c-one" "c-three")))
      (should (equal (mapcar (lambda (c) (plist-get c :score)) concepts) '(6.0 5.0 3.0)))
      (should (equal (plist-get (car concepts) :title) "Concept two"))
      (should (= (plist-get (car concepts) :quotes) 1))
      (should (= (plist-get (car concepts) :questions) 1)))))

(ert-deftest sp-see-also-score-function-is-replaceable ()
  (sp-see-also-test--with-vault
    (let* ((file (sp-see-also-test--write root "a.org" sp-see-also-test--note))
           (sp-see-also-concept-score-function
            (lambda (id _mentions _context) (if (equal id "c-three") 100 1))))
      (should (equal (plist-get (car (sp-see-also-concepts-for-file file)) :id) "c-three")))))

(ert-deftest sp-see-also-questions-for-file ()
  (sp-see-also-test--with-vault
    (let* ((file (sp-see-also-test--write root "a.org" sp-see-also-test--note))
           (questions (sp-see-also-questions-for-file file)))
      (should (= (length questions) 1))
      (should (equal (plist-get (car questions) :keyword) "QUESTION"))
      (should (equal (plist-get (car questions) :title) "What is Y?"))
      (should (= (plist-get (car questions) :count) 2))
      (should (equal (plist-get (car questions) :concepts) '("c-one" "c-two")))
      (should (= (plist-get (car questions) :priority) 6.0)))))

(ert-deftest sp-see-also-other-litnotes-raise-the-score ()
  (sp-see-also-test--with-vault
    (let ((a (sp-see-also-test--write root "a.org" (sp-see-also-test--text "x[fn::[[id:k][K]]]")))
          (b (sp-see-also-test--write root "b.org" (sp-see-also-test--text "y[fn::[[id:k][K]]]"))))
      (let ((alone (plist-get (car (sp-see-also-concepts-for-file a)) :score)))
        (should-not (plist-get (car (sp-see-also-concepts-for-file a)) :other-litnotes))
        (sp-see-also-index t)
        (let ((shared (car (sp-see-also-concepts-for-file a))))
          (should (= (plist-get shared :other-litnotes) 1))
          (should (> (plist-get shared :score) alone)))
        (should (= (length (sp-see-also-concept-usage "k")) 2))
        (should (member b (mapcar (lambda (e) (plist-get e :file))
                                  (sp-see-also-concept-usage "k"))))))))

(ert-deftest sp-see-also-concept-usage-and-table ()
  (sp-see-also-test--with-vault
    (sp-see-also-test--write root "a.org" sp-see-also-test--note)
    (sp-see-also-test--write root "b.org" (sp-see-also-test--text
                                           ":PROPERTIES:" ":ID: b-id" ":END:"
                                           "#+title: Second" "One[fn::[[id:c-one][C | one]]]"))
    (let ((usage (sp-see-also-concept-usage "c-one")))
      (should (equal (mapcar (lambda (e) (plist-get e :title)) usage)
                     '("Litnote on X" "Second")))
      (should (equal (mapcar (lambda (e) (length (plist-get e :mentions))) usage) '(2 1)))
      (let ((table (sp-see-also-usage-table usage)))
        (should (string-match-p "\\[\\[id:file-id\\]\\[Litnote on X\\]\\]" table))
        (should (string-match-p "| QUESTION What is Y\\? |" table))
        (should (= (length (split-string table "\n")) 5)))
      (should (= (length (sp-see-also--filter-usage usage 'quote nil)) 0))
      (should (= (length (sp-see-also--filter-usage usage nil t)) 1)))))

(ert-deftest sp-see-also-dblock-writes-the-table ()
  (sp-see-also-test--with-vault
    (sp-see-also-test--write root "a.org" sp-see-also-test--note)
    (with-temp-buffer
      (org-dblock-write:concept-usage '(:id "c-two" :where quote))
      (should (string-match-p "| quote |" (buffer-string)))
      (should-not (string-match-p "| prose |" (buffer-string))))
    (with-temp-buffer
      (org-dblock-write:concept-usage '(:id "nobody"))
      (should (string-match-p "No litnote" (buffer-string))))))

(provide 'sp-see-also-test)
;;; sp-see-also-test.el ends here
