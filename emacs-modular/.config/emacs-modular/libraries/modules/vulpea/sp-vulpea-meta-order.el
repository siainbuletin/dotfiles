;;; sp-vulpea-meta-order.el --- Order the meta lines of Vulpea notes by key -*- lexical-binding: t; -*-

;;; Commentary:

;; Sorts the first `- key :: value' list of a note by key.  Items keep their
;; continuation lines, repeated keys keep their order, and sorting twice changes
;; nothing.  `sp-vulpea-meta-order-buffer' does one buffer, `-keys' and
;; `-sorted-p' work on a list of keys, `sp-vulpea-meta-order-dryrun' and
;; `-convert' go through many notes.  See the doc
;; docs/tangles/vulpea/sp-vulpea-meta-order.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'sp-batch-report)

(declare-function vulpea-db-query "vulpea-db")
(declare-function vulpea-db-update-file "vulpea-db")
(declare-function vulpea-note-path "vulpea-note")
(declare-function vulpea-note-level "vulpea-note")
(declare-function vulpea-note-tags "vulpea-note")

(defgroup sp-vulpea-meta-order nil
  "Order the meta lines of Vulpea notes by key."
  :group 'org
  :prefix "sp-vulpea-meta-order-")

(defcustom sp-vulpea-meta-order-pinned nil
  "Meta keys that stay first, in this order; the other keys follow alphabetically."
  :type '(repeat string)
  :group 'sp-vulpea-meta-order)

(defcustom sp-vulpea-meta-order-tags nil
  "Only the notes with one of these tags go through the batch commands; nil for all."
  :type '(repeat string)
  :group 'sp-vulpea-meta-order)

(defcustom sp-vulpea-meta-order-directory nil
  "Only the notes below this folder go through the batch commands; nil for all."
  :type '(choice (const :tag "Any folder" nil) directory)
  :group 'sp-vulpea-meta-order)

(defcustom sp-vulpea-meta-order-backup-directory
  (expand-file-name "meta-order-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Folder where `sp-vulpea-meta-order-convert' copies each note before changing it.
Every run makes a sub-folder named with the time."
  :type 'directory
  :group 'sp-vulpea-meta-order)

(defun sp-vulpea-meta-order--rank (key)
  "The rank of KEY: its place in `sp-vulpea-meta-order-pinned', else after all of them."
  (or (cl-position (downcase key) sp-vulpea-meta-order-pinned
                   :test (lambda (a b) (string= a (downcase b))))
      (length sp-vulpea-meta-order-pinned)))

(defun sp-vulpea-meta-order--less-p (a b)
  "Non-nil when the key A goes before the key B."
  (let ((ra (sp-vulpea-meta-order--rank a))
        (rb (sp-vulpea-meta-order--rank b)))
    (or (< ra rb)
        (and (= ra rb) (string< (downcase a) (downcase b))))))

