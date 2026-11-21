;;; thesis-desk-test.el --- Tests for thesis-desk -*- lexical-binding: t; -*-

;; Run from the dotfiles root:
;;   emacs -Q --batch -L thesis-desk/.local/share/thesis-desk/lisp \
;;     -l thesis-desk/tests/thesis-desk-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'thesis-desk)

(defmacro thesis-desk-test--with-dir (&rest body)
  "Run BODY with `thesis-desk-directory' in a fresh temporary folder."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "thesis-desk-test" t))
          (thesis-desk-directory (file-name-as-directory dir))
          (thesis-desk-clock nil)
          (thesis-desk-claim-sources (list #'thesis-desk-map-claims))
          (org-id-locations-file (expand-file-name "ids" dir))
          (org-id-track-globally nil))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b) (string-prefix-p dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory dir t))))

;;;; DEVONthink output

(ert-deftest thesis-desk-parse-front ()
  (let ((thesis-desk-page-offset 0))
    (should (equal (thesis-desk-dt-parse-front "5A1C0D2E-AAAA-BBBB-CCCC-123456789ABC\theinrich-2012-intro.pdf\t41\n")
                   '(:uuid "5A1C0D2E-AAAA-BBBB-CCCC-123456789ABC" :name "heinrich-2012-intro.pdf"
                           :key "heinrich-2012-intro" :page 41))))
  (let ((thesis-desk-page-offset 1))
    (should (= (plist-get (thesis-desk-dt-parse-front "5A1C0D2E-AAAA-BBBB-CCCC-123456789ABC\tx.pdf\t0") :page) 1)))
  (should-not (thesis-desk-dt-parse-front ""))
  (should-not (thesis-desk-dt-parse-front "not a uuid\tx.pdf\t3"))
  (should-not (plist-get (thesis-desk-dt-parse-front "5A1C0D2E-AAAA-BBBB-CCCC-123456789ABC\tx.pdf\t") :page)))

(ert-deftest thesis-desk-url-counts-pages-from-zero ()
  (should (equal (thesis-desk-dt-url "U" 6) "x-devonthink-item://U?page=5"))
  (should (equal (thesis-desk-dt-url "U") "x-devonthink-item://U")))

;;;; Verdicts

