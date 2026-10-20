;; -*- lexical-binding: t; -*-
;; sp-org-issues.el --- An issue tracker for code work, kept as a PARA area

;;; Commentary:

;; One Org file, registered with vulpea-para as an area titled "Issues",
;; holds the issues for every code base I work on.  Under its `* Tasks'
;; heading there is one heading per repository, and each issue is a
;; TODO under its repository.  An issue carries its branch, worktree,
;; pull request and Claude thread in its property drawer.
;;
;; - The file uses the org-gtd keywords (TODO NEXT PROG WAIT DONE CNCL),
;;   set with a #+todo: line, so it does not depend on the global
;;   `org-todo-keywords'.
;; - Every issue is an org-gtd single action (ORG_GTD: Actions), so a
;;   NEXT issue shows up in `org-gtd-engage' like any other next action.
;; - `sp-org-issues-start' gives an issue its own git worktree and opens
;;   Magit there.  For the yadm dotfiles the worktree is added from the
;;   yadm repository itself, so the live config in ~ is never touched.
;; - `sp-org-issues-morning' ranks the open issues and the open pull
;;   requests of the same repositories (read with the gh client) into one
;;   list, and shows it on the first start of Emacs each day.
;;
;; Load it after sp-org-ext: it adds to the capture templates and agenda
;; commands that sp-vulpea-para sets.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'vulpea)
(require 'vulpea-para)
(require 'sp-vulpea-para)

(declare-function org-capture-get "org-capture")
(declare-function org-capture-put "org-capture")
(declare-function org-capture-target-buffer "org-capture")
(declare-function org-capture-put-target-region-and-position "org-capture")
(declare-function org-get-at-bol "org-agenda")
(declare-function magit-gitdir "magit-git")
(declare-function magit-status "magit-status")
(defvar org-agenda-overriding-header)
(defvar org-state)
(defvar magit-status-show-untracked-files)

;;;; Settings

(defgroup sp-org-issues nil
  "An issue tracker for code work, kept as a vulpea-para area."
  :group 'org)

(defcustom sp-org-issues-area-title "Issues"
  "Title of the vulpea-para area that holds the issues."
  :type 'string
  :group 'sp-org-issues)

(defcustom sp-org-issues-repos
  '(("dotfiles"
     :tag "dotfiles"
     :git-dir "~/.local/share/yadm/repo.git"
     :worktree-root "~/src/dotfiles-wt/"
     :base "main"
     :url "https://github.com/siainbuletin/dotfiles")
    ("vulpea-mcp"
     :tag "vulpea"
     :git-dir "~/cloned-scan-ai/vulpea-mcp/.git"
     :worktree-root "~/src/vulpea-mcp-wt/"
     :base "main"))
  "Code bases that get a heading in the issues area.

Each entry is (NAME . PLIST).  NAME is the heading title.  PLIST holds
:tag (an Org tag, so letters, digits and _ only), :git-dir (the
repository's git directory), :worktree-root (where issue worktrees
go), :base (the branch new issue branches start from) and :url."
  :type '(alist :key-type string :value-type plist)
  :group 'sp-org-issues)

(defcustom sp-org-issues-yadm-repo "~/.local/share/yadm/repo.git"
  "The yadm repository.

Magit lists untracked files in worktrees added from it, although the
repository sets status.showUntrackedFiles to no for the home folder."
  :type 'directory
  :group 'sp-org-issues)

(defcustom sp-org-issues-offer-worktree-removal t
  "Non-nil means offer to remove an issue's worktree when it is closed."
  :type 'boolean
  :group 'sp-org-issues)

(defconst sp-org-issues-todo-line
  "#+todo: TODO(t) NEXT(n) PROG(p!) WAIT(w@/!) | DONE(d!) CNCL(c@)"
  "Keyword line of the issues file, matching `org-gtd-keyword-mapping'.")

