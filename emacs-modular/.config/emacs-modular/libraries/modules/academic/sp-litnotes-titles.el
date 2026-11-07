;;; sp-litnotes-titles.el --- Chicago-style titles and citekey file names for litnotes -*- lexical-binding: t; -*-

;;; Commentary:

;; A litnote used to be named after its citation key.  Now the key lives in
;; `ROAM_REFS' (see `sp-litnotes-refs'), so the note can carry a readable title.
;; This module sets `#+title:' to a Chicago-style reference built from the
;; `pub-author', `pub-year' and `pub-title' meta lines, for example
;; "Reuten (2014) The value form as a social form", and renames the file
;; to the citation key alone (`kant2009ideea.org'), keeping the `:ID:'.
;;
;; `sp-litnotes-titles-dryrun' shows what would change and writes nothing.
;; `sp-litnotes-titles-convert' shows the same report, offers to fill in what the
;; failed notes lack (a year, the authors, a title), asks once, copies every
;; note to a backup folder and only then writes.  The key is read from
;; `ROAM_REFS', or from a `#+reference:' keyword when `sp-litnotes-refs' has not
;; converted the note yet.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'sp-async-work)

(defvar sp-notes-dir)
(defvar sp-var-dir)

(declare-function vulpea-db-update-file "vulpea-db")
(declare-function vulpea-db--forget-file "vulpea-db")
(declare-function org-id-add-location "org-id")

