;;; sp-batch-report.el --- Report buffer of the batch commands, files as links -*- lexical-binding: t; -*-

;;; Commentary:

;; The reports of the batch conversions and lints are Org text in a read-only
;; buffer.  Every file is an Org link, so RET visits it.  Entries carry a key
;; (the file by default): `d' drops one from the list, `u' brings it back and `A'
;; applies what is left.  `sp-batch-report-text' builds the Org text from
;; sections of items, `sp-batch-report-open' shows it.
;; See docs/tangles/funct/sp-batch-report.org.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'seq)
(require 'subr-x)

(declare-function sp-backup-open "sp-backup-lookup")
(declare-function sp-backup-diff "sp-backup-lookup")
(declare-function sp-echo-help-set "sp-interaction")
(autoload 'sp-batch-cancel "sp-async-work" nil t)
(defvar sp-async-work--jobs)

(defgroup sp-batch-report nil
  "The report buffer of the batch conversions and lints."
  :group 'org)

(defcustom sp-batch-report-interface 'new
  "Which report view the batch commands open.
`new' is `sp-batch-report-mode'.  `old' is the report mode each module had
before; those are obsolete and kept only to compare with the new one."
  :type '(choice (const :tag "Shared report buffer" new)
                 (const :tag "Old per-module view (obsolete)" old))
  :group 'sp-batch-report)

(defun sp-batch-report-new-p ()
  "Non-nil when the batch commands should open the shared report buffer."
  (not (eq sp-batch-report-interface 'old)))

(defun sp-batch-report-file-link (file &optional label line)
  "Return an Org link that visits FILE.
LABEL is the text of the link; it defaults to the name of FILE without its
folder.  LINE, when given, makes the link land on that line, or, when it is a
string, on what that Org search option finds (\"/REGEXP/\" or a text)."
  (let ((path (expand-file-name file)))
    (org-link-make-string
     (concat "file:" path
             (cond ((integerp line) (format "::%d" line))
                   ((stringp line) (concat "::" line))))
     (or label (file-name-nondirectory (directory-file-name path))))))

(defun sp-batch-report-file-links (files &optional separator)
  "Return the links of FILES, joined with SEPARATOR (default \", \")."
  (mapconcat #'sp-batch-report-file-link files (or separator ", ")))

(defun sp-batch-report-note-link (id title)
  "Return an Org link to the note ID, shown as TITLE."
  (org-link-make-string (concat "id:" id) title))

(defun sp-batch-report-item (text &rest args)
  "Return an item with TEXT; ARGS are :file :line :label :key :children :props."
  (append (list :text text) args))

(defun sp-batch-report-section (title items &optional empty)
  "Return a section named TITLE of ITEMS; EMPTY is shown when there are none."
  (list :title title :items items :empty empty))

(defun sp-batch-report--item-key (item)
  "The key of ITEM: its :key, else its file."
  (if (plist-member item :key) (plist-get item :key) (plist-get item :file)))

(defun sp-batch-report--indent (text prefix)
  "TEXT with PREFIX in front of every line after the first."
  (replace-regexp-in-string "\n" (concat "\n" prefix) text t t))

(defun sp-batch-report--item-string (item &optional dropped)
  "The Org text of ITEM, with its text properties.  DROPPED marks a dropped one."
  (let* ((file (plist-get item :file))
         (line (plist-get item :line))
         (label (or (plist-get item :label)
                    (and file (concat (file-name-nondirectory (directory-file-name file))
                                      (and (integerp line) (format ":%d" line))))))
         (head (and file (sp-batch-report-file-link file label line)))
         (text (concat "- " head (and head (plist-get item :text) "  ")
                       (sp-batch-report--indent (or (plist-get item :text) "") "  ")
                       "\n"
                       (mapconcat (lambda (c)
                                    (concat "  - " (sp-batch-report--indent c "    ") "\n"))
                                  (plist-get item :children) "")))
         (key (sp-batch-report--item-key item)))
    (apply #'propertize text
           (append (and key (list 'sp-batch-report-key key))
                   (and file (list 'sp-batch-report-file file))
                   (and line (list 'sp-batch-report-line line))
                   (and dropped (list 'sp-batch-report-dropped t))
                   (plist-get item :props)))))

(defun sp-batch-report--key-label (key)
  "A label for the dropped KEY."
  (if (and (stringp key) (file-name-absolute-p key))
      (sp-batch-report-file-link key)
    (format "%s" key)))

(defun sp-batch-report-dropped-section (excluded &optional found key-label)
  "The Org text of the section that lists the EXCLUDED keys.
FOUND is an alist of (KEY . ITEM) for the keys the report still knows;
KEY-LABEL turns a key that is not in it into text."
  (concat "* Dropped from the list (u brings one back) (" (number-to-string (length excluded)) ")\n"
          (mapconcat
           (lambda (key)
             (if-let* ((item (cdr (assoc key found))))
                 (sp-batch-report--item-string item t)
               (sp-batch-report--item-string
                (list :text (funcall (or key-label #'sp-batch-report--key-label) key)
                      :key key)
                t)))
           excluded "")))

(defun sp-batch-report-key-entries (text)
  "Return the Org TEXT with the key property on every entry that starts with a file link.
An entry starts at a line like \"- [[file:PATH]...\" or \"** [[file:PATH]...\"; its key is
PATH.  It goes on until a blank line, a heading or the next such line, so the
lines under it belong to it.  This is for reports that are built as plain text."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (let (start key)
      (cl-flet ((close (pos)
                  (when start
                    (put-text-property start pos 'sp-batch-report-key key)
                    (put-text-property start pos 'sp-batch-report-file key)
                    (setq start nil))))
        (while (not (eobp))
          (let ((bol (point)))
            (cond
             ((looking-at "\\(?:\\*+\\|-\\) \\[\\[file:\\([^]]*\\)\\]")
              (close bol)
              (setq start bol
                    key (org-link-unescape (replace-regexp-in-string "::.*\\'" "" (match-string 1)))))
             ((or (looking-at "\\*") (looking-at "$")) (close bol))))
          (forward-line 1))
        (close (point-max))))
    (buffer-string)))

(defun sp-batch-report-without-excluded (items key-function excluded)
  "ITEMS minus the ones whose key, from KEY-FUNCTION, is in EXCLUDED."
  (if excluded
      (cl-remove-if (lambda (item) (member (funcall key-function item) excluded)) items)
    items))

(defun sp-batch-report-text (title sections &rest args)
  "Return the Org text of a report called TITLE made of SECTIONS.
ARGS: :intro (text under the title), :excluded (the dropped keys),
:key-label (function that turns a dropped key into text)."
  (let* ((excluded (plist-get args :excluded))
         found
         (body
          (mapconcat
           (lambda (section)
             (let (kept)
               (dolist (item (plist-get section :items))
                 (let ((key (sp-batch-report--item-key item)))
                   (if (and key (member key excluded))
                       (push (cons key item) found)
                     (push item kept))))
               (setq kept (nreverse kept))
               (concat "* " (plist-get section :title) " (" (number-to-string (length kept)) ")\n"
                       (if kept
                           (mapconcat #'sp-batch-report--item-string kept "")
                         (concat (or (plist-get section :empty) "none") "\n"))
                       "\n")))
           sections "")))
    (concat "#+title: " title "\n"
            (and (plist-get args :intro) (concat "\n" (plist-get args :intro) "\n"))
            "\n" body
            (and excluded
                 (sp-batch-report-dropped-section excluded found (plist-get args :key-label))))))

(defcustom sp-batch-report-batch-size 50
  "Number of entries a batch command goes through before it asks whether to go on.
nil or 0 means no batches: everything at once."
  :type '(choice (const :tag "All at once" nil) integer)
  :group 'sp-batch-report)

(defun sp-batch-report--ask-batch (label batch index total left)
  "Ask what to do with BATCH, number INDEX of TOTAL; LEFT entries come after it.
LABEL names the command.  Return ?a (apply all), ?c (choose each), ?s (skip
this batch), ?g (global: apply this batch and every later one without asking
again) or ?q (quit: leave this and the later batches alone)."
  (read-char-choice
   (format "%s: batch %d/%d, %d entr%s (%d after it).  [a]pply all, [c]hoose each, [s]kip, [g]lobal (all the rest), [q]uit? "
           label index total (length batch) (if (= 1 (length batch)) "y" "ies") left)
   '(?a ?c ?s ?g ?q)))

(defun sp-batch-report-run-batches (items fn &rest args)
  "Call FN on each of ITEMS, a batch at a time, asking before every batch.
FN is called with (ITEM DECISION).  When ITEMS fit in one batch nothing is
asked, because the command asked already.  Otherwise each batch is applied
whole (DECISION is t), chosen item by item, skipped, applied together with
all later batches (global: DECISION is t and nothing more is asked), or ends
the run with quit; what was not reached stays as it was, so the command can run again.
ARGS: :label (name for the prompts), :size (default `sp-batch-report-batch-size')
and :choose (function from an item to its DECISION, or nil to skip it; the
default asks `y-or-n-p' with :describe, a function from an item to text).
Return a plist: :done (items FN was called on), :skipped, :remaining (not
reached) and :stopped (non-nil after quit)."
  (let* ((global nil)
         (size (or (plist-get args :size) sp-batch-report-batch-size))
         (batches (seq-partition items (if (and (integerp size) (> size 0))
                                           size
                                         (max 1 (length items)))))
         (total (length batches))
         (label (or (plist-get args :label) "Batch"))
         (describe (or (plist-get args :describe) (lambda (item) (format "%s" item))))
         (choose (or (plist-get args :choose)
                     (lambda (item) (y-or-n-p (format "%s  " (funcall describe item))))))
         (index 0) (done 0) (skipped 0) (stopped nil))
    (while (and batches (not stopped))
      (let* ((batch (pop batches))
             (choice (cond
                      (global ?a)
                      ((= total 1) ?a)
                      (t
                       (sp-batch-report--ask-batch
                        label batch (1+ index) total
                        (apply #'+ (mapcar #'length batches)))))))
        (cl-incf index)
        (when (eq choice ?g) (setq global t choice ?a))
        (pcase choice
          (?q (setq stopped t) (push batch batches))
          (?s (cl-incf skipped (length batch)))
          (?a (dolist (item batch) (funcall fn item t) (cl-incf done)))
          (?c (dolist (item batch)
                (if-let* ((decision (funcall choose item)))
                    (progn (funcall fn item decision) (cl-incf done))
                  (cl-incf skipped)))))))
    (list :done done :skipped skipped :stopped stopped
          :remaining (apply #'+ (mapcar #'length batches)))))

(defun sp-batch-report-batches-note (run)
  "Text for the end of a message about RUN, what `sp-batch-report-run-batches' returned."
  (concat (and (> (plist-get run :skipped) 0) (format "; %d skipped" (plist-get run :skipped)))
          (and (> (plist-get run :remaining) 0)
               (format "; stopped with %d not reached (run the command again for them)"
                       (plist-get run :remaining)))))

(defvar-local sp-batch-report-refresh-function nil
  "The function that \\<sp-batch-report-mode-map>\\[sp-batch-report-refresh] calls to make the report again, or nil.
It gets the list of dropped keys when it takes an argument.")

(defvar-local sp-batch-report-redraw-function nil
  "The function that `d' and `u' call after the dropped keys changed, or nil.
When nil, `sp-batch-report-refresh-function' is used.")

(defvar-local sp-batch-report-apply-function nil
  "The function that \\<sp-batch-report-mode-map>\\[sp-batch-report-apply] calls, with the dropped keys, or nil.")

(defvar-local sp-batch-report-excluded nil
  "The keys dropped from this report with `d'.")

(defvar sp-batch-report--pending-lines (make-hash-table :test #'equal)
  "Buffer name to the line the point goes back to when the report is made again.")

(defun sp-batch-report--call (function &rest args)
  "Call FUNCTION with as many of ARGS as it takes."
  (let ((max (cdr (func-arity function))))
    (apply function (if (eq max 'many) args (seq-take args max)))))

(defun sp-batch-report--redraw (function excluded)
  "Make the report again with FUNCTION, for the dropped keys EXCLUDED."
  (puthash (buffer-name) (line-number-at-pos) sp-batch-report--pending-lines)
  (setq sp-batch-report-excluded excluded)
  (sp-batch-report--call function excluded))

(defun sp-batch-report-refresh ()
  "Make this report again."
  (interactive)
  (unless sp-batch-report-refresh-function
    (user-error "This report cannot be refreshed"))
  (sp-batch-report--redraw sp-batch-report-refresh-function sp-batch-report-excluded))

(defun sp-batch-report--key-at-point ()
  "The key of the entry at point."
  (or (get-text-property (point) 'sp-batch-report-key)
      (and (> (point) (point-min))
           (get-text-property (1- (point)) 'sp-batch-report-key))
      (user-error "No entry here")))

(defun sp-batch-report--redraw-function ()
  "The function that makes the report again after a drop or a restore."
  (or sp-batch-report-redraw-function sp-batch-report-refresh-function
      (user-error "This report cannot be drawn again")))

(defun sp-batch-report-drop ()
  "Drop the entry at point from the list; a later `A' leaves it out."
  (interactive)
  (let ((key (sp-batch-report--key-at-point)))
    (when (get-text-property (point) 'sp-batch-report-dropped)
      (user-error "This entry is already dropped"))
    (sp-batch-report--redraw (sp-batch-report--redraw-function)
                             (append (remove key sp-batch-report-excluded) (list key)))))

(defun sp-batch-report-restore ()
  "Bring the dropped entry at point back into the list."
  (interactive)
  (let ((key (sp-batch-report--key-at-point)))
    (unless (member key sp-batch-report-excluded)
      (user-error "This entry is not dropped"))
    (sp-batch-report--redraw (sp-batch-report--redraw-function)
                             (remove key sp-batch-report-excluded))))

(defun sp-batch-report-apply ()
  "Apply what this report lists, leaving out the dropped entries."
  (interactive)
  (unless sp-batch-report-apply-function
    (user-error "This report has nothing to apply"))
  (sp-batch-report--call sp-batch-report-apply-function sp-batch-report-excluded))

(defun sp-batch-report--header-line ()
  "The keys of this report, for the header line."
  (concat " RET visit  n/p link"
          (and (or sp-batch-report-redraw-function sp-batch-report-refresh-function)
               "  d drop  u restore")
          (and sp-batch-report-apply-function "  A apply")
          (and sp-batch-report-refresh-function "  g refresh")
          "  b backups  D diff backup"
          (and (bound-and-true-p sp-async-work--jobs) "  k stop job")
          "  q quit"))

(defun sp-batch-report--hints ()
  "The key hints of this report, for `sp-echo-help-set'."
  (append '(("RET" "Visit") ("n/p" "Link"))
          (and (or sp-batch-report-redraw-function sp-batch-report-refresh-function)
               '(("d" "Drop") ("u" "Restore")))
          (and sp-batch-report-apply-function '(("A" "Apply" t)))
          (and sp-batch-report-refresh-function '(("g" "Refresh")))
          '(("k" "Stop running job") ("q" "Quit"))))

(defvar sp-batch-report-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'org-open-at-point)
    (define-key map (kbd "n") #'org-next-link)
    (define-key map (kbd "p") #'org-previous-link)
    (define-key map (kbd "d") #'sp-batch-report-drop)
    (define-key map (kbd "u") #'sp-batch-report-restore)
    (define-key map (kbd "A") #'sp-batch-report-apply)
    (define-key map (kbd "C-c C-c") #'sp-batch-report-apply)
    (define-key map (kbd "g") #'sp-batch-report-refresh)
    (define-key map (kbd "b") #'sp-backup-open)
    (define-key map (kbd "D") #'sp-backup-diff)
    (define-key map (kbd "k") #'sp-batch-cancel)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap of `sp-batch-report-mode'.")

(define-derived-mode sp-batch-report-mode org-mode "Report"
  "Read-only Org buffer holding the report of a batch command.
Files are links: \\<sp-batch-report-mode-map>\\[org-open-at-point] visits the one at point,
\\[org-next-link] and \\[org-previous-link] move between them.  \\[sp-batch-report-drop] drops the entry at point from the list,
\\[sp-batch-report-restore] brings it back, \\[sp-batch-report-apply] applies what is left,
\\[sp-batch-report-refresh] makes the report again and \\[quit-window] closes it.
\\[sp-backup-open] and \\[sp-backup-diff] open or diff a backup of the file on the line."
  (setq buffer-read-only t)
  (setq-local header-line-format '(:eval (sp-batch-report--header-line))))

(defvar use-short-answers)
(defvar save-silently)

(defcustom sp-batch-report-save-and-kill t
  "Whether the batch commands save, then kill, the buffers of the files they use.
Non-nil: a buffer with unsaved changes is saved without asking (the commands
copy the file to their backup folder first), and every buffer of a processed
file is killed afterwards, also one that was open before.  nil: each command
keeps its own rule (skip or refuse a buffer with unsaved changes, leave open
buffers open)."
  :type 'boolean
  :group 'sp-batch-report)

(defvar sp-batch-report-keep-buffers nil
  "Buffers that `sp-batch-report-close-file' saves but does not kill.")

(defun sp-batch-report--quietly (thunk)
  "Call THUNK without any question or message to the user."
  (let ((inhibit-message t)
        (save-silently t)
        (use-short-answers t)
        (use-dialog-box nil)
        (confirm-kill-processes nil)
        (kill-buffer-query-functions nil))
    ;; The "file changed on disk" question: go on and save.
    (cl-letf (((symbol-function 'ask-user-about-supersession-threat) #'ignore))
      (funcall thunk))))

(defun sp-batch-report--note-problem (file text)
  "Record the TEXT about FILE in *Messages* only."
  (when text
    (let ((inhibit-message t))
      (message "sp-batch-report: %s: %s" (file-name-nondirectory file) text))))

(defun sp-batch-report-save-buffer (buffer)
  "Save BUFFER without asking when it has unsaved changes.
Return nil, or the text of the error."
  (when (and (buffer-live-p buffer) (buffer-file-name buffer) (buffer-modified-p buffer))
    (condition-case err
        (sp-batch-report--quietly
         (lambda ()
           (with-current-buffer buffer
             ;; Changed on disk too: the buffer wins (callers back the disk text up).
             (unless (verify-visited-file-modtime) (set-visited-file-modtime))
             (save-buffer))
           nil))
      (error (error-message-string err)))))

(defun sp-batch-report-flush-file (file &optional backup-function)
  "Make the buffer visiting FILE, if any, agree with the disk, when `sp-batch-report-save-and-kill'.
Unsaved changes are saved, after BACKUP-FUNCTION (called with FILE) copied the
disk version.  An unchanged buffer older than the file is reverted.  Return nil,
or the text of the error."
  (when sp-batch-report-save-and-kill
    (when-let* ((buffer (find-buffer-visiting file)))
      (cond
       ((buffer-modified-p buffer)
        (when backup-function (funcall backup-function file))
        (sp-batch-report-save-buffer buffer))
       ((not (verify-visited-file-modtime buffer))
        (condition-case err
            (sp-batch-report--quietly
             (lambda () (with-current-buffer buffer (revert-buffer t t t)) nil))
          (error (error-message-string err))))))))

(defun sp-batch-report-close-file (file)
  "Save, then kill, the buffer visiting FILE, when `sp-batch-report-save-and-kill'.
The buffer in use (current, or in the selected window) is saved but not killed.
A buffer that cannot be saved stays.  Return nil, or the text of the problem;
it is also written to *Messages*."
  (when sp-batch-report-save-and-kill
    (when-let* ((buffer (find-buffer-visiting file)))
      (let ((problem
             (or (sp-batch-report-save-buffer buffer)
                 (unless (or (eq buffer (current-buffer))
                             (memq buffer sp-batch-report-keep-buffers)
                             (eq buffer (window-buffer (selected-window))))
                   (condition-case err
                       (sp-batch-report--quietly
                        (lambda ()
                          (unless (kill-buffer buffer) "the buffer was not killed")))
                     (error (error-message-string err)))))))
        (sp-batch-report--note-problem file problem)
        problem))))

(defun sp-batch-report-with-file (file function &optional backup-function)
  "Call FUNCTION in the buffer visiting FILE, opening it when needed.
With `sp-batch-report-save-and-kill' the buffer is flushed first (see
`sp-batch-report-flush-file') and saved and killed afterwards.  Without it a
buffer the call opened is killed again unless it has unsaved changes.  Return
the value of FUNCTION.  A buffer that cannot be saved before the call signals an error."
  (let ((problem (sp-batch-report-flush-file file backup-function))
        (open (find-buffer-visiting file)))
    (when problem (error "%s: %s" (file-name-nondirectory file) problem))
    (let ((buffer (or open (find-file-noselect file))))
      (unwind-protect
          (with-current-buffer buffer (funcall function))
        (if sp-batch-report-save-and-kill
            (sp-batch-report-close-file file)
          (unless (or open (buffer-modified-p buffer))
            (kill-buffer buffer)))))))

(defun sp-batch-report-open (name text &rest args)
  "Show the Org TEXT in the read-only report buffer NAME and return it.
ARGS: :refresh, :redraw and :apply (functions, see `sp-batch-report-mode'),
:excluded (the dropped keys) and :mode (a mode derived from
`sp-batch-report-mode')."
  (let ((line (gethash name sp-batch-report--pending-lines)))
    (remhash name sp-batch-report--pending-lines)
    (with-current-buffer (get-buffer-create name)
      (funcall (or (plist-get args :mode) #'sp-batch-report-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (goto-char (point-min)))
      (outline-show-all)
      (setq sp-batch-report-refresh-function (plist-get args :refresh)
            sp-batch-report-redraw-function (plist-get args :redraw)
            sp-batch-report-apply-function (plist-get args :apply)
            sp-batch-report-excluded (plist-get args :excluded))
      (when line
        (goto-char (point-min))
        (forward-line (1- line)))
      (when (fboundp 'sp-echo-help-set)
        (sp-echo-help-set (sp-batch-report--hints)))
      (pop-to-buffer (current-buffer))
      (when-let* ((window (get-buffer-window (current-buffer))))
        (set-window-point window (point)))
      (current-buffer))))

(defun sp-batch-report-show (name text &optional refresh mode)
  "Show the Org TEXT in the read-only report buffer NAME and return it.
REFRESH is the function \\`g' calls.  MODE is the major mode to use, a mode
derived from `sp-batch-report-mode'; the default is that mode."
  (sp-batch-report-open name text :refresh refresh :mode mode))

(provide 'sp-batch-report)
;;; sp-batch-report.el ends here