;; CNCL closes an issue, so vulpea-para's database checks should agree
(add-to-list 'vulpea-para-done-keywords "CNCL")

;;;; The issues area

(defun sp-org-issues--repo-heading (name plist)
  "Return the Org text of the repository heading NAME described by PLIST."
  (string-join
   (delq nil
         (list (format "** %s :%s:" name (plist-get plist :tag))
               ":PROPERTIES:"
               (format ":ID:       %s" (org-id-new))
               (format ":CATEGORY: %s"
                       (vulpea-para-category sp-org-issues-area-title name))
               (format ":GIT_DIR:  %s" (plist-get plist :git-dir))
               (format ":WORKTREE_ROOT: %s" (plist-get plist :worktree-root))
               (format ":BASE:     %s" (or (plist-get plist :base) "main"))
               (when (plist-get plist :url)
                 (format ":URL:      %s" (plist-get plist :url)))
               ":END:"))
   "\n"))

(defun sp-org-issues--area-body ()
  "Return the body of a new issues area."
  (concat
   "* Notes\n"
   "One heading per code base under Tasks.  Each issue is a TODO under its\n"
   "repository, with BRANCH, WORKTREE, PR and THREAD in its drawer.\n"
   "Capture with =C-c c I=, start work with =M-x sp-org-issues-start=,\n"
   "and see everything with =C-c o a i i=.\n\n"
   "* Tasks\n"
   (mapconcat (lambda (repo)
                (sp-org-issues--repo-heading (car repo) (cdr repo)))
              sp-org-issues-repos "\n")
   "\n\n* Archive\n"))

(defun sp-org-issues-area ()
  "Return the issues area note, or nil when there is none yet."
  (seq-find (lambda (note)
              (string= (vulpea-note-title note) sp-org-issues-area-title))
            (vulpea-para-areas)))

(defun sp-org-issues-file ()
  "Return the path of the issues file."
  (if-let* ((area (sp-org-issues-area)))
      (vulpea-note-path area)
    (user-error "No %s area yet, run M-x sp-org-issues-create-area"
                sp-org-issues-area-title)))

(defun sp-org-issues-create-area ()
  "Create the issues area, or visit it when it already exists."
  (interactive)
  (if-let* ((area (sp-org-issues-area)))
      (vulpea-visit area)
    (vulpea-visit
     (vulpea-create sp-org-issues-area-title
                    vulpea-para-capture-area-file-name
                    :tags (list vulpea-para-area-tag)
                    :head (concat sp-org-issues-todo-line
                                  "\n#+archive: ::* Archive")
                    :body (sp-org-issues--area-body)))))

(defun sp-org-issues-find ()
  "Visit the issues file."
  (interactive)
  (find-file (sp-org-issues-file)))

;;;; Capture

(defun sp-org-issues--goto-repo (name)
  "Move point to the repository heading NAME, creating it when missing."
  (goto-char (point-min))
  (let ((re (format org-complex-heading-regexp-format (regexp-quote name)))
        found)
    (while (and (not found) (re-search-forward re nil t))
      (when (= (org-current-level) 2)
        (setq found t)))
    (if found
        (beginning-of-line)
      (vulpea-para--goto-tasks-end)
      (insert (sp-org-issues--repo-heading
               name (cdr (assoc name sp-org-issues-repos)))
              "\n")
      (sp-org-issues--goto-repo name))))

(defun sp-org-issues-capture-template ()
  "Return the capture template of an issue, after asking for its repository."
  (org-capture-put :issue-repo
                   (completing-read "Repository: " sp-org-issues-repos
                                    nil t))
  (string-join
   (list "* TODO %^{Issue} %^g"
         ":PROPERTIES:"
         (format ":ID:       %s" (org-id-new))
         (format ":CREATED:  %s" (format-time-string "[%Y-%m-%d %H:%M]"))
         ":ORG_GTD:  Actions"
         ":BRANCH:"
         ":PR:"
         ":THREAD:"
         ":END:"
         "%?")
   "\n"))

(defun sp-org-issues-capture-target ()
  "Move point to the repository heading chosen by the capture template."
  (set-buffer (org-capture-target-buffer (sp-org-issues-file)))
  (org-capture-put-target-region-and-position)
  (widen)
  (sp-org-issues--goto-repo (org-capture-get :issue-repo)))

(add-to-list 'org-capture-templates
             '("I" "Issue" entry
               (function sp-org-issues-capture-target)
               (function sp-org-issues-capture-template))
             t)

