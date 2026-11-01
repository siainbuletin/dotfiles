;;; sp-litnotes-titles.el --- Titles and file names of litnotes from pub-title -*- lexical-binding: t; -*-

;;; Commentary:

;; A litnote used to be named after its citation key.  Now the key lives in
;; `ROAM_REFS' (see `sp-litnotes-refs'), so the note can carry its real title.
;; This module copies the `pub-title' meta line into `#+title:' and renames the
;; file to match, keeping the Denote identifier, the keywords and the `:ID:'.
;;
;; `sp-litnotes-titles-report' shows what would change and writes nothing.
;; `sp-litnotes-titles-apply' shows the same report, asks once, copies every
;; note to a backup folder and only then writes.  It does not depend on the
;; `ROAM_REFS' conversion having run.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ucs-normalize)

(defvar sp-notes-dir)
(defvar sp-var-dir)

(declare-function vulpea-db-update-file "vulpea-db")
(declare-function vulpea-db--forget-file "vulpea-db")
(declare-function org-id-add-location "org-id")

(defgroup sp-litnotes-titles nil
  "Title and file name of literature notes from `pub-title'."
  :group 'sp-academic)

(defcustom sp-litnotes-titles-directory
  (expand-file-name "litnotes/" (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes"))
  "Folder with the literature notes."
  :type 'directory)

(defcustom sp-litnotes-titles-backup-directory
  (expand-file-name "litnote-title-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Folder where `sp-litnotes-titles-apply' copies each note before changing it.
Every run makes a sub-folder named with the time."
  :type 'directory)

(defcustom sp-litnotes-titles-link-directory
  (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes")
  "Folder searched for =file:= links to the old file names.
Those links are reported, not changed; =id:= links keep working."
  :type 'directory)

(defcustom sp-litnotes-titles-rename-files t
  "When non-nil, `sp-litnotes-titles-apply' renames the files as well."
  :type 'boolean)

(defcustom sp-litnotes-titles-max-slug-length 100
  "Longest slug in a new file name, cut at a word boundary."
  :type 'integer)

(defcustom sp-litnotes-titles-slug-function #'sp-litnotes-titles-slug
  "Function of the title and the separator character that returns the slug."
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

(defun sp-litnotes-titles--parse (file)
  "Read FILE as a plist: :file, :id, :title, :pub (the pub-title) and :refs.
:pub is nil when the note has no =pub-title= line before its first heading and
the empty string when the line has no value."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((case-fold-search t) id title pub refs drawer-end
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
      (when (re-search-forward "^\\(?:- +\\|:\\)pub-title\\(?: ?::\\|:\\)[ \t]*\\(.*\\)$" limit t)
        (setq pub (sp-litnotes-titles--clean (match-string 1))))
      (list :file file :id (and drawer-end id) :title title :pub pub :refs refs))))

;;;; File names

(defun sp-litnotes-titles-slug (title separator)
  "TITLE as lower-case ASCII words joined by SEPARATOR (a string)."
  (let* ((s (downcase (ucs-normalize-NFD-string title)))
         (s (replace-regexp-in-string "[\u0300-\u036f]" "" s))
         (s (replace-regexp-in-string "[^a-z0-9]+" separator s))
         (s (string-trim s (regexp-quote separator) (regexp-quote separator))))
    (if (> (length s) sp-litnotes-titles-max-slug-length)
        (let* ((cut (substring s 0 sp-litnotes-titles-max-slug-length))
               (pos (string-match (concat (regexp-quote separator) "[^" separator "]*\\'") cut)))
          (if (and pos (> pos 0)) (substring cut 0 pos) cut))
      s)))

(defun sp-litnotes-titles--name-parts (name)
  "Split the file NAME into (ID SEPARATOR SLUG-SEPARATOR SLUG KEYWORDS), or nil.
Two schemes are read: Denote's =ID--slug__keywords.org= and the Vulpea
=ID_slug.org= with a 14-digit time stamp."
  (cond ((string-match
          "\\`\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)\\(--\\)\\(.*?\\)\\(__.+\\)?\\.org\\'" name)
         (list (match-string 1 name) "--" "-" (match-string 3 name)
               (or (match-string 4 name) "")))
        ((string-match "\\`\\([0-9]\\{14\\}\\)\\(_\\)\\(.+\\)\\.org\\'" name)
         (list (match-string 1 name) "_" "_" (match-string 3 name) ""))))

(defun sp-litnotes-titles--new-name (name title)
  "The file name for TITLE in place of NAME, or a symbol saying why not.
`odd-name' means NAME has an identifier scheme this module does not know;
`no-slug' means TITLE has no letters or digits."
  (if-let* ((parts (sp-litnotes-titles--name-parts name)))
      (let ((slug (funcall sp-litnotes-titles-slug-function title (nth 2 parts))))
        (if (string-empty-p slug)
            'no-slug
          (concat (nth 0 parts) (nth 1 parts) slug (nth 4 parts) ".org")))
    'odd-name))

;;;; Planning

(defun sp-litnotes-titles--plan (parsed)
  "Add to PARSED, from `sp-litnotes-titles--parse', what to do with the note.
The result has :title-status (`no-id', `no-pub-title', `empty-title', `same'
or `change'), :new-title, :new-name and :name-status (`rename', `same-name' or
a reason: `odd-name', `no-slug', or later `exists', `slug-clash', `case-only')."
  (let* ((pub (plist-get parsed :pub))
         (title (plist-get parsed :title))
         (old-name (file-name-nondirectory (plist-get parsed :file)))
         (title-status (cond ((not (plist-get parsed :id)) 'no-id)
                             ((null pub) 'no-pub-title)
                             ((string-empty-p pub) 'empty-title)
                             ((equal pub title) 'same)
                             (t 'change)))
         (usable (memq title-status '(same change)))
         (new-name (and usable (sp-litnotes-titles--new-name old-name pub)))
         (name-status (cond ((not usable) nil)
                            ((symbolp new-name) new-name)
                            ((string= new-name old-name) 'same-name)
                            ((string= (downcase new-name) (downcase old-name)) 'case-only)
                            (t 'rename))))
    (append parsed (list :title-status title-status
                         :new-title (and usable pub)
                         :new-name (and (stringp new-name) new-name)
                         :name-status name-status))))

(defun sp-litnotes-titles--mark-collisions (plans directory)
  "Change :name-status of PLANS to `exists' or `slug-clash' where names collide.
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
              (dolist (plan group) (plist-put plan :name-status 'slug-clash)))
             ((gethash target present)
              (plist-put (car group) :name-status 'exists))))
     targets)
    plans))

(defun sp-litnotes-titles--plans (&optional directory)
  "Plans for every note in DIRECTORY (default `sp-litnotes-titles-directory')."
  (let ((dir (file-name-as-directory (or directory sp-litnotes-titles-directory))))
    (sp-litnotes-titles--mark-collisions
     (mapcar (lambda (file) (sp-litnotes-titles--plan (sp-litnotes-titles--parse file)))
             (directory-files dir t "\\`[^.#].*\\.org\\'"))
     dir)))

(defun sp-litnotes-titles--changes-p (plan)
  "Non-nil when applying PLAN would write the title or rename the file."
  (or (eq (plist-get plan :title-status) 'change)
      (and sp-litnotes-titles-rename-files
           (eq (plist-get plan :name-status) 'rename))))

;;;; Links to the old names

(defun sp-litnotes-titles--file-links (plans)
  "Alist of (OLD-NAME . FILES) for the renamed PLANS that =file:= links name.
Searches `sp-litnotes-titles-link-directory'; =id:= links need no change."
  (let ((old (make-hash-table :test 'equal)) found)
    (dolist (plan plans)
      (when (eq (plist-get plan :name-status) 'rename)
        (puthash (file-name-nondirectory (plist-get plan :file)) t old)))
    (when (and (> (hash-table-count old) 0)
               (file-directory-p sp-litnotes-titles-link-directory))
      (dolist (file (directory-files-recursively
                     sp-litnotes-titles-link-directory "\\`[^.#].*\\.org\\'"))
        (when (file-readable-p file)
         (with-temp-buffer
          (insert-file-contents file)
          (while (re-search-forward "\\[\\[file:\\([^]]+\\.org\\)" nil t)
            (let ((name (file-name-nondirectory (match-string 1))))
              (when (gethash name old)
                (cl-pushnew file (alist-get name found nil nil #'equal)
                            :test #'equal))))))))
    found))

;;;; Report

(defconst sp-litnotes-titles--reasons
  '((no-id . "No :ID: in a top-level property drawer: skipped altogether")
    (no-pub-title . "No pub-title line: skipped")
    (empty-title . "pub-title has no value: skipped")
    (odd-name . "File name is neither Denote's ID--slug__keywords nor ID_slug: title copied, not renamed")
    (no-slug . "pub-title has no letters or digits for a slug: title copied, not renamed")
    (exists . "A file with the new name already exists: title copied, not renamed")
    (slug-clash . "Titles that give the same new name: title copied, not renamed")
    (case-only . "New name differs only in case: title copied, not renamed"))
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
      (dolist (item '((change . "title would change") (same . "title already equals pub-title")
                      (rename . "file would be renamed") (same-name . "file name already right")))
        (insert (format "- %s: %d\n" (cdr item) (gethash (car item) counts 0))))
      (dolist (item sp-litnotes-titles--reasons)
        (when (> (gethash (car item) counts 0) 0)
          (insert (format "- %s: %d\n" (cdr item) (gethash (car item) counts 0)))))
      (insert (format "- notes written by apply: %d\n\n" (length changing)))
      (when changing
        (insert (format "* Would change (%d)\n" (length changing)))
        (dolist (plan changing)
          (let ((old-name (file-name-nondirectory (plist-get plan :file)))
                (renamed (and sp-litnotes-titles-rename-files
                              (eq (plist-get plan :name-status) 'rename))))
            (insert (format "** =%s=\n" old-name))
            (when (plist-get plan :refs)
              (insert (format "- refs: %s\n" (plist-get plan :refs))))
            (insert (format "- title: %s -> %s\n"
                            (or (plist-get plan :title) "(none)") (plist-get plan :new-title)))
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
            (insert (format "\n* %s (%d)\n" (cdr item) (length group)))
            (dolist (plan group)
              (insert (format "- =%s=: title %s; pub-title %s%s\n"
                              (file-name-nondirectory (plist-get plan :file))
                              (or (plist-get plan :title) "(none)")
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
          (insert (format "\n* Notes sharing a pub-title (%d titles)\n" (length dups)))
          (dolist (group dups)
            (insert (format "- %s: %s\n" (plist-get (car group) :new-title)
                            (mapconcat (lambda (p) (format "=%s=" (file-name-nondirectory (plist-get p :file))))
                                       group ", "))))))
      (buffer-string))))

;;;###autoload
(defun sp-litnotes-titles-report ()
  "Show what `sp-litnotes-titles-apply' would do.  Writes nothing."
  (interactive)
  (let* ((plans (sp-litnotes-titles--plans))
         (text (sp-litnotes-titles--report-text plans (sp-litnotes-titles--file-links plans))))
    (with-current-buffer (get-buffer-create "*litnote titles*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (org-mode)
        (goto-char (point-min))
        (read-only-mode 1)))
    (pop-to-buffer "*litnote titles*")
    plans))

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

;;;###autoload
(defun sp-litnotes-titles-apply ()
  "Copy `pub-title' to `#+title:' and rename the litnotes, after the report.
Shows the report and asks once.  Every note is copied to a time-stamped folder in
`sp-litnotes-titles-backup-directory' before it is written; the Vulpea database
is updated after each change.  The `:ID:' is never touched, so `id:' links keep
working; `file:' links to old names are listed in the report but not changed.
Running it again changes nothing."
  (interactive)
  (let* ((plans (sp-litnotes-titles-report))
         (todo (cl-remove-if-not #'sp-litnotes-titles--changes-p plans)))
    (if (null todo)
        (message "Nothing to change.")
      (when (yes-or-no-p (format "Write %d litnotes (backups in %s)? "
                                 (length todo) sp-litnotes-titles-backup-directory))
        (let* ((stamp (format-time-string "%Y%m%dT%H%M%S"))
               (results (mapcar (lambda (plan) (sp-litnotes-titles--apply-plan plan stamp))
                                todo))
               (bad (cl-remove-if (lambda (r) (eq (plist-get r :status) 'written)) results)))
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
                     ""))
          results)))))

(provide 'sp-litnotes-titles)
;; sp-litnotes-titles.el ends here
