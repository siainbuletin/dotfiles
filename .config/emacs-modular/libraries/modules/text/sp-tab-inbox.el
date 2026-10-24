;;; sp-tab-inbox.el --- Link inbox sidebar widgets for vulpea-ui -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "29.1") (vulpea "2") (vulpea-ui "0") (vui "0"))

;;; Commentary:

;; A `vulpea-ui' sidebar widget that searches a directory of plain files
;; (the "link inbox") for mentions of the current note's title and aliases,
;; without adding those files to the vulpea database.
;;
;; - Each hit is shown on its own lines, with the body text word-wrapped.
;; - Hits whose only match sits inside an id: link into the current note's
;;   file (the note itself or any heading with an :ID:) are filtered out.
;; - `collect' moves a hit under a heading of the current note using
;;   `sp-move-region-to-heading', keeping the list bullet in both places and
;;   leaving a link behind.  `collect all' does this for every hit, asking for
;;   the heading once.
;; - `collect all' runs in the background: it works in short slices while Emacs
;;   is idle, so you can keep editing (also in the note being collected into),
;;   and saves everything once at the end.  `sp-tab-inbox-cancel-collect'
;;   stops it.
;; - `send' (or `sp-tab-inbox-send-elsewhere') sends a hit to another
;;   note you pick or create, for when the match is about something else.
;;   At that prompt, an embark action ("L", see `sp-tab-inbox-embark-map')
;;   also links that note under "See also" in the note you searched from.
;; - A second widget, `Inbox backlinks', lists the lines of the inbox files that
;;   link to the current note (e.g. the links `collect' leaves behind), with
;;   several lines of context, again without indexing the files.
;; - Inbox files that were not already open are saved and killed afterwards.
;;
;; Load it after vulpea-ui, e.g.:
;;
;;   (with-eval-after-load 'vulpea-ui
;;     (require 'sp-tab-inbox))
;;
;; and set `sp-tab-inbox-dir' to your inbox directory.  Press `g' in the
;; sidebar to refresh.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vulpea)
(require 'vulpea-ui)
(require 'vui)
(require 'sp-move-region-to-heading)

;;;; Configuration
(defcustom sp-tab-inbox-dir (concat org-directory "/inbox/tabs/")
  "Directory of plain files with unsorted links."
  :type 'directory
  :group 'spcustom)

(defcustom sp-tab-inbox-fill-column 40
  "Wrap width for link inbox results.
Tune to your sidebar width."
  :type 'integer
  :group 'spcustom)

(defcustom sp-tab-inbox-auto-resources t
  "When non-nil, collect under the note's \"Resources\" heading automatically.
The heading is matched like `sp--resources-heading-p' does, in any case,
and only inside the subtree the sidebar is scoped to (the whole file for
a file-level note, the narrowed heading otherwise).  If there is no such
heading, or the choice is ambiguous, you are prompted for one as usual.
See `sp-tab-inbox--resources-target' for how ties are handled."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-tab-inbox-new-note-body "* Resources\n"
  "Body of a note created by `sp-tab-inbox-send-elsewhere'.
The default gives the new note a Resources heading, so the hit lands there
without another prompt.  Set to nil for an empty note."
  :type '(choice (const :tag "Empty note" nil) string)
  :group 'spcustom)

(defcustom sp-tab-inbox-see-also-heading "See also"
  "Title of the heading that collects backlinks in the originating note.
It is a direct child of the subtree the sidebar is scoped to, and the
last heading in it."
  :type 'string
  :group 'spcustom)

(defcustom sp-tab-inbox-backlink-context-lines 4
  "Lines of context shown above and below each inbox backlink."
  :type 'integer
  :group 'spcustom)

(defvar sp-tab-inbox-generation 0
  "Bumped after collecting, so the widget's memo recomputes.")

(defvar sp-tab-inbox--current nil
  "The (NOTE . HITS) the widget last rendered, for the interactive commands.")

(defvar sp-tab-inbox--pending nil
  "The (FILE LINE TEXT ORIGIN) hit waiting for an embark action.
Embark quits the minibuffer before running an action, so the hit being
sent has to live outside the command that is prompting.")

(defconst sp-tab-inbox-bullet-re
  "\\(?:[ \t]*[-+]\\|[ \t]*[0-9]+[.)]\\|[ \t]+\\*\\)[ \t]+\\(?:\\[[ xX-]\\][ \t]+\\)?"
  "Matches a list bullet (and optional checkbox) at the start of a line.
A column-0 `*' is an Org heading, so it is not treated as a bullet.")

;;;; Searching

(defun sp-tab-inbox--note-ids (note)
  "Return the ID of NOTE plus every :ID: property in NOTE's file."
  (let ((path (vulpea-note-path note))
        (ids (list (vulpea-note-id note))))
    (when (and path (file-readable-p path))
      (with-temp-buffer
        (if-let* ((buf (find-buffer-visiting path)))
            (insert (with-current-buffer buf
                      (save-restriction
                        (widen)
                        (buffer-substring-no-properties (point-min) (point-max)))))
          (insert-file-contents path))
        (goto-char (point-min))
        (while (re-search-forward "^[ \t]*:ID:[ \t]+\\([^ \t\n]+\\)" nil t)
          (push (match-string 1) ids))))
    (delete-dups ids)))

(defun sp-tab-inbox--unlinked-p (text terms ids)
  "Non-nil if some term in TERMS occurs in TEXT outside links to any of IDS."
  (let* ((case-fold-search t)
         (link-re (concat "\\[\\[id:" (regexp-opt ids)
                          "\\]\\(?:\\[[^]]*\\]\\)?\\]"))
         (stripped (replace-regexp-in-string link-re "" text t t)))
    (seq-some (lambda (term) (string-match-p (regexp-quote term) stripped))
              terms)))

(defun sp-tab-inbox-search (note)
  "Return list of (FILE LINE TEXT) mentioning NOTE's title or aliases.
Matches that only sit inside id: links into NOTE's file are dropped."
  (when-let* ((rg (executable-find "rg"))
              (terms (seq-filter
                      (lambda (s) (>= (length s) 3))
                      (cons (vulpea-note-title note)
                            (vulpea-note-aliases note)))))
    (with-temp-buffer
      (apply #'call-process rg nil t nil
             "--line-number" "--no-heading" "--with-filename"
             "--ignore-case" "--fixed-strings" "--word-regexp"
             (append (mapcan (lambda (term) (list "-e" term)) terms)
                     (list (expand-file-name sp-tab-inbox-dir))))
      (goto-char (point-min))
      (let ((ids (sp-tab-inbox--note-ids note))
            result)
        (while (re-search-forward "^\\(.+?\\):\\([0-9]+\\):\\(.*\\)$" nil t)
          (let ((text (string-trim (match-string 3))))
            (when (sp-tab-inbox--unlinked-p text terms ids)
              (push (list (match-string 1)
                          (string-to-number (match-string 2))
                          text)
                    result))))
        (nreverse result)))))

;;;; Display helpers

(defun sp-tab-inbox-wrap (text)
  "Fill TEXT to `sp-tab-inbox-fill-column' and indent it by two spaces."
  (with-temp-buffer
    (insert text)
    (let ((fill-column sp-tab-inbox-fill-column))
      (fill-region (point-min) (point-max)))
    (goto-char (point-min))
    (while (not (eobp))
      (insert "  ")
      (forward-line 1))
    (buffer-string)))

(defun sp-tab-inbox-visit (file line)
  "Visit LINE of FILE in another window."
  (find-file-other-window file)
  (goto-char (point-min))
  (forward-line (1- line)))

;;;; Collecting

(defun sp-tab-inbox--heading-marker (note)
  "Return a marker at the heading NOTE refers to, or nil.
The position stored in NOTE is trusted only if the heading there carries
NOTE's ID; otherwise the heading is looked up by ID."
  (with-current-buffer (find-file-noselect (vulpea-note-path note))
    (org-with-wide-buffer
     (let ((id (vulpea-note-id note))
           (pos (vulpea-note-pos note)))
       (or (and pos (<= 1 pos (point-max))
                (progn (goto-char pos)
                       (and (org-at-heading-p)
                            (equal (org-entry-get nil "ID") id)
                            (point-marker))))
           (org-id-find id t))))))

(defun sp-tab-inbox--scope-root (note)
  "Return (MARKER . LEVEL) for the subtree the sidebar is scoped to.
For a heading-level NOTE (e.g. when the sidebar follows narrowing) this is
that heading.  For a file-level note, or if the heading can't be found, it
is the whole file: MARKER at the start of the file and LEVEL 0."
  (or (and (> (or (vulpea-note-level note) 0) 0)
           (when-let* ((m (sp-tab-inbox--heading-marker note)))
             (cons m (with-current-buffer (marker-buffer m)
                       (org-with-wide-buffer
                        (goto-char m)
                        (org-current-level))))))
      (with-current-buffer (find-file-noselect (vulpea-note-path note))
        (cons (org-with-wide-buffer (copy-marker (point-min))) 0))))

(defun sp-tab-inbox--resources-candidates (root &optional pred)
  "Return (MARKER LEVEL ID) for each Resources heading below ROOT.
ROOT is (MARKER . LEVEL) as returned by `sp-tab-inbox--scope-root'.
The root heading itself is not a candidate.  PRED, if given, replaces
`sp--resources-heading-p' as the test on the heading's title."
  (with-current-buffer (marker-buffer (car root))
    (org-with-wide-buffer
     (let (result)
       (goto-char (car root))
       (org-map-entries
        (lambda ()
          (when (and (> (org-current-level) (cdr root))
                     (funcall (or pred #'sp--resources-heading-p)
                              (org-get-heading t t t t)))
            (push (list (point-marker)
                        (org-current-level)
                        (org-entry-get nil "ID"))
                  result)))
        nil
        (if (zerop (cdr root)) nil 'tree))
       (nreverse result)))))

(defun sp-tab-inbox--subtree-parts (marker)
  "Return (BEG END HEAD BODY CHILDREN) for the subtree at MARKER.
BEG and END delimit the whole subtree.  HEAD is the heading line plus its
planning line and property drawer, BODY is the text before the first
sub-heading, and CHILDREN is everything from the first sub-heading on."
  (save-excursion
    (goto-char marker)
    (let* ((beg (line-beginning-position))
           (end (progn (org-end-of-subtree t t) (point)))
           (meta-end (progn (goto-char beg)
                            (org-end-of-meta-data)
                            (min (point) end)))
           (next (progn (goto-char beg)
                        (end-of-line)
                        (if (outline-next-heading) (min (point) end) end)))
           (child-beg (max meta-end next)))
      (list beg end
            (buffer-substring-no-properties beg meta-end)
            (buffer-substring-no-properties meta-end child-beg)
            (buffer-substring-no-properties child-beg end)))))

(defun sp-tab-inbox--parent-marker (marker)
  "Return a marker at the parent heading of the heading at MARKER, or nil.
Nil means the heading sits directly under the file."
  (with-current-buffer (marker-buffer marker)
    (org-with-wide-buffer
     (goto-char marker)
     (when (org-up-heading-safe)
       (point-marker)))))

(defun sp-tab-inbox--merge-resources (tied parent &optional label)
  "Merge the TIED sibling Resources headings into a single one under PARENT.
TIED are (MARKER LEVEL ID) entries as returned by
`sp-tab-inbox--resources-candidates', all children of PARENT (a marker, or
nil for the file itself) at the same level.  The first heading's line and
properties are kept; the bodies of all headings are concatenated in file
order, followed by all their sub-headings.  The result is a single heading
at the same level, placed at the end of PARENT's subtree, as its last
child.  LABEL names the headings in messages and in the returned path
(default \"Resources\").  Return (MARKER . PATH) for the merged heading."
  (with-current-buffer (marker-buffer (car (car tied)))
    (org-with-wide-buffer
     (let* ((parts (mapcar (lambda (c) (sp-tab-inbox--subtree-parts (car c)))
                           (sort (copy-sequence tied)
                                 (lambda (a b) (< (car a) (car b))))))
            (nl (lambda (s)
                  (if (or (string-empty-p s) (string-suffix-p "\n" s))
                      s
                    (concat s "\n"))))
            ;; each part is (BEG END HEAD BODY CHILDREN)
            (text (concat (funcall nl (nth 2 (car parts)))
                          (mapconcat (lambda (p) (funcall nl (nth 3 p))) parts "")
                          (mapconcat (lambda (p) (funcall nl (nth 4 p))) parts ""))))
       ;; delete bottom-up so the earlier positions stay valid
       (dolist (p (reverse parts))
         (delete-region (nth 0 p) (nth 1 p)))
       (if parent
           (progn (goto-char parent) (org-end-of-subtree t t))
         (goto-char (point-max)))
       (unless (bolp) (insert "\n"))
       (let ((pos (point)))
         (insert text)
         (message "Merged %d %s headings" (length parts) (or label "Resources"))
         (cons (copy-marker pos) (or label "Resources")))))))

(defun sp-tab-inbox--resources-target (note)
  "Return (MARKER . PATH) for the Resources heading to collect under, or nil.
Only the subtree NOTE is scoped to is searched, and the shallowest
Resources heading wins.  If several are tied at that depth:
- when they are siblings under the same parent, that is a formatting
  error: they are merged in place into a single Resources heading at the
  same level, last under that parent (see `sp-tab-inbox--merge-resources'),
  which is then used -- unless any of them has an ID, in which case nil is
  returned (the caller prompts), since merging would drop IDs that may be
  linked to;
- when they sit under different parents, the choice is ambiguous and nil
  is returned (the caller prompts); nothing is changed."
  (let* ((root (sp-tab-inbox--scope-root note))
         (cands (sp-tab-inbox--resources-candidates root)))
    (when cands
      (let* ((min-level (apply #'min (mapcar #'cadr cands)))
             (tied (seq-filter (lambda (c) (= (cadr c) min-level)) cands)))
        (if (null (cdr tied))
            (cons (car (car tied)) "Resources")
          (let* ((parents (mapcar (lambda (c) (sp-tab-inbox--parent-marker (car c)))
                                  tied))
                 (positions (mapcar (lambda (m) (and m (marker-position m)))
                                    parents)))
            (and (zerop (seq-count #'caddr tied))
                 (seq-every-p (lambda (pos) (equal pos (car positions)))
                              positions)
                 (sp-tab-inbox--merge-resources tied (car parents)))))))))

(defun sp-tab-inbox--target (note)
  "Return the (MARKER . PATH) heading target to collect into for NOTE.
Uses the Resources heading when `sp-tab-inbox-auto-resources' is set and
one exists, and otherwise prompts like `sp-move-region-to-heading' does."
  (or (and sp-tab-inbox-auto-resources
           (sp-tab-inbox--resources-target note))
      (sp--read-org-heading (vulpea-note-path note))))

;;;; Collecting: one hit

(defun sp-tab-inbox--collect-line (buf line text target)
  "Move LINE of BUF under TARGET, keeping the list bullet in both places.
TARGET is (MARKER . PATH) as used by `sp-move-region-to-heading'.  Neither
buffer is saved: that is the caller's job.  Return non-nil on success, and
nil if the line no longer reads TEXT (nothing is changed then)."
  (let ((tbuf (marker-buffer (car target))))
    (unless (buffer-live-p tbuf)
      (error "The note buffer for the target heading is gone"))
    (with-current-buffer buf
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (forward-line (1- line))
          (let ((bol (line-beginning-position))
                (end (line-end-position)))
            (when (equal (string-trim (buffer-substring-no-properties bol end))
                         text)
              (goto-char bol)
              (let* ((bullet-end (and (looking-at sp-tab-inbox-bullet-re)
                                      (match-end 0)))
                     ;; with a bullet, start at the bullet (skip indentation)
                     (beg (if bullet-end
                              (progn (skip-chars-forward " \t") (point))
                            bol))
                     (bullet (and bullet-end
                                  (buffer-substring-no-properties beg bullet-end))))
                (goto-char beg)
                ;; `sp-move-region-to-heading' saves the target note on every
                ;; call, which is what makes big batches crawl; hold that back
                ;; (the caller saves once) and look at the whole target buffer
                ;; even if the user has it narrowed.
                (cl-letf (((symbol-function 'save-buffer) #'ignore))
                  (with-current-buffer tbuf
                    (org-with-wide-buffer
                     (with-current-buffer buf
                       (sp-move-region-to-heading
                        beg end (car target) (cdr target))))))
                ;; the link now sits at BEG; put the bullet back before it
                (when bullet
                  (goto-char beg)
                  (insert bullet)))
              t)))))))

(defun sp-tab-inbox-collect (file line text note &optional target)
  "Move LINE of FILE under a heading of NOTE with `sp-move-region-to-heading'.
The list bullet, if any, is moved with the text and also kept in FILE in
front of the link left behind.  Both files are saved.
TEXT is the hit text, checked against the file to catch stale line numbers.
TARGET is an optional (MARKER . PATH) to skip the heading choice.
Return the target used."
  (let* ((target (or target (sp-tab-inbox--target note)))
         (existing (find-buffer-visiting file))
         (buf (or existing (find-file-noselect file))))
    (unwind-protect
        (progn
          (unless (sp-tab-inbox--collect-line buf line text target)
            (user-error "Line %d of %s changed; refresh the sidebar"
                        line (file-name-nondirectory file)))
          (with-current-buffer buf (save-buffer))
          (with-current-buffer (marker-buffer (car target)) (save-buffer)))
      ;; only kill buffers this command opened
      (when (and (not existing) (buffer-live-p buf))
        (kill-buffer buf)))
    target))

;;;; Collecting: all hits, in the background

(defcustom sp-tab-inbox-async-slice 0.05
  "Seconds of work `collect all' does per timer tick before yielding."
  :type 'number
  :group 'spcustom)

(defcustom sp-tab-inbox-async-delay 0.1
  "Seconds Emacs must sit idle before `collect all' does its next slice."
  :type 'number
  :group 'spcustom)

(cl-defstruct (sp-tab-inbox-job (:constructor sp-tab-inbox-job--make)
                                 (:copier nil))
  queue target total (done 0) (skipped 0) file buf existing timer (last-msg 0.0))

(defvar sp-tab-inbox--job nil
  "The running `collect all' job, if any.")

(defun sp-tab-inbox--ensure-idle ()
  "Signal a user error if a `collect all' job is still running."
  (when sp-tab-inbox--job
    (user-error
     "A link inbox job is still running (M-x sp-tab-inbox-cancel-collect stops it)")))

(defun sp-tab-inbox--job-close-file (job)
  "Save and, if JOB opened it, kill the inbox file JOB is working on."
  (when-let* ((buf (sp-tab-inbox-job-buf job)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (buffer-modified-p) (save-buffer)))
      (unless (sp-tab-inbox-job-existing job)
        (kill-buffer buf)))
    (setf (sp-tab-inbox-job-buf job) nil
          (sp-tab-inbox-job-file job) nil)))

(defun sp-tab-inbox--job-finish (job &optional reason)
  "End JOB: save everything once, refresh the sidebar and report.
REASON, if given, says why the job stopped early."
  (when (timerp (sp-tab-inbox-job-timer job))
    (cancel-timer (sp-tab-inbox-job-timer job)))
  (unwind-protect
      (progn
        (sp-tab-inbox--job-close-file job)
        (let ((tbuf (marker-buffer (car (sp-tab-inbox-job-target job)))))
          (when (buffer-live-p tbuf)
            (with-current-buffer tbuf
              (when (buffer-modified-p) (save-buffer))))))
    (setq sp-tab-inbox--job nil))
  (cl-incf sp-tab-inbox-generation)
  (ignore-errors (vulpea-ui-sidebar-refresh))
  (message "Link inbox: collected %d of %d lines%s%s"
           (sp-tab-inbox-job-done job)
           (sp-tab-inbox-job-total job)
           (if (> (sp-tab-inbox-job-skipped job) 0)
               (format ", %d skipped (changed since the search)"
                       (sp-tab-inbox-job-skipped job))
             "")
           (if reason (format " - stopped: %s" reason) "")))

(defun sp-tab-inbox--job-do-one (job)
  "Collect the next queued hit of JOB, opening its file if needed."
  (pcase-let ((`(,file ,line ,text) (pop (sp-tab-inbox-job-queue job))))
    (unless (equal file (sp-tab-inbox-job-file job))
      (sp-tab-inbox--job-close-file job)
      (let ((existing (find-buffer-visiting file)))
        (setf (sp-tab-inbox-job-existing job) existing
              (sp-tab-inbox-job-buf job) (or existing (find-file-noselect file))
              (sp-tab-inbox-job-file job) file)))
    (if (sp-tab-inbox--collect-line (sp-tab-inbox-job-buf job) line text
                                     (sp-tab-inbox-job-target job))
        (cl-incf (sp-tab-inbox-job-done job))
      (cl-incf (sp-tab-inbox-job-skipped job)))))

(defun sp-tab-inbox--job-schedule (job)
  "Arrange for JOB's next slice to run when Emacs is idle."
  (setf (sp-tab-inbox-job-timer job)
        (run-with-idle-timer sp-tab-inbox-async-delay nil
                             #'sp-tab-inbox--job-tick job)))

(defun sp-tab-inbox--job-tick (job)
  "Do one short slice of JOB, then yield to the user."
  (setf (sp-tab-inbox-job-timer job) nil)
  (when (eq job sp-tab-inbox--job)
    (if (active-minibuffer-window)
        (sp-tab-inbox--job-schedule job)
      (let ((deadline (+ (float-time) sp-tab-inbox-async-slice))
            failure)
        (condition-case err
            (cl-loop
             do (sp-tab-inbox--job-do-one job)
             while (and (sp-tab-inbox-job-queue job)
                        (< (float-time) deadline)
                        (not (input-pending-p))))
          (error (setq failure (error-message-string err))))
        (cond
         (failure (sp-tab-inbox--job-finish job failure))
         ((null (sp-tab-inbox-job-queue job)) (sp-tab-inbox--job-finish job))
         (t
          (when (> (- (float-time) (sp-tab-inbox-job-last-msg job)) 1.0)
            (setf (sp-tab-inbox-job-last-msg job) (float-time))
            (message "Link inbox: collected %d/%d..."
                     (+ (sp-tab-inbox-job-done job)
                        (sp-tab-inbox-job-skipped job))
                     (sp-tab-inbox-job-total job)))
          (sp-tab-inbox--job-schedule job)))))))

;;;###autoload
(defun sp-tab-inbox-cancel-collect ()
  "Stop the running `collect all' job.  What was collected so far stays."
  (interactive)
  (if sp-tab-inbox--job
      (sp-tab-inbox--job-finish sp-tab-inbox--job "cancelled")
    (message "No link inbox job is running")))

(defun sp-tab-inbox-collect-one (file line text note)
  "Collect a single hit (FILE, LINE, TEXT) into NOTE and refresh the sidebar."
  (sp-tab-inbox--ensure-idle)
  (sp-tab-inbox-collect file line text note)
  (cl-incf sp-tab-inbox-generation)
  (vulpea-ui-sidebar-refresh))

(defun sp-tab-inbox-collect-all (hits note)
  "Collect every hit in HITS into NOTE, in the background.
The heading is chosen up front (so any prompt or merge happens now); the
lines are then moved in short slices while Emacs is idle, one inbox file
at a time, so you can keep editing, including in NOTE's own file.  Both
kinds of file are saved once the job is done.  Each moved line is replaced
by a one-line link, so line numbers stay valid between hits.  Progress is
shown in the echo area; `sp-tab-inbox-cancel-collect' stops the job."
  (sp-tab-inbox--ensure-idle)
  (when hits
    (let* ((target (sp-tab-inbox--target note))
           (queue (sort (copy-sequence hits)
                        (lambda (a b)
                          (if (equal (car a) (car b))
                              (< (cadr a) (cadr b))
                            (string< (car a) (car b))))))
           (job (sp-tab-inbox-job--make :queue queue
                                         :target target
                                         :total (length queue))))
      (setq sp-tab-inbox--job job)
      (message "Link inbox: collecting %d lines in the background..."
               (length queue))
      (sp-tab-inbox--job-schedule job))))

;;;; Sending to another note

(defvar embark-keymap-alist)

(defvar-keymap sp-tab-inbox-embark-map
  :doc "Embark actions available while choosing where to send a link inbox hit."
  "L" #'sp-tab-inbox-embark-send-and-link)

(defun sp-tab-inbox--embark-alist ()
  "Return `embark-keymap-alist' extended with `sp-tab-inbox-embark-map'.
The map is added in front of whatever is already registered for the
`vulpea-note' category, and is meant to be bound only while prompting,
so that the action exists nowhere else."
  (if (and (require 'embark nil t) (boundp 'embark-keymap-alist))
      (let ((existing (alist-get 'vulpea-note embark-keymap-alist)))
        (cons (cons 'vulpea-note
                    (cons 'sp-tab-inbox-embark-map
                          (if (listp existing) existing (list existing))))
              embark-keymap-alist))
    (bound-and-true-p embark-keymap-alist)))

(defun sp-tab-inbox--ensure-note (note-or-title)
  "Return a real note for NOTE-OR-TITLE, creating a file-level one if needed.
NOTE-OR-TITLE is a title string or a `vulpea-note'; a note without an ID
is what `vulpea-select' returns for a title that doesn't exist yet."
  (if (and (not (stringp note-or-title)) (vulpea-note-id note-or-title))
      note-or-title
    (let ((title (string-trim
                  (or (if (stringp note-or-title)
                          note-or-title
                        (vulpea-note-title note-or-title))
                      ""))))
      (when (string-empty-p title)
        (user-error "Empty note title"))
      (vulpea-create title nil :body sp-tab-inbox-new-note-body))))

(defun sp-tab-inbox--candidate-note (candidate)
  "Return the note CANDIDATE stands for, or its title if there is none.
The ID is read from the `vulpea-note-id' text property, or from the
trailing UUID vulpea appends to every candidate; embark can drop the
property but not the text.  Without an ID, an exact title match among
file-level notes is used if there is exactly one."
  (let* ((id (or (get-text-property 0 'vulpea-note-id candidate)
                 (and (string-match
                       (concat "\\([0-9A-Fa-f]\\{8\\}\\(?:-[0-9A-Fa-f]\\{4\\}\\)\\{3\\}"
                               "-[0-9A-Fa-f]\\{12\\}\\)[ \t]*\\'")
                       candidate)
                      (match-string 1 candidate))))
         (title (string-trim candidate)))
    (or (and id (vulpea-db-get-by-id id))
        (let ((exact (seq-filter
                      (lambda (n)
                        (and (zerop (vulpea-note-level n))
                             (string-equal-ignore-case (vulpea-note-title n) title)))
                      (vulpea-db-search-by-title title))))
          (if (= (length exact) 1) (car exact) title)))))

(defun sp-tab-inbox--see-also-heading-p (title)
  "Non-nil if TITLE is the See also heading, ignoring case and spacing."
  (string-equal-ignore-case (string-trim title) sp-tab-inbox-see-also-heading))

(defun sp-tab-inbox--create-last-child (root title)
  "Create a heading TITLE as the last child of ROOT.
ROOT is (MARKER . LEVEL).  Return a marker at the new heading."
  (with-current-buffer (marker-buffer (car root))
    (org-with-wide-buffer
     (goto-char (car root))
     (if (zerop (cdr root))
         (goto-char (point-max))
       (org-end-of-subtree t t))
     (unless (bolp) (insert "\n"))
     (let ((pos (point)))
       (insert (make-string (1+ (cdr root)) ?*) " " title "\n")
       (copy-marker pos)))))

(defun sp-tab-inbox--see-also-marker (note)
  "Return a marker at NOTE's See also heading, creating it if needed.
The heading is a direct child of the subtree NOTE is scoped to: top level
in a file-level note, one level below the heading when narrowed to one.
It is created as the last heading of that subtree.  If there are several,
they are merged in place unless one has an ID, in which case the first is
used and nothing is changed."
  (let* ((root (sp-tab-inbox--scope-root note))
         (cands (seq-filter
                 (lambda (c) (= (cadr c) (1+ (cdr root))))
                 (sp-tab-inbox--resources-candidates
                  root #'sp-tab-inbox--see-also-heading-p))))
    (cond
     ((null cands)
      (sp-tab-inbox--create-last-child root sp-tab-inbox-see-also-heading))
     ((null (cdr cands))
      (car (car cands)))
     ((zerop (seq-count #'caddr cands))
      (car (sp-tab-inbox--merge-resources
            cands
            (and (> (cdr root) 0) (car root))
            sp-tab-inbox-see-also-heading)))
     (t (car (car cands))))))

(defun sp-tab-inbox--insert-link (origin note)
  "Insert a list item linking to NOTE under ORIGIN's See also heading.
The heading is found or created by `sp-tab-inbox--see-also-marker'.
Nothing is inserted if it already links to NOTE, or if NOTE is ORIGIN."
  (unless (equal (vulpea-note-id note) (vulpea-note-id origin))
    (let ((heading (sp-tab-inbox--see-also-marker origin)))
      (with-current-buffer (marker-buffer heading)
        (org-with-wide-buffer
         (goto-char heading)
         (let ((end (save-excursion (org-end-of-subtree t t) (point))))
           (if (save-excursion
                 (re-search-forward
                  (regexp-quote (concat "[[id:" (vulpea-note-id note) "]"))
                  end t))
               (message "%s already links to %s"
                        (vulpea-note-title origin) (vulpea-note-title note))
             ;; end of the heading's own body, before any sub-heading
             (end-of-line)
             (outline-next-heading)
             (goto-char (min (point) end))
             (unless (bolp) (insert "\n"))
             (insert "- " (vulpea-utils-link-make-string note) "\n"))))
        (save-buffer)))))

(defun sp-tab-inbox--resolve-hit ()
  "Return (FILE LINE TEXT ORIGIN) for the hit to send, asking if needed.
In a file inside `sp-tab-inbox-dir' the line at point is the hit;
anywhere else you pick one of the sidebar's current hits.  ORIGIN is the
note the sidebar is showing."
  (let ((origin (car sp-tab-inbox--current))
        (file (buffer-file-name)))
    (unless origin
      (user-error "Open the vulpea-ui sidebar on a note first"))
    (if (and file (file-in-directory-p file (expand-file-name sp-tab-inbox-dir)))
        (list file
              (line-number-at-pos nil t)
              (string-trim (buffer-substring-no-properties
                            (line-beginning-position) (line-end-position)))
              origin)
      (let* ((hits (cdr sp-tab-inbox--current))
             (alist (mapcar (lambda (h)
                              (cons (format "%s:%d  %s"
                                            (file-name-nondirectory (nth 0 h))
                                            (nth 1 h) (nth 2 h))
                                    h))
                            hits)))
        (unless alist (user-error "No link inbox hits for %s"
                                  (vulpea-note-title origin)))
        (append (cdr (assoc (completing-read "Send hit: " alist nil t) alist))
                (list origin))))))

;;;###autoload
(defun sp-tab-inbox-send-elsewhere (&optional file line text origin)
  "Send a link inbox hit to another note, picked or created on the spot.
The hit is the line LINE of FILE with content TEXT, found from ORIGIN, the
note the sidebar is showing.  Interactively, these are the line at point
in an inbox file, or a hit you choose from the sidebar's current ones.

The note is chosen with `vulpea-select'; a title that doesn't exist yet
creates a new file-level note (see `sp-tab-inbox-new-note-body').  The
line then moves under the chosen note's Resources heading like `collect'
does.  No link back is added here; at the prompt, run the embark action
on `sp-tab-inbox-embark-map' to also link the note from ORIGIN."
  (interactive)
  (sp-tab-inbox--ensure-idle)
  (pcase-let ((`(,file ,line ,text ,origin)
               (if (and file line text origin)
                   (list file line text origin)
                 (sp-tab-inbox--resolve-hit))))
    (setq sp-tab-inbox--pending (list file line text origin))
    (when-let* ((picked (let ((embark-keymap-alist (sp-tab-inbox--embark-alist)))
                         (vulpea-select
                          "Send to note"
                          :require-match nil
                          :filter-fn (lambda (n) (zerop (vulpea-note-level n)))))))
      (setq sp-tab-inbox--pending nil)
      (sp-tab-inbox-collect file line text (sp-tab-inbox--ensure-note picked))
      (cl-incf sp-tab-inbox-generation)
      (vulpea-ui-sidebar-refresh))))

(defun sp-tab-inbox-embark-send-and-link (candidate)
  "Embark action: send the pending hit to CANDIDATE and link it from its origin.
CANDIDATE is an existing note, or a title to create a note for.  Besides
moving the line like `sp-tab-inbox-send-elsewhere', this adds a link to
the note under the See also heading of the note the search started from."
  (interactive "sNote: ")
  (sp-tab-inbox--ensure-idle)
  (pcase-let ((`(,file ,line ,text ,origin)
               (or sp-tab-inbox--pending
                   (user-error "No link inbox hit is waiting to be sent"))))
    (setq sp-tab-inbox--pending nil)
    (let ((note (sp-tab-inbox--ensure-note
                 (sp-tab-inbox--candidate-note candidate))))
      (sp-tab-inbox-collect file line text note)
      (sp-tab-inbox--insert-link origin note)
      (cl-incf sp-tab-inbox-generation)
      (vulpea-ui-sidebar-refresh))))

;;;; Widget

(vui-defcomponent sp-tab-inbox-widget ()
  "Plain-text mentions of the current note in the link inbox."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (let ((hits (vui-use-memo (note sp-tab-inbox-generation)
                    (sp-tab-inbox-search note))))
        (setq sp-tab-inbox--current (cons note hits))
        (vui-component 'vulpea-ui-widget
          :title "Link inbox"
          :count (length hits)
          :children
          (lambda ()
            (if (null hits)
                (vui-text "No mentions")
              (apply #'vui-vstack
                     (vui-button "collect all"
                                 :on-click (lambda ()
                                             (sp-tab-inbox-collect-all hits note)))
                     (mapcar
                      (lambda (hit)
                        (pcase-let ((`(,file ,line ,text) hit))
                          (vui-vstack
                           (vui-hstack
                            (vui-button
                             (format "%s:%d" (file-name-nondirectory file) line)
                             :on-click (lambda () (sp-tab-inbox-visit file line)))
                            (vui-text " ")
                            (vui-button
                             "collect"
                             :on-click (lambda ()
                                         (sp-tab-inbox-collect-one
                                          file line text note)))
                            (vui-text " ")
                            (vui-button
                             "send"
                             :on-click (lambda ()
                                         (sp-tab-inbox-send-elsewhere
                                          file line text note))))
                           (vui-text
                            (propertize (sp-tab-inbox-wrap text)
                                        'face 'vulpea-ui-mention-context-face)))))
                      hits)))))))))

(vulpea-ui-register-widget 'link-inbox
  :component 'sp-tab-inbox-widget
  :order 360) ; right after unlinked-mentions (350)

;;;; Inbox backlinks widget

(defun sp-tab-inbox--scope-ids (note)
  "Return the IDs of NOTE and of every heading inside its scoped subtree."
  (let ((root (sp-tab-inbox--scope-root note))
        (ids (list (vulpea-note-id note))))
    (with-current-buffer (marker-buffer (car root))
      (org-with-wide-buffer
       (goto-char (car root))
       (org-map-entries
        (lambda ()
          (when-let* ((id (org-entry-get nil "ID")))
            (push id ids)))
        nil
        (if (zerop (cdr root)) nil 'tree))))
    (delete-dups ids)))

(defun sp-tab-inbox--backlink-hits (note)
  "Return a sorted list of (FILE LINE) for inbox lines linking into NOTE."
  (when-let* ((rg (executable-find "rg"))
              (ids (sp-tab-inbox--scope-ids note)))
    (with-temp-buffer
      (apply #'call-process rg nil t nil
             "--line-number" "--no-heading" "--with-filename"
             "--ignore-case" "--fixed-strings"
             (append (mapcan (lambda (id) (list "-e" (concat "id:" id "]"))) ids)
                     (list (expand-file-name sp-tab-inbox-dir))))
      (goto-char (point-min))
      (let (result)
        (while (re-search-forward "^\\(.+?\\):\\([0-9]+\\):" nil t)
          (push (list (match-string 1) (string-to-number (match-string 2)))
                result))
        (sort result
              (lambda (a b)
                (if (equal (car a) (car b))
                    (< (cadr a) (cadr b))
                  (string< (car a) (car b)))))))))

(defun sp-tab-inbox--backlink-windows (note)
  "Return (FILE START END HIT-LINES) context windows for NOTE's inbox backlinks.
Hits whose contexts touch or overlap are merged into one window."
  (let ((n sp-tab-inbox-backlink-context-lines)
        windows)
    (dolist (hit (sp-tab-inbox--backlink-hits note))
      (let ((file (car hit))
            (line (cadr hit))
            (w (car windows)))
        (if (and w (equal (nth 0 w) file) (<= (- line n) (1+ (nth 2 w))))
            (setf (nth 2 w) (+ line n)
                  (nth 3 w) (append (nth 3 w) (list line)))
          (push (list file (max 1 (- line n)) (+ line n) (list line)) windows))))
    (nreverse windows)))

(defun sp-tab-inbox--file-lines (file start end)
  "Return the lines START to END (1-based, inclusive) of FILE.
Reads the visiting buffer if FILE is open, so unsaved edits show up."
  (let ((buf (find-buffer-visiting file)))
    (with-temp-buffer
      (if buf
          (insert (with-current-buffer buf
                    (save-restriction
                      (widen)
                      (buffer-substring-no-properties (point-min) (point-max)))))
        (insert-file-contents file))
      (goto-char (point-min))
      (forward-line (1- (max 1 start)))
      (let ((n (max 1 start))
            lines)
        (while (and (<= n end) (not (eobp)))
          (push (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position))
                lines)
          (forward-line 1)
          (cl-incf n))
        (nreverse lines)))))

(defun sp-tab-inbox--prettify (text)
  "Replace Org links in TEXT by their descriptions, or their targets."
  (thread-last text
    (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1")
    (replace-regexp-in-string "\\[\\[\\([^]]*\\)\\]\\]" "\\1")))

(defun sp-tab-inbox--render-window (file start end hit-lines)
  "Return the wrapped context of FILE lines START to END as one string.
Lines in HIT-LINES are shown in bold, the rest in the context face."
  (let ((line start)
        parts)
    (dolist (text (sp-tab-inbox--file-lines file start end))
      (let ((s (string-trim (sp-tab-inbox--prettify text))))
        (unless (string-empty-p s)
          (push (propertize (sp-tab-inbox-wrap s)
                            'face (if (memq line hit-lines)
                                      'bold
                                    'vulpea-ui-mention-context-face))
                parts)))
      (cl-incf line))
    (concat (mapconcat #'identity (nreverse parts) "\n") "\n")))

(vui-defcomponent sp-tab-inbox-backlinks-widget ()
  "Lines of the link inbox files that link to the current note."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (let ((windows (vui-use-memo (note sp-tab-inbox-generation)
                       (sp-tab-inbox--backlink-windows note))))
        (vui-component 'vulpea-ui-widget
          :title "Inbox backlinks"
          :count (apply #'+ (mapcar (lambda (w) (length (nth 3 w))) windows))
          :children
          (lambda ()
            (if (null windows)
                (vui-text "No links")
              (apply #'vui-vstack
                     (mapcar
                      (lambda (w)
                        (pcase-let ((`(,file ,start ,end ,hit-lines) w))
                          (vui-vstack
                           (vui-button
                            (format "%s:%d" (file-name-nondirectory file)
                                    (car hit-lines))
                            :on-click (lambda ()
                                        (sp-tab-inbox-visit file (car hit-lines))))
                           (vui-text
                            (sp-tab-inbox--render-window
                             file start end hit-lines)))))
                      windows)))))))))

(vulpea-ui-register-widget 'link-inbox-backlinks
  :component 'sp-tab-inbox-backlinks-widget
  :order 370) ; right after the link inbox widget (360)

(provide 'sp-tab-inbox)
;;; sp-tab-inbox.el ends here
