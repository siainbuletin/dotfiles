;;; ext-workbench.el --- Parallel work on many extensions with Magit + Claude Code -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1") (magit "3.3") (transient "0.4") (claude-code "0.1"))

;;; Commentary:
;;
;; A small workbench for developing several Emacs extensions at once.
;;
;; Model:
;;   - Every extension is its own git repo (listed in `ext-workbench-repos'
;;     or discovered under `ext-workbench-scan-root').
;;   - Every task (feature, fix, experiment) is a *git worktree* on its own
;;     branch, created under `ext-workbench-worktree-root'.  You can have as
;;     many in flight as you like, across any number of extensions.
;;   - Every worktree gets a private, git-ignored `.brainstorm.org' holding
;;     the running design notes, and its own interactive Claude Code session
;;     (via `claude-code.el') rooted in that worktree.
;;
;; Moving information between Emacs and Claude:
;;   To Claude    `ext-workbench-claude-ask': writes branch context (and the
;;                active region, if any) to `.brainstorm-context.md' and sends
;;                Claude a one-line prompt pointing at it and at the notes.
;;                This avoids pasting multi-line text into the terminal UI.
;;   From Claude  `ext-workbench-claude-capture': copies the region (or the
;;                last N lines) of the Claude buffer into the notes file.
;;                Claude may also append to `.brainstorm.org' itself when you
;;                ask it to record something (see `ext-workbench-rules').
;;
;; Entry point: M-x ext-workbench-menu   (or `ext-workbench-dashboard').
;;
;; Requirements: `claude-code.el' (install from its GitHub repo, see its
;; README) with a terminal backend (eat or vterm), and the `claude' CLI,
;; signed in with your subscription.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'transient)
(require 'tabulated-list)
(require 'claude-code)

(declare-function claude-code-send-command "claude-code")
(declare-function claude-code--find-claude-buffers-for-directory "claude-code")

;;;; Customization

(defgroup ext-workbench nil
  "Parallel extension development with Magit worktrees and Claude Code."
  :group 'tools
  :prefix "ext-workbench-")

(defcustom ext-workbench-repos nil
  "List of directories, each the root of one extension's git repo."
  :type '(repeat directory))

(defcustom ext-workbench-scan-root nil
  "If non-nil, every git repo directly under this directory is also an extension."
  :type '(choice (const nil) directory))

(defcustom ext-workbench-worktree-root "~/.worktrees/"
  "Directory under which task worktrees are created.
Layout: ROOT/<extension>/<branch-with-slashes-replaced>."
  :type 'directory)

(defcustom ext-workbench-branch-prefix "feat/"
  "Prefix proposed when naming a new task branch."
  :type 'string)

(defcustom ext-workbench-notes-file ".brainstorm.org"
  "Name of the per-worktree notes file (kept out of git)."
  :type 'string)

(defcustom ext-workbench-context-file ".brainstorm-context.md"
  "Name of the per-worktree context file written for Claude (kept out of git)."
  :type 'string)

(defcustom ext-workbench-start-claude-on-new-task nil
  "If non-nil, start a Claude Code session when creating a new task."
  :type 'boolean)

(defcustom ext-workbench-claude-capture-lines 80
  "Lines taken from the end of the Claude buffer when no region is active."
  :type 'integer)

(defcustom ext-workbench-max-context-chars 12000
  "Upper bound on characters of each context section written for Claude."
  :type 'integer)

(defcustom ext-workbench-rules
  "We are brainstorming the design of an Emacs extension. I am an experienced \
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

;;;; Repo and worktree discovery

(defun ext-workbench--repos ()
  "Return the list of extension repo roots (absolute, no trailing slash)."
  (let ((dirs (mapcar #'expand-file-name ext-workbench-repos)))
    (when (and ext-workbench-scan-root
               (file-directory-p ext-workbench-scan-root))
      (dolist (d (directory-files (expand-file-name ext-workbench-scan-root) t
                                  directory-files-no-dot-files-regexp))
        (when (and (file-directory-p d)
                   (file-exists-p (expand-file-name ".git" d)))
          (push d dirs))))
    (delete-dups (mapcar #'directory-file-name dirs))))

(defun ext-workbench--name (repo)
  "Short extension name for REPO."
  (file-name-nondirectory (directory-file-name repo)))

(defun ext-workbench--worktrees (repo)
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

(defun ext-workbench--all-worktrees ()
  "Return list of (EXTENSION . PLIST) across all repos."
  (cl-loop for repo in (ext-workbench--repos)
           append (cl-loop for wt in (ext-workbench--worktrees repo)
                           collect (cons (ext-workbench--name repo)
                                         (plist-put wt :repo repo)))))

(unless (fboundp 'magit-main-worktree)
  (defun magit-main-worktree (dir)
    "Fallback: return the main worktree path for the repo containing DIR."
    (let ((default-directory (file-name-as-directory dir)))
      (directory-file-name (car (car (magit-list-worktrees)))))))

(defun ext-workbench--read-repo ()
  "Prompt for an extension repo, defaulting to the current one."
  (let* ((repos (ext-workbench--repos))
         (cur (when-let ((top (magit-toplevel)))
                (cl-find-if (lambda (r) (file-equal-p r (magit-main-worktree top)))
                            repos)))
         (names (mapcar (lambda (r) (cons (ext-workbench--name r) r)) repos)))
    (unless repos (user-error "No extensions: set `ext-workbench-repos'"))
    (cdr (assoc (completing-read "Extension: " names nil t nil nil
                                 (and cur (ext-workbench--name cur)))
                names))))

