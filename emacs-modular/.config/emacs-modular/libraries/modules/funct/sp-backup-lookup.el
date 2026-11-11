;;; sp-backup-lookup.el --- Open or diff the backups of the file you are visiting -*- lexical-binding: t; -*-

;;; Commentary:

;; The batch conversions and lints copy each file to a backup folder before they
;; write it.  `sp-backup-lookup-list' finds the backups of one file in all those
;; folders; `sp-backup-open' and `sp-backup-diff' use it from the file's buffer,
;; or from a batch report (keys `b' and `D').
;; See docs/tangles/funct/sp-backup-lookup.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defgroup sp-backup-lookup nil
  "Find the backups the batch commands made of a file."
  :group 'files)

(defcustom sp-backup-lookup-directories
  '(("BibTeX lint" . sp-bibtex-lint-backup-directory)
    ("Litnote titles" . sp-litnotes-titles-backup-directory)
    ("Litnote meta" . sp-litnotes-meta-backup-directory)
    ("Meta order" . sp-vulpea-meta-order-backup-directory)
    ("Litnote references" . sp-litnotes-refs-backup-directory)
    ("Footnote lint" . sp-org-lint-fn-backup-directory)
    ("Author notes" . sp-author-notes-backup-directory)
    ("Notes filing" . sp-notes-filing-backup-dir))
  "The backup folders to search, as (LABEL . VARIABLE) or (LABEL . DIRECTORY).
VARIABLE is a symbol whose value is the folder; one that is unbound or nil
is skipped, so a module that is not loaded costs nothing."
  :type '(alist :key-type string :value-type (choice symbol directory))
  :group 'sp-backup-lookup)

(defconst sp-backup-lookup--stamp-regexp
  "\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)[-T]?\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)"
  "A time stamp as the batch commands write it: 20261109T225317 or 20261109-225317.")

(defun sp-backup-lookup--stamp-time (stamp)
  "The time of STAMP, or nil when it is not a time stamp."
  (when (and stamp (string-match (concat "\\`" sp-backup-lookup--stamp-regexp "\\'") stamp))
    (let ((n (lambda (i) (string-to-number (match-string i stamp)))))
      (encode-time (list (funcall n 6) (funcall n 5) (funcall n 4)
                         (funcall n 3) (funcall n 2) (funcall n 1)
                         nil -1 nil)))))

(defun sp-backup-lookup--directory (spec)
  "The backup folder named by SPEC, a variable or a folder, or nil."
  (let ((value (cond ((and (symbolp spec) (boundp spec)) (symbol-value spec))
                     ((stringp spec) spec))))
    (and (stringp value) (file-directory-p value)
         (file-name-as-directory (expand-file-name value)))))

(defun sp-backup-lookup--tail-p (parts file)
  "Non-nil when the path PARTS (a list of names) ends the path of FILE.
A leading \"files\" part, the notes filing layout, is not counted."
  (let* ((parts (if (equal (car parts) "files") (cdr parts) parts))
         (mine (split-string (file-truename file) "/" t)))
    (and (<= (length parts) (length mine))
         (equal parts (last mine (length parts))))))

(defun sp-backup-lookup--entry (label root path file)
  "The backup entry for PATH below ROOT when it is a backup of FILE, else nil.
The entry is a plist: :path :label :stamp :time."
  (let* ((rel (file-relative-name path root))
         (parts (split-string rel "/" t))
         (name (file-name-nondirectory file))
         (base (car (last parts)))
         (suffix (and (string-prefix-p (concat name ".") base)
                      (substring base (1+ (length name)))))
         (matches (or (equal base name)
                      (and suffix (sp-backup-lookup--stamp-time suffix)))))
    (when matches
      (let* ((stamp (if (cdr parts) (car parts) suffix))
             (kept (and (cdr parts) (cdr (butlast parts)))))
        (when (or (null kept)
                  (sp-backup-lookup--tail-p (append kept (list name)) file))
          (list :path path :label label :stamp stamp
                :time (or (sp-backup-lookup--stamp-time stamp)
                          (file-attribute-modification-time (file-attributes path)))))))))

(defun sp-backup-lookup-list (file)
  "The backups of FILE in every folder of `sp-backup-lookup-directories'.
Newest first.  Each element is a plist with :path :label :stamp :time."
  (let ((file (expand-file-name file))
        (found nil))
    (pcase-dolist (`(,label . ,spec) sp-backup-lookup-directories)
      (when-let* ((root (sp-backup-lookup--directory spec)))
        (dolist (path (directory-files-recursively
                       root (concat "\\`" (regexp-quote (file-name-nondirectory file)))))
          (when-let* ((entry (sp-backup-lookup--entry label root path file)))
            (push entry found)))))
    (sort found (lambda (a b) (time-less-p (plist-get b :time) (plist-get a :time))))))

(defun sp-backup-lookup--link-file ()
  "The file of the first Org file link on this line, or nil."
  (save-excursion
    (let ((end (line-end-position)))
      (beginning-of-line)
      (when (re-search-forward "\\[\\[file:\\([^]]+?\\)\\(?:::[^]]*\\)?\\]" end t)
        (expand-file-name (match-string-no-properties 1))))))

(defun sp-backup-lookup--file (prompt)
  "The file to look up: the visited one, the report line's one, or ask with PROMPT."
  (cond (buffer-file-name)
        ((sp-backup-lookup--link-file))
        (t (read-file-name prompt nil nil t))))

(defun sp-backup-lookup--annotate (entries)
  "A completion annotation function for ENTRIES."
  (lambda (candidate)
    (when-let* ((e (cdr (assoc candidate entries))))
      (format "  %s  %s" (plist-get e :label)
              (file-size-human-readable
               (file-attribute-size (file-attributes (plist-get e :path))))))))

(defun sp-backup-lookup--read (file)
  "Ask which backup of FILE; return its path.  Signal an error when there is none."
  (let ((entries
         (mapcar (lambda (e)
                   (cons (format-time-string "%Y-%m-%d %H:%M:%S" (plist-get e :time)) e))
                 (or (sp-backup-lookup-list file)
                     (user-error "No backup of %s in any backup folder"
                                 (file-name-nondirectory file))))))
    (let ((table (lambda (string pred action)
                   (if (eq action 'metadata)
                       `(metadata (display-sort-function . identity)
                                  (annotation-function . ,(sp-backup-lookup--annotate entries)))
                     (complete-with-action action entries string pred)))))
      (plist-get (cdr (assoc (completing-read
                              (format "Backup of %s: " (file-name-nondirectory file))
                              table nil t nil nil (caar entries))
                             entries))
                 :path))))

;;;###autoload
(defun sp-backup-open ()
  "Open one of the backups of the current file, read-only.
In a batch report, the file is the one linked on the current line."
  (interactive)
  (let* ((file (sp-backup-lookup--file "File: "))
         (backup (sp-backup-lookup--read file)))
    (find-file-other-window backup)
    (setq buffer-read-only t)
    (message "Backup of %s" (abbreviate-file-name file))))

;;;###autoload
(defun sp-backup-diff ()
  "Diff one of the backups of the current file against the file.
In a batch report, the file is the one linked on the current line.  With a
prefix argument, use Ediff instead of a diff buffer."
  (interactive)
  (let* ((ediff current-prefix-arg)
         (file (sp-backup-lookup--file "File: "))
         (backup (sp-backup-lookup--read file)))
    (if ediff
        (ediff-files backup file)
      (diff backup file))))

(provide 'sp-backup-lookup)
;;; sp-backup-lookup.el ends here
