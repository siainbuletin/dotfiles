;;; sp-merge-pick.el --- Pick two commits in a Magit graph to review or merge -*- lexical-binding: t; -*-

;;; Commentary:

;; A graph log of all branches in Magit, with unicode lane glyphs, in which
;; you mark one commit as INTO and another as FROM.  From the two marks you
;; can preview the merge without touching the worktree (`git merge-tree'),
;; list the conflicts, review a file in a three-way Ediff (INTO, FROM and
;; their merge base), see what FROM adds, or start a `--no-commit' merge for
;; the usual Magit, Ediff and Smerge conflict resolution.  Nothing here makes
;; a merge commit.  Depends on `magit', `transient' and `ediff'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)

(declare-function magit-toplevel "magit-git")
(declare-function magit-rev-parse "magit-git")
(declare-function magit-rev-abbrev "magit-git")
(declare-function magit-rev-format "magit-git")
(declare-function magit-git-lines "magit-git")
(declare-function magit-git-success "magit-git")
(declare-function magit-get-current-branch "magit-git")
(declare-function magit-merge-base "magit-git")
(declare-function magit-changed-files "magit-git")
(declare-function magit-anything-modified-p "magit-git")
(declare-function magit-gitdir "magit-git")
(declare-function magit-commit-at-point "magit-git")
(declare-function magit-process-file "magit-process")
(declare-function magit-run-git "magit-process")
(declare-function magit-log-setup-buffer "magit-log")
(declare-function magit-diff-range "magit-diff")
(declare-function magit-merge-nocommit "magit-merge")
(declare-function magit-find-file-noselect "magit-files")
(declare-function ediff-merge-buffers-with-ancestor "ediff")
(declare-function ediff-buffers "ediff")

