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

(defconst sp-see-also-test--definition-note
  (sp-see-also-test--text
   "#+title: Real litnote"
   "#+filetags: :booksection:litnote:"
   ""
   "* Notes"
   "Un obiect[fn:1] clar[fn:2] fara legatura[fn:3]."
   "#+begin_quote"
   "Citat[fn:4]"
   "#+end_quote"
   ""
   "* Footnotes"
   "[fn:1] Dar de ce? Vezi [[id:d-one][Renastere]] si"
   "inca o linie cu [[id:d-two][Doi]]."
   "[fn:2] Cu [[id:d-one][Renastere]]."
   ""
   "[fn:3] Fara legaturi."
   "[fn:4] Un citat despre [[id:d-two][Doi]]."))

(ert-deftest sp-see-also-parse-definition-footnotes ()
  (with-temp-buffer
    (insert sp-see-also-test--definition-note)
    (let ((footnotes (sp-see-also-parse-buffer)))
      (should (equal (mapcar (lambda (f) (plist-get f :label)) footnotes) '("1" "2" "4")))
      (should (equal (plist-get (car footnotes) :links)
                     '(("d-one" . "Renastere") ("d-two" . "Doi"))))
      (should (equal (buffer-substring (plist-get (car footnotes) :beg)
                                       (plist-get (car footnotes) :end))
                     "[fn:1]"))
      (should (eq (plist-get (nth 2 footnotes) :where) 'quote))
      (should (equal (plist-get (car footnotes) :heading) "Notes"))
      (should (string-match-p "Un obiect" (plist-get (car footnotes) :snippet))))))

(ert-deftest sp-see-also-definition-without-reference ()
  (with-temp-buffer
    (insert "[fn:9] Orphan with [[id:o][O]].\n")
    (let ((f (car (sp-see-also-parse-buffer))))
      (should (= (plist-get f :beg) 1))
      (should (equal (plist-get f :label) "9")))))

(ert-deftest sp-see-also-concepts-for-definition-litnote ()
  (sp-see-also-test--with-vault
    (let* ((file (sp-see-also-test--write root "real.org" sp-see-also-test--definition-note))
           (concepts (sp-see-also-concepts-for-file file)))
      (should (equal (mapcar (lambda (c) (plist-get c :id)) concepts) '("d-two" "d-one")))
      (should (= (plist-get (car concepts) :quotes) 1))
      (should (= (length (sp-see-also-concept-usage "d-one")) 1)))))

(defconst sp-see-also-test--section-note
  (sp-see-also-test--text
   ":PROPERTIES:"
   ":ID: file-id"
   ":END:"
   "#+title: Litnote with sections"
   "Intro[fn::[[id:c-fn][Footnoted]]]."
   "* Entry with an id"
   ":PROPERTIES:"
   ":ID: entry-id"
   ":END:"
   "Body text."
   "** see Also"
   ":PROPERTIES:"
   ":ID: section-own-id"
   ":END:"
   "- [[id:s-one][Section one]] because of the method"
   "- [[id:s-two][Section two]] and [[id:s-three][three]]"
   "- A footnote in the list[fn::[[id:c-fn2][Inside]]]"
   "#+begin_src org"
   "[[id:s-skip][Skipped]]"
   "#+end_src"
   "# [[id:s-comment][Commented]]"
   "*** Deeper heading"
   "- [[id:s-deep][Deep]]"
   "* QUESTION Open one"
   "** See also"
   "- [[id:s-question][Under question]]"
   "* Last"
   "Not a section [[id:s-plain][Plain link]]."
   "* See also"
   "Plain text [[id:s-file][File level]]."))

(ert-deftest sp-see-also-section-links-are-mentions ()
  (with-temp-buffer
    (insert sp-see-also-test--section-note)
    (let ((mentions (sp-see-also-mentions-in-buffer)))
      (should (equal (mapcar (lambda (m) (plist-get m :id)) mentions)
                     '("c-fn" "s-one" "s-two" "s-three" "c-fn2" "s-deep"
                       "s-question" "s-file")))
      (should (equal (mapcar (lambda (m) (plist-get m :where)) mentions)
                     '(prose section section section prose section section section))))))

(ert-deftest sp-see-also-section-scope-is-the-parent ()
  (with-temp-buffer
    (insert sp-see-also-test--section-note)
    (let* ((mentions (sp-see-also-mentions-in-buffer))
           (one (nth 1 mentions))
           (deep (nth 5 mentions))
           (question (nth 6 mentions))
           (file-level (nth 7 mentions)))
      (should (equal (plist-get one :heading) "Entry with an id"))
      (should (equal (plist-get one :heading-id) "entry-id"))
      (should (equal (plist-get deep :heading-id) "entry-id"))
      (should (equal (plist-get one :snippet) "Section one because of the method"))
      (should (equal (plist-get question :question) "QUESTION"))
      (should (plist-get question :open))
      (should (null (plist-get file-level :heading-id)))
      (should (null (plist-get file-level :heading)))
      (should (equal (plist-get file-level :snippet) "Plain text File level.")))))

(ert-deftest sp-see-also-section-links-are-optional-for-the-parser ()
  (with-temp-buffer
    (insert sp-see-also-test--section-note)
    (should (equal (mapcar (lambda (f) (plist-get f :where)) (sp-see-also-parse-buffer))
                   '(prose prose)))
    (should (= (length (sp-see-also-parse-buffer nil t)) 8))))

(ert-deftest sp-see-also-section-links-reach-the-dashboards ()
  (sp-see-also-test--with-vault
    (let* ((file (sp-see-also-test--write root "sections.org" sp-see-also-test--section-note))
           (concepts (sp-see-also-concepts-for-file file))
           (usage (sp-see-also-concept-usage "s-one")))
      (should (member "s-file" (mapcar (lambda (c) (plist-get c :id)) concepts)))
      (should (= (length usage) 1))
      (should (equal (plist-get (car usage) :id) "file-id"))
      (should (eq (plist-get (car (plist-get (car usage) :mentions)) :where) 'section)))))

(ert-deftest sp-see-also-section-edit-is-read-again ()
  (sp-see-also-test--with-vault
    (let ((file (sp-see-also-test--write root "edit.org" "* Entry\n:PROPERTIES:\n:ID: e\n:END:\n")))
      (should (null (sp-see-also-concepts-for-file file)))
      (sleep-for 0.01)
      (with-temp-file file
        (insert "* Entry\n:PROPERTIES:\n:ID: e\n:END:\n** See also\n- [[id:n][New]]\n"))
      (set-file-times file (time-add (current-time) 5))
      (should (equal (mapcar (lambda (c) (plist-get c :id))
                             (sp-see-also-concepts-for-file file))
                     '("n"))))))

(ert-deftest sp-see-also-view-shows-headings-and-clickable-entries ()
  (sp-see-also-test--with-vault
    (let* ((file (sp-see-also-test--write root "view.org" sp-see-also-test--note))
           (visited nil))
      (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
                ((symbol-function 'sp-see-also-visit)
                 (lambda (f pos) (setq visited (cons f pos)))))
        (sp-see-also-show file)
       (with-current-buffer "*see-also*"
        (should (derived-mode-p 'sp-see-also-view-mode))
        (goto-char (point-min))
        (search-forward "Concept one")
        (should (eq (get-text-property (match-beginning 0) 'face)
                    'sp-see-also-file-heading))
        (search-forward "Intro with a reminder")
        (should (memq 'sp-see-also-match
                      (ensure-list (get-text-property (match-beginning 0) 'face))))
        (push-button (match-beginning 0))
        (should (equal (car visited) (expand-file-name file)))
        (should (integerp (cdr visited)))
        ;; TAB folds the context of the entry and folds it open again
        (sp-see-also-view-toggle)
        (should (sp-see-also-view--fold-at (point)))
        (sp-see-also-view-toggle)
        (should-not (sp-see-also-view--fold-at (point)))
        ;; n and p walk the headings
        (goto-char (point-min))
        (sp-see-also-view-next)
        (should (> (point) (point-min)))
        (sp-see-also-view-previous)
        (should (= (point) (point-min)))
        (revert-buffer)
        (should (> (buffer-size) 0))))
      (kill-buffer "*see-also*"))))

(ert-deftest sp-see-also-view-concept-by-name-picks-by-title ()
  (let (args shown)
    (cl-letf (((symbol-function 'sp-select-note)
               (lambda (&rest a) (setq args a) 'a-note))
              ((symbol-function 'vulpea-note-id)
               (lambda (n) (and (eq n 'a-note) "c-one")))
              ((symbol-function 'sp-see-also-show-concept)
               (lambda (id) (setq shown id))))
      (sp-see-also-show-concept-by-name)
      (should (equal shown "c-one"))
      (should (plist-get (cdr args) :grouped))
      (should (plist-get (cdr args) :require-match)))))

(ert-deftest sp-see-also-view-concept-groups-by-litnote ()
  (sp-see-also-test--with-vault
    (sp-see-also-test--write root "view.org" sp-see-also-test--note)
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-see-also-show-concept "c-one"))
    (with-current-buffer "*see-also-concept*"
      (goto-char (point-min))
      (search-forward "Litnote on X")
      (should (eq (get-text-property (match-beginning 0) 'face)
                  'sp-see-also-file-heading))
      (should (search-forward "Prose under a question" nil t)))
    (kill-buffer "*see-also-concept*")))

(provide 'sp-see-also-test)
;;; sp-see-also-test.el ends here
