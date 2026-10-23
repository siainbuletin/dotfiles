;; -*- lexical-binding: t; -*-
;; sp-org-normalise.el --- Normalise tasks and TODO keywords across the vault

;;; Commentary:

;; Scans the Org files of the notes vault in two ways:
;;
;; - Checkbox items under a "Tasks" heading become child headings with a
;;   TODO keyword, so that they can be tracked.
;; - TODO-like keywords in headings are inventoried, and those in
;;   `sp-org-normalise-keyword-map' are rewritten to the org-gtd set.
;;
;; Everything goes through a plan first (`sp-org-normalise-plan-file'),
;; which is shown in a report buffer.  Nothing is written until each
;; file, or each change, is confirmed.  See
;; docs/tangles/custom/sp-org-normalise.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'sp-paths nil t)

(defvar sp-notes-dir)

;;;; Settings

(defgroup sp-org-normalise nil
  "Normalise tasks and TODO keywords across the vault."
  :group 'org)

(defcustom sp-org-normalise-directory
  (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes")
  "Directory scanned for Org files."
  :type 'directory
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-exclude-regexp
  "/\\(?:\\.[^/]+\\|ltximg\\|attach\\|data\\)/"
  "Files whose path matches this regexp are not scanned.
The default skips hidden directories and the usual attachment ones."
  :type 'regexp
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-keyword-map
  '(("STARTED"     . "PROG")
    ("DOING"       . "PROG")
    ("INPROGRESS"  . "PROG")
    ("IN-PROGRESS" . "PROG")
    ("WIP"         . "PROG")
    ("WAITING"     . "WAIT")
    ("BLOCKED"     . "WAIT")
    ("CANCELLED"   . "CNCL")
    ("CANCELED"    . "CNCL")
    ("CANCEL"      . "CNCL")
    ("DROPPED"     . "CNCL")
    ("FINISHED"    . "DONE")
    ("COMPLETED"   . "DONE"))
  "Keywords to rewrite, as (OLD . NEW).
Only headings that start with one of the OLD words are changed, so a
word that is not here is reported by the inventory but never touched.
NEW should be a keyword of `sp-org-normalise-target-sequence'."
  :type '(alist :key-type string :value-type string)
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-target-sequence
  '(("TODO" "NEXT" "PROG" "WAIT") ("DONE" "CNCL"))
  "The keyword sequence to normalise to, as (ACTIVE DONE).
It matches `org-gtd-keyword-mapping' in `sp-org-taskman-extra'."
  :type '(list (repeat string) (repeat string))
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-declare-todo-line t
  "When non-nil, propose a #+todo: line for files that need one.
That is the case when a change introduces a keyword that Org does not
know in that file and the file declares no sequence of its own.  A
file that declares its own sequence is never edited this way; the plan
only notes the missing keywords."
  :type 'boolean
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-tasks-heading-regexp "\\`Tasks?\\'"
  "Headings whose title matches this are Tasks sections."
  :type 'regexp
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-checkbox-keywords
  '((" " . "TODO") ("X" . "DONE") ("-" . "PROG"))
  "Keyword for each checkbox state: [ ], [X] and [-]."
  :type '(alist :key-type string :value-type string)
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-promote-plain-headings nil
  "When non-nil, also give a TODO to plain child headings of a Tasks heading.
Off by default, since a Tasks heading is often a container of sections
\(one per project) and not a list of tasks."
  :type 'boolean
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-promote-keyword "TODO"
  "Keyword given to a plain child heading of a Tasks heading."
  :type 'string
  :group 'sp-org-normalise)

(defcustom sp-org-normalise-save-after-apply nil
  "When non-nil, save each file after its changes are applied.
Otherwise the buffers are left modified so that the result can be read
\(for example in a diff) and undone before saving."
  :type 'boolean
  :group 'sp-org-normalise)

;;;; Keywords

(defun sp-org-normalise--strip-key (word)
  "WORD without its (fast key and logging) suffix."
  (replace-regexp-in-string "(.*\\'" "" word))

(defun sp-org-normalise-declared-keywords (text)
  "Keywords declared by the #+todo:-style lines of the Org TEXT."
  (let (words (case-fold-search t))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (re-search-forward
              "^#\\+\\(?:seq_todo\\|typ_todo\\|todo\\):[ \t]*\\(.*\\)$" nil t)
        (dolist (w (split-string (match-string 1)))
          (unless (equal w "|")
            (push (sp-org-normalise--strip-key w) words)))))
    (nreverse words)))

(defun sp-org-normalise-global-keywords (&optional spec)
  "Flat list of the keywords in SPEC, default `org-todo-keywords'."
  (let (words)
    (dolist (seq (or spec org-todo-keywords))
      (dolist (w (if (memq (car seq) '(sequence type)) (cdr seq) seq))
        (when (and (stringp w) (not (equal w "|")))
          (push (sp-org-normalise--strip-key w) words))))
    (nreverse words)))

(defun sp-org-normalise--known-keywords (text global)
  "Keywords Org recognises in TEXT: its own declaration, else GLOBAL."
  (or (sp-org-normalise-declared-keywords text) global))

;;;; Lines

(defun sp-org-normalise--parse-heading (line)
  "Split the heading LINE into (LEVEL KEYWORD TITLE), or nil.
KEYWORD is the first word if it looks like one, else nil."
  (when (let ((case-fold-search nil))
          (string-match "\\`\\(\\*+\\)\\(?: +\\(.*\\)\\)?\\'" line))
    (let ((level (length (match-string 1 line)))
          (case-fold-search nil)
          (rest (or (match-string 2 line) "")))
      (if (string-match
           "\\`\\([A-Z][A-Z0-9_-]+\\)\\(?: +\\(.*\\)\\)?\\'" rest)
          (list level (match-string 1 rest) (or (match-string 2 rest) ""))
        (list level nil rest)))))

(defun sp-org-normalise--literal-lines (lines)
  "Vector with t for each of LINES inside a block or a drawer."
  (let ((v (make-vector (length lines) nil))
        (case-fold-search t)
        (i 0) end-re)
    (dolist (l lines)
      (cond
       (end-re
        (aset v i t)
        (when (string-match-p end-re l) (setq end-re nil)))
       ((string-match-p "\\`[ \t]*#\\+begin_" l)
        (aset v i t)
        (setq end-re "\\`[ \t]*#\\+end_"))
       ((string-match-p "\\`[ \t]*:\\(?:PROPERTIES\\|LOGBOOK\\):[ \t]*\\'" l)
        (aset v i t)
        (setq end-re "\\`[ \t]*:END:[ \t]*\\'")))
      (setq i (1+ i)))
    v))

(defun sp-org-normalise--indent (line)
  "Number of leading blanks of LINE."
  (if (string-match "\\`[ \t]*" line) (match-end 0) 0))

(defun sp-org-normalise--blank-p (line)
  (string-match-p "\\`[ \t]*\\'" line))

;;;; Planning

(defconst sp-org-normalise--checkbox-re
  "\\`\\([ \t]*\\)\\(?:[-+]\\|[0-9]+[.)]\\) +\\[\\([ xX-]\\)\\]\\(?: +\\(.*\\)\\)?\\'"
  "A list item with a checkbox: indent, state and text.")

(defun sp-org-normalise--item-end (lines lit i indent)
  "Index of the last line of the list item that starts at I.
INDENT is its indent: the item runs over the lines indented deeper."
  (let ((n (length lines)) (k i) (j (1+ i)) done)
    (while (and (< j n) (not done))
      (let ((l (aref lines j)))
        (cond ((sp-org-normalise--blank-p l) (setq j (1+ j)))
              ((and (> (sp-org-normalise--indent l) indent)
                    (or (aref lit j) (not (sp-org-normalise--parse-heading l))))
               (setq k j j (1+ j)))
              (t (setq done t)))))
    k))

(defun sp-org-normalise--dedent (line n)
  "LINE without up to N leading blanks."
  (substring line (min n (sp-org-normalise--indent line))))

(defun sp-org-normalise--checkbox-change (lines lit i level)
  "The change that turns the checkbox item at I into a heading below LEVEL.
Nil if the item has no text.  The second value is the next line to read."
  (let ((line (aref lines i)))
    (when (string-match sp-org-normalise--checkbox-re line)
      (let* ((indent (length (match-string 1 line)))
             (state (upcase (match-string 2 line)))
             (title (string-trim (or (match-string 3 line) "")))
             (width (- (or (match-beginning 3) (length line)) 0))
             (kw (cdr (assoc state sp-org-normalise-checkbox-keywords)))
             (end (sp-org-normalise--item-end lines lit i indent)))
        (when (and kw (not (string-empty-p title)))
          (list :kind 'checkbox :start i :end end :keyword kw
                :old (cl-loop for j from i to end collect (aref lines j))
                :new (cons (format "%s %s %s" (make-string (1+ level) ?*)
                                   kw title)
                           (cl-loop for j from (1+ i) to end
                                    collect (sp-org-normalise--dedent
                                             (aref lines j) width)))))))))

(defun sp-org-normalise--header-end (lines)
  "Index where a new #+ keyword line goes: after the leading #+ lines."
  (let ((n (length lines)) (i 0))
    (when (and (< i n) (string-match-p "\\`:PROPERTIES:[ \t]*\\'" (aref lines i)))
      (while (and (< i n) (not (string-match-p "\\`:END:" (aref lines i))))
        (setq i (1+ i)))
      (setq i (min n (1+ i))))
    (while (and (< i n) (string-match-p "\\`#\\+" (aref lines i)))
      (setq i (1+ i)))
    i))

(defun sp-org-normalise--todo-line ()
  "The #+todo: line for `sp-org-normalise-target-sequence'."
  (format "#+todo: %s | %s"
          (string-join (car sp-org-normalise-target-sequence) " ")
          (string-join (cadr sp-org-normalise-target-sequence) " ")))

(defun sp-org-normalise-plan-text (text &optional global)
  "The list of changes that normalise the Org TEXT.
GLOBAL is the list of globally declared keywords (default: those of
`org-todo-keywords')."
  (let* ((global (or global (sp-org-normalise-global-keywords)))
         (lines (vconcat (split-string text "\n")))
         (lit (sp-org-normalise--literal-lines (append lines nil)))
         (file-kws (sp-org-normalise-declared-keywords text))
         (known (or file-kws global))
         (n (length lines))
         (i 0) changes used tasks-level cur-level cur-kw)
    (while (< i n)
      (let* ((line (aref lines i))
             (head (and (not (aref lit i)) (sp-org-normalise--parse-heading line)))
             (item (and (not head) (not (aref lit i)) tasks-level (not cur-kw)
                        (string-match-p sp-org-normalise--checkbox-re line))))
        (cond
         (head
          (pcase-let ((`(,level ,kw ,title) head))
            (setq cur-level level cur-kw (and kw t))
            (when (and tasks-level (<= level tasks-level)) (setq tasks-level nil))
            (let ((new (cdr (assoc kw sp-org-normalise-keyword-map))))
              (cond
               ((and kw new (not (equal kw new)))
                (push (list :kind 'keyword :start i :end i :keyword new
                            :old (list line)
                            :new (list (format "%s %s%s" (make-string level ?*) new
                                               (if (string-empty-p title) ""
                                                 (concat " " title)))))
                      changes)
                (push new used))
               ((string-match-p sp-org-normalise-tasks-heading-regexp title)
                (setq tasks-level level))
               ((and tasks-level sp-org-normalise-promote-plain-headings
                     (= level (1+ tasks-level)) (not (string-empty-p title)))
                (push (list :kind 'promote :start i :end i
                            :keyword sp-org-normalise-promote-keyword
                            :old (list line)
                            :new (list (format "%s %s %s" (make-string level ?*)
                                               sp-org-normalise-promote-keyword
                                               title)))
                      changes)
                (push sp-org-normalise-promote-keyword used)))))
          (setq i (1+ i)))
         (item
          (let ((c (sp-org-normalise--checkbox-change lines lit i cur-level)))
            (if c
                (progn (push c changes)
                       (push (plist-get c :keyword) used)
                       (setq i (1+ (plist-get c :end))))
              (setq i (1+ i)))))
         (t (setq i (1+ i))))))
    (let ((missing (cl-set-difference (cl-remove-duplicates used :test #'equal)
                                      known :test #'equal)))
      (when missing
        (setq missing (sort missing #'string<))
        (if file-kws
            (push (list :kind 'note
                        :message (format "declares its own sequence (%s) without %s"
                                         (string-join file-kws " ")
                                         (string-join missing " ")))
                  changes)
          (when sp-org-normalise-declare-todo-line
            (let ((p (sp-org-normalise--header-end lines)))
              (push (list :kind 'declare :start p :end (1- p) :old nil
                          :keyword (string-join missing " ")
                          :new (list (sp-org-normalise--todo-line)))
                    changes))))))
    (sort (nreverse changes)
          (lambda (a b) (< (or (plist-get a :start) -1) (or (plist-get b :start) -1))))))

;;;; Applying

(defun sp-org-normalise--sorted-edits (changes)
  "The CHANGES that edit text, last first."
  (sort (cl-remove-if-not (lambda (c) (plist-get c :new)) (copy-sequence changes))
        (lambda (a b)
          (or (> (plist-get a :start) (plist-get b :start))
              (and (= (plist-get a :start) (plist-get b :start))
                   (> (plist-get a :end) (plist-get b :end)))))))

(defun sp-org-normalise-apply-to-text (text changes)
  "TEXT with CHANGES applied."
  (let ((lines (split-string text "\n")))
    (dolist (c (sp-org-normalise--sorted-edits changes))
      (setq lines (append (cl-subseq lines 0 (plist-get c :start))
                          (plist-get c :new)
                          (nthcdr (1+ (plist-get c :end)) lines))))
    (string-join lines "\n")))

(defun sp-org-normalise-apply-to-buffer (changes)
  "Apply CHANGES to the current buffer, last first."
  (save-excursion
    (dolist (c (sp-org-normalise--sorted-edits changes))
      (goto-char (point-min))
      (forward-line (plist-get c :start))
      (let ((beg (point)))
        (forward-line (- (1+ (plist-get c :end)) (plist-get c :start)))
        (delete-region beg (point))
        (insert (string-join (plist-get c :new) "\n") "\n")))))

;;;; Files

(defun sp-org-normalise-files (&optional dir)
  "Org files below DIR (default `sp-org-normalise-directory'), sorted."
  (sort (cl-remove-if
         (lambda (f) (string-match-p sp-org-normalise-exclude-regexp f))
         (directory-files-recursively
          (expand-file-name (or dir sp-org-normalise-directory)) "\\.org\\'"))
        #'string<))

(defun sp-org-normalise--file-text (file)
  "Text of FILE: from its buffer if it is visited, else from disk."
  (if-let ((buf (find-buffer-visiting file)))
      (with-current-buffer buf (buffer-substring-no-properties (point-min) (point-max)))
    (with-temp-buffer (insert-file-contents file) (buffer-string))))

(defun sp-org-normalise-plan-files (files)
  "Plan for FILES: a list of (FILE TEXT . CHANGES), files with changes only."
  (let ((global (sp-org-normalise-global-keywords)) plans)
    (dolist (f files)
      (let* ((text (sp-org-normalise--file-text f))
             (changes (sp-org-normalise-plan-text text global)))
        (when changes (push (cons f (cons text changes)) plans))))
    (nreverse plans)))

;;;; Inventory

(defun sp-org-normalise-inventory-data (files)
  "Rows (KEYWORD HEADINGS FILES UNRECOGNISED MAPPED-TO) for FILES, commonest first.
UNRECOGNISED counts the files where Org would not treat KEYWORD as one.
The second value lists (FILE . KEYWORDS) for files that declare a sequence."
  (let ((global (sp-org-normalise-global-keywords))
        (table (make-hash-table :test #'equal)) declared rows)
    (dolist (f files)
      (let* ((text (sp-org-normalise--file-text f))
             (lines (split-string text "\n"))
             (lit (sp-org-normalise--literal-lines lines))
             (file-kws (sp-org-normalise-declared-keywords text))
             (known (or file-kws global))
             (seen (make-hash-table :test #'equal))
             (i 0))
        (when file-kws (push (cons f file-kws) declared))
        (dolist (l lines)
          (let ((head (and (not (aref lit i)) (sp-org-normalise--parse-heading l))))
            (when (and head (nth 1 head))
              (let* ((kw (nth 1 head))
                     (row (or (gethash kw table) (list 0 0 0))))
                (cl-incf (nth 0 row))
                (unless (gethash kw seen)
                  (puthash kw t seen)
                  (cl-incf (nth 1 row))
                  (unless (member kw known) (cl-incf (nth 2 row))))
                (puthash kw row table))))
          (setq i (1+ i)))))
    (maphash (lambda (kw r)
               (push (list kw (nth 0 r) (nth 1 r) (nth 2 r)
                           (cdr (assoc kw sp-org-normalise-keyword-map)))
                     rows))
             table)
    (cl-values (sort rows (lambda (a b) (or (> (nth 1 a) (nth 1 b))
                                         (and (= (nth 1 a) (nth 1 b))
                                              (string< (car a) (car b))))))
            (nreverse declared))))

(defun sp-org-normalise--inventory-text (rows declared)
  "Text of the inventory report for ROWS and DECLARED."
  (concat
   (format "%-14s %9s %6s %13s  %s\n" "KEYWORD" "HEADINGS" "FILES" "UNRECOGNISED" "MAPS TO")
   (mapconcat (lambda (r)
                (format "%-14s %9d %6d %13d  %s" (nth 0 r) (nth 1 r) (nth 2 r)
                        (nth 3 r) (or (nth 4 r) "-")))
              rows "\n")
   "\n\nUNRECOGNISED is the number of files in which Org does not know the word:"
   "\nit is not in that file's #+todo: lines (or, with none, in `org-todo-keywords')."
   "\nWords like README or FAQ show up here too; only words in"
   "\n`sp-org-normalise-keyword-map' are ever rewritten.\n"
   (if declared
       (concat "\nFiles with their own keyword sequence:\n"
               (mapconcat (lambda (d) (format "  %s: %s" (car d) (string-join (cdr d) " ")))
                          declared "\n")
               "\n")
     "")))

;;;; Report

(defun sp-org-normalise-describe-change (c)
  "One-line description of the change C."
  (pcase (plist-get c :kind)
    ('note (format "note: %s" (plist-get c :message)))
    ('declare (format "insert at line %d: %s (adds %s)" (1+ (plist-get c :start))
                      (car (plist-get c :new)) (plist-get c :keyword)))
    (_ (format "line %d: %s  =>  %s" (1+ (plist-get c :start))
               (string-trim (car (plist-get c :old)))
               (string-trim (car (plist-get c :new)))))))

(defvar sp-org-normalise-report-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'sp-org-normalise-visit)
    map))

(define-derived-mode sp-org-normalise-report-mode special-mode "Org-normalise"
  "Report of the changes proposed by `sp-org-normalise-preview'.")

(defun sp-org-normalise-visit ()
  "Visit the file and line of the change at point."
  (interactive)
  (if-let ((loc (get-text-property (point) 'sp-org-normalise-loc)))
      (progn (find-file-other-window (car loc))
             (goto-char (point-min))
             (forward-line (cdr loc)))
    (user-error "No change here")))

(defun sp-org-normalise--show-plan (plans)
  "Show PLANS in the report buffer."
  (with-current-buffer (get-buffer-create "*Org normalise*")
    (let ((inhibit-read-only t))
      (sp-org-normalise-report-mode)
      (erase-buffer)
      (if (null plans)
          (insert "Nothing to change.\n")
        (insert (format "%d file(s), %d change(s).  Nothing has been written.\n\n"
                        (length plans)
                        (cl-loop for p in plans
                                 sum (length (cl-remove-if-not
                                              (lambda (c) (plist-get c :new))
                                              (cddr p))))))
        (dolist (p plans)
          (insert (abbreviate-file-name (car p)) "\n")
          (dolist (c (cddr p))
            (let ((start (point)))
              (insert "  " (sp-org-normalise-describe-change c) "\n")
              (when (plist-get c :start)
                (put-text-property start (point) 'sp-org-normalise-loc
                                   (cons (car p) (plist-get c :start))))))
          (insert "\n")))
      (goto-char (point-min)))
    (pop-to-buffer (current-buffer))))

;;;; Commands

(defun sp-org-normalise--dir-arg ()
  (if current-prefix-arg
      (read-directory-name "Scan directory: " sp-org-normalise-directory)
    sp-org-normalise-directory))

;;;###autoload
(defun sp-org-normalise-inventory (&optional dir)
  "List every keyword-like heading word under DIR, with counts."
  (interactive (list (sp-org-normalise--dir-arg)))
  (cl-multiple-value-bind (rows declared)
      (sp-org-normalise-inventory-data (sp-org-normalise-files dir))
    (with-current-buffer (get-buffer-create "*Org keywords*")
      (let ((inhibit-read-only t))
        (special-mode)
        (erase-buffer)
        (insert (sp-org-normalise--inventory-text rows declared))
        (goto-char (point-min)))
      (pop-to-buffer (current-buffer)))))

;;;###autoload
(defun sp-org-normalise-preview (&optional dir)
  "Show the changes proposed for the Org files under DIR.  Writes nothing."
  (interactive (list (sp-org-normalise--dir-arg)))
  (sp-org-normalise--show-plan (sp-org-normalise-plan-files (sp-org-normalise-files dir))))

(defun sp-org-normalise--apply-plan (plan changes)
  "Apply CHANGES to the file of PLAN (FILE TEXT . CHANGES).  Return non-nil if done."
  (let ((buf (find-file-noselect (car plan))))
    (with-current-buffer buf
      (cond
       ((not (equal (buffer-substring-no-properties (point-min) (point-max))
                    (cadr plan)))
        (message "Skipped %s: it changed since the plan was made" (car plan))
        nil)
       (t (sp-org-normalise-apply-to-buffer changes)
          (when sp-org-normalise-save-after-apply (save-buffer))
          t)))))

;;;###autoload
(defun sp-org-normalise-run (&optional dir)
  "Preview the changes under DIR, then apply them file by file after asking."
  (interactive (list (sp-org-normalise--dir-arg)))
  (let ((plans (sp-org-normalise-plan-files (sp-org-normalise-files dir)))
        (done 0) (quit nil))
    (sp-org-normalise--show-plan plans)
    (dolist (p plans)
      (unless quit
        (let* ((edits (cl-remove-if-not (lambda (c) (plist-get c :new)) (cddr p)))
               (choice (and edits
                            (read-char-choice
                             (format "%s: %d change(s).  [y]es, [n]o, [c]hoose each, [q]uit? "
                                     (abbreviate-file-name (car p)) (length edits))
                             '(?y ?n ?c ?q)))))
          (pcase choice
            (?q (setq quit t))
            (?y (when (sp-org-normalise--apply-plan p edits) (cl-incf done)))
            (?c (let ((picked (cl-remove-if-not
                               (lambda (c)
                                 (y-or-n-p (format "%s  " (sp-org-normalise-describe-change c))))
                               edits)))
                  (when (and picked (sp-org-normalise--apply-plan p picked))
                    (cl-incf done))))))))
    (message "Changed %d file(s)%s" done
             (if sp-org-normalise-save-after-apply
                 "."
               "; the buffers are modified but not saved (C-x s to save, or revert them)."))))

(provide 'sp-org-normalise)
;;; sp-org-normalise.el ends here
