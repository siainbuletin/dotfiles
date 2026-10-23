;;; sp-org-keywords.el --- The one list of Org TODO keywords -*- lexical-binding: t; -*-

;;; Commentary:

;; Defines every TODO keyword sequence once, one constant per use, and
;; joins them into `org-todo-keywords'. No other module sets that
;; variable. `sp-org-keywords-done' lists the keywords that count as
;; finished, for code that reasons without a buffer (vulpea-para).

;;; Code:

(defconst sp-org-keywords-tasks
  '((sequence "TODO(t)" "NEXT(n)" "PROG(p!)" "WAIT(w@/!)" "|" "DONE(d!)" "CNCL(c@)"))
  "Tasks, projects and issues; the sequence `org-gtd-keyword-mapping' uses.")

(defconst sp-org-keywords-legacy
  '((sequence "DOING" "WAITING" "|" "CANCELLED"))
  "Keywords older notes still use; migrate them to the task sequence.")

(defconst sp-org-keywords-trails
  '((sequence "QUESTION(q)" "REVIEW(v)" "|" "ANSWERED(n)" "DROPPED(x)")
    (sequence "ACTIVE(a)" "PARKED(k)" "|" "ARCHIVED(A)")
    (sequence "TOREAD(r)" "|" "READ(d)" "PRUNED(p)"))
  "Questions, trails and pages of `sp-trails'.")

(defconst sp-org-keywords-questions
  '((sequence "QUESTION" "SCOPING(s)" "READING" "SYNTHESIZING(y)" "|" "STABLE(t)" "DROPPED")
    (sequence "UNREAD(u)" "|" "READ" "SKIPPED"))
  "Questions and reading tasks of the discourse-graphs workflow.")

(setq org-todo-keywords
      (append sp-org-keywords-tasks
              sp-org-keywords-legacy
              sp-org-keywords-trails
              sp-org-keywords-questions))

(defun sp-org-keywords-done ()
  "Return the keywords of `org-todo-keywords' that count as finished."
  (let (done)
    (dolist (seq org-todo-keywords)
      (let ((words (cdr seq)))
        (when (member "|" words)
          (dolist (word (cdr (member "|" words)))
            (push (replace-regexp-in-string "(.*)\\'" "" word) done)))))
    (nreverse done)))

(provide 'sp-org-keywords)
;; sp-org-keywords.el ends here.
