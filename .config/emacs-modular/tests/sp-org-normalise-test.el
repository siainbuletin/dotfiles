;; -*- lexical-binding: t; -*-
;; sp-org-normalise-test.el --- Tests for sp-org-normalise

(require 'ert)
(require 'sp-org-normalise)

(defun sp-org-normalise-test--text (&rest lines)
  "LINES joined, with a final newline."
  (concat (string-join lines "\n") "\n"))

(defconst sp-org-normalise-test--global '("TODO" "DONE"))

(defun sp-org-normalise-test--plan (text)
  (sp-org-normalise-plan-text text sp-org-normalise-test--global))

(defun sp-org-normalise-test--result (text)
  (sp-org-normalise-apply-to-text text (sp-org-normalise-test--plan text)))

(ert-deftest sp-org-normalise-declared-keywords-strip-keys-and-bar ()
  (should (equal (sp-org-normalise-declared-keywords
                  (sp-org-normalise-test--text
                   "#+title: x" "#+todo: TODO(t) WAIT(w@/!) | DONE(d!)"
                   "#+SEQ_TODO: IDEA | USED"))
                 '("TODO" "WAIT" "DONE" "IDEA" "USED"))))

(ert-deftest sp-org-normalise-global-keywords-flatten-the-spec ()
  (should (equal (sp-org-normalise-global-keywords
                  '((sequence "TODO(t)" "DOING" "|" "DONE") (type "A" "B")))
                 '("TODO" "DOING" "DONE" "A" "B"))))

(ert-deftest sp-org-normalise-mapped-keyword-is-rewritten ()
  (should (equal (sp-org-normalise-test--result
                  (sp-org-normalise-test--text "* Tasks" "** DOING write [1/2]" "** CANCELLED"))
                 (sp-org-normalise-test--text "#+todo: TODO NEXT PROG WAIT | DONE CNCL"
                                              "* Tasks" "** PROG write [1/2]" "** CNCL"))))

(ert-deftest sp-org-normalise-unmapped-keyword-is-left-alone ()
  (should-not (sp-org-normalise-test--plan
               (sp-org-normalise-test--text "* README first" "* FAQ"))))

(ert-deftest sp-org-normalise-keywords-in-blocks-and-body-are-ignored ()
  (should-not (sp-org-normalise-test--plan
               (sp-org-normalise-test--text
                "* TODO a" "#+begin_example" "** DOING x" "#+end_example"
                ":PROPERTIES:" "** DOING y" ":END:" "DOING in prose"))))

(ert-deftest sp-org-normalise-checkboxes-become-headings ()
  (should (equal (sp-org-normalise-test--result
                  (sp-org-normalise-test--text
                   "#+todo: TODO NEXT PROG WAIT | DONE CNCL"
                   "* Tasks" "- [ ] one" "- [X] two" "- [-] three"))
                 (sp-org-normalise-test--text
                  "#+todo: TODO NEXT PROG WAIT | DONE CNCL"
                  "* Tasks" "** TODO one" "** DONE two" "** PROG three"))))

(ert-deftest sp-org-normalise-checkboxes-outside-tasks-are-left-alone ()
  (should-not (sp-org-normalise-test--plan
               (sp-org-normalise-test--text "* Shopping" "- [ ] milk"))))

(ert-deftest sp-org-normalise-tasks-section-ends-at-next-sibling ()
  (should (equal (sp-org-normalise-test--result
                  (sp-org-normalise-test--text
                   "#+todo: TODO | DONE" "* Tasks" "- [ ] a" "* Other" "- [ ] b"))
                 (sp-org-normalise-test--text
                  "#+todo: TODO | DONE" "* Tasks" "** TODO a" "* Other" "- [ ] b"))))

(ert-deftest sp-org-normalise-checkbox-in-source-block-is-ignored ()
  (should-not (sp-org-normalise-test--plan
               (sp-org-normalise-test--text
                "* Tasks" "#+begin_src md" "- [ ] not a task" "#+end_src"))))

(ert-deftest sp-org-normalise-nested-items-stay-in-the-body ()
  (should (equal (sp-org-normalise-test--result
                  (sp-org-normalise-test--text
                   "#+todo: TODO | DONE"
                   "* Tasks" "  - [ ] parent" "    more text" "    - [ ] child"
                   "  - [X] next"))
                 (sp-org-normalise-test--text
                  "#+todo: TODO | DONE"
                  "* Tasks" "** TODO parent" "more text" "- [ ] child" "** DONE next"))))

(ert-deftest sp-org-normalise-checklist-under-a-keyworded-heading-stays ()
  (should-not (sp-org-normalise-test--plan
               (sp-org-normalise-test--text "* Tasks" "** TODO write" "- [ ] outline"))))

(ert-deftest sp-org-normalise-heading-level-follows-the-enclosing-heading ()
  (should (equal (sp-org-normalise-test--result
                  (sp-org-normalise-test--text
                   "#+todo: TODO | DONE" "* Project" "** Tasks" "- [ ] a"
                   "*** Week 1" "- [ ] b"))
                 (sp-org-normalise-test--text
                  "#+todo: TODO | DONE" "* Project" "** Tasks" "*** TODO a"
                  "*** Week 1" "**** TODO b"))))

(ert-deftest sp-org-normalise-empty-checkbox-is-skipped ()
  (should-not (sp-org-normalise-test--plan
               (sp-org-normalise-test--text "* Tasks" "- [ ]"))))

(ert-deftest sp-org-normalise-plain-headings-promoted-only-when-asked ()
  (let ((text (sp-org-normalise-test--text "#+todo: TODO | DONE" "* Tasks" "** Write")))
    (should-not (sp-org-normalise-test--plan text))
    (let ((sp-org-normalise-promote-plain-headings t))
      (should (equal (sp-org-normalise-test--result text)
                     (sp-org-normalise-test--text "#+todo: TODO | DONE" "* Tasks" "** TODO Write"))))))

(ert-deftest sp-org-normalise-todo-line-is-declared-when-keyword-unknown ()
  (should (equal (sp-org-normalise-test--result
                  (sp-org-normalise-test--text "#+title: Notes" "* Tasks" "- [-] a"))
                 (sp-org-normalise-test--text "#+title: Notes"
                                              "#+todo: TODO NEXT PROG WAIT | DONE CNCL"
                                              "* Tasks" "** PROG a"))))

(ert-deftest sp-org-normalise-todo-line-goes-after-a-properties-drawer ()
  (should (equal (sp-org-normalise-test--result
                  (sp-org-normalise-test--text ":PROPERTIES:" ":ID: x" ":END:" "#+title: N"
                                               "* Tasks" "- [-] a"))
                 (sp-org-normalise-test--text ":PROPERTIES:" ":ID: x" ":END:" "#+title: N"
                                              "#+todo: TODO NEXT PROG WAIT | DONE CNCL"
                                              "* Tasks" "** PROG a"))))

(ert-deftest sp-org-normalise-own-sequence-is-noted-not-edited ()
  (let* ((text (sp-org-normalise-test--text "#+todo: TODO | DONE" "* Tasks" "- [-] a"))
         (plan (sp-org-normalise-test--plan text)))
    (should (memq 'note (mapcar (lambda (c) (plist-get c :kind)) plan)))
    (should-not (string-match-p "NEXT" (sp-org-normalise-apply-to-text text plan)))))

(ert-deftest sp-org-normalise-no-declaration-when-global-knows-the-keyword ()
  (let ((plan (sp-org-normalise-plan-text
               (sp-org-normalise-test--text "* Tasks" "- [ ] a")
               '("TODO" "DONE"))))
    (should (equal (mapcar (lambda (c) (plist-get c :kind)) plan) '(checkbox)))))

(ert-deftest sp-org-normalise-second-run-proposes-nothing ()
  (let* ((text (sp-org-normalise-test--text
                "* Tasks" "- [ ] a" "  - [ ] sub" "* DOING b" "** WAITING c"))
         (once (sp-org-normalise-test--result text)))
    (should (sp-org-normalise-test--plan text))
    (should-not (sp-org-normalise-plan-text once '("TODO" "NEXT" "PROG" "WAIT" "DONE" "CNCL")))))

(ert-deftest sp-org-normalise-buffer-and-text-application-agree ()
  (let* ((text (sp-org-normalise-test--text
                "#+title: x" "* Tasks" "- [ ] a" "  body" "* DOING b"))
         (changes (sp-org-normalise-test--plan text)))
    (with-temp-buffer
      (insert text)
      (sp-org-normalise-apply-to-buffer changes)
      (should (equal (buffer-string) (sp-org-normalise-apply-to-text text changes))))))

(ert-deftest sp-org-normalise-inventory-counts-and-recognition ()
  (let* ((dir (make-temp-file "sp-norm" t))
         (a (expand-file-name "a.org" dir))
         (b (expand-file-name "b.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file a (insert (sp-org-normalise-test--text "* TODO x" "* DOING y" "* DOING z")))
          (with-temp-file b (insert (sp-org-normalise-test--text "#+todo: DOING | DONE" "* DOING q")))
          (cl-multiple-value-bind (rows declared)
              (let ((org-todo-keywords '((sequence "TODO" "|" "DONE"))))
                (sp-org-normalise-inventory-data (sp-org-normalise-files dir)))
            (should (equal (assoc "DOING" rows) '("DOING" 3 2 1 "PROG")))
            (should (equal (assoc "TODO" rows) '("TODO" 1 1 0 nil)))
            (should (equal declared (list (cons b '("DOING" "DONE")))))))
      (delete-directory dir t))))

(ert-deftest sp-org-normalise-files-skip-hidden-directories ()
  (let* ((dir (make-temp-file "sp-norm" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name ".git" dir))
          (with-temp-file (expand-file-name ".git/x.org" dir) (insert "* TODO x"))
          (with-temp-file (expand-file-name "ok.org" dir) (insert "* TODO x"))
          (should (equal (mapcar #'file-name-nondirectory (sp-org-normalise-files dir))
                         '("ok.org"))))
      (delete-directory dir t))))

(ert-deftest sp-org-normalise-apply-plan-refuses-a-changed-buffer ()
  (let* ((dir (make-temp-file "sp-norm" t))
         (f (expand-file-name "a.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file f (insert (sp-org-normalise-test--text "* DOING x")))
          (let* ((plan (car (sp-org-normalise-plan-files (list f))))
                 (buf (find-file-noselect f)))
            (with-current-buffer buf (goto-char (point-max)) (insert "edited\n"))
            (should-not (sp-org-normalise--apply-plan plan (cddr plan)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf)))
      (delete-directory dir t))))

(ert-deftest sp-org-normalise-apply-plan-leaves-buffer-unsaved-by-default ()
  (let* ((dir (make-temp-file "sp-norm" t))
         (f (expand-file-name "a.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file f (insert (sp-org-normalise-test--text "* DOING x")))
          (let* ((plan (car (sp-org-normalise-plan-files (list f))))
                 (sp-org-normalise-save-after-apply nil))
            (should (sp-org-normalise--apply-plan plan (cddr plan)))
            (should (string-match-p "PROG x" (with-current-buffer (find-buffer-visiting f) (buffer-string))))
            (should (string-match-p "DOING x" (with-temp-buffer (insert-file-contents f) (buffer-string))))
            (with-current-buffer (find-buffer-visiting f) (set-buffer-modified-p nil))
            (kill-buffer (find-buffer-visiting f))))
      (delete-directory dir t))))
