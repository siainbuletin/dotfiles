;;; sp-reload.el --- Reload changed config modules in the running Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; After pulling `origin/main' (or checking out a PR branch) run
;;
;;   M-x sp-reload-modules
;;
;; (`sp-reload-changed' is the same command under its original name)
;;
;; to re-evaluate every module that changed since the config was last
;; synchronised with the running Emacs.  "Last synchronised" is a git revision
;; remembered in `sp-reload--base-rev': HEAD at startup, then HEAD after each
;; successful reload.  That makes it work for pulls, branch switches and
;; switching back to main alike, and it also sees uncommitted edits to tracked
;; files.  C-u prompts for a different base revision.
;;
;; What it does for each changed, already loaded module (in the order the
;; modules were originally loaded, which respects their `require's):
;;
;;  1. switches off active minor modes the file defines, using the OLD
;;     definition so they clean up after themselves;
;;  2. undoes hooks, advice and timers the file registered (needs
;;     `sp-reload-enable-tracking', see below);
;;  3. resets the variables the file `defvar's/`defcustom's, so edited default
;;     values take effect (keymaps keep their identity);
;;  4. `load's the .el source;
;;  5. switches the minor modes back on and re-runs the major mode in buffers
;;     that use a major mode the file defines;
;;  6. afterwards, `fmakunbound's functions that no loaded file defines any
;;     more.
;;
;; The config is installed with GNU Stow, so the module files are symlinks into
;; the dotfiles checkout.  Paths are resolved with `file-truename' and git runs
;; in the checkout, so that diffs, load history and `load' all see one path.
;;
;; init.el, early-init.el and friends are never reloaded; they are reported as
;; needing a restart, as are a few heuristic red flags found in the diff.
;;
;; Limits (read the report buffer, it repeats the relevant ones):
;;  - Hooks, advice and timers are only undone for modules that were loaded
;;    AFTER `sp-reload-enable-tracking' ran, and only when registered while the
;;    file was loading (not from deferred :config blocks).  This module is
;;    required first in `lem--default-modules' and starts the tracking itself.
;;  - Removed `define-key', `keymap-set', `add-to-list', `push' lines leave
;;    their effect behind until restart.
;;  - Macros: dependents are not re-expanded; the report names them.
;;  - use-package/elpaca: :init/:config re-run, new packages are queued with
;;    `elpaca-process-queues' (async, untested against every elpaca version).
;;  - State kept in variables the file defines is reset; protect some with
;;    `sp-reload-preserve-variables'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup sp-reload nil
  "Reload changed configuration modules in the running Emacs."
  :group 'convenience
  :prefix "sp-reload-")

(defconst sp-reload--file
  (let ((f (or load-file-name buffer-file-name)))
    (and f (file-truename f)))
  "Real path of this file, Stow symlinks resolved.
Used to find the modules directory.")

(defcustom sp-reload-modules-dir
  (and sp-reload--file
       (expand-file-name ".." (file-name-directory sp-reload--file)))
  "Directory holding the module files (this file lives in a subdirectory)."
  :type 'directory)

(defcustom sp-reload-track-on-load t
  "Non-nil means loading this module starts `sp-reload-enable-tracking'.
Tracking only sees modules loaded after it, so this module is the first one
required by `lem--default-modules'."
  :type 'boolean)

(defcustom sp-reload-restart-files '("init.el" "early-init.el" "claude-early.el"
                                     "sp-config-profiles.el")
  "File names that are never reloaded; changes are reported as needing a restart."
  :type '(repeat string))

(defcustom sp-reload-preserve-variables
  '("\\`sp-reload-" "-history\\'" "-cache\\'")
  "Regexps matching variables that reloading must not reset."
  :type '(repeat regexp))

(defcustom sp-reload-refresh-buffers t
  "Non-nil means re-run major modes defined by a reloaded file in their buffers."
  :type 'boolean)

(defcustom sp-reload-magit-action 'notify
  "What to do when a Magit refresh shows HEAD moved since the last reload.
nil does nothing, `notify' only says so in the echo area, `prompt' asks, and
`reload' reloads straight away."
  :type '(choice (const nil) (const notify) (const prompt) (const reload)))

(defvar sp-reload--base-rev nil
  "Git revision the running Emacs was last synchronised with.")

(defvar sp-reload--busy nil)
(defvar sp-reload--last-nudge nil)

;;;; Git

(defun sp-reload--config-dir ()
  (file-name-as-directory (file-truename (expand-file-name "../.." sp-reload-modules-dir))))

(defun sp-reload--git (prefix &rest args)
  "Run git with PREFIX and ARGS in the config dir; return trimmed stdout or nil."
  (let ((default-directory (sp-reload--config-dir))
        (process-environment (cons "GIT_OPTIONAL_LOCKS=0" process-environment)))
    (with-temp-buffer
      (when (eq 0 (apply #'process-file "git" nil (list t nil) nil
                         (append prefix args)))
        (string-trim-right (buffer-string))))))

(defun sp-reload--git-context ()
  "Return (PREFIX . ROOT): git arguments for the config repo, and its work tree.
PREFIX is always nil now that the config is installed with Stow: the config
directory is inside the dotfiles checkout (also a linked worktree)."
  (let ((top (sp-reload--git nil "rev-parse" "--show-toplevel")))
    (unless top
      (user-error "sp-reload: %s is not inside a git checkout"
                  (sp-reload--config-dir)))
    (cons nil (file-name-as-directory (file-truename top)))))

(defun sp-reload--rev (ctx rev)
  (sp-reload--git (car ctx) "rev-parse" "--verify" "--quiet" (concat rev "^{commit}")))

(defun sp-reload--changed (ctx base)
  "Absolute .el paths changed (or added) between BASE and the work tree."
  (let* ((rel (file-relative-name (sp-reload--config-dir) (cdr ctx)))
         (out (sp-reload--git (car ctx) "diff" "--name-only" "-z"
                              "--diff-filter=ACMR" base "--" rel)))
    (cl-loop for f in (split-string (or out "") "\0" t)
             for abs = (expand-file-name f (cdr ctx))
             when (and (string-suffix-p ".el" abs) (file-exists-p abs))
             collect abs)))

(defun sp-reload--tracking-p ()
  (advice-member-p #'sp-reload--track-add-hook 'add-hook))

(defun sp-reload--diff-warnings (ctx base files)
  "Heuristic restart warnings from the removed/added lines of FILES' diff."
  (let ((diff (sp-reload--git (car ctx) "diff" "-U0" base "--"
                              (file-relative-name (sp-reload--config-dir) (cdr ctx))))
        file warnings)
    (dolist (line (split-string (or diff "") "\n"))
      (cond
       ((string-match "\\`+++ b/\\(.*\\)" line)
        (setq file (expand-file-name (match-string 1 line) (cdr ctx))))
       ((and file (member file files))
        (let ((name (file-name-nondirectory file)))
          (cond
           ((string-match-p "\\`-[ \t]*(\\(define-key\\|keymap-set\\|global-set-key\\|local-set-key\\|add-to-list\\|push\\)" line)
            (push (format "%s: removed `%s' – its effect lingers until restart (heuristic)"
                          name (string-trim (substring line 1)))
                  warnings))
           ((string-match "\\`-[ \t]*(use-package \\([^ \t\n)]+\\)" line)
            (push (format "%s: use-package %s removed – stays loaded until restart (heuristic)"
                          name (match-string 1 line))
                  warnings))
           ((string-match "\\`+[ \t]*(use-package \\([^ \t\n)]+\\)" line)
            (push (format "%s: use-package %s added – elpaca may need to install it (heuristic)"
                          name (match-string 1 line))
                  warnings)))))))
    (nreverse (delete-dups warnings))))