;;;; Agenda

(defun sp-org-issues--agenda-files ()
  "Return the agenda files of the issue views."
  (list (sp-org-issues-file)))

(defun sp-org-issues-agenda-repo ()
  "Show the open issues of one repository."
  (interactive)
  (let* ((name (completing-read "Repository: " sp-org-issues-repos nil t))
         (tag (plist-get (cdr (assoc name sp-org-issues-repos)) :tag))
         (org-agenda-files (sp-org-issues--agenda-files))
         (vulpea-para-agenda-inhibit-files-update t)
         (org-agenda-overriding-header (format "Issues in %s" name)))
    (org-tags-view t tag)))

(dolist (command
         `(("i" . "Issues")
           ("ii" "Issue board"
            ((todo "PROG" ((org-agenda-overriding-header "In progress")))
             (todo "NEXT" ((org-agenda-overriding-header "Next")))
             (todo "WAIT" ((org-agenda-overriding-header "Waiting on review or a reply")))
             (todo "TODO" ((org-agenda-overriding-header "Open"))))
            ((org-agenda-files (sp-org-issues--agenda-files))
             (org-agenda-buffer-name "*Issues*")))
           ("ib" "Issues with a branch" tags-todo "BRANCH<>\"\""
            ((org-agenda-files (sp-org-issues--agenda-files))
             (org-agenda-overriding-header "Issues with a branch")))))
  (add-to-list 'org-agenda-custom-commands command t))

;;;; Branches and worktrees

(defmacro sp-org-issues--at-issue (&rest body)
  "Run BODY at the issue heading at point, in Org or in the agenda."
  (declare (indent 0))
  `(let ((marker (if (derived-mode-p 'org-agenda-mode)
                     (or (org-get-at-bol 'org-marker)
                         (user-error "No issue on this line"))
                   (point-marker))))
     (with-current-buffer (marker-buffer marker)
       (org-with-wide-buffer
        (goto-char marker)
        (org-back-to-heading t)
        ,@body))))

(defun sp-org-issues--git (git-dir &rest args)
  "Run git on GIT-DIR with ARGS and return its output.
Signal an error with git's message when it fails."
  (let ((default-directory (expand-file-name "~/")))
    (with-temp-buffer
      (let ((status (apply #'process-file "git" nil t nil
                           (concat "--git-dir=" (expand-file-name git-dir))
                           args)))
        (unless (zerop status)
          (user-error "git %s: %s" (string-join args " ")
                      (string-trim (buffer-string))))
        (string-trim (buffer-string))))))

(defun sp-org-issues--ref-p (git-dir ref)
  "Return non-nil when REF exists in GIT-DIR."
  (ignore-errors
    (sp-org-issues--git git-dir "rev-parse" "--verify" "--quiet" ref)
    t))

(defun sp-org-issues--slug (string)
  "Return STRING as a short branch or directory name."
  (let ((slug (replace-regexp-in-string "[^a-z0-9/]+" "-" (downcase string))))
    (string-trim (truncate-string-to-width slug 40) "-" "-")))

(defun sp-org-issues--nonempty (value)
  "Return VALUE unless it is nil or blank."
  (and value (not (string-blank-p value)) value))

(defun sp-org-issues-worktree-add (git-dir dir branch base)
  "Add a worktree at DIR for BRANCH of GIT-DIR.
Use the local BRANCH when it exists, else track origin/BRANCH, else
start BRANCH from BASE."
  (cond
   ((sp-org-issues--ref-p git-dir (concat "refs/heads/" branch))
    (sp-org-issues--git git-dir "worktree" "add" dir branch))
   ((sp-org-issues--ref-p git-dir (concat "refs/remotes/origin/" branch))
    (sp-org-issues--git git-dir "worktree" "add" "--track" "-b" branch dir
                        (concat "origin/" branch)))
   (t
    (sp-org-issues--git git-dir "worktree" "add" "-b" branch dir base))))

(defun sp-org-issues-start ()
  "Work on the issue at point in its own worktree, then open Magit there.

Asks for a branch when the issue has none, adds the worktree under the
repository's WORKTREE_ROOT when it is missing, records BRANCH and
WORKTREE on the issue, and moves a TODO or NEXT issue to PROG."
  (interactive)
  (let ((dir
         (sp-org-issues--at-issue
           (let* ((git-dir (or (org-entry-get nil "GIT_DIR" t)
                               (user-error "This heading is not in a repository")))
                  (root (or (org-entry-get nil "WORKTREE_ROOT" t)
                            (user-error "The repository has no WORKTREE_ROOT")))
                  (base (or (org-entry-get nil "BASE" t) "main"))
                  (branch (or (sp-org-issues--nonempty (org-entry-get nil "BRANCH"))
                              (read-string
                               "Branch: "
                               (concat "issue/"
                                       (sp-org-issues--slug
                                        (org-get-heading t t t t))))))
                  (dir (expand-file-name
                        (or (sp-org-issues--nonempty (org-entry-get nil "WORKTREE"))
                            (expand-file-name
                             (replace-regexp-in-string "/" "-" branch) root)))))
             (unless (file-directory-p dir)
               (sp-org-issues-worktree-add git-dir dir branch base))
             (org-entry-put nil "BRANCH" branch)
             (org-entry-put nil "WORKTREE" (abbreviate-file-name dir))
             (when (member (org-get-todo-state) '("TODO" "NEXT"))
               (org-todo "PROG"))
             dir))))
    (magit-status dir)))

(defun sp-org-issues--offer-worktree-removal ()
  "Offer to remove the worktree of an issue that was just closed."
  (when-let* (((and sp-org-issues-offer-worktree-removal
                    (member org-state '("DONE" "CNCL"))))
              (git-dir (org-entry-get nil "GIT_DIR" t))
              (dir (sp-org-issues--nonempty (org-entry-get nil "WORKTREE")))
              ((file-directory-p dir))
              ((y-or-n-p (format "Remove the worktree %s? " dir))))
    (condition-case err
        (progn
          (sp-org-issues--git git-dir "worktree" "remove" (expand-file-name dir))
          (org-entry-delete nil "WORKTREE"))
      (user-error (message "%s" (error-message-string err))))))

(add-hook 'org-after-todo-state-change-hook
          #'sp-org-issues--offer-worktree-removal)

(defun sp-org-issues--show-untracked-in-yadm-worktrees ()
  "List untracked files in Magit when this is a worktree of the yadm repo."
  (when-let* ((gitdir (magit-gitdir)))
    (when (string-prefix-p
           (file-name-as-directory
            (expand-file-name "worktrees" sp-org-issues-yadm-repo))
           (expand-file-name gitdir))
      (setq-local magit-status-show-untracked-files t))))

(with-eval-after-load 'magit
  (add-hook 'magit-status-mode-hook
            #'sp-org-issues--show-untracked-in-yadm-worktrees))

;;;; Morning list

(defcustom sp-org-issues-morning-scores
  '((ci-failed . 100) (conflict . 90) (changes-requested . 85)
    (ready . 80) (pr-gone . 75) (review . 70)
    (prog . 60) (next . 50) (ci-pending . 30)
    (wait . 20) (draft . 10) (todo . 10))
  "Base score of each kind of item in the morning list.
The pull request kinds are `ci-failed', `conflict', `changes-requested',
`ready', `review', `ci-pending' and `draft'.  `pr-gone' is an open issue
whose pull request is no longer open.  The others are issue states."
  :type '(alist :key-type symbol :value-type integer)
  :group 'sp-org-issues)

(defcustom sp-org-issues-morning-limit 10
  "Number of items shown under Today; the rest are parked."
  :type 'integer
  :group 'sp-org-issues)

(defcustom sp-org-issues-morning-park-below 25
  "Items with a lower score than this are always parked."
  :type 'integer
  :group 'sp-org-issues)

(defcustom sp-org-issues-morning-extra-repos nil
  "GitHub repositories (owner/name) to list besides those in `sp-org-issues-repos'."
  :type '(repeat string)
  :group 'sp-org-issues)

(defcustom sp-org-issues-morning-auto t
  "Non-nil means show the morning list on the first start of Emacs each day."
  :type 'boolean
  :group 'sp-org-issues)

(defcustom sp-org-issues-morning-stamp-file
  (expand-file-name "sp-org-issues-morning-day"
                    (if (boundp 'sp-cache-dir) sp-cache-dir user-emacs-directory))
  "File that remembers the day the morning list was last shown."
  :type 'file
  :group 'sp-org-issues)

(defcustom sp-org-issues-gh-program "gh"
  "The GitHub command line client, logged in with `gh auth login'."
  :type 'string
  :group 'sp-org-issues)

(defconst sp-org-issues-morning--pr-fields
  "number,title,url,isDraft,reviewDecision,mergeable,baseRefName,headRefName,updatedAt,statusCheckRollup"
  "The fields asked of `gh pr list'.")

(defun sp-org-issues-morning--ci (rollup)
  "Return `failure', `pending' or `success' for the check ROLLUP.
Return nil when ROLLUP is empty."
  (let (failed pending)
    (dolist (check rollup)
      (let ((conclusion (alist-get 'conclusion check))
            (status (alist-get 'status check))
            (state (alist-get 'state check)))
        (cond
         ((member conclusion '("FAILURE" "TIMED_OUT" "CANCELLED" "ACTION_REQUIRED"
                               "STARTUP_FAILURE"))
          (setq failed t))
         ((member state '("FAILURE" "ERROR")) (setq failed t))
         ((member state '("PENDING" "EXPECTED")) (setq pending t))
         ((and status (not (equal status "COMPLETED"))) (setq pending t)))))
    (cond (failed 'failure) (pending 'pending) (rollup 'success))))

(defun sp-org-issues-morning--parse-prs (json label)
  "Return the pull requests in the JSON of `gh pr list'.
Tag each with the repository LABEL."
  (mapcar (lambda (pr)
            (list :repo label
                  :number (alist-get 'number pr)
                  :title (alist-get 'title pr)
                  :url (alist-get 'url pr)
                  :draft (and (alist-get 'isDraft pr) t)
                  :decision (or (alist-get 'reviewDecision pr) "")
                  :mergeable (alist-get 'mergeable pr)
                  :base (alist-get 'baseRefName pr)
                  :head (alist-get 'headRefName pr)
                  :updated (alist-get 'updatedAt pr)
                  :ci (sp-org-issues-morning--ci (alist-get 'statusCheckRollup pr))))
          (json-parse-string json :object-type 'alist :array-type 'list
                             :null-object nil :false-object nil)))

(defun sp-org-issues-morning--pr-number (value)
  "Return the pull request number at the end of VALUE (a URL, #17 or 17), or nil."
  (when (and value (string-match "\\([0-9]+\\)/?[[:space:]]*\\'" value))
    (string-to-number (match-string 1 value))))

(defun sp-org-issues-morning--repo-slug (url)
  "Return owner/name for the GitHub URL, or nil."
  (when (and url (string-match "github\\.com[/:]\\([^/]+/[^/]+?\\)\\(?:\\.git\\)?/?\\'" url))
    (match-string 1 url)))

(defun sp-org-issues-morning--repos ()
  "Return the (LABEL . OWNER/NAME) pairs whose pull requests are listed."
  (append
   (delq nil
         (mapcar (lambda (repo)
                   (when-let* ((slug (sp-org-issues-morning--repo-slug
                                      (plist-get (cdr repo) :url))))
                     (cons (car repo) slug)))
                 sp-org-issues-repos))
   (mapcar (lambda (slug) (cons slug slug)) sp-org-issues-morning-extra-repos)))

(defun sp-org-issues-morning--pr-category (pr)
  "Return the category of the pull request PR."
  (let ((ci (plist-get pr :ci))
        (decision (plist-get pr :decision)))
    (cond
     ((plist-get pr :draft) 'draft)
     ((eq ci 'failure) 'ci-failed)
     ((equal (plist-get pr :mergeable) "CONFLICTING") 'conflict)
     ((equal decision "CHANGES_REQUESTED") 'changes-requested)
     ((and (equal decision "APPROVED") (not (eq ci 'pending))) 'ready)
     ((eq ci 'pending) 'ci-pending)
     (t 'review))))

(defun sp-org-issues-morning--stack-depth (pr prs)
  "Return (DEPTH . PARENT) of PR among PRS.
DEPTH is how many open pull requests PR is stacked on and PARENT is the
number of the one directly below it, or nil."
  (let ((depth 0) (parent nil) (current pr) (limit (length prs)))
    (while (and (< depth limit)
                (when-let* ((below (seq-find
                                    (lambda (other)
                                      (and (equal (plist-get other :repo)
                                                  (plist-get current :repo))
                                           (equal (plist-get other :head)
                                                  (plist-get current :base))))
                                    prs)))
                  (unless parent (setq parent (plist-get below :number)))
                  (setq current below)
                  (cl-incf depth))))
    (cons depth parent)))

(defconst sp-org-issues-morning--reasons
  '((ci-failed . "checks are failing")
    (conflict . "merge conflict")
    (changes-requested . "changes were requested")
    (ready . "approved, ready to merge")
    (review . "waiting for your review")
    (ci-pending . "checks are still running")
    (draft . "draft"))
  "Why a pull request of each category is in the list.")

(defun sp-org-issues-morning--age-days (updated now)
  "Return the whole days from the ISO time UPDATED to NOW."
  (if updated
      (max 0 (floor (/ (float-time (time-subtract now (date-to-time updated)))
                       86400)))
    0))

(defun sp-org-issues-morning--pr-score (pr prs now)
  "Return (SCORE . REASON) of the pull request PR among PRS at NOW."
  (let* ((category (sp-org-issues-morning--pr-category pr))
         (stack (sp-org-issues-morning--stack-depth pr prs))
         (age (if (memq category '(review ready changes-requested))
                  (min 10 (sp-org-issues-morning--age-days (plist-get pr :updated) now))
                0))
         (reason (alist-get category sp-org-issues-morning--reasons)))
    (cons (+ (alist-get category sp-org-issues-morning-scores)
             age
             (* -15 (car stack)))
          (if (cdr stack)
              (format "%s, but only after #%d" reason (cdr stack))
            reason))))

(defun sp-org-issues-morning--issues-in-buffer ()
  "Return the open issues of the Org buffer, as plists."
  (let (issues)
    (org-with-wide-buffer
     (org-map-entries
      (lambda ()
        (let ((state (org-get-todo-state)))
          (when (member state '("TODO" "NEXT" "PROG" "WAIT"))
            (push (list :title (org-get-heading t t t t)
                        :state (intern (downcase state))
                        :repo (nth 1 (org-get-outline-path))
                        :id (org-entry-get nil "ID")
                        :pr (sp-org-issues-morning--pr-number
                             (org-entry-get nil "PR"))
                        :branch (sp-org-issues--nonempty (org-entry-get nil "BRANCH"))
                        :thread (sp-org-issues--nonempty (org-entry-get nil "THREAD"))
                        :deadline (when-let* ((d (org-entry-get nil "DEADLINE")))
                                    (org-time-string-to-time d))
                        :scheduled (when-let* ((s (org-entry-get nil "SCHEDULED")))
                                     (org-time-string-to-time s)))
                  issues))))))
    (nreverse issues)))

(defun sp-org-issues-morning--issues (file)
  "Return the open issues of the Org FILE."
  (with-current-buffer (find-file-noselect file)
    (sp-org-issues-morning--issues-in-buffer)))

(defun sp-org-issues-morning--days-from (time now)
  "Return the calendar days from NOW to TIME, negative when TIME is past."
  (- (time-to-days time) (time-to-days now)))

(defun sp-org-issues-morning--issue-score (issue now)
  "Return (SCORE . REASON) of the open ISSUE at NOW."
  (let* ((state (plist-get issue :state))
         (deadline (plist-get issue :deadline))
         (scheduled (plist-get issue :scheduled))
         (deadline-days (and deadline (sp-org-issues-morning--days-from deadline now)))
         (score (alist-get state sp-org-issues-morning-scores)))
    (cons (+ score
             (cond ((null deadline-days) 0)
                   ((<= deadline-days 0) 30)
                   ((<= deadline-days 3) 15)
                   (t 0))
             (if (and scheduled (<= (sp-org-issues-morning--days-from scheduled now) 0))
                 10 0))
          (concat (pcase state
                    ('prog "in progress") ('next "next action")
                    ('wait "waiting") ('todo "not started"))
                  (cond ((null deadline-days) "")
                        ((< deadline-days 0) ", overdue")
                        ((= deadline-days 0) ", due today")
                        ((<= deadline-days 3)
                         (format ", due in %d day%s" deadline-days
                                 (if (= deadline-days 1) "" "s")))
                        (t ""))))))

(defun sp-org-issues-morning--items (issues prs now &optional fetched)
  "Return the ranked items for ISSUES and PRS at NOW, best first.
FETCHED lists the repositories whose pull requests were read."
  (let ((rest-prs (copy-sequence prs))
        items)
    (dolist (issue issues)
      (let* ((repo (plist-get issue :repo))
             (number (plist-get issue :pr))
             (pr (and number
                      (seq-find (lambda (p) (and (equal (plist-get p :repo) repo)
                                                 (eql (plist-get p :number) number)))
                                prs)))
             (own (sp-org-issues-morning--issue-score issue now))
             (best own))
        (cond
         (pr
          (setq rest-prs (delq pr rest-prs))
          (let ((theirs (sp-org-issues-morning--pr-score pr prs now)))
            (when (> (car theirs) (car own)) (setq best theirs))))
         ((and number (member repo fetched))
          (setq best (cons (+ (alist-get 'pr-gone sp-org-issues-morning-scores)
                              (- (car own) (alist-get (plist-get issue :state)
                                                      sp-org-issues-morning-scores)))
                           (format "PR #%d is no longer open: close the issue" number)))))
        (push (list :score (car best) :reason (cdr best)
                    :title (plist-get issue :title) :repo repo
                    :number (or number (and pr (plist-get pr :number)))
                    :url (and pr (plist-get pr :url)) :id (plist-get issue :id))
              items)))
    (dolist (pr rest-prs)
      (let ((score (sp-org-issues-morning--pr-score pr prs now)))
        (push (list :score (car score) :reason (cdr score)
                    :title (plist-get pr :title) :repo (plist-get pr :repo)
                    :number (plist-get pr :number) :url (plist-get pr :url))
              items)))
    (seq-sort-by (lambda (item) (plist-get item :score)) #'> (nreverse items))))

(defun sp-org-issues-morning--line (item)
  "Return the Org list line of ITEM."
  (let* ((title (plist-get item :title))
         (id (plist-get item :id))
         (url (plist-get item :url))
         (number (plist-get item :number))
         (repo (plist-get item :repo))
         (where (cond ((and url number) (format "[[%s][%s #%s]]" url repo number))
                      (number (format "%s #%s" repo number))
                      (t repo))))
    (format "- %s :: %s (%d)"
            (if id
                (format "[[id:%s][%s]] (%s)" id title where)
              (format "%s %s" where title))
            (plist-get item :reason)
            (plist-get item :score))))

(defun sp-org-issues-morning--render (items now &optional notes)
  "Return the Org text of the morning list for ITEMS at NOW, with NOTES."
  (let* ((today (seq-take (seq-filter (lambda (item)
                                        (>= (plist-get item :score)
                                            sp-org-issues-morning-park-below))
                                      items)
                          sp-org-issues-morning-limit))
         (parked (seq-remove (lambda (item) (memq item today)) items)))
    (concat
     (format-time-string "#+title: Morning %F %a\n" now)
     "Ranked by score, see `sp-org-issues-morning-scores'.  Press g to refresh.\n"
     (mapconcat (lambda (note) (format "\n/%s/\n" note)) notes "")
     "\n* Today\n"
     (if today
         (concat (mapconcat #'sp-org-issues-morning--line today "\n") "\n")
       "Nothing needs you today.\n")
     (when parked
       (concat "\n* Parked\n"
               (mapconcat #'sp-org-issues-morning--line parked "\n")
               "\n")))))

(defun sp-org-issues-morning--fetch (repos callback)
  "Read the open pull requests of REPOS, then call CALLBACK.
REPOS is a list of (LABEL . OWNER/NAME).  CALLBACK gets the pull requests
and the labels of the repositories that could not be read."
  (let ((prs nil) (failed nil) (todo (copy-sequence repos)))
    (cl-labels
        ((next ()
           (if (null todo)
               (funcall callback prs (nreverse failed))
             (let* ((repo (pop todo))
                    (out (generate-new-buffer " *sp-gh*"))
                    (err (generate-new-buffer " *sp-gh-err*")))
               (make-process
                :name "sp-gh" :buffer out :stderr err :noquery t
                :command (list sp-org-issues-gh-program "pr" "list"
                               "--repo" (cdr repo) "--state" "open"
                               "--limit" "50"
                               "--json" sp-org-issues-morning--pr-fields)
                :sentinel
                (lambda (process _event)
                  (unless (process-live-p process)
                    (condition-case nil
                        (if (zerop (process-exit-status process))
                            (setq prs (append prs (sp-org-issues-morning--parse-prs
                                                   (with-current-buffer out (buffer-string))
                                                   (car repo))))
                          (push (car repo) failed))
                      (error (push (car repo) failed)))
                    (kill-buffer out)
                    (kill-buffer err)
                    (next))))))))
      (next))))

(defvar sp-org-issues-morning-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "g" #'sp-org-issues-morning)
    (define-key map "q" #'quit-window)
    map)
  "Keymap of `sp-org-issues-morning-mode'.")

(define-derived-mode sp-org-issues-morning-mode org-mode "Morning"
  "Org mode for the read-only morning list.")

(defun sp-org-issues-morning--show (issues prs failed repos &optional notes)
  "Show the morning list for ISSUES and PRS.
FAILED lists the repositories that could not be read, out of REPOS.
NOTES are extra remarks for the top of the list."
  (let* ((now (current-time))
         (fetched (seq-remove (lambda (label) (member label failed))
                              (mapcar #'car repos)))
         (notes (append (mapcar (lambda (label)
                                  (format "GitHub could not be read for %s" label))
                                failed)
                        notes))
         (text (sp-org-issues-morning--render
                (sp-org-issues-morning--items issues prs now fetched) now notes)))
    (with-current-buffer (get-buffer-create "*Morning*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (sp-org-issues-morning-mode)
        (goto-char (point-min)))
      (setq buffer-read-only t)
      (pop-to-buffer (current-buffer)))))

;;;###autoload
(defun sp-org-issues-morning ()
  "Show what to do next: open issues and pull requests, ranked."
  (interactive)
  (let ((issues (sp-org-issues-morning--issues (sp-org-issues-file)))
        (repos (sp-org-issues-morning--repos)))
    (if (and repos (executable-find sp-org-issues-gh-program))
        (sp-org-issues-morning--fetch
         repos (lambda (prs failed)
                 (sp-org-issues-morning--show issues prs failed repos)))
      (sp-org-issues-morning--show
       issues nil nil nil
       (when repos
         (list (format "%s was not found, so pull requests are not listed"
                       sp-org-issues-gh-program)))))))

(defun sp-org-issues-morning-greet ()
  "Show the morning list when it has not been shown today."
  (let ((today (format-time-string "%F")))
    (unless (equal today
                   (ignore-errors
                     (with-temp-buffer
                       (insert-file-contents sp-org-issues-morning-stamp-file)
                       (string-trim (buffer-string)))))
      (condition-case err
          (progn
            (make-directory (file-name-directory sp-org-issues-morning-stamp-file) t)
            (write-region today nil sp-org-issues-morning-stamp-file nil 'silent)
            (sp-org-issues-morning))
        (error (message "Morning list: %s" (error-message-string err)) nil)))))

(defun sp-org-issues-morning--schedule ()
  "Greet once Emacs is idle after startup."
  (when sp-org-issues-morning-auto
    (run-with-idle-timer 2 nil #'sp-org-issues-morning-greet)))

(add-hook 'emacs-startup-hook #'sp-org-issues-morning--schedule)

;;; Provide:

(provide 'sp-org-issues)
;; sp-org-issues.el ends here.