(defgroup sp-merge-pick nil
  "Pick two commits in a Magit graph to review or merge."
  :group 'magit)

(defcustom sp-merge-pick-log-arguments
  '("--graph" "--color" "--decorate" "--topo-order" "-n256")
  "Arguments of the log `sp-merge-pick-log' shows, besides `--all'.
Magit colours the graph only up to `magit-log-color-graph-limit' commits
\(256 by default); raise both to see more history in colour."
  :type '(repeat string)
  :group 'spcustom)

(defcustom sp-merge-pick-unicode-graph t
  "Draw the lanes of the graph with unicode glyphs instead of ASCII."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-merge-pick-graph-glyphs
  '((?* . "●") (?| . "│") (?/ . "╱") (?\\ . "╲"))
  "Glyph shown for each ASCII character git uses in the graph.
Only the display changes; the buffer text stays ASCII."
  :type '(alist :key-type character :value-type string)
  :group 'spcustom)

(defface sp-merge-pick-into
  '((t :inherit highlight :extend t))
  "Face of the line marked as INTO, the commit that receives the merge.")

(defface sp-merge-pick-from
  '((t :inherit secondary-selection :extend t))
  "Face of the line marked as FROM, the commit that is merged in.")

;;;; Marks

(defvar sp-merge-pick--into nil
  "Plist (:rev HASH :root DIR :label NAME :branch BRANCH) for INTO, or nil.")
(defvar sp-merge-pick--from nil
  "Plist (:rev HASH :root DIR :label NAME :branch BRANCH) for FROM, or nil.")
(defvar sp-merge-pick--conflicts nil
  "Files that conflicted in the last preview, as (INTO FROM . FILES).")

(defun sp-merge-pick--branches-at (rev)
  "Return the local branches whose tip is REV, the current branch first."
  (let ((current (magit-get-current-branch))
        (names (magit-git-lines "branch" "--points-at" rev
                                "--format=%(refname:short)")))
    (if (member current names)
        (cons current (delete current names))
      names)))

(defun sp-merge-pick--describe (rev)
  "Return a mark plist for the commit REV."
  (let* ((hash (magit-rev-parse rev))
         (branch (car (sp-merge-pick--branches-at hash))))
    (list :rev hash
          :root (magit-toplevel)
          :branch branch
          :label (or branch
                     (format "%s %s" (magit-rev-abbrev hash)
                             (magit-rev-format "%s" hash))))))

(defun sp-merge-pick--commit-at-point ()
  "Return the commit at point or signal a `user-error'."
  (or (magit-commit-at-point)
      (user-error "Put point on a commit in the graph first")))

(defun sp-merge-pick--require-marks ()
  "Return (INTO . FROM), or signal a `user-error' if one is missing."
  (unless (and sp-merge-pick--into sp-merge-pick--from)
    (user-error "Mark both commits first (INTO with `i', FROM with `f')"))
  (unless (equal (plist-get sp-merge-pick--into :root)
                 (plist-get sp-merge-pick--from :root))
    (user-error "The two marks are in different repositories; clear them"))
  (unless (equal (plist-get sp-merge-pick--into :root) (magit-toplevel))
    (user-error "The marks belong to another repository (%s)"
                (plist-get sp-merge-pick--into :root)))
  (cons sp-merge-pick--into sp-merge-pick--from))

;;;; Drawing the graph and the marks

(defun sp-merge-pick--prettify-graph ()
  "Show unicode glyphs for the ASCII lanes in the current log buffer.
Magit puts the graph before the hash, or after it when the hashes are
aligned, so the pattern accepts both."
  (when sp-merge-pick-unicode-graph
    (with-silent-modifications
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (when (looking-at "\\(?:[0-9a-f]\\{7,40\\} \\)?\\([-_/|\\\\*o<>. ]+\\)")
            (let ((pos (match-beginning 1))
                  (end (match-end 1)))
              (while (< pos end)
                (when-let ((glyph (alist-get (char-after pos)
                                             sp-merge-pick-graph-glyphs)))
                  (put-text-property pos (1+ pos) 'display glyph))
                (setq pos (1+ pos)))))
          (forward-line 1))))))

(defun sp-merge-pick--mark-overlay (mark face text)
  "Highlight the line of MARK in the buffer with FACE and TEXT at its end."
  (when-let ((rev (plist-get mark :rev)))
    (save-excursion
      (goto-char (point-min))
      (catch 'found
        (while (re-search-forward "^[^\n]*?\\b\\([0-9a-f]\\{7,40\\}\\) " nil t)
          (when (string-prefix-p (match-string 1) rev)
            (let ((ov (make-overlay (line-beginning-position)
                                    (line-end-position))))
              (overlay-put ov 'sp-merge-pick t)
              (overlay-put ov 'face face)
              (overlay-put ov 'after-string
                           (propertize (concat "  ← " text) 'face 'bold))
              (throw 'found ov))))))))

(defun sp-merge-pick--redraw ()
  "Redraw the glyphs and the two marks in the current log buffer."
  (when (derived-mode-p 'magit-log-mode)
    (remove-overlays (point-min) (point-max) 'sp-merge-pick t)
    (sp-merge-pick--prettify-graph)
    (sp-merge-pick--mark-overlay sp-merge-pick--into 'sp-merge-pick-into "INTO")
    (sp-merge-pick--mark-overlay sp-merge-pick--from 'sp-merge-pick-from "FROM")))

;;;; Commands: marking

;;;###autoload
(defun sp-merge-pick-log ()
  "Show a graph log of every branch, ready for marking two commits."
  (interactive)
  (unless (magit-toplevel)
    (user-error "Not in a repository; open Magit first (M-x yadm for the dotfiles)"))
  (magit-log-setup-buffer (list "--all") sp-merge-pick-log-arguments nil))

(defun sp-merge-pick-set-into ()
  "Mark the commit at point as INTO, the commit that receives the merge."
  (interactive)
  (setq sp-merge-pick--into (sp-merge-pick--describe (sp-merge-pick--commit-at-point)))
  (sp-merge-pick--redraw)
  (message "INTO: %s" (plist-get sp-merge-pick--into :label)))

(defun sp-merge-pick-set-from ()
  "Mark the commit at point as FROM, the commit that is merged in."
  (interactive)
  (setq sp-merge-pick--from (sp-merge-pick--describe (sp-merge-pick--commit-at-point)))
  (sp-merge-pick--redraw)
  (message "FROM: %s" (plist-get sp-merge-pick--from :label)))

(defun sp-merge-pick-swap ()
  "Swap INTO and FROM."
  (interactive)
  (cl-rotatef sp-merge-pick--into sp-merge-pick--from)
  (sp-merge-pick--redraw))

(defun sp-merge-pick-clear ()
  "Forget both marks."
  (interactive)
  (setq sp-merge-pick--into nil
        sp-merge-pick--from nil)
  (sp-merge-pick--redraw))

;;;; Commands: reviewing

(defun sp-merge-pick--merge-tree (into from)
  "Merge FROM into INTO in memory.  Return (TREE . CONFLICTED-FILES).
Neither the worktree, the index nor any ref changes: `git merge-tree
--write-tree' only writes objects.  Needs git 2.38 or later."
  (with-temp-buffer
    (let ((default-directory (magit-toplevel))
          (code (magit-process-file "git" nil t nil "merge-tree" "--write-tree"
                                    "--name-only" "--no-messages" into from)))
      (unless (memq code '(0 1))
        (user-error "git merge-tree failed (git 2.38 or later is needed): %s"
                    (string-trim (buffer-string))))
      (goto-char (point-min))
      (cons (buffer-substring (point) (line-end-position))
            (split-string (buffer-substring (min (point-max) (1+ (line-end-position)))
                                            (point-max))
                          "\n" t)))))

(defun sp-merge-pick--rev-buffer (rev file)
  "Return a buffer with FILE as it is in REV, or an empty one if absent."
  (if (magit-git-success "cat-file" "-e" (format "%s:%s" rev file))
      (magit-find-file-noselect rev file t t)
    (generate-new-buffer (format "%s:%s (absent)" (magit-rev-abbrev rev) file))))

(defun sp-merge-pick--ediff-file (into from file)
  "Review FILE in a three-way Ediff of INTO, FROM and their merge base."
  (let ((base (magit-merge-base into from))
        (a (sp-merge-pick--rev-buffer into file))
        (b (sp-merge-pick--rev-buffer from file)))
    (if base
        (ediff-merge-buffers-with-ancestor
         a b (sp-merge-pick--rev-buffer base file))
      (ediff-buffers a b))))

(defun sp-merge-pick-preview ()
  "Preview merging FROM into INTO without touching anything.
Lists the files that would conflict; a button opens each in a three-way
Ediff.  The result is only computed, never written to the worktree."
  (interactive)
  (pcase-let* ((`(,into . ,from) (sp-merge-pick--require-marks))
               (into-rev (plist-get into :rev))
               (from-rev (plist-get from :rev))
               (`(,tree . ,files) (sp-merge-pick--merge-tree into-rev from-rev))
               (root (magit-toplevel))
               (stat (let ((default-directory root))
                       (with-temp-buffer
                         (magit-process-file "git" nil t nil "diff" "--stat"
                                             into-rev tree)
                         (buffer-string)))))
    (setq sp-merge-pick--conflicts (cons (cons into-rev from-rev) files))
    (with-current-buffer (get-buffer-create "*sp-merge-preview*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (setq default-directory root)
        (insert (propertize (format "Merge %s into %s\n"
                                    (plist-get from :label)
                                    (plist-get into :label))
                            'face 'bold)
                (if files
                    (format "%d file(s) would conflict.  RET on a file opens a three-way Ediff.\n\n"
                            (length files))
                  "Clean: no conflicts.\n\n"))
        (dolist (file files)
          (insert "  ")
          (insert-text-button
           file 'action (lambda (_) (sp-merge-pick--ediff-file into-rev from-rev file))
           'follow-link t)
          (insert "\n"))
        (when files (insert "\n"))
        (insert (propertize "What the merge would change in INTO\n" 'face 'bold)
                (if (string-empty-p stat) "(nothing)\n" stat)
                "\nNothing was changed.  To merge for real without committing: C-c v n.\n"))
      (goto-char (point-min))
      (pop-to-buffer (current-buffer)))))

(defun sp-merge-pick-diff ()
  "Show in Magit what FROM adds to INTO since their merge base."
  (interactive)
  (pcase-let ((`(,into . ,from) (sp-merge-pick--require-marks)))
    (magit-diff-range (format "%s...%s" (plist-get into :rev) (plist-get from :rev)))))

(defun sp-merge-pick-ediff ()
  "Review one file in a three-way Ediff of INTO, FROM and their merge base.
Files that conflicted in the last preview are offered first."
  (interactive)
  (pcase-let* ((`(,into . ,from) (sp-merge-pick--require-marks))
               (into-rev (plist-get into :rev))
               (from-rev (plist-get from :rev))
               (base (or (magit-merge-base into-rev from-rev) into-rev))
               (changed (delete-dups
                         (append (magit-changed-files base into-rev)
                                 (magit-changed-files base from-rev))))
               (known (and (equal (car sp-merge-pick--conflicts)
                                  (cons into-rev from-rev))
                           (cdr sp-merge-pick--conflicts)))
               (choices (append known (cl-set-difference changed known :test #'equal)))
               (file (completing-read "File to review: " choices nil t)))
    (sp-merge-pick--ediff-file into-rev from-rev file)))

;;;; Commands: merging

(defun sp-merge-pick-merge-nocommit ()
  "Start `git merge --no-commit --no-ff' of FROM into INTO.
INTO must be the checked-out branch, or have a local branch that this
offers to check out when the worktree is clean.  Conflicts are then
resolved in Magit's status buffer: `e' on a file for Ediff (`M' in the
Ediff menu for all of them), or visit the file and use Smerge.  Undo with
`m a' (`magit-merge-abort') before committing."
  (interactive)
  (pcase-let* ((`(,into . ,from) (sp-merge-pick--require-marks))
               (into-rev (plist-get into :rev))
               (branch (plist-get into :branch)))
    (when (file-exists-p (expand-file-name "MERGE_HEAD" (magit-gitdir)))
      (user-error "A merge is already in progress; finish it or abort with `m a'"))
    (unless (equal into-rev (magit-rev-parse "HEAD"))
      (unless branch
        (user-error "INTO has no local branch and is not checked out; check it out first"))
      (when (magit-anything-modified-p)
        (user-error "The worktree has changes; commit or stash them before switching to %s"
                    branch))
      (unless (y-or-n-p (format "Check out %s first? " branch))
        (user-error "Merge cancelled"))
      (magit-run-git "checkout" branch))
    (unless (y-or-n-p (format "Merge %s into %s, without committing? "
                              (plist-get from :label) (or branch (plist-get into :label))))
      (user-error "Merge cancelled"))
    (magit-merge-nocommit (or (plist-get from :branch) (plist-get from :rev)))
    (message "Merging, not committed.  Review in the status buffer; abort with `m a'.")))

;;;; Menu and keys

(defun sp-merge-pick--summary ()
  "Return a one-line description of the two marks."
  (format "INTO %s    FROM %s"
          (if sp-merge-pick--into (plist-get sp-merge-pick--into :label) "-")
          (if sp-merge-pick--from (plist-get sp-merge-pick--from :label) "-")))

;;;###autoload (autoload 'sp-merge-pick-menu "sp-merge-pick" nil t)
(transient-define-prefix sp-merge-pick-menu ()
  "Pick two commits in the graph, then review or merge them."
  [:description sp-merge-pick--summary
   ["Mark (point on a commit)"
    ("i" "INTO: receives the merge" sp-merge-pick-set-into)
    ("f" "FROM: is merged in" sp-merge-pick-set-from)
    ("s" "Swap" sp-merge-pick-swap)
    ("x" "Clear" sp-merge-pick-clear)]
   ["Review (changes nothing)"
    ("p" "Preview merge, list conflicts" sp-merge-pick-preview)
    ("d" "What FROM adds (diff)" sp-merge-pick-diff)
    ("e" "Three-way Ediff of a file" sp-merge-pick-ediff)]
   ["Merge"
    ("n" "Merge FROM into INTO, no commit" sp-merge-pick-merge-nocommit)]])

;; Magit buffers redraw the marks after every refresh; `C-c v' opens the menu.
(with-eval-after-load 'magit
  (keymap-set magit-mode-map "C-c v" #'sp-merge-pick-menu)
  (add-hook 'magit-refresh-buffer-hook #'sp-merge-pick--redraw))

(provide 'sp-merge-pick)
;; sp-merge-pick.el ends here