;;;; Tracking of hooks, advice and timers, keyed by the file being loaded

(defvar sp-reload--ledger (make-hash-table :test #'equal)
  "File key -> list of side effects registered while that file loaded.")

(defun sp-reload--key (file)
  (file-name-sans-extension (file-truename file)))

(defun sp-reload--record (entry)
  (when load-file-name
    (push entry (gethash (sp-reload--key load-file-name) sp-reload--ledger))))

(defun sp-reload--track-add-hook (orig hook function &optional depth local)
  (prog1 (funcall orig hook function depth local)
    (unless local (sp-reload--record (list 'hook hook function)))))

(defun sp-reload--track-advice-add (orig symbol how function &optional props)
  (prog1 (funcall orig symbol how function props)
    (sp-reload--record (list 'advice symbol function))))

(defun sp-reload--track-timer (timer)
  (when (timerp timer) (sp-reload--record (list 'timer timer)))
  timer)

;;;###autoload
(defun sp-reload-enable-tracking ()
  "Start recording hooks, advice and timers per loading file.
Call this in init.el before the modules are required."
  (interactive)
  (advice-add 'add-hook :around #'sp-reload--track-add-hook)
  (advice-add 'advice-add :around #'sp-reload--track-advice-add)
  (advice-add 'run-at-time :filter-return #'sp-reload--track-timer)
  (advice-add 'run-with-idle-timer :filter-return #'sp-reload--track-timer))

(defun sp-reload--undo (key)
  "Undo the recorded side effects of KEY; return how many."
  (let ((entries (gethash key sp-reload--ledger)))
    (dolist (e entries)
      (ignore-errors
        (pcase e
          (`(hook ,h ,f) (remove-hook h f))
          (`(advice ,s ,f) (advice-remove s f))
          (`(timer ,tm) (cancel-timer tm)))))
    (remhash key sp-reload--ledger)
    (length entries)))

;;;; load-history helpers

(defun sp-reload--history-tables ()
  "Return (BY-FILE BY-FEATURE ORDER) built from `load-history'.
ORDER maps an entry to its original load order (smaller = loaded earlier)."
  (let ((by-file (make-hash-table :test #'equal))
        (by-feature (make-hash-table :test #'eq))
        (order (make-hash-table :test #'eq))
        (n (length load-history)))
    (cl-loop for e in load-history
             for i downfrom n
             when (stringp (car e))
             do (puthash e i order)
             (puthash (sp-reload--key (car e)) e by-file)
             (dolist (el (cdr e))
               (when (eq (car-safe el) 'provide)
                 (puthash (cdr el) e by-feature))))
    (list by-file by-feature order)))

(defun sp-reload--entry-defuns (entry)
  (cl-loop for el in (cdr entry)
           when (eq (car-safe el) 'defun) collect (cdr el)))

(defun sp-reload--entry-features (entry)
  (cl-loop for el in (cdr entry)
           when (eq (car-safe el) 'provide) collect (cdr el)))

;;;; Variables

(defun sp-reload--file-variables (file)
  "Return (SYMBOL . KIND) for top-level variable definitions with a value in FILE.
KIND is `keymap' for `defvar-keymap', else `var'."
  (let (res)
    (cl-labels
        ((collect (form)
           (pcase form
             (`(progn . ,body) (mapc #'collect body))
             (`(defvar-keymap ,(and (pred symbolp) s) . ,_) (push (cons s 'keymap) res))
             (`(,(or 'defvar 'defvar-local 'defconst 'defcustom)
                ,(and (pred symbolp) s) ,_ . ,_)
              (push (cons s 'var) res)))))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (with-syntax-table emacs-lisp-mode-syntax-table
          (condition-case nil
              (while t (collect (read (current-buffer))))
            (error nil)))))
    (nreverse res)))

(defun sp-reload--preserved-p (sym)
  (cl-some (lambda (re) (string-match-p re (symbol-name sym)))
           sp-reload-preserve-variables))

(defun sp-reload--reset-variables (file)
  "Unbind FILE's variables so the load re-initialises them.  Return an alist
of (SYMBOL . OLD-VALUE) for the ones that were bound."
  (let (saved)
    (dolist (v (sp-reload--file-variables file))
      (let ((sym (car v)))
        (when (and (default-boundp sym) (not (sp-reload--preserved-p sym)))
          (push (cons sym (default-value sym)) saved)
          (makunbound sym))))
    saved))

(defun sp-reload--restore-variables (saved ok)
  "After loading: on OK keep keymap identity, else put old values back."
  (dolist (s saved)
    (let ((sym (car s)) (old (cdr s)))
      (cond
       ((not ok) (unless (default-boundp sym) (set-default sym old)))
       ((and (keymapp old) (boundp sym) (keymapp (symbol-value sym))
             (not (eq old (symbol-value sym))))
        (setcdr old (cdr (symbol-value sym)))
        (set-default sym old))))))

;;;; Modes

(defun sp-reload--minor-modes-off (defuns)
  "Switch off active minor modes among DEFUNS; return what to re-enable."
  (let (restore)
    (dolist (m defuns)
      (when (and (memq m minor-mode-list) (boundp m))
        (if (local-variable-if-set-p m)
            (let ((bufs (cl-remove-if-not
                         (lambda (b) (buffer-local-value m b)) (buffer-list))))
              (when bufs
                (dolist (b bufs) (with-current-buffer b (ignore-errors (funcall m -1))))
                (push (cons m bufs) restore)))
          (when (default-value m)
            (ignore-errors (funcall m -1))
            (push (cons m 'global) restore)))))
    restore))

(defun sp-reload--minor-modes-on (restore)
  (dolist (r restore)
    (if (eq (cdr r) 'global)
        (ignore-errors (funcall (car r) 1))
      (dolist (b (cdr r))
        (when (buffer-live-p b)
          (with-current-buffer b (ignore-errors (funcall (car r) 1))))))))

(defun sp-reload--refresh-major-modes (defuns)
  (let ((n 0))
    (when sp-reload-refresh-buffers
      (dolist (b (buffer-list))
        (when (and (memq (buffer-local-value 'major-mode b) defuns)
                   (not (memq (buffer-local-value 'major-mode b) minor-mode-list)))
          (with-current-buffer b
            (let ((inhibit-message t)) (ignore-errors (funcall major-mode)))
            (cl-incf n)))))
    n))

;;;; Reloading

(defun sp-reload--one (file entry)
  "Reload FILE whose old load-history ENTRY is given.  Return a plist."
  (let* ((key (sp-reload--key file))
         (old-defuns (sp-reload--entry-defuns entry))
         (features (sp-reload--entry-features entry))
         (tracked (and (gethash key sp-reload--ledger) t))
         (restore (sp-reload--minor-modes-off old-defuns))
         (undone (sp-reload--undo key))
         (saved (sp-reload--reset-variables file))
         (ok nil) err)
    (unwind-protect
        (condition-case e
            (progn (load file nil t t) (setq ok t))
          (error (setq err e)))
      (sp-reload--restore-variables saved ok)
      (sp-reload--minor-modes-on restore))
    (let* ((new-entry (cl-find-if (lambda (e) (and (stringp (car e))
                                                   (equal (sp-reload--key (car e)) key)))
                                  load-history))
           (new-defuns (and ok new-entry (sp-reload--entry-defuns new-entry))))
      (list :file file :ok ok :error err :features features
            :tracked tracked :undone undone
            :stale (and ok (cl-set-difference old-defuns new-defuns))
            :macros (and ok (cl-remove-if-not #'macrop new-defuns))
            :modes (and ok (sp-reload--refresh-major-modes new-defuns))
            :minor (mapcar #'car restore)))))

(defun sp-reload--dependents (features exclude)
  "Names of loaded files that `require' one of FEATURES, except EXCLUDE."
  (cl-loop for e in load-history
           when (and (stringp (car e)) (not (member (car e) exclude))
                     (cl-some (lambda (el) (and (eq (car-safe el) 'require)
                                                (memq (cdr el) features)))
                              (cdr e)))
           collect (file-name-nondirectory (car e))))

(defun sp-reload--defined-anywhere ()
  (let ((h (make-hash-table :test #'eq)))
    (dolist (e load-history)
      (dolist (el (cdr-safe e))
        (when (eq (car-safe el) 'defun) (puthash (cdr el) t h))))
    h))

(defun sp-reload--run (files &optional extra-warnings)
  "Reload FILES (absolute paths) and show the report."
  (when sp-reload--busy (user-error "sp-reload is already running"))
  (let* ((sp-reload--busy t)
         (tables (sp-reload--history-tables))
         (by-file (nth 0 tables)) (by-feature (nth 1 tables)) (order (nth 2 tables))
         reload not-loaded restart other)
    (dolist (f files)
      (let* ((name (file-name-nondirectory f))
             (entry (or (gethash (sp-reload--key f) by-file)
                        (gethash (intern (file-name-sans-extension name)) by-feature))))
        (cond
         ((member name sp-reload-restart-files) (push name restart))
         ((not (file-in-directory-p f sp-reload-modules-dir)) (push name other))
         (entry (push (cons f entry) reload))
         (t (push name not-loaded)))))
    ;; Original load order; this file last so it does not change under itself.
    (setq reload (sort reload
                       (lambda (a b)
                         (cond ((equal (car a) sp-reload--file) nil)
                               ((equal (car b) sp-reload--file) t)
                               (t (< (gethash (cdr a) order 0)
                                     (gethash (cdr b) order 0)))))))
    (let* ((results (mapcar (lambda (r) (sp-reload--one (car r) (cdr r))) reload))
           (defined (sp-reload--defined-anywhere))
           (stale (delete-dups
                   (cl-loop for r in results append (plist-get r :stale))))
           removed)
      (dolist (s stale)
        (when (and (fboundp s) (not (gethash s defined)))
          (fmakunbound s) (push s removed)))
      (when (and (fboundp 'elpaca-process-queues) results)
        (let ((inhibit-message t)) (ignore-errors (elpaca-process-queues))))
      (sp-reload--report results (nreverse removed) (nreverse not-loaded)
                         (nreverse restart) (nreverse other) extra-warnings)
      results)))

(defun sp-reload--report (results removed not-loaded restart other warnings)
  (let ((buf (get-buffer-create "*sp-reload*"))
        (failed (cl-remove-if (lambda (r) (plist-get r :ok)) results))
        (rel (lambda (f) (file-relative-name f sp-reload-modules-dir))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "sp-reload: %d reloaded, %d failed\n\n"
                        (- (length results) (length failed)) (length failed)))
        (dolist (r results)
          (insert (format "  %s %s%s\n" (if (plist-get r :ok) "ok    " "FAILED")
                          (funcall rel (plist-get r :file))
                          (concat
                           (if (plist-get r :error)
                               (format "\n          %S" (plist-get r :error)) "")
                           (if (plist-get r :undone)
                               (format "  [undid %d hook/advice/timer]"
                                       (plist-get r :undone)) "")
                           (if (plist-get r :minor)
                               (format "  [re-enabled %s]"
                                       (mapconcat #'symbol-name (plist-get r :minor) ", "))
                             "")
                           (if (> (or (plist-get r :modes) 0) 0)
                               (format "  [re-ran major mode in %d buffer(s)]"
                                       (plist-get r :modes)) "")))))
        (let (warn)
          (when restart
            (push (format "NEEDS RESTART: %s changed (never reloaded)"
                          (string-join restart ", ")) warn))
          (when removed
            (push (format "removed stale functions: %s"
                          (mapconcat #'symbol-name removed ", ")) warn))
          (dolist (r results)
            (when (plist-get r :macros)
              (let ((deps (sp-reload--dependents (plist-get r :features)
                                                 (list (plist-get r :file)))))
                (push (format "%s defines macros (%s); callers are not re-expanded%s"
                              (funcall rel (plist-get r :file))
                              (mapconcat #'symbol-name (plist-get r :macros) ", ")
                              (if deps (format " – reload/restart for: %s"
                                               (string-join deps ", ")) ""))
                      warn)))
            (unless (or (sp-reload--tracking-p) (not (plist-get r :ok)))
              (push (format "%s was reloaded without tracking: hooks/advice/timers may now be duplicated or stale; call `sp-reload-enable-tracking' early in init.el"
                            (funcall rel (plist-get r :file)))
                    warn)))
          (when failed
            (push "some files failed; state is partial. Fix and re-run, the base revision was not advanced."
                  warn))
          (setq warn (append (nreverse warn) warnings))
          (when warn
            (insert "\nLikely needs attention / restart:\n")
            (dolist (w warn) (insert "  - " w "\n"))))
        (when other
          (insert (format "\nChanged outside the modules dir, not reloaded: %s\n"
                          (string-join other ", "))))
        (when not-loaded
          (insert (format "\nNot loaded in this session (picked up on first use): %s\n"
                          (string-join not-loaded ", "))))
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buf)
    (message "sp-reload: %d reloaded, %d failed%s"
             (- (length results) (length failed)) (length failed)
             (if (or restart failed) " – see *sp-reload*" ""))))

;;;###autoload
(defun sp-reload-changed (&optional since)
  "Reload modules changed since the last synchronisation with git.
With prefix argument, prompt for the revision to compare against (default
ORIG_HEAD, which `git pull' sets)."
  (interactive (list (when current-prefix-arg
                       (read-string "Reload files changed since rev: " "ORIG_HEAD"))))
  (let* ((ctx (sp-reload--git-context))
         (head (or (sp-reload--rev ctx "HEAD") (user-error "No HEAD")))
         (base (or since sp-reload--base-rev "ORIG_HEAD")))
    (unless (sp-reload--rev ctx base) (user-error "Cannot resolve revision %s" base))
    (let* ((files (sp-reload--changed ctx base))
           (results (if files
                        (sp-reload--run files (sp-reload--diff-warnings ctx base files))
                      (message "sp-reload: no .el changes since %s" base)
                      nil)))
      (when (cl-every (lambda (r) (plist-get r :ok)) results)
        (setq sp-reload--base-rev head)))))

;;;###autoload
(defalias 'sp-reload-modules #'sp-reload-changed
  "Reload the modules changed since the last synchronisation with git.")

;;;###autoload
(defun sp-reload-file (file)
  "Reload FILE (default: the current buffer's file) with the same machinery."
  (interactive (list (or buffer-file-name (user-error "Buffer has no file"))))
  (sp-reload--run (list (expand-file-name file))))

;;;; Magit

(defun sp-reload--magit-refreshed ()
  "Nudge, prompt or reload when HEAD moved since the last reload."
  (when (and sp-reload-magit-action sp-reload--base-rev (not sp-reload--busy))
    (condition-case nil
        (let* ((ctx (sp-reload--git-context))
               (head (sp-reload--rev ctx "HEAD")))
          (when (and head (not (equal head sp-reload--base-rev))
                     (not (equal head sp-reload--last-nudge)))
            (setq sp-reload--last-nudge head)
            (let ((n (length (sp-reload--changed ctx sp-reload--base-rev))))
              (when (> n 0)
                (pcase sp-reload-magit-action
                  ('reload (sp-reload-changed))
                  ('prompt (when (y-or-n-p (format "%d config file(s) changed; reload? " n))
                             (sp-reload-changed)))
                  (_ (message "sp-reload: %d .el file(s) changed since last reload; M-x sp-reload-modules" n)))))))
      (error nil))))

(with-eval-after-load 'magit
  (add-hook 'magit-post-refresh-hook #'sp-reload--magit-refreshed)
  (ignore-errors
    (transient-append-suffix 'magit-pull "e"
      '("R" "Reload changed modules" sp-reload-changed))))

;; Remember where the running Emacs stands.
(unless sp-reload--base-rev
  (setq sp-reload--base-rev
        (ignore-errors (sp-reload--rev (sp-reload--git-context) "HEAD"))))

(when sp-reload-track-on-load
  (sp-reload-enable-tracking))

(provide 'sp-reload)
;;; sp-reload.el ends here
