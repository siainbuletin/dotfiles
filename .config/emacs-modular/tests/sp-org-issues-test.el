;;; sp-org-issues-test.el --- Tests for sp-org-issues  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-org-issues-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org-capture)
(require 'org-agenda)

(when noninteractive
  (dolist (feature '(vulpea vulpea-para sp-vulpea-para))
    (provide feature))
  (defvar vulpea-para-done-keywords nil))

(load (expand-file-name
       "../libraries/modules/custom/sp-org-issues.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defvar sp-org-issues-test--now (date-to-time "2026-10-21T12:00:00Z")
  "The moment all tests pretend it is.")

(defun sp-org-issues-test--pr (number &rest props)
  "Return a pull request plist for NUMBER, with PROPS overriding the defaults."
  (append props
          (list :repo "dotfiles" :number number
                :title (format "PR %d" number)
                :url (format "https://github.com/o/r/pull/%d" number)
                :draft nil :decision "" :mergeable "MERGEABLE"
                :base "main" :head (format "branch-%d" number)
                :ci 'success :updated "2026-10-21T12:00:00Z")))

(defconst sp-org-issues-test--issues-text
  "#+todo: TODO NEXT PROG WAIT | DONE CNCL
* Tasks
** dotfiles
:PROPERTIES:
:GIT_DIR: /x
:END:
*** PROG Write sp-paths
:PROPERTIES:
:ID: aaa
:PR: https://github.com/o/r/pull/22
:BRANCH: issue/paths
:END:
*** NEXT Fix the tests
DEADLINE: <2026-10-21 Wed>
*** DONE Old issue
*** WAIT Wait for a reply
** vulpea-mcp
*** TODO Document the tools
"
  "A small issues file.")

(defun sp-org-issues-test--issues ()
  "Return the open issues of `sp-org-issues-test--issues-text'."
  (with-temp-buffer
    (insert (replace-regexp-in-string "^," "" sp-org-issues-test--issues-text))
    (org-mode)
    (sp-org-issues-morning--issues-in-buffer)))

(defun sp-org-issues-test--issue (title)
  "Return the issue called TITLE of the small issues file."
  (seq-find (lambda (issue) (equal (plist-get issue :title) title))
            (sp-org-issues-test--issues)))

(ert-deftest sp-org-issues-morning-ci-state ()
  (should (eq 'success (sp-org-issues-morning--ci
                        '(((conclusion . "SUCCESS") (status . "COMPLETED"))))))
  (should (eq 'failure (sp-org-issues-morning--ci
                        '(((conclusion . "SUCCESS") (status . "COMPLETED"))
                          ((conclusion . "FAILURE") (status . "COMPLETED"))))))
  (should (eq 'pending (sp-org-issues-morning--ci
                        '(((conclusion . "") (status . "IN_PROGRESS"))))))
  (should (eq 'pending (sp-org-issues-morning--ci '(((state . "PENDING"))))))
  (should (eq 'failure (sp-org-issues-morning--ci '(((state . "ERROR"))))))
  ;; a failure is reported even while other checks still run
  (should (eq 'failure (sp-org-issues-morning--ci
                        '(((conclusion . "FAILURE") (status . "COMPLETED"))
                          ((conclusion . "") (status . "QUEUED"))))))
  (should-not (sp-org-issues-morning--ci nil)))

(ert-deftest sp-org-issues-morning-parse-prs ()
  (let* ((json "[{\"number\":17,\"title\":\"Tint boxes\",
 \"url\":\"https://github.com/o/r/pull/17\",\"isDraft\":false,
 \"reviewDecision\":\"APPROVED\",\"mergeable\":\"MERGEABLE\",
 \"baseRefName\":\"main\",\"headRefName\":\"claude/a\",
 \"updatedAt\":\"2026-10-20T21:06:23Z\",
 \"statusCheckRollup\":[{\"conclusion\":\"FAILURE\",\"status\":\"COMPLETED\"}]}]")
         (pr (car (sp-org-issues-morning--parse-prs json "dotfiles"))))
    (should (equal (plist-get pr :repo) "dotfiles"))
    (should (= (plist-get pr :number) 17))
    (should (equal (plist-get pr :title) "Tint boxes"))
    (should (equal (plist-get pr :decision) "APPROVED"))
    (should (equal (plist-get pr :base) "main"))
    (should (equal (plist-get pr :head) "claude/a"))
    (should (eq (plist-get pr :ci) 'failure))
    (should-not (plist-get pr :draft)))
  (should-not (sp-org-issues-morning--parse-prs "[]" "dotfiles")))

(ert-deftest sp-org-issues-morning-pr-number ()
  (should (= 4 (sp-org-issues-morning--pr-number "https://github.com/o/r/pull/4")))
  (should (= 17 (sp-org-issues-morning--pr-number "#17")))
  (should (= 17 (sp-org-issues-morning--pr-number " 17 ")))
  (should-not (sp-org-issues-morning--pr-number ""))
  (should-not (sp-org-issues-morning--pr-number nil)))

(ert-deftest sp-org-issues-morning-repo-slug ()
  (should (equal "siainbuletin/dotfiles"
                 (sp-org-issues-morning--repo-slug
                  "https://github.com/siainbuletin/dotfiles")))
  (should (equal "o/r" (sp-org-issues-morning--repo-slug "git@github.com:o/r.git")))
  (should-not (sp-org-issues-morning--repo-slug nil))
  (should-not (sp-org-issues-morning--repo-slug "https://example.org/o/r")))

(ert-deftest sp-org-issues-morning-pr-category ()
  (cl-flet ((cat (&rest props)
              (sp-org-issues-morning--pr-category
               (apply #'sp-org-issues-test--pr 1 props))))
    (should (eq 'review (cat)))
    (should (eq 'review (cat :ci nil)))
    (should (eq 'draft (cat :draft t :ci 'failure)))
    (should (eq 'ci-failed (cat :ci 'failure :decision "APPROVED")))
    (should (eq 'conflict (cat :mergeable "CONFLICTING")))
    (should (eq 'changes-requested (cat :decision "CHANGES_REQUESTED")))
    (should (eq 'ready (cat :decision "APPROVED")))
    (should (eq 'ci-pending (cat :decision "APPROVED" :ci 'pending)))
    (should (eq 'ci-pending (cat :ci 'pending)))))

(ert-deftest sp-org-issues-morning-stack-depth ()
  (let* ((a (sp-org-issues-test--pr 17 :head "a"))
         (b (sp-org-issues-test--pr 18 :base "a" :head "b"))
         (c (sp-org-issues-test--pr 19 :base "b" :head "c"))
         (other (sp-org-issues-test--pr 22 :head "x"))
         (elsewhere (sp-org-issues-test--pr 5 :repo "vulpea-mcp" :base "a"))
         (prs (list a b c other elsewhere)))
    (should (equal '(0) (list (car (sp-org-issues-morning--stack-depth a prs)))))
    (should (equal '(1 . 17) (sp-org-issues-morning--stack-depth b prs)))
    (should (equal '(2 . 18) (sp-org-issues-morning--stack-depth c prs)))
    (should (= 0 (car (sp-org-issues-morning--stack-depth other prs))))
    ;; a branch with the same name in another repository is not a parent
    (should (= 0 (car (sp-org-issues-morning--stack-depth elsewhere prs))))))

(ert-deftest sp-org-issues-morning-stack-cycle-ends ()
  (let* ((a (sp-org-issues-test--pr 1 :base "b" :head "a"))
         (b (sp-org-issues-test--pr 2 :base "a" :head "b")))
    (should (numberp (car (sp-org-issues-morning--stack-depth a (list a b)))))))

(ert-deftest sp-org-issues-morning-pr-score ()
  (cl-flet ((score (&rest props)
              (car (sp-org-issues-morning--pr-score
                    (apply #'sp-org-issues-test--pr 1 props) nil
                    sp-org-issues-test--now))))
    (should (> (score :ci 'failure) (score :mergeable "CONFLICTING")))
    (should (> (score :mergeable "CONFLICTING") (score :decision "CHANGES_REQUESTED")))
    (should (> (score :decision "CHANGES_REQUESTED") (score :decision "APPROVED")))
    (should (> (score :decision "APPROVED") (score)))
    (should (> (score) (score :ci 'pending)))
    (should (> (score :ci 'pending) (score :draft t)))
    ;; a quiet pull request gains a point a day, up to ten
    (should (= (1+ (score)) (score :updated "2026-10-20T12:00:00Z")))
    (should (= (+ 10 (score)) (score :updated "2026-01-01T00:00:00Z")))))

(ert-deftest sp-org-issues-morning-stacked-pr-waits-for-its-base ()
  (let* ((a (sp-org-issues-test--pr 17 :head "a"))
         (b (sp-org-issues-test--pr 18 :base "a" :head "b"))
         (prs (list a b)))
    (pcase-let ((`(,sa . ,_) (sp-org-issues-morning--pr-score a prs sp-org-issues-test--now))
                (`(,sb . ,rb) (sp-org-issues-morning--pr-score b prs sp-org-issues-test--now)))
      (should (< sb sa))
      (should (string-match-p "#17" rb)))))

(ert-deftest sp-org-issues-morning-reads-open-issues-only ()
  (let ((issues (sp-org-issues-test--issues)))
    (should (equal '("Write sp-paths" "Fix the tests" "Wait for a reply"
                     "Document the tools")
                   (mapcar (lambda (i) (plist-get i :title)) issues)))))

(ert-deftest sp-org-issues-morning-reads-issue-fields ()
  (let ((issue (sp-org-issues-test--issue "Write sp-paths")))
    (should (eq 'prog (plist-get issue :state)))
    (should (equal "dotfiles" (plist-get issue :repo)))
    (should (equal "aaa" (plist-get issue :id)))
    (should (= 22 (plist-get issue :pr)))
    (should (equal "issue/paths" (plist-get issue :branch))))
  (should (equal "vulpea-mcp"
                 (plist-get (sp-org-issues-test--issue "Document the tools") :repo)))
  (should (time-equal-p
           (org-time-string-to-time "<2026-10-21 Wed>")
           (plist-get (sp-org-issues-test--issue "Fix the tests") :deadline))))

(ert-deftest sp-org-issues-morning-reads-the-issues-file ()
  (let ((file (make-temp-file "issues" nil ".org"
                              (replace-regexp-in-string
                               "^," "" sp-org-issues-test--issues-text))))
    (unwind-protect
        (should (= 4 (length (sp-org-issues-morning--issues file))))
      (kill-buffer (find-buffer-visiting file))
      (delete-file file))))

(ert-deftest sp-org-issues-morning-issue-score ()
  (cl-flet ((score (title)
              (car (sp-org-issues-morning--issue-score
                    (sp-org-issues-test--issue title) sp-org-issues-test--now))))
    (should (> (score "Write sp-paths") (score "Wait for a reply")))
    (should (> (score "Wait for a reply") (score "Document the tools")))
    ;; NEXT with a deadline today beats PROG
    (should (> (score "Fix the tests") (score "Write sp-paths"))))
  (let ((issue (list :state 'todo :title "x")))
    (cl-flet ((score (&rest props)
                (car (sp-org-issues-morning--issue-score
                      (append props issue) sp-org-issues-test--now))))
      (should (> (score :deadline (date-to-time "2026-10-01T00:00:00Z")) (score)))
      (should (> (score :deadline (date-to-time "2026-10-23T00:00:00Z")) (score)))
      (should (= (score) (score :deadline (date-to-time "2026-12-01T00:00:00Z"))))
      (should (> (score :scheduled (date-to-time "2026-10-21T00:00:00Z")) (score))))))

(ert-deftest sp-org-issues-morning-items-are-ranked ()
  (let* ((prs (list (sp-org-issues-test--pr 1)
                    (sp-org-issues-test--pr 2 :ci 'failure)
                    (sp-org-issues-test--pr 3 :draft t)))
         (items (sp-org-issues-morning--items nil prs sp-org-issues-test--now)))
    (should (equal '(2 1 3) (mapcar (lambda (i) (plist-get i :number)) items)))
    (should (apply #'>= (mapcar (lambda (i) (plist-get i :score)) items)))))

(ert-deftest sp-org-issues-morning-issue-takes-its-pr ()
  "An issue with an open pull request is one line, and shows the better score."
  (let* ((prs (list (sp-org-issues-test--pr 22 :ci 'failure)))
         (items (sp-org-issues-morning--items
                 (list (sp-org-issues-test--issue "Write sp-paths"))
                 prs sp-org-issues-test--now)))
    (should (= 1 (length items)))
    (should (equal "Write sp-paths" (plist-get (car items) :title)))
    (should (= 22 (plist-get (car items) :number)))
    (should (equal "https://github.com/o/r/pull/22" (plist-get (car items) :url)))
    (should (equal "aaa" (plist-get (car items) :id)))
    (should (>= (plist-get (car items) :score)
                (alist-get 'ci-failed sp-org-issues-morning-scores)))))

(ert-deftest sp-org-issues-morning-closed-pr-is-flagged ()
  (let* ((issue (sp-org-issues-test--issue "Write sp-paths"))
         (items (sp-org-issues-morning--items
                 (list issue) nil sp-org-issues-test--now '("dotfiles"))))
    (should (string-match-p "no longer open" (plist-get (car items) :reason)))
    (should (>= (plist-get (car items) :score)
                (alist-get 'pr-gone sp-org-issues-morning-scores))))
  ;; when GitHub was not reached the pull request stays unknown
  (let ((items (sp-org-issues-morning--items
                (list (sp-org-issues-test--issue "Write sp-paths"))
                nil sp-org-issues-test--now nil)))
    (should-not (string-match-p "no longer open" (plist-get (car items) :reason)))))

(ert-deftest sp-org-issues-morning-render ()
  (let* ((items (sp-org-issues-morning--items
                 (sp-org-issues-test--issues)
                 (list (sp-org-issues-test--pr 17 :ci 'failure :title "Tint boxes"))
                 sp-org-issues-test--now '("dotfiles")))
         (text (sp-org-issues-morning--render
                items sp-org-issues-test--now '("GitHub was not reached for x"))))
    (should (string-match-p "^#\\+title: Morning" text))
    (should (string-match-p "^\\* Today" text))
    (should (string-match-p "^\\* Parked" text))
    (should (string-match-p "GitHub was not reached for x" text))
    (should (string-match-p "\\[\\[https://github.com/o/r/pull/17\\]\\[dotfiles #17\\]\\] Tint boxes" text))
    (should (string-match-p "\\[\\[id:aaa\\]\\[Write sp-paths\\]\\]" text))
    ;; the failing pull request comes before everything else
    (should (< (string-match "Tint boxes" text) (string-match "Fix the tests" text)))
    ;; low scores are parked below the Parked heading
    (should (> (string-match "Document the tools" text) (string-match "^\\* Parked" text)))))

(ert-deftest sp-org-issues-morning-render-respects-the-limit ()
  (let* ((sp-org-issues-morning-limit 2)
         (prs (mapcar #'sp-org-issues-test--pr '(1 2 3 4)))
         (text (sp-org-issues-morning--render
                (sp-org-issues-morning--items nil prs sp-org-issues-test--now)
                sp-org-issues-test--now nil)))
    (should (> (string-match "PR 3" text) (string-match "^\\* Parked" text)))
    (should (< (string-match "PR 2" text) (string-match "^\\* Parked" text)))))

(ert-deftest sp-org-issues-morning-render-empty ()
  (should (string-match-p "Nothing"
                          (sp-org-issues-morning--render nil sp-org-issues-test--now nil))))

(defun sp-org-issues-test--fake-gh ()
  "Write a script that answers like gh, and return its path.
It fails for the repository failing/repo."
  (let ((script (make-temp-file "fake-gh" nil ".sh")))
    (with-temp-file script
      (insert "#!/bin/sh\n"
              "case \"$*\" in *failing/repo*) echo boom >&2; exit 1;; esac\n"
              "echo 'a warning that must not reach the JSON' >&2\n"
              "cat <<'EOF'\n"
              "[{\"number\":7,\"title\":\"Seven\",\"url\":\"u\",\"isDraft\":false,"
              "\"reviewDecision\":\"\",\"mergeable\":\"MERGEABLE\","
              "\"baseRefName\":\"main\",\"headRefName\":\"h\","
              "\"updatedAt\":\"2026-10-21T12:00:00Z\",\"statusCheckRollup\":[]}]\n"
              "EOF\n"))
    (set-file-modes script #o755)
    script))

(defun sp-org-issues-test--fetch (repos)
  "Fetch REPOS with the fake gh and return (PRS FAILED)."
  (let ((script (sp-org-issues-test--fake-gh))
        result)
    (unwind-protect
        (let ((sp-org-issues-gh-program script)
              (deadline (+ (float-time) 10)))
          (sp-org-issues-morning--fetch
           repos (lambda (prs failed) (setq result (list prs failed))))
          (while (and (not result) (< (float-time) deadline))
            (accept-process-output nil 0.1)))
      (delete-file script))
    result))

(ert-deftest sp-org-issues-morning-fetch ()
  (pcase-let ((`(,prs ,failed)
               (sp-org-issues-test--fetch
                '(("dotfiles" . "o/r") ("other" . "o/s") ("bad" . "failing/repo")))))
    (should (equal '("dotfiles" "other")
                   (mapcar (lambda (pr) (plist-get pr :repo)) prs)))
    (should (equal '("bad") failed))))

(ert-deftest sp-org-issues-morning-fetch-nothing ()
  (should (equal '(nil nil) (sp-org-issues-test--fetch nil))))

(ert-deftest sp-org-issues-morning-repos ()
  (let ((sp-org-issues-repos
         '(("dotfiles" :url "https://github.com/siainbuletin/dotfiles")
           ("local-only" :tag "x")))
        (sp-org-issues-morning-extra-repos '("o/other")))
    (should (equal '(("dotfiles" . "siainbuletin/dotfiles") ("o/other" . "o/other"))
                   (sp-org-issues-morning--repos)))))

(ert-deftest sp-org-issues-morning-works-without-gh ()
  (let* ((file (make-temp-file "issues" nil ".org"
                               (replace-regexp-in-string
                                "^," "" sp-org-issues-test--issues-text)))
         (sp-org-issues-gh-program "no-such-gh-program")
         (sp-org-issues-repos
          '(("dotfiles" :url "https://github.com/siainbuletin/dotfiles"))))
    (unwind-protect
        (cl-letf (((symbol-function 'sp-org-issues-file) (lambda () file)))
          (sp-org-issues-morning)
          (with-current-buffer "*Morning*"
            (should (string-match-p "Write sp-paths" (buffer-string)))
            (should (string-match-p "no-such-gh-program" (buffer-string)))
            (should buffer-read-only)))
      (when (get-buffer "*Morning*") (kill-buffer "*Morning*"))
      (kill-buffer (find-buffer-visiting file))
      (delete-file file))))

(ert-deftest sp-org-issues-morning-greets-once-a-day ()
  (let ((sp-org-issues-morning-stamp-file (make-temp-file "morning-stamp"))
        (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'sp-org-issues-morning)
                   (lambda () (cl-incf calls))))
          (delete-file sp-org-issues-morning-stamp-file)
          (sp-org-issues-morning-greet)
          (sp-org-issues-morning-greet)
          (should (= 1 calls))
          (with-temp-file sp-org-issues-morning-stamp-file
            (insert "2020-01-01"))
          (sp-org-issues-morning-greet)
          (should (= 2 calls)))
      (ignore-errors (delete-file sp-org-issues-morning-stamp-file)))))

(ert-deftest sp-org-issues-morning-greeting-never-breaks-startup ()
  (let ((sp-org-issues-morning-stamp-file (make-temp-file "morning-stamp")))
    (unwind-protect
        (cl-letf (((symbol-function 'sp-org-issues-morning)
                   (lambda () (user-error "No Issues area yet"))))
          (delete-file sp-org-issues-morning-stamp-file)
          (should-not (sp-org-issues-morning-greet)))
      (ignore-errors (delete-file sp-org-issues-morning-stamp-file)))))

(provide 'sp-org-issues-test)
;;; sp-org-issues-test.el ends here