(defun sp-vulpea-meta-order-keys (keys)
  "Return the list of meta KEYS in order; repeated keys keep their order."
  (cl-stable-sort (copy-sequence keys) #'sp-vulpea-meta-order--less-p))

(defun sp-vulpea-meta-order-sorted-p (keys)
  "Non-nil when the list of meta KEYS is in order."
  (equal keys (sp-vulpea-meta-order-keys keys)))

(defconst sp-vulpea-meta-order--item-re
  "^-[ \t]+\\([^ \t\n:]+\\)[ \t]+::\\(?:[ \t]\\|$\\)"
  "Matches the first line of a meta item; group 1 is the key.")

(defun sp-vulpea-meta-order--bounds ()
  "The start and end of the first meta list of the buffer, as (BEG . END), or nil."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t)
            (limit (save-excursion
                     (let ((case-fold-search nil))
                       (if (re-search-forward "^\\*+[ \t]" nil t)
                           (match-beginning 0)
                         (point-max)))))
            beg last done)
        (while (and (not done) (< (point) limit))
          (cond
           ((looking-at sp-vulpea-meta-order--item-re)
            (unless beg (setq beg (point)))
            (setq last (line-end-position)))
           ((and (not beg) (looking-at "[ \t]*:PROPERTIES:[ \t]*$"))
            (re-search-forward "^[ \t]*:END:" limit 'move))
           ((and (not beg) (looking-at "[ \t]*#\\+begin_\\(\\w+\\)"))
            (re-search-forward (concat "^[ \t]*#\\+end_" (match-string 1)) limit 'move))
           ((and beg (looking-at "[ \t]+[^ \t\n]"))
            (setq last (line-end-position)))
           (beg (setq done t)))
          (unless done (forward-line 1)))
        (and beg (cons beg last))))))

(defun sp-vulpea-meta-order--items (text)
  "Split TEXT, the lines of a meta list, into a list of (KEY . ITEM-TEXT).
Lines that are not an item start belong to the item before them."
  (let (items)
    (dolist (line (split-string text "\n"))
      (if (string-match sp-vulpea-meta-order--item-re line)
          (push (cons (match-string 1 line) line) items)
        (setcdr (car items) (concat (cdar items) "\n" line))))
    (nreverse items)))

(defun sp-vulpea-meta-order-block-keys ()
  "The keys of the meta list of the current buffer, in file order."
  (when-let* ((bounds (sp-vulpea-meta-order--bounds)))
    (mapcar #'car (sp-vulpea-meta-order--items
                   (buffer-substring-no-properties (car bounds) (cdr bounds))))))

