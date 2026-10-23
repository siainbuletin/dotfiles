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
;;
;; Load it after sp-org-ext: it adds to the capture templates and agenda
;; commands that sp-vulpea-para sets.

;;; Code:

(require 'org)
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
  :group 'spcustom)

(defcustom sp-org-issues-repos
  `(("dotfiles"
     :tag "dotfiles"
     :git-dir ,sp-yadm-repo
     :worktree-root ,(sp-path sp-src-dir "dotfiles-wt/")
     :base "main"
     :url "https://github.com/siainbuletin/dotfiles")
    ("vulpea-mcp"
     :tag "vulpea"
     :git-dir ,(sp-path sp-clones-dir "cloned-scan-ai/vulpea-mcp/.git")
     :worktree-root ,(sp-path sp-src-dir "vulpea-mcp-wt/")
     :base "main"))
  "Code bases that get a heading in the issues area.

Each entry is (NAME . PLIST).  NAME is the heading title.  PLIST holds
:tag (an Org tag, so letters, digits and _ only), :git-dir (the
repository's git directory), :worktree-root (where issue worktrees
go), :base (the branch new issue branches start from) and :url."
  :type '(alist :key-type string :value-type plist)
  :group 'spcustom)

(defcustom sp-org-issues-yadm-repo sp-yadm-repo
  "The yadm repository.

Magit lists untracked files in worktrees added from it, although the
repository sets status.showUntrackedFiles to no for the home folder."
  :type 'directory
  :group 'spcustom)

(defcustom sp-org-issues-offer-worktree-removal t
  "Non-nil means offer to remove an issue's worktree when it is closed."
  :type 'boolean
  :group 'spcustom)

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

;;; Provide:

(provide 'sp-org-issues)
;; sp-org-issues.el ends here.