(ert-deftest thesis-desk-verdicts-round-trip ()
  (let ((alist '(("c2-real" . supports) ("20261027T150202.069446" . background))))
    (should (equal (thesis-desk--verdicts-parse (thesis-desk--verdicts-format alist)) alist)))
  (should-not (thesis-desk--verdicts-parse nil)))

;;;; The map

(ert-deftest thesis-desk-map-claims-read ()
  (with-temp-buffer
    (insert "#+todo: CLAIM QUESTION | ARGUED\n* Chapter\n** CLAIM Abstraction is real\n:PROPERTIES:\n:ID: c1\n:DG_TYPE: claim\n:END:\n"
            "*** QUESTION Does it survive Searle?\n:PROPERTIES:\n:ID: q1\n:DG_TYPE: Question\n:END:\n"
            "** A note\n:PROPERTIES:\n:ID: n1\n:DG_TYPE: source\n:END:\n")
    (org-mode)
    (let ((claims (thesis-desk-map-claims-in-buffer)))
      (should (equal (mapcar (lambda (c) (plist-get c :id)) claims) '("c1" "q1")))
      (should (equal (plist-get (car claims) :title) "Abstraction is real"))
      (should (equal (plist-get (cadr claims) :type) "question")))))

(ert-deftest thesis-desk-claim-candidates-unique ()
  (let ((cands (thesis-desk-claim-candidates
                '((:id "a" :title "Same" :type "claim") (:id "b" :title "Same" :type "claim")))))
    (should (equal (mapcar #'cdr cands) '("a" "b")))
    (should (= (length (delete-dups (mapcar #'car cands))) 2))))

;;;; The journal

(ert-deftest thesis-desk-journal-create-and-close ()
  (thesis-desk-test--with-dir
    (let* ((record '(:uuid "U-1" :key "heinrich-2012" :page 41))
           (id (thesis-desk-journal--create record '("c1" "c2") "his definition of real abstraction")))
      (let ((active (thesis-desk-journal-active)))
        (should (equal (plist-get active :id) id))
        (should (equal (plist-get active :claims) '("c1" "c2")))
        (should (equal (plist-get active :start-page) 41))
        (should (equal (plist-get active :state) "READING")))
      (should (equal (thesis-desk-journal--close id :reason 'later :page 58
                                                 :verdicts '(("c1" . supports) ("c2" . background))
                                                 :next "resume at p. 58" :note "ch. 3.4 matters")
                     "PAUSED"))
      (should-not (thesis-desk-journal-active))
      (let ((s (car (thesis-desk-journal-sessions '("PAUSED")))))
        (should (equal (plist-get s :end-page) 58))
        (should (eq (plist-get s :left) 'later))
        (should (equal (plist-get s :verdicts) '(("c1" . supports) ("c2" . background))))
        (should (equal (plist-get s :next) "resume at p. 58"))
        (should (integerp (plist-get s :line))))
      (with-current-buffer (thesis-desk-journal--buffer)
        (should (string-match-p "ch\\. 3\\.4 matters" (buffer-string)))
        (should (string-match-p "^\\* 20[0-9][0-9]" (buffer-string)))))))

(ert-deftest thesis-desk-journal-dropped-needs-a-reason ()
  (thesis-desk-test--with-dir
    (let ((id (thesis-desk-journal--create '(:uuid "U-2" :key "k") nil "")))
      (should-error (thesis-desk-journal--close id :reason 'not-relevant) :type 'user-error)
      (should (equal (thesis-desk-journal--close id :reason 'not-relevant :why "only about aesthetics")
                     "DROPPED"))
      (should (equal (plist-get (car (thesis-desk-journal-sessions '("DROPPED"))) :why)
                     "only about aesthetics")))))

(ert-deftest thesis-desk-journal-resume-marks-the-old-session ()
  (thesis-desk-test--with-dir
    (let* ((old (thesis-desk-journal--create '(:uuid "U-3" :key "k") '("c1") "first")))
      (thesis-desk-journal--close old :reason 'dense :next "read Arthur first")
      (should (equal (plist-get (thesis-desk--latest-paused "U-3" "k") :id) old))
      (let ((new (thesis-desk-journal--create '(:uuid "U-3" :key "k") '("c1") "first" :resumes old)))
        (should-not (thesis-desk--latest-paused "U-3" "k"))
        (should (equal (plist-get (car (thesis-desk-journal-sessions '("RESUMED"))) :id) old))
        (should (equal (plist-get (thesis-desk-journal-active) :id) new))))))

(ert-deftest thesis-desk-switch-asks-and-rates ()
  (thesis-desk-test--with-dir
    (let* ((rated nil)
           (thesis-desk-set-rating-function (lambda (uuid r) (setq rated (list uuid r))))
           (thesis-desk-front-record-function (lambda () '(:uuid "U-4" :key "k" :page 12)))
           (answers (list ?n))
           (strings (list "it is about music" "")))
      (thesis-desk-journal--create '(:uuid "U-4" :key "k") '("c1") "x")
      (cl-letf (((symbol-function 'read-multiple-choice)
                 (lambda (_p _c &rest _) (list (pop answers))))
                ((symbol-function 'read-string)
                 (lambda (&rest _) (pop strings))))
        (should (eq (thesis-desk-switch t) 'not-relevant)))
      (should (equal rated '("U-4" 1)))
      (let ((s (car (thesis-desk-journal-sessions '("DROPPED")))))
        (should (equal (plist-get s :end-page) 12))
        (should (equal (plist-get s :verdicts) '(("c1" . irrelevant))))))))

;;;; Views

(ert-deftest thesis-desk-group-by-claim-order ()
  (let* ((a '(:id "s1" :claims ("c2")))
         (b '(:id "s2" :claims ("c1" "c2")))
         (c '(:id "s3"))
         (d '(:id "s4" :claims ("gone")))
         (groups (thesis-desk-group-by-claim
                  (list a b c d)
                  '((:id "c1" :title "One") (:id "c2" :title "Two")))))
    (should (equal (mapcar #'car groups) '("One" "Two" "gone" "No claim")))
    (should (equal (cdr (assoc "Two" groups)) (list a b)))))

(ert-deftest thesis-desk-where-sections-shape ()
  (let* ((thesis-desk-record-link-function (lambda (u p d) (format "[[x:%s:%s][%s]]" u p d)))
         (sections (thesis-desk-where-sections
                    '((:id "s1" :key "k" :uuid "U" :end-page 58 :next "resume" :purpose "why"
                           :claims ("c1") :file "/j.org" :line 7 :left later))
                    '((:id "c1" :title "One"))))
         (item (car (plist-get (car sections) :items))))
    (should (equal (plist-get (car sections) :title) "One"))
    (should (equal (plist-get item :key) "s1"))
    (should (equal (plist-get item :line) 7))
    (should (string-match-p "resume\\. For: why" (plist-get item :text)))
    (should (member "[[x:U:58][open at p. 58]]" (plist-get item :children)))))

(ert-deftest thesis-desk-report-fallback-text ()
  (let ((text (thesis-desk-report-org-text
               "T" '((:title "S" :items ((:file "/a.org" :line 3 :label "a" :text "t" :children ("c"))))
                     (:title "E" :items nil :empty "nothing")))))
    (should (string-match-p "^\\* S (1)$" text))
    (should (string-match-p "\\[\\[file:/a.org::3\\]\\[a\\]\\]  t" text))
    (should (string-match-p "^  - c$" text))
    (should (string-match-p "^nothing$" text))))

;;;; Hotspots

(defun thesis-desk-test--table ()
  (let ((table (make-hash-table :test #'equal)))
    (puthash "big" (list '(:file "/a.org" :litnote-id "A" :snippet "one" :where quote :open t :desc "Real abstraction")
                         '(:file "/b.org" :litnote-id "B" :snippet "two" :where prose :desc "Real abstraction")
                         '(:file "/c.org" :litnote-id "C" :snippet "three" :where prose :desc "real abstr."))
             table)
    (puthash "small" (list '(:file "/a.org" :litnote-id "A" :snippet "x" :where prose)) table)
    table))

(ert-deftest thesis-desk-hotspots-rank-counts-new-calls ()
  (let* ((table (thesis-desk-test--table))
         (spots (thesis-desk-hotspots-rank table nil 3)))
    (should (equal (mapcar (lambda (s) (plist-get s :id)) spots) '("big")))
    (should (equal (plist-get (car spots) :title) "Real abstraction"))
    (should (= (plist-get (car spots) :open) 1))
    (should (= (plist-get (car spots) :quotes) 1))
    (should (= (plist-get (car spots) :litnotes) 3))
    ;; Two of the three calls addressed: below the minimum.
    (let ((state (list (cons "big" (mapcar #'thesis-desk-mention-key
                                           (seq-take (gethash "big" table) 2))))))
      (should-not (thesis-desk-hotspots-rank table state 3))
      (should (= (length (plist-get (car (thesis-desk-hotspots-rank table state 1)) :new)) 1)))))

(ert-deftest thesis-desk-synthesis-create-and-find ()
  (thesis-desk-test--with-dir
    (let ((thesis-desk-synthesis-directory (expand-file-name "synthesis/" thesis-desk-directory)))
      (should-not (thesis-desk-synthesis-file "big"))
      (let ((file (thesis-desk-synthesis-create "big" "Real abstraction")))
        (should (string-match-p "state-of-research-real-abstraction\\.org\\'" file))
        (should (equal (thesis-desk-synthesis-file "big") file))
        (should (equal (thesis-desk-synthesis-create "big" "Real abstraction") file))
        (with-temp-buffer
          (insert-file-contents file)
          (should (search-forward ":THESIS_SYNTHESIS_OF: big" nil t))
          (should (search-forward "#+BEGIN: concept-usage :id \"big\"" nil t)))))))

(ert-deftest thesis-desk-mark-addressed-writes-state ()
  (thesis-desk-test--with-dir
    (let ((thesis-desk-mentions-function #'thesis-desk-test--table))
      (thesis-desk-synthesis-mark-addressed "big")
      (should (= (length (cdr (assoc "big" (thesis-desk--state-read)))) 3))
      (should-not (seq-find (lambda (s) (equal (plist-get s :id) "big"))
                            (thesis-desk-hotspots-rank (thesis-desk-test--table)
                                                       (thesis-desk--state-read) 1))))))

;;;; Litnote proposals

(ert-deftest thesis-desk-litnotes-of-project-filters ()
  (thesis-desk-test--with-dir
    (let ((dir (expand-file-name "lit/" thesis-desk-directory)))
      (make-directory dir t)
      (with-temp-file (expand-file-name "a.org" dir)
        (insert ":PROPERTIES:\n:ID: A\n:END:\n#+title: Alpha\n- bib-project :: [[id:P1][Proj]]\n"))
      (with-temp-file (expand-file-name "b.org" dir)
        (insert ":PROPERTIES:\n:ID: B\n:END:\n#+title: Beta\n- bib-project :: [[id:P2][Other]]\n"))
      (with-temp-file (expand-file-name "c.org" dir)
        (insert ":PROPERTIES:\n:ID: C\n:END:\n#+title: Gamma\nmentions id:P1 in the body only\n"))
      (should (equal (mapcar (lambda (n) (plist-get n :id)) (thesis-desk-litnotes-of-project "P1" dir))
                     '("A"))))))

(ert-deftest thesis-desk-claude-result-reads-envelope ()
  (let ((out (json-encode '((type . "result") (is_error . :json-false)
                            (result . "Here:\n```json\n{\"notes\": [{\"id\": \"A\", \"summary\": \"S\"}]}\n```")))))
    (should (equal (plist-get (car (plist-get (thesis-desk-claude-result out) :notes)) :summary) "S")))
  (should-error (thesis-desk-claude-result (json-encode '((is_error . t) (result . "boom"))))))

(ert-deftest thesis-desk-proposals-merge-and-group ()
  (let* ((notes '((:id "A" :title "Alpha" :file "/dev/null") (:id "B" :title "Beta" :file "/dev/null")))
         (merged (thesis-desk-proposals-merge
                  notes '(:notes ((:id "A" :summary "SA" :theme "t1" :relevance ((:target "c1" :kind "adapts" :strength 2 :nuance "n")))
                                  (:id "Z" :summary "unknown note")))))
         (grouped (thesis-desk-proposals-group merged '(:groups ((:name "G1" :ids ("A")))))))
    (should (equal (mapcar (lambda (p) (plist-get p :id)) merged) '("A")))
    (should (equal (plist-get (car grouped) :group) "G1"))
    (let ((section (car (thesis-desk-litnotes-sections grouped '((:id "c1" :title "Claim one"))))))
      (should (equal (plist-get section :title) "G1"))
      (should (member "relevance: adapts 2 Claim one: n"
                      (plist-get (car (plist-get section :items)) :children))))))

(ert-deftest thesis-desk-summary-write-adds-then-replaces ()
  (thesis-desk-test--with-dir
    (let ((file (expand-file-name "a.org" thesis-desk-directory))
          (claims '((:id "c1" :title "Claim one"))))
      (with-temp-file file
        (insert ":PROPERTIES:\n:ID: A\n:END:\n#+title: Alpha\n- bib-project :: x\n\n* Notes\nmine\n"))
      (thesis-desk-summary-write file '(:summary "First." :group "G" :role "r"
                                                 :relevance ((:target "c1" :kind "adopts" :strength 3 :nuance "all of it")))
                                 "Proj" claims)
      (thesis-desk-summary-write file '(:summary "Second." :group "G") "Proj" claims)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((text (buffer-string)))
          (should (= 1 (how-many "^\\* Summary for Proj" (point-min) (point-max))))
          (should (string-match-p "Second\\." text))
          (should-not (string-match-p "First\\." text))
          (should (string-match-p "^\\* Notes\nmine" text))
          (should (< (string-search "Summary for Proj" text) (string-search "* Notes" text))))))))

(ert-deftest thesis-desk-summary-text-links-claims ()
  (let ((text (thesis-desk-summary-text
               '(:summary "S" :group "G" :relevance ((:target "c1" :kind "adapts" :strength 2 :nuance "n")
                                                     (:target "fetishism" :kind "contrasts" :strength 1 :nuance "m")))
               "Proj" '((:id "c1" :title "Claim one")))))
    (should (string-match-p "relevance :: \\[\\[id:c1\\]\\[Claim one\\]\\] adapts 2: n" text))
    (should (string-match-p "relevance :: fetishism contrasts 1: m" text))))

(provide 'thesis-desk-test)
;;; thesis-desk-test.el ends here