(defgroup sp-litnotes-titles nil
  "Title and file name of literature notes from their bibliographic meta lines."
  :group 'sp-academic)

(defcustom sp-litnotes-titles-directory
  (expand-file-name "litnotes/" (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes"))
  "Folder with the literature notes."
  :type 'directory)

(defcustom sp-litnotes-titles-backup-directory
  (expand-file-name "litnote-title-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Folder where `sp-litnotes-titles-convert' copies each note before changing it.
Every run makes a sub-folder named with the time."
  :type 'directory)

(defcustom sp-litnotes-titles-link-directory
  (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes")
  "Folder searched for =file:= links to the old file names.
Those links are reported, not changed; =id:= links keep working."
  :type 'directory)

(defcustom sp-litnotes-titles-rename-files t
  "When non-nil, `sp-litnotes-titles-convert' renames the files to the citekey."
  :type 'boolean)

(defcustom sp-litnotes-titles-et-al-from 4
  "With this many authors or more, the title lists the first two and `et al.'."
  :type 'integer)

(defcustom sp-litnotes-titles-format-function #'sp-litnotes-titles-format
  "Function of the author names, the year and the title that returns the new title.
The names are a list of (LAST . FIRST) pairs (FIRST may be empty), the year a
string."
  :type 'function)

;;;; Reading a note

(defun sp-litnotes-titles--clean (value)
  "VALUE without quotes and Org links, and with spaces collapsed."
  (let* ((v (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" value))
         (v (replace-regexp-in-string "\\[\\[[^]]*\\]\\]" "" v))
         (v (string-trim v))
         (v (replace-regexp-in-string "\\`\"\\(.*\\)\"\\'" "\\1" v))
         (v (replace-regexp-in-string "[ \t\n]+" " " v)))
    (string-trim v)))

(defun sp-litnotes-titles--meta (key limit)
  "The raw value of the meta line KEY before LIMIT, searching from the top, or nil."
  (goto-char (point-min))
  (when (re-search-forward
         (format "^\\(?:- +\\|:\\)%s\\(?: ?::\\|:\\)[ \t]*\\(.*\\)$" (regexp-quote key))
         limit t)
    (string-trim (match-string 1))))

(defun sp-litnotes-titles--parse (file)
  "Read FILE as a plist.
The keys are :file, :id, :title (the =#+title:=), :pub (the cleaned pub-title),
:author and :year (raw and cleaned values) and :keys (the citation keys of
=ROAM_REFS=, or of =#+reference:= when there is none).  A meta value is nil when
the note has no such line before its first heading."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((case-fold-search t) id title refs keyword drawer-end
          (limit (save-excursion
                   (goto-char (point-min))
                   (or (and (re-search-forward "^\\*+ " nil t) (line-beginning-position))
                       (point-max)))))
      (goto-char (point-min))
      (when (looking-at ":PROPERTIES:[ \t]*$")
        (when (re-search-forward "^:END:[ \t]*$" nil t)
          (setq drawer-end (line-beginning-position))
          (goto-char (point-min))
          (when (re-search-forward "^:ID:[ \t]+\\(.+\\)$" drawer-end t)
            (setq id (string-trim (match-string 1))))
          (goto-char (point-min))
          (when (re-search-forward "^:ROAM_REFS:[ \t]*\\(.*\\)$" drawer-end t)
            (setq refs (string-trim (match-string 1))))))
      (goto-char (point-min))
      (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" limit t)
        (setq title (string-trim (match-string 1))))
      (goto-char (point-min))
      (when (re-search-forward "^#\\+reference:[ \t]*\\(.*\\)$" limit t)
        (setq keyword (string-trim (match-string 1))))
      (let ((pub (sp-litnotes-titles--meta "pub-title" limit))
            (author (sp-litnotes-titles--meta "pub-author" limit))
            (year (sp-litnotes-titles--meta "pub-year" limit)))
        (list :file file :id (and drawer-end id) :title title
              :pub (and pub (sp-litnotes-titles--clean pub))
              :author author
              :year (and year (sp-litnotes-titles--clean year))
              :keys (sp-litnotes-titles--keys (if (and refs (not (string-empty-p refs)))
                                                  refs keyword)))))))

(defun sp-litnotes-titles--keys (string)
  "The citation keys in STRING (=@key=, =key=, =cite:key= or =[cite:@a;@b]=)."
  (let ((clean (replace-regexp-in-string "\\[cite[^:]*:\\|\\]" "" (or string ""))) keys)
    (dolist (token (split-string clean "[ \t;,]+" t))
      (let ((bare (replace-regexp-in-string "\\`\\(cite:\\)?@?" "" token)))
        (when (and (not (string-match-p "\\`https?:\\|\\`doi:\\|/" token))
                   (string-match-p "\\`[[:alnum:]_:-]+\\'" bare))
          (push bare keys))))
    (delete-dups (nreverse keys))))

;;;; Authors and the title

(defun sp-litnotes-titles--split-name (name)
  "NAME, \"Last, First\" or \"First Last\", as (LAST . FIRST).
In the second form the surname is the last word with the lower-case particles
before it (\"van der Berg\")."
  (let ((name (string-trim name)))
    (if (string-match "\\`\\([^,]+\\),[ \t]*\\(.*\\)\\'" name)
        (cons (string-trim (match-string 1 name)) (string-trim (match-string 2 name)))
      (let* ((words (split-string name "[ \t]+" t))
             (n (length words)) (i (1- n)))
        (while (and (> i 1) (string-match-p "\\`[[:lower:]]" (nth (1- i) words)))
          (cl-decf i))
        (cons (string-join (nthcdr i words) " ")
              (string-join (cl-subseq words 0 i) " "))))))

(defun sp-litnotes-titles--authors (raw)
  "The authors in the pub-author value RAW as a list of (LAST . FIRST), or `ambiguous'.
Links give their text, quoted names are one name each, and the rest is split at
`;' and `and'.  A plain piece with more than one comma (\"A B, C D, E F\") may
be one author or several, so it makes the whole value `ambiguous'."
  (let ((pos 0) names ambiguous)
    (cl-flet ((plain (text)
                (dolist (seg (split-string (replace-regexp-in-string "[\"“”]" "" text)
                                           "\\(?:[ \t]*;[ \t]*\\|[ \t]+and[ \t]+\\)" t))
                  (let ((seg (string-trim seg "[ \t,]+" "[ \t,]+")))
                    (cond ((string-empty-p seg))
                          ((> (length (split-string seg "," t "[ \t]+")) 2)
                           (setq ambiguous t))
                          (t (push (sp-litnotes-titles--split-name seg) names)))))))
      (while (string-match
              "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]\\|\\[\\[[^]]*\\]\\]\\|[\"“]\\([^\"“”]*\\)[\"”]"
              raw pos)
        (let ((beg (match-beginning 0)) (end (match-end 0))
              (name (or (match-string 1 raw) (match-string 2 raw))))
          (plain (substring raw pos beg))
          (when (and name (not (string-empty-p (string-trim name))))
            (push (sp-litnotes-titles--split-name name) names))
          (setq pos end)))
      (plain (substring raw pos)))
    (if ambiguous 'ambiguous (nreverse names))))

(defun sp-litnotes-titles-format (names year title)
  "A reference with last names only: \"Last (YEAR) TITLE\".
Two authors are \"A and B\", three \"A, B and C\"; with
`sp-litnotes-titles-et-al-from' authors or more the first two and `et al.':
\"A, B et al.\"."
  (let* ((last (mapcar #'car names))
         (authors (cond ((>= (length last) sp-litnotes-titles-et-al-from)
                         (format "%s, %s et al." (nth 0 last) (nth 1 last)))
                        ((null (cdr last)) (car last))
                        (t (format "%s and %s" (string-join (butlast last) ", ")
                                   (car (last last)))))))
    (format "%s (%s) %s" authors year title)))

;;;; Planning

(defun sp-litnotes-titles--plan (parsed)
  "Add to PARSED, from `sp-litnotes-titles--parse', what to do with the note.
The result has :title-status (`no-id', `no-pub-title', `empty-title',
`no-author', `ambiguous-author', `no-year', `same' or `change'), :new-title, :new-name and
:name-status (`rename', `same-name', `no-citekey', or later `exists',
`key-clash', `case-only').  The new name is the first citation key and
=.org=; :keys has all of them."
  (let* ((pub (plist-get parsed :pub))
         (raw (plist-get parsed :author))
         (authors (and raw (sp-litnotes-titles--authors raw)))
         (title (plist-get parsed :title))
         (old-name (file-name-nondirectory (plist-get parsed :file)))
         (year (let ((y (plist-get parsed :year))) (and y (not (string-empty-p y)) y)))
         (new-title (and (consp authors) year
                         pub (not (string-empty-p pub))
                         (funcall sp-litnotes-titles-format-function authors year pub)))
         (title-status (cond ((not (plist-get parsed :id)) 'no-id)
                             ((null pub) 'no-pub-title)
                             ((string-empty-p pub) 'empty-title)
                             ((eq authors 'ambiguous) 'ambiguous-author)
                             ((null authors) 'no-author)
                             ((null year) 'no-year)
                             ((equal new-title title) 'same)
                             (t 'change)))
         (usable (plist-get parsed :id))
         (key (car (plist-get parsed :keys)))
         (new-name (and key (concat key ".org")))
         (name-status (cond ((not usable) nil)
                            ((null new-name) 'no-citekey)
                            ((string= new-name old-name) 'same-name)
                            ((string= (downcase new-name) (downcase old-name)) 'case-only)
                            (t 'rename))))
    (append parsed (list :title-status title-status
                         :new-title (and (memq title-status '(same change)) new-title)
                         :new-name (and (memq name-status '(rename case-only)) new-name)
                         :name-status name-status))))

(defun sp-litnotes-titles--mark-collisions (plans directory)
  "Change :name-status of PLANS to `exists' or `key-clash' where names collide.
DIRECTORY is the folder of the notes; names are compared without case."
  (let ((targets (make-hash-table :test 'equal))
        (present (make-hash-table :test 'equal)))
    (dolist (name (directory-files directory nil "\\`[^.]"))
      (puthash (downcase name) t present))
    (dolist (plan plans)
      (when (eq (plist-get plan :name-status) 'rename)
        (push plan (gethash (downcase (plist-get plan :new-name)) targets))))
    (maphash
     (lambda (target group)
       (cond ((cdr group)
              (dolist (plan group) (plist-put plan :name-status 'key-clash)))
             ((gethash target present)
              (plist-put (car group) :name-status 'exists))))
     targets)
    plans))

(defvar sp-litnotes-titles--overrides (make-hash-table :test 'equal)
  "Values typed in by `sp-litnotes-titles--resolve', by file: a plist of
:pub, :author and :year that replaces what the note has.")

(defun sp-litnotes-titles--parse-with-overrides (file)
  "`sp-litnotes-titles--parse' of FILE, with the values typed in for it."
  (let ((parsed (sp-litnotes-titles--parse file)))
    (cl-loop for (key value) on (gethash file sp-litnotes-titles--overrides) by #'cddr
             do (setq parsed (plist-put parsed key value)))
    parsed))

(defun sp-litnotes-titles--plans (&optional directory)
  "Plans for every note in DIRECTORY (default `sp-litnotes-titles-directory')."
  (let ((dir (file-name-as-directory (or directory sp-litnotes-titles-directory))))
    (sp-litnotes-titles--mark-collisions
     (mapcar (lambda (file)
               (sp-litnotes-titles--plan (sp-litnotes-titles--parse-with-overrides file)))
             (directory-files dir t "\\`[^.#].*\\.org\\'"))
     dir)))

(defun sp-litnotes-titles--changes-p (plan)
  "Non-nil when applying PLAN would write the title or rename the file."
  (or (eq (plist-get plan :title-status) 'change)
      (and sp-litnotes-titles-rename-files
           (eq (plist-get plan :name-status) 'rename))))

;;;; Links to the old names

(defun sp-litnotes-titles--old-names (plans)
  "Hash table of the old file names (without folder) of the renamed PLANS."
  (let ((old (make-hash-table :test 'equal)))
    (dolist (plan plans)
      (when (eq (plist-get plan :name-status) 'rename)
        (puthash (file-name-nondirectory (plist-get plan :file)) t old)))
    old))

(defun sp-litnotes-titles--link-files (old)
  "The Org files under `sp-litnotes-titles-link-directory' to search for the names in OLD."
  (when (and (> (hash-table-count old) 0)
             (file-directory-p sp-litnotes-titles-link-directory))
    (directory-files-recursively
     sp-litnotes-titles-link-directory "\\`[^.#].*\\.org\\'")))

(defun sp-litnotes-titles--scan-links (file old found)
  "Add the old names of OLD that =file:= links in FILE name to the alist cell FOUND.
FOUND is a cons whose car is the alist (OLD-NAME . FILES)."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (while (re-search-forward "\\[\\[file:\\([^]]+\\.org\\)" nil t)
        (let ((name (file-name-nondirectory (match-string 1))))
          (when (gethash name old)
            (cl-pushnew file (alist-get name (car found) nil nil #'equal)
                        :test #'equal)))))))

(defun sp-litnotes-titles--file-links (plans)
  "Alist of (OLD-NAME . FILES) for the renamed PLANS that =file:= links name.
Searches `sp-litnotes-titles-link-directory'; =id:= links need no change."
  (let* ((old (sp-litnotes-titles--old-names plans))
         (found (list nil)))
    (dolist (file (sp-litnotes-titles--link-files old))
      (sp-litnotes-titles--scan-links file old found))
    (car found)))

(defun sp-litnotes-titles--scan (callback)
  "Read the notes in slices and call CALLBACK with PLANS and LINKS.
LINKS is the alist of `sp-litnotes-titles--file-links'.  The folder of the
links is searched in slices too, file by file.  Nothing is written.
Return the job."
  (let* ((dir (file-name-as-directory sp-litnotes-titles-directory))
         plans old (found (list nil)))
    (sp-async-work-run
     "Litnote titles"
     (list (list "reading notes"
                 (lambda () (directory-files dir t "\\`[^.#].*\\.org\\'"))
                 (lambda (file _job)
                   (push (sp-litnotes-titles--plan
                          (sp-litnotes-titles--parse-with-overrides file))
                         plans)))
           (list "looking for links"
                 (lambda ()
                   (setq plans (sp-litnotes-titles--mark-collisions (nreverse plans) dir)
                         old (sp-litnotes-titles--old-names plans))
                   (sp-litnotes-titles--link-files old))
                 (lambda (file _job)
                   (sp-litnotes-titles--scan-links file old found))))
     :done (lambda (_job) (funcall callback plans (car found))))))

;;;; Report

(defconst sp-litnotes-titles--promptable
  '(no-pub-title empty-title no-author ambiguous-author no-year)
  "Title statuses that `sp-litnotes-titles--resolve' can fix by asking.")

(defconst sp-litnotes-titles--reasons
  '((no-id . "No :ID: in a top-level property drawer: skipped altogether")
    (no-pub-title . "No pub-title line: skipped")
    (empty-title . "pub-title has no value: skipped")
    (no-author . "No pub-author line or no name in it: title left as it is")
    (ambiguous-author . "pub-author has a piece with several commas (one author or several?): title left as it is")
    (no-year . "No pub-year: title left as it is")
    (no-citekey . "No citation key in ROAM_REFS or #+reference:: not renamed")
    (exists . "A file with the citekey name already exists: not renamed")
    (key-clash . "Notes with the same first citekey: not renamed")
    (case-only . "Citekey differs from the file name only in case: not renamed"))
  "Why a note, or its file name, is left as it is.")

(defun sp-litnotes-titles--report-text (plans links)
  "Return the dry-run report for PLANS; LINKS is from `sp-litnotes-titles--file-links'."
  (let ((counts (make-hash-table :test 'eq))
        (changing (cl-remove-if-not #'sp-litnotes-titles--changes-p plans)))
    (dolist (plan plans)
      (cl-incf (gethash (plist-get plan :title-status) counts 0))
      (when-let* ((s (plist-get plan :name-status)))
        (cl-incf (gethash s counts 0))))
    (with-temp-buffer
      (insert (format "#+title: Litnote titles: dry run\n\nFolder: =%s=\nNotes: %d\nRenaming files: %s\n\n"
                      sp-litnotes-titles-directory (length plans)
                      (if sp-litnotes-titles-rename-files "yes" "no")))
      (insert "* Counts\n")
      (dolist (item '((change . "title would change") (same . "title already right")
                      (rename . "file would be renamed") (same-name . "file name already the citekey")))
        (insert (format "- %s: %d\n" (cdr item) (gethash (car item) counts 0))))
      (dolist (item sp-litnotes-titles--reasons)
        (when (> (gethash (car item) counts 0) 0)
          (insert (format "- %s: %d\n" (cdr item) (gethash (car item) counts 0)))))
      (insert (format "- failed items (apply asks you for the values that are missing): %d\n"
                      (cl-count-if (lambda (p) (memq (plist-get p :title-status)
                                                     sp-litnotes-titles--promptable))
                                   plans)))
      (insert (format "- notes written by apply: %d\n\n" (length changing)))
      (when changing
        (insert (format "* Would change (%d)\n" (length changing)))
        (dolist (plan changing)
          (let ((old-name (file-name-nondirectory (plist-get plan :file)))
                (renamed (and sp-litnotes-titles-rename-files
                              (eq (plist-get plan :name-status) 'rename))))
            (insert (format "** =%s=\n" old-name))
            (when (cdr (plist-get plan :keys))
              (insert (format "- several citekeys: %s (the first names the file)\n"
                              (string-join (plist-get plan :keys) " "))))
            (if (eq (plist-get plan :title-status) 'change)
                (insert (format "- title: %s -> %s\n"
                                (or (plist-get plan :title) "(none)") (plist-get plan :new-title)))
              (insert "- title: unchanged\n"))
            (if renamed
                (insert (format "- file: %s -> =%s=\n" old-name (plist-get plan :new-name)))
              (insert "- file: unchanged\n"))
            (when-let* ((files (cdr (assoc old-name links))))
              (insert (format "- file: links to the old name in: %s\n"
                              (mapconcat (lambda (f) (format "=%s=" (file-name-nondirectory f)))
                                         files ", ")))))))
      (dolist (item sp-litnotes-titles--reasons)
        (let ((group (cl-remove-if-not
                      (lambda (p) (or (eq (plist-get p :title-status) (car item))
                                      (eq (plist-get p :name-status) (car item))))
                      plans)))
          (when group
            (insert (format "\n* Failed: %s (%d)\n" (cdr item) (length group)))
            (dolist (plan group)
              (insert (format "- =%s=: title %s; pub-author %s; pub-title %s%s\n"
                              (file-name-nondirectory (plist-get plan :file))
                              (or (plist-get plan :title) "(none)")
                              (or (plist-get plan :author) "(none)")
                              (or (plist-get plan :pub) "(none)")
                              (if (plist-get plan :new-name)
                                  (format "; would be =%s=" (plist-get plan :new-name))
                                "")))))))
      (let ((by-title (make-hash-table :test 'equal)) dups)
        (dolist (plan plans)
          (when-let* ((title (plist-get plan :new-title)))
            (push plan (gethash (downcase title) by-title))))
        (maphash (lambda (_ group) (when (cdr group) (push (reverse group) dups))) by-title)
        (when dups
          (insert (format "\n* Notes that would get the same title (%d titles)\n" (length dups)))
          (dolist (group dups)
            (insert (format "- %s: %s\n" (plist-get (car group) :new-title)
                            (mapconcat (lambda (p) (format "=%s=" (file-name-nondirectory (plist-get p :file))))
                                       group ", "))))))
      (buffer-string))))

;;;###autoload
(defun sp-litnotes-titles-dryrun ()
  "Show what `sp-litnotes-titles-convert' would do.  Writes nothing.
The notes are read in slices, so Emacs stays usable; the report opens
when they are read."
  (interactive)
  (clrhash sp-litnotes-titles--overrides)
  (sp-litnotes-titles--show-report))

(define-obsolete-function-alias 'sp-litnotes-titles-report 'sp-litnotes-titles-dryrun "2026-11-07")

(defun sp-litnotes-titles--show-report (&optional callback)
  "Read the notes, show the report and call CALLBACK with the plans.
Reading is done in slices; the report opens, and CALLBACK runs, when it is done."
  (message "Reading the litnotes in the background...")
  (sp-litnotes-titles--scan
   (lambda (plans links)
     (let ((text (sp-litnotes-titles--report-text plans links)))
       (with-current-buffer (get-buffer-create "*litnote titles*")
         (let ((inhibit-read-only t))
           (erase-buffer)
           (insert text)
           (org-mode)
           (goto-char (point-min))
           (read-only-mode 1)))
       (pop-to-buffer "*litnote titles*"))
     (when callback (funcall callback plans)))))

;;;; Writing

(defun sp-litnotes-titles--backup (file stamp)
  "Copy FILE to the STAMP sub-folder of `sp-litnotes-titles-backup-directory'."
  (let ((dir (expand-file-name (concat stamp "/") sp-litnotes-titles-backup-directory)))
    (make-directory dir t)
    (copy-file file (expand-file-name (file-name-nondirectory file) dir) nil t)))

(defun sp-litnotes-titles--write-title (file title)
  "Set the =#+title:= of FILE to TITLE, after its property drawer when it has none."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((case-fold-search t))
      (if (re-search-forward "^#\\+title:.*$" nil t)
          (replace-match (concat "#+title: " title) t t)
        (re-search-forward "^:END:[ \t]*$")
        (end-of-line)
        (insert "\n#+title: " title)))
    (write-region nil nil file nil 'silent)))

(defun sp-litnotes-titles--apply-plan (plan stamp)
  "Write PLAN, after a backup in STAMP.  Return a plist for the summary."
  (let* ((file (plist-get plan :file))
         (buffer (find-buffer-visiting file))
         (id (plist-get plan :id)))
    (cond
     ((stringp (file-locked-p file)) (list :file file :status 'skipped :why "locked by another Emacs"))
     ((and buffer (buffer-modified-p buffer))
      (list :file file :status 'skipped :why "unsaved changes in its buffer"))
     (t
      (condition-case err
          (let ((new file))
            (sp-litnotes-titles--backup file stamp)
            (when buffer (kill-buffer buffer))
            (when (eq (plist-get plan :title-status) 'change)
              (sp-litnotes-titles--write-title file (plist-get plan :new-title))
              (unless (equal id (plist-get (sp-litnotes-titles--parse file) :id))
                (error "the :ID: changed; restore from the backup")))
            (when (and sp-litnotes-titles-rename-files
                       (eq (plist-get plan :name-status) 'rename))
              (setq new (expand-file-name (plist-get plan :new-name)
                                          (file-name-directory file)))
              (when (file-exists-p new) (error "%s exists" new))
              (rename-file file new nil)
              (when (fboundp 'vulpea-db--forget-file)
                (ignore-errors (vulpea-db--forget-file file)))
              (when (fboundp 'org-id-add-location)
                (ignore-errors (org-id-add-location id new))))
            (when (fboundp 'vulpea-db-update-file)
              (ignore-errors (vulpea-db-update-file new)))
            (list :file file :status 'written :new new))
        (error (list :file file :status 'failed :why (error-message-string err))))))))

;;;; Asking for what is missing

(defun sp-litnotes-titles--prompt (plan status)
  "The question for the failed PLAN of title STATUS, and the field it fills."
  (let ((name (file-name-nondirectory (plist-get plan :file)))
        (context (format "author %s, year %s, title %s"
                         (or (plist-get plan :author) "-") (or (plist-get plan :year) "-")
                         (or (plist-get plan :pub) "-"))))
    (pcase status
      ((or 'no-pub-title 'empty-title)
       (cons :pub (format "%s (%s)\nTitle (empty skips): " name context)))
      ((or 'no-author 'ambiguous-author)
       (cons :author (format "%s (%s)\nAuthors as \"Last, First; Last, First\" (empty skips): "
                             name context)))
      ('no-year (cons :year (format "%s (%s)\nYear (empty skips): " name context))))))

(defun sp-litnotes-titles--resolve (plans)
  "Ask for the missing values of the failed PLANS; return how many were typed.
An empty answer leaves the note as it is.  The values are used for the title
only and kept in `sp-litnotes-titles--overrides'; the note's meta lines are not
changed."
  (let ((typed 0))
    (dolist (plan plans)
      (when (memq (plist-get plan :title-status) sp-litnotes-titles--promptable)
        (let ((file (plist-get plan :file)) (go t))
          (while go
            (let* ((current (sp-litnotes-titles--plan
                             (sp-litnotes-titles--parse-with-overrides file)))
                   (status (plist-get current :title-status))
                   (ask (and (memq status sp-litnotes-titles--promptable)
                             (sp-litnotes-titles--prompt current status)))
                   (answer (and ask (string-trim (read-string (cdr ask))))))
              (cond ((or (null ask) (string-empty-p answer)) (setq go nil))
                    ((and (eq (car ask) :author)
                          (not (consp (sp-litnotes-titles--authors answer))))
                     (message "Could not read authors from \"%s\"; skipping %s"
                              answer (file-name-nondirectory file))
                     (setq go nil))
                    (t (puthash file (plist-put (gethash file sp-litnotes-titles--overrides)
                                                (car ask) answer)
                                sp-litnotes-titles--overrides)
                       (cl-incf typed))))))))
    typed))

;; A note is written only if it still gets the title and name of the report.
(defun sp-litnotes-titles--current-p (plan)
  "Non-nil when the note of PLAN would still get the title and name PLAN has."
  (let ((now (ignore-errors
               (sp-litnotes-titles--plan
                (sp-litnotes-titles--parse-with-overrides (plist-get plan :file))))))
    (and now
         (equal (plist-get now :id) (plist-get plan :id))
         (equal (plist-get now :new-title) (plist-get plan :new-title))
         (equal (plist-get now :new-name) (plist-get plan :new-name)))))

(defvar sp-litnotes-titles--last-results nil
  "What the last `sp-litnotes-titles-convert' wrote: a plist per note.")

(defun sp-litnotes-titles--write-all (todo)
  "Write the plans TODO in slices, after a backup of each, and report at the end."
  (let* ((stamp (format-time-string "%Y%m%dT%H%M%S"))
         results)
    (sp-async-work-run
     "Litnote titles"
     (list (list "writing"
                 (lambda () todo)
                 (lambda (plan _job)
                   (push (if (sp-litnotes-titles--current-p plan)
                             (sp-litnotes-titles--apply-plan plan stamp)
                           (list :file (plist-get plan :file) :status 'skipped
                                 :why "changed since the report"))
                         results))))
     :done (lambda (_job)
             (setq results (nreverse results))
             (let ((bad (cl-remove-if (lambda (r) (eq (plist-get r :status) 'written))
                                      results)))
               (message "Wrote %d of %d litnotes; backups in %s%s"
                        (- (length results) (length bad)) (length results)
                        (expand-file-name (concat stamp "/") sp-litnotes-titles-backup-directory)
                        (if bad
                            (format "; %s" (mapconcat
                                            (lambda (r) (format "%s %s (%s)"
                                                                (plist-get r :status)
                                                                (file-name-nondirectory (plist-get r :file))
                                                                (plist-get r :why)))
                                            bad ", "))
                          "")))
             (setq sp-litnotes-titles--last-results results)))))

(defun sp-litnotes-titles--confirm-and-write (plans)
  "Ask once about the changes in PLANS, then write them."
  (let ((todo (cl-remove-if-not #'sp-litnotes-titles--changes-p plans)))
    (if (null todo)
        (message "Nothing to change.")
      (when (yes-or-no-p (format "Write %d litnotes (backups in %s)? "
                                 (length todo) sp-litnotes-titles-backup-directory))
        (sp-litnotes-titles--write-all todo)))))

(defun sp-litnotes-titles--after-report (plans)
  "Offer to ask for what the failed PLANS lack, then go on to write."
  (let ((failed (cl-remove-if-not
                 (lambda (p) (memq (plist-get p :title-status) sp-litnotes-titles--promptable))
                 plans)))
    (if (and failed
             (y-or-n-p (format "%d notes failed for a missing title, author or year.  Fill them in now? "
                               (length failed)))
             (> (sp-litnotes-titles--resolve failed) 0))
        (sp-litnotes-titles--show-report #'sp-litnotes-titles--confirm-and-write)
      (sp-litnotes-titles--confirm-and-write plans))))

;;;###autoload
(defun sp-litnotes-titles-convert ()
  "Set the litnote titles to Chicago-style references and rename them to the citekey.
The notes are read in slices, so Emacs stays usable, and the report opens.
When notes failed for a missing title, author or year, you are offered to
type the values (used for the title only); the report is made again and you
are asked once before anything is written.  Every note is copied to a
time-stamped folder in `sp-litnotes-titles-backup-directory' before it is
written, in slices; a note with unsaved changes in its buffer, or changed
since the report, is skipped.  The Vulpea database is updated after each
change.  The `:ID:' is never touched, so `id:' links keep working; `file:'
links to old names are listed in the report but not changed.  Running it
again changes nothing.  Only when `sp-async-work-synchronous' is set does
this return the results, a plist per note."
  (interactive)
  (clrhash sp-litnotes-titles--overrides)
  (setq sp-litnotes-titles--last-results nil)
  (sp-litnotes-titles--show-report #'sp-litnotes-titles--after-report)
  sp-litnotes-titles--last-results)

(define-obsolete-function-alias 'sp-litnotes-titles-apply 'sp-litnotes-titles-convert "2026-11-07")

(provide 'sp-litnotes-titles)
;; sp-litnotes-titles.el ends here
