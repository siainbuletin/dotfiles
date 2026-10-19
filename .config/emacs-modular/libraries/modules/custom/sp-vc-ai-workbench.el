;;; sp-vc-ai-workbench.el --- Parallel work on many extensions with Magit + Claude Code -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1") (magit "3.3") (transient "0.4") (claude-code "0.1"))

;;; Commentary:
;;
;; Generated from sp-vc-ai-workbench.org -- edit that file, not this one.
;;
;; One git worktree per task, one notes file and one Claude Code session
;; per worktree.  Entry point: M-x sp-workbench-menu.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'transient)
(require 'tabulated-list)
(require 'claude-code)

(declare-function claude-code-send-command "claude-code")
(declare-function claude-code--find-claude-buffers-for-directory "claude-code")

(defgroup sp-workbench nil
  "Parallel extension development with Magit worktrees and Claude Code."
  :group 'tools
  :prefix "sp-workbench-")

(defcustom sp-workbench-repos nil
  "List of directories, each the root of one extension's git repo."
  :type '(repeat directory))

(defcustom sp-workbench-scan-root nil
  "If non-nil, every git repo directly under this directory is also an extension."
  :type '(choice (const nil) directory))

(defcustom sp-workbench-worktree-root "~/.worktrees/"
  "Directory under which task worktrees are created.
Layout: ROOT/<extension>/<branch-with-slashes-replaced>."
  :type 'directory)

(defcustom sp-workbench-branch-prefix "feat/"
  "Prefix proposed when naming a new task branch."
  :type 'string)

(defcustom sp-workbench-notes-file ".brainstorm.org"
  "Name of the per-worktree notes file (kept out of git)."
  :type 'string)

(defcustom sp-workbench-context-file ".brainstorm-context.md"
  "Name of the per-worktree context file written for Claude (kept out of git)."
  :type 'string)

(defcustom sp-workbench-start-claude-on-new-task nil
  "If non-nil, start a Claude Code session when creating a new task."
  :type 'boolean)

(defcustom sp-workbench-claude-capture-lines 80
  "Lines taken from the end of the Claude buffer when no region is active."
  :type 'integer)

(defcustom sp-workbench-max-context-chars 12000
  "Upper bound on characters of each context section written for Claude."
  :type 'integer)

(defcustom sp-workbench-rules
  "We are brainstorming the design of an Emacs extension.  I am an experienced \
Emacs Lisp developer; do not explain basics.
- Help me think: ask clarifying questions that expose hidden assumptions, \
give 2-4 design options with trade-offs, point out edge cases (Windows/WSL \
paths, large buffers, org versions, byte-compilation, autoloads), suggest \
API and naming, and propose a small next step.
- Do not edit any file, except that when I explicitly ask you to record \
something you may append it under the `* Claude' heading at the end of \
.brainstorm.org, as an org-mode `**' subheading.
- Use short elisp snippets only to illustrate an interface, never whole \
implementations.  Be concise and say so when unsure."
  "Ground rules placed at the top of the context file."
  :type 'string)

(defun sp-workbench--repos ()
  "Return the list of extension repo roots (absolute, no trailing slash)."
  (let ((dirs (mapcar #'expand-file-name sp-workbench-repos)))
    (when (and sp-workbench-scan-root
               (file-directory-p sp-workbench-scan-root))
      (dolist (d (directory-files (expand-file-name sp-workbench-scan-root) t
                                  directory-files-no-dot-files-regexp))
        (when (and (file-directory-p d)
                   (file-exists-p (expand-file-name ".git" d)))
          (push d dirs))))
    (delete-dups (mapcar #'directory-file-name dirs))))

(defun sp-workbench--name (repo)
  "Short extension name for REPO."
  (file-name-nondirectory (directory-file-name repo)))

(defun sp-workbench--worktrees (repo)
  "Return list of plists (:path :branch :dirty) for each worktree of REPO."
  (let ((default-directory (file-name-as-directory repo)))
    (mapcar
     (lambda (wt)
       (let* ((path (car wt))
              (branch (nth 2 wt))
              (default-directory (file-name-as-directory path)))
         (list :path (directory-file-name path)
               :branch (or branch "(detached)")
               :dirty (and (file-directory-p path)
                           (magit-anything-modified-p)))))
     (magit-list-worktrees))))

(defun sp-workbench--all-worktrees ()
  "Return list of (EXTENSION . PLIST) across all repos."
  (cl-loop for repo in (sp-workbench--repos)
           append (cl-loop for wt in (sp-workbench--worktrees repo)
                           collect (cons (sp-workbench--name repo)
                                         (plist-put wt :repo repo)))))

(unless (fboundp 'magit-main-worktree)
  (defun magit-main-worktree (dir)
    "Fallback: return the main worktree path for the repo containing DIR."
    (let ((default-directory (file-name-as-directory dir)))
      (directory-file-name (car (car (magit-list-worktrees)))))))

(defun sp-workbench--read-repo ()
  "Prompt for an extension repo, defaulting to the current one."
  (let* ((repos (sp-workbench--repos))
         (cur (when-let ((top (magit-toplevel)))
                (cl-find-if (lambda (r) (file-equal-p r (magit-main-worktree top)))
                            repos)))
         (names (mapcar (lambda (r) (cons (sp-workbench--name r) r)) repos)))
    (unless repos (user-error "No extensions: set `sp-workbench-repos'"))
    (cdr (assoc (completing-read "Extension: " names nil t nil nil
                                 (and cur (sp-workbench--name cur)))
                names))))

(defun sp-workbench--read-worktree ()
  "Prompt for any worktree of any extension; return its plist."
  (let* ((all (sp-workbench--all-worktrees))
         (cands (mapcar (lambda (e)
                          (cons (format "%s: %s%s" (car e)
                                        (plist-get (cdr e) :branch)
                                        (if (plist-get (cdr e) :dirty) " *" ""))
                                (cdr e)))
                        all)))
    (unless cands (user-error "No worktrees found"))
    (cdr (assoc (completing-read "Worktree: " cands nil t) cands))))

(defun sp-workbench--current-worktree ()
  "Return the toplevel of the worktree we are in, or signal an error."
  (directory-file-name
   (or (magit-toplevel) (user-error "Not inside a git worktree"))))

(defun sp-workbench--notes-path (dir)
  "Path of the notes file in worktree DIR."
  (expand-file-name sp-workbench-notes-file dir))

(defun sp-workbench--visit-notes (dir)
  "Visit the notes file of DIR (auto-reverting, since Claude may edit it)."
  (let ((buf (find-file-noselect (sp-workbench--notes-path dir))))
    (with-current-buffer buf (auto-revert-mode 1))
    (pop-to-buffer-same-window buf)))

(defun sp-workbench--ignore-local-files (dir)
  "Add the notes and context files to the repo's local exclude list, from DIR."
  (let* ((default-directory (file-name-as-directory dir))
         (rel (magit-git-string "rev-parse" "--git-path" "info/exclude"))
         (file (and rel (expand-file-name rel dir))))
    (when file
      (make-directory (file-name-directory file) t)
      (dolist (line (list sp-workbench-notes-file sp-workbench-context-file))
        (unless (and (file-exists-p file)
                     (with-temp-buffer
                       (insert-file-contents file)
                       (re-search-forward
                        (concat "^" (regexp-quote line) "$") nil t)))
          (write-region (concat line "\n") nil file t 'silent))))))

(defun sp-workbench--init-notes (dir extension branch goal)
  "Create the notes file in worktree DIR for EXTENSION/BRANCH with GOAL."
  (let ((file (sp-workbench--notes-path dir)))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert (format "#+title: %s / %s\n" extension branch)
                (format "#+created: %s\n\n"
                        (format-time-string "[%Y-%m-%d %a %H:%M]"))
                "* Goal\n" (if (string-empty-p goal) "\n" (concat goal "\n"))
                "* Notes\n\n"
                "* Open questions\n\n"
                "* Claude\n")))
    (sp-workbench--ignore-local-files dir)
    file))

(defun sp-workbench--append-to-notes (dir title body)
  "Append a `**' entry TITLE with BODY (in an example block) to DIR's notes."
  (let ((buf (find-file-noselect (sp-workbench--notes-path dir))))
    (with-current-buffer buf
      (auto-revert-mode 1)
      (save-excursion
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (format "\n** %s  /%s/\n#+begin_example\n%s\n#+end_example\n"
                        title (format-time-string "%Y-%m-%d %H:%M")
                        (string-trim-right body))))
      (save-buffer))
    buf))

(defun sp-workbench--worktree-dir (repo branch)
  "Directory for a new worktree of REPO on BRANCH."
  (expand-file-name (replace-regexp-in-string "/" "-" branch)
                    (expand-file-name (sp-workbench--name repo)
                                      sp-workbench-worktree-root)))

;;;###autoload
(defun sp-workbench-new-task (repo branch goal)
  "Create a worktree + branch for a new task in extension REPO.
BRANCH is the new branch name; GOAL is a one-line description that seeds
the notes file.  Opens the notes file and Magit status side by side."
  (interactive
   (let* ((repo (sp-workbench--read-repo))
          (branch (read-string "New branch: " sp-workbench-branch-prefix))
          (goal (read-string "Goal (one line): ")))
     (list repo branch goal)))
  (let* ((dir (sp-workbench--worktree-dir repo branch))
         (default-directory (file-name-as-directory repo))
         (start (magit-main-branch)))
    (when (file-exists-p dir)
      (user-error "Worktree directory already exists: %s" dir))
    (make-directory (file-name-directory dir) t)
    (magit-worktree-branch dir branch start)
    (sp-workbench--init-notes dir (sp-workbench--name repo) branch goal)
    (delete-other-windows)
    (sp-workbench--visit-notes dir)
    (magit-status-setup-buffer dir)
    (display-buffer (current-buffer) '(display-buffer-in-side-window
                                       (side . right)))
    (when sp-workbench-start-claude-on-new-task
      (sp-workbench-claude-open dir))
    (message "Task ready: %s" dir)))

;;;###autoload
(defun sp-workbench-finish-task ()
  "Remove the current worktree, refusing if it is dirty or unmerged.
Any Claude Code session for the worktree is killed first."
  (interactive)
  (let* ((dir (sp-workbench--current-worktree))
         (main (magit-main-worktree dir))
         (branch (magit-get-current-branch))
         (default-directory (file-name-as-directory main)))
    (when (file-equal-p dir main)
      (user-error "This is the main worktree; nothing to finish"))
    (let ((default-directory (file-name-as-directory dir)))
      (when (magit-anything-modified-p)
        (user-error "Worktree has uncommitted changes")))
    (when (and branch
               (not (magit-git-success "merge-base" "--is-ancestor"
                                       branch (magit-main-branch))))
      (unless (yes-or-no-p
               (format "%s is not merged into %s.  Remove anyway? "
                       branch (magit-main-branch)))
        (user-error "Aborted")))
    (when-let ((buf (get-file-buffer (sp-workbench--notes-path dir))))
      (with-current-buffer buf (save-buffer)))
    (dolist (b (sp-workbench--claude-buffers dir))
      (let ((kill-buffer-query-functions nil))
        (kill-buffer b)))
    (magit-worktree-delete dir)))

;;;###autoload
(defun sp-workbench-switch ()
  "Jump to any task: open its notes file and Magit status."
  (interactive)
  (let* ((wt (sp-workbench--read-worktree))
         (path (plist-get wt :path)))
    (delete-other-windows)
    (if (file-exists-p (sp-workbench--notes-path path))
        (sp-workbench--visit-notes path)
      (dired path))
    (magit-status-setup-buffer path)
    (display-buffer (current-buffer) '(display-buffer-in-side-window
                                       (side . right)))))

(defvar sp-workbench-dashboard-mode-map
  (let ((m (make-sparse-keymap)))
    (set-keymap-parent m tabulated-list-mode-map)
    (define-key m (kbd "RET") #'sp-workbench-dashboard-visit)
    (define-key m (kbd "m")   #'sp-workbench-dashboard-magit)
    (define-key m (kbd "c")   #'sp-workbench-dashboard-claude)
    (define-key m (kbd "n")   #'sp-workbench-new-task)
    (define-key m (kbd "?")   #'sp-workbench-menu)
    m))

(define-derived-mode sp-workbench-dashboard-mode tabulated-list-mode
  "SpWorkbench"
  "Overview of every extension worktree."
  (setq tabulated-list-format
        [("Extension" 22 t) ("Branch" 34 t) ("State" 8 t)
         ("Claude" 7 t) ("Path" 0 t)])
  (setq tabulated-list-sort-key '("Extension"))
  (add-hook 'tabulated-list-revert-hook
            #'sp-workbench--dashboard-refresh nil t))

(defun sp-workbench--dashboard-refresh ()
  "Rebuild the dashboard entries."
  (setq tabulated-list-entries
        (cl-loop for (ext . wt) in (sp-workbench--all-worktrees)
                 for path = (plist-get wt :path)
                 collect (list path
                               (vector ext
                                       (plist-get wt :branch)
                                       (if (plist-get wt :dirty) "dirty" "clean")
                                       (if (sp-workbench--claude-buffers path)
                                           "live" "-")
                                       (abbreviate-file-name path))))))

;;;###autoload
(defun sp-workbench-dashboard ()
  "Show all extensions and their worktrees."
  (interactive)
  (let ((buf (get-buffer-create "*sp-workbench*")))
    (with-current-buffer buf
      (sp-workbench-dashboard-mode)
      (sp-workbench--dashboard-refresh)
      (tabulated-list-init-header)
      (tabulated-list-print t))
    (pop-to-buffer buf)))

(defun sp-workbench--dashboard-path ()
  "Worktree path at point in the dashboard."
  (or (tabulated-list-get-id) (user-error "No worktree here")))

(defun sp-workbench-dashboard-visit ()
  "Open the notes of the worktree at point."
  (interactive)
  (let ((path (sp-workbench--dashboard-path)))
    (if (file-exists-p (sp-workbench--notes-path path))
        (sp-workbench--visit-notes path)
      (dired path))))

(defun sp-workbench-dashboard-magit ()
  "Open Magit status for the worktree at point."
  (interactive)
  (magit-status-setup-buffer (sp-workbench--dashboard-path)))

(defun sp-workbench-dashboard-claude ()
  "Open (or start) the Claude Code session for the worktree at point."
  (interactive)
  (sp-workbench-claude-open (sp-workbench--dashboard-path)))

(defun sp-workbench--dir-variants (dir)
  "Spellings of DIR that may appear in a Claude buffer name."
  (let ((d (directory-file-name (expand-file-name dir))))
    (delete-dups
     (list d (concat d "/")
           (abbreviate-file-name d) (concat (abbreviate-file-name d) "/")
           (directory-file-name (file-truename d))
           (concat (directory-file-name (file-truename d)) "/")))))

(defun sp-workbench--claude-buffers (dir)
  "Live Claude Code buffers belonging to worktree DIR."
  (let* ((variants (sp-workbench--dir-variants dir))
         (found
          (cl-remove-if-not
           (lambda (b)
             (let ((n (buffer-name b)))
               (and (string-prefix-p "*claude:" n)
                    (buffer-live-p b)
                    (cl-some (lambda (v) (string-search (concat ":" v) n))
                             variants))))
           (buffer-list))))
    (or found
        (when (fboundp 'claude-code--find-claude-buffers-for-directory)
          (ignore-errors
            (claude-code--find-claude-buffers-for-directory
             (file-name-as-directory dir)))))))

(defun sp-workbench--claude-buffer-p (buf)
  "Non-nil if BUF is a Claude Code buffer."
  (string-prefix-p "*claude:" (buffer-name buf)))

;;;###autoload
(defun sp-workbench-claude-open (&optional dir)
  "Show the Claude Code session for worktree DIR, starting one if needed.
DIR defaults to the current worktree."
  (interactive)
  (let* ((dir (or dir (sp-workbench--current-worktree)))
         (default-directory (file-name-as-directory dir)))
    (sp-workbench--ignore-local-files dir)
    (if-let ((buf (car (sp-workbench--claude-buffers dir))))
        (pop-to-buffer buf)
      (claude-code))))

(defun sp-workbench--truncate (s)
  "Truncate S to `sp-workbench-max-context-chars', keeping the tail."
  (if (> (length s) sp-workbench-max-context-chars)
      (concat "[...truncated...]\n"
              (substring s (- (length s) sp-workbench-max-context-chars)))
    s))

(defun sp-workbench--write-context (dir selection source)
  "Write the context file for worktree DIR.
SELECTION is region text (or nil); SOURCE describes where it came from."
  (let* ((default-directory (file-name-as-directory dir))
         (main (magit-main-branch))
         (branch (or (magit-get-current-branch) "(detached)"))
         (log (string-join
               (magit-git-lines "log" "--oneline" "--no-decorate" "-n" "30"
                                (format "%s..HEAD" main))
               "\n"))
         (stat (string-join (magit-git-lines "diff" "--stat" main) "\n"))
         (file (expand-file-name sp-workbench-context-file dir)))
    (with-temp-file file
      (insert "# Brainstorm context\n\n"
              "## Ground rules\n" sp-workbench-rules "\n\n"
              (format "## Worktree\nExtension: %s\nBranch: %s\nBase: %s\n\n"
                      (sp-workbench--name (magit-main-worktree dir))
                      branch main)
              "## Commits ahead of base\n"
              (if (string-empty-p log) "(none yet)" log) "\n\n"
              "## Diff summary vs base\n"
              (if (string-empty-p stat) "(no changes)" stat) "\n")
      (when selection
        (insert (format "\n## Code under discussion (%s)\n```elisp\n%s\n```\n"
                        source (sp-workbench--truncate selection)))))
    file))

(defun sp-workbench--send-to-claude (dir prompt)
  "Send one-line PROMPT to the Claude session of worktree DIR.
If no session exists, start one and put PROMPT on the kill ring instead."
  (let ((default-directory (file-name-as-directory dir))
        (line (replace-regexp-in-string "[\n\r]+" " " prompt)))
    (if (sp-workbench--claude-buffers dir)
        (claude-code-send-command line)
      (kill-new line)
      (claude-code)
      (message "Claude is starting; prompt copied, paste it with C-y when ready"))))

;;;###autoload
(defun sp-workbench-claude-ask (question)
  "Ask Claude QUESTION about the current worktree.
Branch context and the active region (if any) go into the context file;
Claude is pointed at that file and at the notes."
  (interactive (list (read-string "Ask Claude: ")))
  (when (string-empty-p (string-trim question))
    (user-error "Empty question"))
  (let* ((dir (sp-workbench--current-worktree))
         (selection (and (use-region-p)
                         (buffer-substring-no-properties
                          (region-beginning) (region-end))))
         (source (when selection
                   (format "%s:%d-%d"
                           (if buffer-file-name
                               (file-relative-name buffer-file-name dir)
                             (buffer-name))
                           (line-number-at-pos (region-beginning))
                           (line-number-at-pos (region-end))))))
    (sp-workbench--init-notes dir
                              (sp-workbench--name (magit-main-worktree dir))
                              (or (magit-get-current-branch) "(detached)") "")
    (sp-workbench--write-context dir selection source)
    (sp-workbench--send-to-claude
     dir
     (format "Read %s (ground rules and context) and %s (my running notes), then: %s"
             sp-workbench-context-file sp-workbench-notes-file question))))

;;;###autoload
(defun sp-workbench-claude-kickoff ()
  "Ask Claude for an initial design discussion based on the Goal in the notes."
  (interactive)
  (sp-workbench-claude-ask
   "What are the key design decisions, hidden assumptions and risks before I start? Propose a small first step."))

(defun sp-workbench--clean-terminal-text (text)
  "Strip ANSI escapes, TUI borders and trailing space from TEXT."
  (let ((s (replace-regexp-in-string "\e\\[[0-9;?]*[ -/]*[@-~]" "" text)))
    (setq s (replace-regexp-in-string "^[│┃] ?" "" s))
    (setq s (replace-regexp-in-string " ?[│┃]$" "" s))
    (setq s (replace-regexp-in-string "^[╭╰][─ ]*[╮╯]?$" "" s))
    (setq s (replace-regexp-in-string "[ \t]+$" "" s))
    (string-trim (replace-regexp-in-string "\n\\{3,\\}" "\n\n" s))))

;;;###autoload
(defun sp-workbench-claude-capture (&optional visit)
  "Copy output from the Claude buffer into the notes file.
Uses the active region if called from the Claude buffer with one (in eat/vterm,
select it in copy mode), otherwise the last `sp-workbench-claude-capture-lines'
lines.  With prefix argument VISIT, show the notes afterwards."
  (interactive "P")
  (let* ((dir (sp-workbench--current-worktree))
         (cbuf (if (sp-workbench--claude-buffer-p (current-buffer))
                   (current-buffer)
                 (or (car (sp-workbench--claude-buffers dir))
                     (user-error "No Claude session for this worktree"))))
         (raw (with-current-buffer cbuf
                (if (and (eq cbuf (current-buffer)) (use-region-p))
                    (buffer-substring-no-properties (region-beginning)
                                                    (region-end))
                  (save-excursion
                    (goto-char (point-max))
                    (forward-line (- sp-workbench-claude-capture-lines))
                    (buffer-substring-no-properties (point) (point-max))))))
         (text (sp-workbench--clean-terminal-text raw)))
    (when (string-empty-p text)
      (user-error "Nothing to capture"))
    (sp-workbench--init-notes dir
                              (sp-workbench--name (magit-main-worktree dir))
                              (or (magit-get-current-branch) "(detached)") "")
    (let ((buf (sp-workbench--append-to-notes dir "Captured from Claude" text)))
      (message "Captured %d lines into %s"
               (length (split-string text "\n"))
               (abbreviate-file-name (sp-workbench--notes-path dir)))
      (when visit (pop-to-buffer buf)))))

;;;###autoload
(defun sp-workbench-claude-copy-notes ()
  "Put the current worktree's notes on the kill ring, e.g. to paste into Claude."
  (interactive)
  (let ((file (sp-workbench--notes-path (sp-workbench--current-worktree))))
    (unless (file-exists-p file) (user-error "No notes file yet"))
    (kill-new (with-temp-buffer (insert-file-contents file) (buffer-string)))
    (message "Notes copied to kill ring")))

;;;###autoload (autoload 'sp-workbench-menu "sp-vc-ai-workbench" nil t)
(transient-define-prefix sp-workbench-menu ()
  "Parallel extension workbench."
  [["Tasks"
    ("n" "New task (worktree)" sp-workbench-new-task)
    ("s" "Switch task"         sp-workbench-switch)
    ("f" "Finish task"         sp-workbench-finish-task)
    ("d" "Dashboard"           sp-workbench-dashboard)]
   ["Claude"
    ("o" "Open Claude session"            sp-workbench-claude-open)
    ("a" "Ask (region = context)"         sp-workbench-claude-ask)
    ("k" "Kick off design talk"           sp-workbench-claude-kickoff)
    ("c" "Capture Claude output -> notes" sp-workbench-claude-capture)
    ("y" "Copy notes to kill ring"        sp-workbench-claude-copy-notes)]
   ["Git"
    ("m" "Magit status here" magit-status)]])

(provide 'sp-vc-ai-workbench)
;;; sp-vc-ai-workbench.el ends here