;;;###autoload
(defun sp-vulpea-meta-order-buffer ()
  "Order the first meta list of the current buffer by key.
Return non-nil when the buffer changed.  Items keep their continuation lines,
repeated keys keep their order, text outside the list is left alone."
  (when-let* ((bounds (sp-vulpea-meta-order--bounds)))
    (let* ((old (buffer-substring-no-properties (car bounds) (cdr bounds)))
           (sorted (cl-stable-sort (sp-vulpea-meta-order--items old)
                                   #'sp-vulpea-meta-order--less-p :key #'car))
           (new (mapconcat #'cdr sorted "\n")))
      (unless (equal old new)
        (save-excursion
          (save-restriction
            (widen)
            (delete-region (car bounds) (cdr bounds))
            (goto-char (car bounds))
            (insert new)))
        t))))

(defun sp-vulpea-meta-order-string (text)
  "Return the Org TEXT with its meta list ordered."
  (with-temp-buffer
    (insert text)
    (sp-vulpea-meta-order-buffer)
    (buffer-string)))

;;;###autoload
(defun sp-vulpea-meta-order-note ()
  "Order the meta lines of the note in the current buffer."
  (interactive)
  (when buffer-read-only (user-error "This buffer is read-only"))
  (message (if (sp-vulpea-meta-order-buffer)
               "Meta lines ordered"
             "Meta lines already in order")))

(defconst sp-vulpea-meta-order--buffer "*vulpea meta order*")

(defvar sp-vulpea-meta-order--excluded nil
  "The notes (files) dropped from the report with `d'.")

(defun sp-vulpea-meta-order--default-filter ()
  "The filter made of the options."
  (list :tags sp-vulpea-meta-order-tags :directory sp-vulpea-meta-order-directory))

(defun sp-vulpea-meta-order--read-filter ()
  "The filter: the options, or what the user types when there is a prefix argument."
  (if (not current-prefix-arg)
      (sp-vulpea-meta-order--default-filter)
    (list :tags (split-string (read-string "Only notes with one of these tags (space separated, empty for any): ")
                              "[ ,:]+" t)
          :directory (and (y-or-n-p "Only notes below one folder? ")
                          (read-directory-name "Folder: ")))))

(defun sp-vulpea-meta-order--files (filter)
  "The files of the file-level notes that FILTER lets through, sorted."
  (let ((tags (plist-get filter :tags))
        (dir (and (plist-get filter :directory)
                  (expand-file-name (plist-get filter :directory))))
        files)
    (dolist (note (vulpea-db-query))
      (when-let* ((path (vulpea-note-path note)))
        (when (and (eql 0 (vulpea-note-level note))
                   (file-exists-p path)
                   (or (null tags) (seq-intersection tags (vulpea-note-tags note)))
                   (or (null dir) (file-in-directory-p path dir)))
          (push path files))))
    (sort (delete-dups files) #'string<)))

(defun sp-vulpea-meta-order--plan (file)
  "What ordering the note FILE does, as a plist; nothing is written."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((before (sp-vulpea-meta-order-block-keys)))
      (list :file file :before before
            :changed (and (sp-vulpea-meta-order-buffer) t)
            :after (sp-vulpea-meta-order-block-keys)))))

(defun sp-vulpea-meta-order--plans (filter)
  "The plans of all the notes FILTER lets through."
  (let* ((files (sp-vulpea-meta-order--files filter))
         (progress (make-progress-reporter "Planning meta order..." 0 (length files)))
         (n 0) plans)
    (dolist (file files)
      (push (sp-vulpea-meta-order--plan file) plans)
      (progress-reporter-update progress (cl-incf n)))
    (progress-reporter-done progress)
    (nreverse plans)))

(defun sp-vulpea-meta-order--file (plan)
  "The file of PLAN."
  (plist-get plan :file))

(defun sp-vulpea-meta-order--todo (plans excluded)
  "The plans of PLANS that change a note and are not in EXCLUDED."
  (sp-batch-report-without-excluded
   (seq-filter (lambda (p) (plist-get p :changed)) plans)
   #'sp-vulpea-meta-order--file excluded))

(defun sp-vulpea-meta-order--report-text (plans filter excluded)
  "The Org text of the report of PLANS for FILTER, with the notes EXCLUDED dropped."
  (let ((todo (seq-filter (lambda (p) (plist-get p :changed)) plans)))
    (sp-batch-report-text
     "Vulpea meta order: dry run"
     (list (sp-batch-report-section
            "To reorder"
            (mapcar (lambda (p)
                      (sp-batch-report-item
                       nil :file (plist-get p :file)
                       :children (list (concat "now: " (string-join (plist-get p :before) ", "))
                                       (concat "new: " (string-join (plist-get p :after) ", ")))))
                    todo)
            "nothing to reorder"))
     :intro (format "%d notes checked%s; %d already in order.\nA reorders the notes that are left, d drops one, g checks again."
                    (length plans)
                    (concat (and (plist-get filter :tags)
                                 (format ", tagged %s" (string-join (plist-get filter :tags) " or ")))
                            (and (plist-get filter :directory)
                                 (format ", below %s" (plist-get filter :directory))))
                    (- (length plans) (length todo)))
     :excluded excluded)))

(defun sp-vulpea-meta-order--show (plans filter excluded)
  "Show the report of PLANS for FILTER in its own buffer, without the notes EXCLUDED."
  (sp-batch-report-open
   sp-vulpea-meta-order--buffer
   (sp-batch-report-key-entries
    (sp-vulpea-meta-order--report-text plans filter excluded))
   :refresh (lambda (excl) (sp-vulpea-meta-order-dryrun filter excl))
   :redraw (lambda (excl)
             (setq sp-vulpea-meta-order--excluded excl)
             (sp-vulpea-meta-order--show plans filter excl))
   :apply (lambda (excl) (sp-vulpea-meta-order-convert filter excl))
   :excluded excluded))

;;;###autoload
(defun sp-vulpea-meta-order-dryrun (&optional filter excluded)
  "Show which Vulpea notes `sp-vulpea-meta-order-convert' would change; write nothing.
FILTER is a plist with :tags and :directory, by default the options
`sp-vulpea-meta-order-tags' and `-directory'; with a prefix argument you are
asked.  EXCLUDED lists notes (files) to leave out; the report's \\`d' sets it.
Return the plans of the notes that would change."
  (interactive (list (sp-vulpea-meta-order--read-filter)))
  (let* ((filter (or filter (sp-vulpea-meta-order--default-filter)))
         (plans (sp-vulpea-meta-order--plans filter)))
    (setq sp-vulpea-meta-order--excluded excluded)
    (sp-vulpea-meta-order--show plans filter excluded)
    (sp-vulpea-meta-order--todo plans excluded)))

(defun sp-vulpea-meta-order--backup (file stamp)
  "Copy FILE to the STAMP sub-folder of `sp-vulpea-meta-order-backup-directory'."
  (let ((dir (expand-file-name (concat stamp "/") sp-vulpea-meta-order-backup-directory)))
    (make-directory dir t)
    (copy-file file (expand-file-name (file-name-nondirectory file) dir) nil t)))

(defun sp-vulpea-meta-order--apply (file stamp)
  "Back up and order the note FILE; return non-nil when it changed."
  (let ((buf (find-buffer-visiting file)))
    (when (and buf (buffer-modified-p buf))
      (error "%s has unsaved changes" (file-name-nondirectory file)))
    (sp-vulpea-meta-order--backup file stamp)
    (let ((changed
           (if buf
               (with-current-buffer buf
                 (when (sp-vulpea-meta-order-buffer) (save-buffer) t))
             (with-temp-buffer
               (insert-file-contents file)
               (when (sp-vulpea-meta-order-buffer)
                 (write-region nil nil file nil 'silent)
                 t)))))
      (when (and changed (fboundp 'vulpea-db-update-file))
        (ignore-errors (vulpea-db-update-file file)))
      changed)))

;;;###autoload
(defun sp-vulpea-meta-order-convert (&optional filter excluded)
  "Order the meta lines of the Vulpea notes that FILTER lets through.
Run `sp-vulpea-meta-order-dryrun' first.  This makes the same plan, asks once
before writing, copies each note to a time-stamped folder in
`sp-vulpea-meta-order-backup-directory' and sorts it.  FILTER and EXCLUDED
are as in the dry run; the report's \\`A' passes the notes dropped with \\`d'.
After the run the report is shown again.  Return an alist of file to t (it
changed), nil (it did not) or the error text.  The notes go in batches of
`sp-batch-report-batch-size'; before each you apply, choose, skip or quit."
  (interactive (list (sp-vulpea-meta-order--read-filter)))
  (let* ((filter (or filter (sp-vulpea-meta-order--default-filter)))
         (plans (sp-vulpea-meta-order--plans filter))
         (todo (sp-vulpea-meta-order--todo plans excluded)))
    (setq sp-vulpea-meta-order--excluded excluded)
    (sp-vulpea-meta-order--show plans filter excluded)
    (if (null todo)
        (progn (message "Nothing to reorder.") nil)
      (when (yes-or-no-p (format "Reorder the meta lines of %d notes, %d at a time (backups in %s)? "
                                 (length todo) (or sp-batch-report-batch-size (length todo))
                                 sp-vulpea-meta-order-backup-directory))
        (let* ((stamp (format-time-string "%Y%m%d-%H%M%S"))
               results
               (run (sp-batch-report-run-batches
                     todo
                     (lambda (plan _decision)
                       (push (cons (plist-get plan :file)
                                   (condition-case err
                                       (sp-vulpea-meta-order--apply (plist-get plan :file) stamp)
                                     (error (error-message-string err))))
                             results))
                     :label "Meta order"
                     :describe (lambda (plan)
                                 (format "Order the meta lines of %s?"
                                         (file-name-nondirectory (plist-get plan :file)))))))
          (setq results (nreverse results))
          (message "Ordered %d of %d notes; %d failed%s"
                   (seq-count (lambda (r) (eq (cdr r) t)) results) (length todo)
                   (seq-count (lambda (r) (stringp (cdr r))) results)
                   (sp-batch-report-batches-note run))
          (sp-vulpea-meta-order--show (sp-vulpea-meta-order--plans filter) filter excluded)
          results)))))

(provide 'sp-vulpea-meta-order)
;;; sp-vulpea-meta-order.el ends here