(defun ext-workbench--read-worktree ()
  "Prompt for any worktree of any extension; return its plist."
  (let* ((all (ext-workbench--all-worktrees))
         (cands (mapcar (lambda (e)
                          (cons (format "%s: %s%s" (car e)
                                        (plist-get (cdr e) :branch)
                                        (if (plist-get (cdr e) :dirty) " *" ""))
                                (cdr e)))
                        all)))
    (unless cands (user-error "No worktrees found"))
    (cdr (assoc (completing-read "Worktree: " cands nil t) cands))))

(defun ext-workbench--current-worktree ()
  "Return the toplevel of the worktree we are in, or signal an error."
  (directory-file-name
   (or (magit-toplevel) (user-error "Not inside a git worktree"))))

;;;; Notes file

(defun ext-workbench--notes-path (dir)
  "Path of the notes file in worktree DIR."
  (expand-file-name ext-workbench-notes-file dir))

(defun ext-workbench--visit-notes (dir)
  "Visit the notes file of DIR (auto-reverting, since Claude may edit it)."
  (let ((buf (find-file-noselect (ext-workbench--notes-path dir))))
    (with-current-buffer buf (auto-revert-mode 1))
    (pop-to-buffer-same-window buf)))

(defun ext-workbench--ignore-local-files (dir)
  "Add the notes and context files to the repo's local exclude list, from DIR."
  (let* ((default-directory (file-name-as-directory dir))
         (rel (magit-git-string "rev-parse" "--git-path" "info/exclude"))
         (file (and rel (expand-file-name rel dir))))
    (when file
      (make-directory (file-name-directory file) t)
      (dolist (line (list ext-workbench-notes-file ext-workbench-context-file))
        (unless (and (file-exists-p file)
                     (with-temp-buffer
                       (insert-file-contents file)
                       (re-search-forward
                        (concat "^" (regexp-quote line) "$") nil t)))
          (write-region (concat line "\n") nil file t 'silent))))))

(defun ext-workbench--init-notes (dir extension branch goal)
  "Create the notes file in worktree DIR for EXTENSION/BRANCH with GOAL."
  (let ((file (ext-workbench--notes-path dir)))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert (format "#+title: %s / %s\n" extension branch)
                (format "#+created: %s\n\n"
                        (format-time-string "[%Y-%m-%d %a %H:%M]"))
                "* Goal\n" (if (string-empty-p goal) "\n" (concat goal "\n"))
                "* Notes\n\n"
                "* Open questions\n\n"
                "* Claude\n")))
    (ext-workbench--ignore-local-files dir)
    file))

(defun ext-workbench--append-to-notes (dir title body)
  "Append a `**' entry TITLE with BODY (in an example block) to DIR's notes."
  (let ((buf (find-file-noselect (ext-workbench--notes-path dir))))
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

;;;; Creating and finishing tasks

(defun ext-workbench--worktree-dir (repo branch)
  "Directory for a new worktree of REPO on BRANCH."
  (expand-file-name (replace-regexp-in-string "/" "-" branch)
                    (expand-file-name (ext-workbench--name repo)
                                      ext-workbench-worktree-root)))

;;;###autoload
(defun ext-workbench-new-task (repo branch goal)
  "Create a worktree + branch for a new task in extension REPO.
BRANCH is the new branch name; GOAL is a one-line description that seeds
the notes file.  Opens the notes file and Magit status side by side."
  (interactive
   (let* ((repo (ext-workbench--read-repo))
          (branch (read-string "New branch: " ext-workbench-branch-prefix))
          (goal (read-string "Goal (one line): ")))
     (list repo branch goal)))
  (let* ((dir (ext-workbench--worktree-dir repo branch))
         (default-directory (file-name-as-directory repo))
         (start (magit-main-branch)))
    (when (file-exists-p dir)
      (user-error "Worktree directory already exists: %s" dir))
    (make-directory (file-name-directory dir) t)
    (magit-worktree-branch dir branch start)
    (ext-workbench--init-notes dir (ext-workbench--name repo) branch goal)
    (delete-other-windows)
    (ext-workbench--visit-notes dir)
    (magit-status-setup-buffer dir)
    (display-buffer (current-buffer) '(display-buffer-in-side-window
                                       (side . right)))
    (when ext-workbench-start-claude-on-new-task
      (ext-workbench-claude-open dir))
    (message "Task ready: %s" dir)))

;;;###autoload
(defun ext-workbench-finish-task ()
  "Remove the current worktree, refusing if it is dirty or unmerged.
Any Claude Code session for the worktree is killed first."
  (interactive)
  (let* ((dir (ext-workbench--current-worktree))
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
    (when-let ((buf (get-file-buffer (ext-workbench--notes-path dir))))
      (with-current-buffer buf (save-buffer)))
    (dolist (b (ext-workbench--claude-buffers dir))
      (let ((kill-buffer-query-functions nil))
        (kill-buffer b)))
    (magit-worktree-delete dir)))

;;;###autoload
(defun ext-workbench-switch ()
  "Jump to any task: open its notes file and Magit status."
  (interactive)
  (let* ((wt (ext-workbench--read-worktree))
         (path (plist-get wt :path)))
    (delete-other-windows)
    (if (file-exists-p (ext-workbench--notes-path path))
        (ext-workbench--visit-notes path)
      (dired path))
    (magit-status-setup-buffer path)
    (display-buffer (current-buffer) '(display-buffer-in-side-window
                                       (side . right)))))

;;;; Dashboard

(defvar ext-workbench-dashboard-mode-map
  (let ((m (make-sparse-keymap)))
    (set-keymap-parent m tabulated-list-mode-map)
    (define-key m (kbd "RET") #'ext-workbench-dashboard-visit)
    (define-key m (kbd "m")   #'ext-workbench-dashboard-magit)
    (define-key m (kbd "c")   #'ext-workbench-dashboard-claude)
    (define-key m (kbd "n")   #'ext-workbench-new-task)
    (define-key m (kbd "?")   #'ext-workbench-menu)
    m))

(define-derived-mode ext-workbench-dashboard-mode tabulated-list-mode
  "ExtWorkbench"
  "Overview of every extension worktree."
  (setq tabulated-list-format
        [("Extension" 22 t) ("Branch" 34 t) ("State" 8 t)
         ("Claude" 7 t) ("Path" 0 t)])
  (setq tabulated-list-sort-key '("Extension"))
  (add-hook 'tabulated-list-revert-hook
            #'ext-workbench--dashboard-refresh nil t))

(defun ext-workbench--dashboard-refresh ()
  "Rebuild the dashboard entries."
  (setq tabulated-list-entries
        (cl-loop for (ext . wt) in (ext-workbench--all-worktrees)
                 for path = (plist-get wt :path)
                 collect (list path
                               (vector ext
                                       (plist-get wt :branch)
                                       (if (plist-get wt :dirty) "dirty" "clean")
                                       (if (ext-workbench--claude-buffers path)
                                           "live" "-")
                                       (abbreviate-file-name path))))))

;;;###autoload
(defun ext-workbench-dashboard ()
  "Show all extensions and their worktrees."
  (interactive)
  (let ((buf (get-buffer-create "*ext-workbench*")))
    (with-current-buffer buf
      (ext-workbench-dashboard-mode)
      (ext-workbench--dashboard-refresh)
      (tabulated-list-init-header)
      (tabulated-list-print t))
    (pop-to-buffer buf)))

(defun ext-workbench--dashboard-path ()
  "Worktree path at point in the dashboard."
  (or (tabulated-list-get-id) (user-error "No worktree here")))

(defun ext-workbench-dashboard-visit ()
  "Open the notes of the worktree at point."
  (interactive)
  (let ((path (ext-workbench--dashboard-path)))
    (if (file-exists-p (ext-workbench--notes-path path))
        (ext-workbench--visit-notes path)
      (dired path))))

(defun ext-workbench-dashboard-magit ()
  "Open Magit status for the worktree at point."
  (interactive)
  (magit-status-setup-buffer (ext-workbench--dashboard-path)))

(defun ext-workbench-dashboard-claude ()
  "Open (or start) the Claude Code session for the worktree at point."
  (interactive)
  (ext-workbench-claude-open (ext-workbench--dashboard-path)))

;;;; Claude Code integration

(defun ext-workbench--dir-variants (dir)
  "Spellings of DIR that may appear in a Claude buffer name."
  (let ((d (directory-file-name (expand-file-name dir))))
    (delete-dups
     (list d (concat d "/")
           (abbreviate-file-name d) (concat (abbreviate-file-name d) "/")
           (directory-file-name (file-truename d))
           (concat (directory-file-name (file-truename d)) "/")))))

(defun ext-workbench--claude-buffers (dir)
  "Live Claude Code buffers belonging to worktree DIR."
  (let* ((variants (ext-workbench--dir-variants dir))
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

(defun ext-workbench--claude-buffer-p (buf)
  "Non-nil if BUF is a Claude Code buffer."
  (string-prefix-p "*claude:" (buffer-name buf)))

;;;###autoload
(defun ext-workbench-claude-open (&optional dir)
  "Show the Claude Code session for worktree DIR, starting one if needed.
DIR defaults to the current worktree."
  (interactive)
  (let* ((dir (or dir (ext-workbench--current-worktree)))
         (default-directory (file-name-as-directory dir)))
    (ext-workbench--ignore-local-files dir)
    (if-let ((buf (car (ext-workbench--claude-buffers dir))))
        (pop-to-buffer buf)
      ;; `claude-code' roots the session at the project of `default-directory';
      ;; a worktree is its own project root, so each task gets its own session.
      (claude-code))))

(defun ext-workbench--truncate (s)
  "Truncate S to `ext-workbench-max-context-chars', keeping the tail."
  (if (> (length s) ext-workbench-max-context-chars)
      (concat "[...truncated...]\n"
              (substring s (- (length s) ext-workbench-max-context-chars)))
    s))

(defun ext-workbench--write-context (dir selection source)
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
         (file (expand-file-name ext-workbench-context-file dir)))
    (with-temp-file file
      (insert "# Brainstorm context\n\n"
              "## Ground rules\n" ext-workbench-rules "\n\n"
              (format "## Worktree\nExtension: %s\nBranch: %s\nBase: %s\n\n"
                      (ext-workbench--name (magit-main-worktree dir))
                      branch main)
              "## Commits ahead of base\n"
              (if (string-empty-p log) "(none yet)" log) "\n\n"
              "## Diff summary vs base\n"
              (if (string-empty-p stat) "(no changes)" stat) "\n")
      (when selection
        (insert (format "\n## Code under discussion (%s)\n```elisp\n%s\n```\n"
                        source (ext-workbench--truncate selection)))))
    file))

(defun ext-workbench--send-to-claude (dir prompt)
  "Send one-line PROMPT to the Claude session of worktree DIR.
If no session exists, start one and put PROMPT on the kill ring instead."
  (let ((default-directory (file-name-as-directory dir))
        (line (replace-regexp-in-string "[\n\r]+" " " prompt)))
    (if (ext-workbench--claude-buffers dir)
        (claude-code-send-command line)
      (kill-new line)
      (claude-code)
      (message "Claude is starting; prompt copied, paste it with C-y when ready"))))

;;;###autoload
(defun ext-workbench-claude-ask (question)
  "Ask Claude QUESTION about the current worktree.
Branch context and the active region (if any) go into the context file;
Claude is pointed at that file and at the notes."
  (interactive (list (read-string "Ask Claude: ")))
  (when (string-empty-p (string-trim question))
    (user-error "Empty question"))
  (let* ((dir (ext-workbench--current-worktree))
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
    (ext-workbench--init-notes dir
                               (ext-workbench--name (magit-main-worktree dir))
                               (or (magit-get-current-branch) "(detached)") "")
    (ext-workbench--write-context dir selection source)
    (ext-workbench--send-to-claude
     dir
     (format "Read %s (ground rules and context) and %s (my running notes), then: %s"
             ext-workbench-context-file ext-workbench-notes-file question))))

;;;###autoload
(defun ext-workbench-claude-kickoff ()
  "Ask Claude for an initial design discussion based on the Goal in the notes."
  (interactive)
  (ext-workbench-claude-ask
   "What are the key design decisions, hidden assumptions and risks before I start? Propose a small first step."))

(defun ext-workbench--clean-terminal-text (text)
  "Strip ANSI escapes, TUI borders and trailing space from TEXT."
  (let ((s (replace-regexp-in-string "\e\\[[0-9;?]*[ -/]*[@-~]" "" text)))
    (setq s (replace-regexp-in-string "^[│┃] ?" "" s))
    (setq s (replace-regexp-in-string " ?[│┃]$" "" s))
    (setq s (replace-regexp-in-string "^[╭╰][─ ]*[╮╯]?$" "" s))
    (setq s (replace-regexp-in-string "[ \t]+$" "" s))
    (string-trim (replace-regexp-in-string "\n\\{3,\\}" "\n\n" s))))

;;;###autoload
(defun ext-workbench-claude-capture (&optional visit)
  "Copy output from the Claude buffer into the notes file.
Uses the active region if called from the Claude buffer with one (in eat/vterm,
select it in copy mode), otherwise the last `ext-workbench-claude-capture-lines'
lines.  With prefix argument VISIT, show the notes afterwards."
  (interactive "P")
  (let* ((dir (ext-workbench--current-worktree))
         (cbuf (if (ext-workbench--claude-buffer-p (current-buffer))
                   (current-buffer)
                 (or (car (ext-workbench--claude-buffers dir))
                     (user-error "No Claude session for this worktree"))))
         (raw (with-current-buffer cbuf
                (if (and (eq cbuf (current-buffer)) (use-region-p))
                    (buffer-substring-no-properties (region-beginning)
                                                    (region-end))
                  (save-excursion
                    (goto-char (point-max))
                    (forward-line (- ext-workbench-claude-capture-lines))
                    (buffer-substring-no-properties (point) (point-max))))))
         (text (ext-workbench--clean-terminal-text raw)))
    (when (string-empty-p text)
      (user-error "Nothing to capture"))
    (ext-workbench--init-notes dir
                               (ext-workbench--name (magit-main-worktree dir))
                               (or (magit-get-current-branch) "(detached)") "")
    (let ((buf (ext-workbench--append-to-notes dir "Captured from Claude" text)))
      (message "Captured %d lines into %s"
               (length (split-string text "\n"))
               (abbreviate-file-name (ext-workbench--notes-path dir)))
      (when visit (pop-to-buffer buf)))))

;;;###autoload
(defun ext-workbench-claude-copy-notes ()
  "Put the current worktree's notes on the kill ring, e.g. to paste into Claude."
  (interactive)
  (let ((file (ext-workbench--notes-path (ext-workbench--current-worktree))))
    (unless (file-exists-p file) (user-error "No notes file yet"))
    (kill-new (with-temp-buffer (insert-file-contents file) (buffer-string)))
    (message "Notes copied to kill ring")))

;;;; Menu

;;;###autoload (autoload 'ext-workbench-menu "ext-workbench" nil t)
(transient-define-prefix ext-workbench-menu ()
  "Parallel extension workbench."
  [["Tasks"
    ("n" "New task (worktree)" ext-workbench-new-task)
    ("s" "Switch task"         ext-workbench-switch)
    ("f" "Finish task"         ext-workbench-finish-task)
    ("d" "Dashboard"           ext-workbench-dashboard)]
   ["Claude"
    ("o" "Open Claude session"          ext-workbench-claude-open)
    ("a" "Ask (region = context)"       ext-workbench-claude-ask)
    ("k" "Kick off design talk"         ext-workbench-claude-kickoff)
    ("c" "Capture Claude output -> notes" ext-workbench-claude-capture)
    ("y" "Copy notes to kill ring"      ext-workbench-claude-copy-notes)]
   ["Git"
    ("m" "Magit status here" magit-status)]])

(provide 'ext-workbench)
;;; ext-workbench.el ends here
