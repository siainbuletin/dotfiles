;;; sp-notes.el --- The notes module: the notes picker, creating notes and filing by tag -*- lexical-binding: t; -*-

;;; Commentary:

;; The bigger notes module.  Notes are ID-based (`:ID:' property) and indexed
;; by vulpea; Denote was removed (docs: adr/0024-remove-denote-file-notes-by-tag.org).
;;
;; - `sp-notes-notebook' opens the vulpea picker in the buffer window.
;; - `C-c w d g' greps the notes (`sp-search-in-notes').
;; - `sp-notes-create' makes a note (ID, :CREATED:, tags, tag folder);
;;   `sp-notes-open' picks one from all subfolders (date, tags, title).
;; - `sp-notes-filing-*' files the notes into subfolders by tag (dry-run lint,
;;   backup, restore, filing on save, scheduled run) and drops Denote names.
;; - Literature notes are made and kept by `sp-litnotes', which writes them into
;;   litnotes/ (the folder the `litnote' filing rule uses).
;;
;; Literate source: docs/tangles/academic/sp-notes.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'org-id)
(require 'sp-globals nil t)
(require 'sp-batch-report)

(defvar sp-notes-dir)
(defvar sp-var-dir)
(declare-function vulpea-db-update-file "vulpea-db")
(declare-function vulpea-db--forget-file "vulpea-db")


;;;; Notebook keys
(global-set-key (kbd "C-c w d f") #'sp-notes-notebook)
(global-set-key (kbd "C-c w d g") #'sp-search-in-notes)
(declare-function sp-search-in-notes "sp-search")

;; The notes are ID-based and indexed by vulpea, so the notebook is the vulpea picker.
(defun sp-notes-notebook ()
  "Pick a note with `vulpea-find', in the buffer window rather than the minibuffer."
  (interactive)
  (let ((vertico-buffer-display-action
         '(display-buffer-reuse-window)))
    (call-interactively #'vulpea-find)))

;;;; Create a note

(declare-function sp-org--write-note "sp-org-link-conversion")
(declare-function sp-org-tag-read-note-tags "sp-org-tag-lint")
(declare-function sp-org-created-stamp "sp-org-link-conversion")

(defun sp-notes-create-folder (tags)
  "The folder, as a directory name, where a new note with TAGS is written.
A note with tags goes straight into its filing folder (`sp-notes-filing-folder');
a note without tags stays at the top of the root, like `sp-notes-filing-mode' leaves it."
  (let ((root (file-name-as-directory (expand-file-name sp-notes-filing-root))))
    (if tags
        (file-name-as-directory (expand-file-name (sp-notes-filing-folder tags) root))
      root)))

(declare-function vulpea-create "vulpea-create")
(declare-function vulpea-note-path "vulpea-note")
(defvar vulpea-default-notes-directory)

(defun sp-notes-create-base ()
  "The directory `vulpea-create' resolves a relative file template against.
`vulpea-default-notes-directory' is nil unless set (vulpea then works the
directory out from the sync directories), so a nil falls back to
`sp-notes-filing-root'.  Always a non-nil directory name."
  (file-name-as-directory
   (expand-file-name (or (bound-and-true-p vulpea-default-notes-directory)
                         sp-notes-filing-root))))

(defun sp-notes-create-file-template (tags)
  "The `vulpea-create' file-name template for a new note with TAGS.
It is `sp-notes-create-folder' relative to `sp-notes-create-base', which is
where vulpea resolves the template; the name part follows
`vulpea-create-default-function' (timestamp, underscore, slug)."
  (concat (string-remove-prefix
           "./" (file-relative-name (sp-notes-create-folder tags) (sp-notes-create-base)))
          "${timestamp}_${slug}.org"))

(defun sp-notes-ensure-created (file)
  "Add :CREATED: to the file-level drawer of FILE when it has none.
If a buffer visits FILE, it is edited (and left unsaved) so that Emacs does
not see the file change underneath it."
  (when (and file (file-readable-p file))
    (let ((buffer (find-buffer-visiting file)))
      (if buffer
          (with-current-buffer buffer
            (save-excursion
              (save-restriction
                (widen)
                (goto-char (point-min))
                (unless (org-entry-get nil "CREATED")
                  (org-entry-put nil "CREATED" (sp-org-created-stamp))))))
        (with-temp-buffer
          (insert-file-contents file)
          (delay-mode-hooks (org-mode))
          (goto-char (point-min))
          (unless (org-entry-get nil "CREATED")
            (org-entry-put nil "CREATED" (sp-org-created-stamp))
            (write-region nil nil file nil 'silent)))))))

(defun sp-notes-created-after-vulpea-create (note)
  "Filter the return value of `vulpea-create': give NOTE a :CREATED: property.
This covers every way of making a note with vulpea (`vulpea-find',
`vulpea-insert', the inbox tab, `sp-notes-create'), whether or not the
vulpea version writes the properties it is given.  Returns NOTE."
  (when (and note (fboundp 'vulpea-note-path))
    (require 'sp-org-link-conversion)
    (ignore-errors (sp-notes-ensure-created (vulpea-note-path note))))
  note)

(with-eval-after-load 'vulpea
  (advice-add 'vulpea-create :filter-return #'sp-notes-created-after-vulpea-create))

;;;###autoload
(defun sp-notes-create (title)
  "Create a note called TITLE with `vulpea-create', ask for its tags and visit it.
- Vulpea writes the file, the :ID: and the tags and indexes the note.
- :CREATED: (`sp-org-created-stamp') is passed as a property; the advice on
  `vulpea-create' (below) adds it if the file lacks it.
- The file goes into the folder its tags file it under (`sp-notes-create-folder').
- A note with that title (any case) in the vulpea database is reported first."
  (interactive (list (read-string "New note title: ")))
  (require 'sp-org-link-conversion)
  (require 'vulpea)
  (let ((title (string-trim (replace-regexp-in-string "[\n\r]+" " " title))))
    (when (string-empty-p title) (user-error "Empty title"))
    (when (and (fboundp 'sp-vulpea-notes-with-title) (fboundp 'vulpea-db-query)
               (sp-vulpea-notes-with-title title)
               (not (y-or-n-p (format "A note titled \"%s\" exists.  Create another? " title))))
      (user-error "Aborted"))
    (let* ((tags (sp-org-tag-read-note-tags (format "Tags for \"%s\": " title)))
           ;; Pin the base directory, so a nil `vulpea-default-notes-directory'
           ;; cannot reach `file-name-as-directory' inside vulpea.
           (vulpea-default-notes-directory (sp-notes-create-base))
           (note (vulpea-create title (sp-notes-create-file-template tags)
                                :tags tags
                                :properties (list (cons "CREATED" (sp-org-created-stamp)))))
           (file (vulpea-note-path note)))
      (sp-notes-ensure-created file)
      (find-file file)
      (goto-char (point-max))
      file)))

;;;; Open a note

(defcustom sp-notes-open-exclude-regexp
  "\\`\\(?:\\.[^/]*\\|ltximg\\|attach\\|data\\)\\(?:/\\|\\'\\)"
  "Top-level names (relative to the root) that `sp-notes-open' does not list."
  :type 'regexp
  :group 'sp-notes-filing)

(defvar sp-notes-open--cache (make-hash-table :test #'equal)
  "File -> (MTIME . INFO), so a second call reads only the files that changed.")

(defun sp-notes-open--parse-date (string)
  "Return \"YYYY-MM-DD[ HH:MM]\" from an Org timestamp STRING, or nil."
  (when (and string
             (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)\\(?: [[:alpha:]]+\\)?\\(?: \\([0-9]\\{2\\}:[0-9]\\{2\\}\\)\\)?"
                           string))
    (concat (match-string 1 string)
            (when (match-string 2 string) (concat " " (match-string 2 string))))))

(defun sp-notes-open--name-date (name)
  "The date in the file NAME when it starts with a 14-digit id (or Denote id), or nil."
  (when (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T?\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)[0-9]\\{2\\}\\(?:[^0-9]\\|\\'\\)" name)
    (format "%s-%s-%s %s:%s" (match-string 1 name) (match-string 2 name)
            (match-string 3 name) (match-string 4 name) (match-string 5 name))))

(defun sp-notes-open--info (file)
  "Return a plist (:title :tags :created) for FILE, from its head."
  (let ((mtime (file-attribute-modification-time (file-attributes file)))
        (hit (gethash file sp-notes-open--cache)))
    (if (and hit (equal (car hit) mtime))
        (cdr hit)
      (let ((info
             (with-temp-buffer
               (insert-file-contents file nil 0 8192)
               (let* ((case-fold-search t)
                      (limit (save-excursion
                               (goto-char (point-min))
                               (if (re-search-forward "^\\*+ " nil t) (match-beginning 0) (point-max))))
                      title tags created)
                 (goto-char (point-min))
                 (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" limit t)
                   (setq title (string-trim (match-string-no-properties 1))))
                 (goto-char (point-min))
                 (while (re-search-forward "^#\\+filetags:[ \t]*\\(.*\\)$" limit t)
                   (setq tags (append tags (split-string (match-string-no-properties 1) "[: \t]+" t))))
                 (goto-char (point-min))
                 (when (re-search-forward "^[ \t]*:CREATED:[ \t]+\\(.*\\)$" limit t)
                   (setq created (sp-notes-open--parse-date (match-string-no-properties 1))))
                 (list :title title :tags tags :created created)))))
        ;; No :CREATED:?  Use the date in the file name, then the modification time.
        (unless (plist-get info :created)
          (setq info (plist-put info :created
                                (or (sp-notes-open--name-date (file-name-nondirectory file))
                                    (format-time-string "%Y-%m-%d %H:%M" mtime)))))
        (puthash file (cons mtime info) sp-notes-open--cache)
        info))))

(defun sp-notes-open--files ()
  "The org files under the root that `sp-notes-open' lists."
  (let ((root (file-name-as-directory (expand-file-name sp-notes-filing-root))))
    (seq-filter
     (lambda (f)
       (let ((rel (file-relative-name f root)))
         (and (file-regular-p f)
              (not (string-match-p "~\\'\\|/\\.#\\|^\\.#" rel))
              (not (string-match-p sp-notes-open-exclude-regexp rel)))))
     (directory-files-recursively root "\\.org\\'"))))

(defun sp-notes-open--candidates ()
  "Alist (RELATIVE-NAME . PLIST) for the notes, newest first.
The plist is `sp-notes-open--info' plus :file."
  (let* ((root (file-name-as-directory (expand-file-name sp-notes-filing-root)))
         (items (mapcar (lambda (f)
                          (cons (file-relative-name f root)
                                (append (list :file f) (sp-notes-open--info f))))
                        (sp-notes-open--files))))
    (sort items (lambda (a b) (string> (plist-get (cdr a) :created)
                                       (plist-get (cdr b) :created))))))

(defun sp-notes-open--annotate (info)
  "The picker's right-hand side for INFO: created date, tags, title."
  (let ((tags (plist-get info :tags)))
    (concat "  " (propertize (plist-get info :created) 'face 'completions-annotations)
            (when tags (concat "  " (propertize (format ":%s:" (string-join tags ":"))
                                               'face 'completions-annotations)))
            (when-let* ((title (plist-get info :title)))
              (concat "  " title)))))

;;;###autoload
(defun sp-notes-open ()
  "Pick a note from all the subfolders of the notes root and open it.
Like `denote-open': each candidate is a file name, with the creation date,
the tags and the title beside it, newest first.  The date is :CREATED:, else
the id in the file name, else the modification time."
  (interactive)
  (let* ((items (sp-notes-open--candidates))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      '(metadata
                        (category . file)
                        (display-sort-function . identity)
                        (cycle-sort-function . identity)
                        (annotation-function
                         . (lambda (c) (sp-notes-open--annotate
                                        (cdr (assoc c items))))))
                    (complete-with-action action (mapcar #'car items) string pred))))
         (choice (completing-read "Open note: " table nil t)))
    (find-file (plist-get (cdr (assoc choice items)) :file))))

;;;; File notes by tag

(defgroup sp-notes-filing nil
  "File notes into subfolders by tag."
  :group 'org
  :prefix "sp-notes-filing-")

(defcustom sp-notes-filing-root
  (or (bound-and-true-p sp-notes-dir) "~/notes")
  "The notes folder whose notes are filed."
  :type 'directory
  :group 'sp-notes-filing)

(defcustom sp-notes-filing-rules
  '((("litnote")                              . "litnotes")
    (("person")                               . "people")
    (("emacs")                                . "docs-emacs")
    (("docs" "process" "workflow" "system")   . "docs")
    (("film")                                 . "objects/films")
    (("hardware")                             . "objects/hardware")
    (("concept" "zettel")                     . "knowledge"))
  "Ordered rules (TAGS . FOLDER); the first rule with a matching tag wins.
- A rule matches a note that has any of its TAGS.
- The order is the precedence when a note has tags of several rules.
- FOLDER is relative to `sp-notes-filing-root'."
  :type '(alist :key-type (repeat string) :value-type string)
  :group 'sp-notes-filing)

(defcustom sp-notes-filing-fallback-folder "other"
  "Folder for a note that matches no rule."
  :type 'string
  :group 'sp-notes-filing)

(defcustom sp-notes-filing-protected-regexp
  "\\`\\(?:\\.[^/]*\\|inbox\\|area\\|log\\|workbook\\|search-views\\|ltximg\\|attach\\|data\\|archive\\)\\(?:/\\|\\'\\)"
  "Top-level names (relative to the root) that are never scanned.
These folders hold files that other modules address by path (inbox, GTD, logs)."
  :type 'regexp
  :group 'sp-notes-filing)

(defcustom sp-notes-filing-protected-files '("inbox.org" "dg-synthesis.org")
  "Files at the top of the root that are never moved."
  :type '(repeat string)
  :group 'sp-notes-filing)

(defcustom sp-notes-filing-strip-denote t
  "Non-nil: drop the Denote file name and #+identifier: line when filing."
  :type 'boolean
  :group 'sp-notes-filing)

(defcustom sp-notes-filing-backup-dir
  (expand-file-name "notes-filing-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Where `sp-notes-filing-apply' stores its backup, one folder per run."
  :type 'directory
  :group 'sp-notes-filing)

(defcustom sp-notes-filing-schedule-interval nil
  "Seconds between scheduled runs of `sp-notes-filing-run-scheduled', or nil."
  :type '(choice (const nil) integer)
  :group 'sp-notes-filing)

;;;; Pure rules

(defun sp-notes-filing-folder (tags)
  "Return the folder (relative) for a note with TAGS, a list of strings.
Tags are compared without regard to case.  No match gives
`sp-notes-filing-fallback-folder'."
  (let ((tags (mapcar #'downcase tags)))
    (or (cdr (seq-find (lambda (rule)
                         (seq-some (lambda (tag) (member tag tags)) (car rule)))
                       sp-notes-filing-rules))
        sp-notes-filing-fallback-folder)))

(defconst sp-notes-filing--denote-re
  "\\`\\([0-9]\\{8\\}\\)T\\([0-9]\\{6\\}\\)\\(?:==[^-_.]*\\)?\\(?:--\\([^_.]*\\)\\)?\\(?:__[^.]*\\)?\\(\\.[^/]*\\)?\\'"
  "A Denote file name: group 1-2 the date and time, 3 the title slug, 4 the extension.")

(defun sp-notes-filing-clean-name (name)
  "Return NAME without Denote conventions, keeping the identifier.
- 20240101T120000--my-title__a_b.org becomes 20240101120000_my_title.org.
- A name that is not a Denote name is returned unchanged."
  (if (string-match sp-notes-filing--denote-re name)
      (let ((id (concat (match-string 1 name) (match-string 2 name)))
            (title (match-string 3 name))
            (ext (or (match-string 4 name) "")))
        (concat id
                (if (and title (not (string-empty-p title)))
                    (concat "_" (replace-regexp-in-string "-" "_" title))
                  "")
                ext))
    name))

;;;; Reading a note

(defun sp-notes-filing--head (file)
  "Read FILE's head as a plist (:tags :id :identifier :denote-links)."
  (with-temp-buffer
    (insert-file-contents file nil 0 8192)
    (let ((case-fold-search t) tags id identifier
          (limit (save-excursion
                   (goto-char (point-min))
                   (if (re-search-forward "^\\*+ " nil t) (match-beginning 0) (point-max)))))
      (goto-char (point-min))
      (while (re-search-forward "^#\\+filetags:[ \t]*\\(.*\\)$" limit t)
        (setq tags (append tags (split-string (match-string-no-properties 1) "[: \t]+" t))))
      (goto-char (point-min))
      (when (re-search-forward "^[ \t]*:ID:[ \t]+\\([^ \t\n]+\\)" limit t)
        (setq id (match-string-no-properties 1)))
      (goto-char (point-min))
      (when (re-search-forward "^#\\+identifier:[ \t]*\\([^ \t\n]+\\)" limit t)
        (setq identifier (match-string-no-properties 1)))
      (list :tags tags :id id :identifier identifier))))

;;;; Planning

(defun sp-notes-filing--relative (file)
  "FILE relative to the root."
  (file-relative-name file (file-name-as-directory (expand-file-name sp-notes-filing-root))))

(defun sp-notes-filing--candidates (&optional top-level-only)
  "The org files to consider.
With TOP-LEVEL-ONLY, only those directly in the root."
  (let* ((root (file-name-as-directory (expand-file-name sp-notes-filing-root)))
         (files (if top-level-only
                    (directory-files root t "\\.org\\'")
                  (directory-files-recursively root "\\.org\\'"))))
    (seq-filter
     (lambda (f)
       (let ((rel (sp-notes-filing--relative f)))
         (and (file-regular-p f)
              (not (string-match-p "~\\'\\|/\\.#\\|^\\.#" rel))
              (not (string-match-p sp-notes-filing-protected-regexp rel))
              (not (member rel sp-notes-filing-protected-files)))))
     files)))

(defun sp-notes-filing--plan-file (file)
  "The plan entry for FILE, or nil if it is already where it belongs."
  (let* ((root (file-name-as-directory (expand-file-name sp-notes-filing-root)))
         (head (sp-notes-filing--head file))
         (tags (plist-get head :tags))
         (folder (sp-notes-filing-folder tags))
         (name (file-name-nondirectory file))
         (new-name (if sp-notes-filing-strip-denote (sp-notes-filing-clean-name name) name))
         (to (expand-file-name new-name (expand-file-name folder root)))
         (strip (and sp-notes-filing-strip-denote
                     (plist-get head :identifier) (plist-get head :id) t)))
    (unless (and (file-equal-p file to) (not strip))
      (list :from file :to to :tags tags :id (plist-get head :id)
            :folder folder :fallback (null (seq-find (lambda (r) (seq-some (lambda (tg) (member (downcase tg) (car r))) tags))
                                                     sp-notes-filing-rules))
            :strip-identifier strip
            :renamed (not (equal name new-name))))))

(defun sp-notes-filing-plan (&optional top-level-only)
  "Return the plan: a list of entries, with collisions marked :skip.
With TOP-LEVEL-ONLY, only notes directly in the root are planned."
  (let ((seen (make-hash-table :test #'equal)) plan)
    (dolist (file (sp-notes-filing--candidates top-level-only))
      (when-let* ((entry (sp-notes-filing--plan-file file)))
        (let ((to (plist-get entry :to)))
          (cond
           ((and (not (file-equal-p file to)) (file-exists-p to))
            (setq entry (plist-put entry :skip "target exists")))
           ((gethash to seen)
            (setq entry (plist-put entry :skip "two notes want the same target"))))
          (puthash to t seen)
          (push entry plan))))
    (nreverse plan)))

;;;; Applying

(defun sp-notes-filing--strip-identifier (file)
  "Remove the #+identifier: line from FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((case-fold-search t))
      (when (re-search-forward "^#\\+identifier:.*\n" nil t)
        (replace-match "" t t)
        (write-region nil nil file nil 'silent)))))

(defun sp-notes-filing--backup (plan stamp)
  "Copy the files of PLAN under STAMP in the backup folder; write a manifest.
Return the backup folder."
  (let* ((dir (expand-file-name stamp sp-notes-filing-backup-dir))
         (root (file-name-as-directory (expand-file-name sp-notes-filing-root))))
    (make-directory dir t)
    (with-temp-file (expand-file-name "manifest.tsv" dir)
      (dolist (e plan)
        (let* ((from (plist-get e :from))
               (copy (expand-file-name (file-relative-name from root) (expand-file-name "files/" dir))))
          (make-directory (file-name-directory copy) t)
          (copy-file from copy t t)
          (insert (file-relative-name from root) "\t"
                  (file-relative-name (plist-get e :to) root) "\n"))))
    dir))

(defun sp-notes-filing--move (entry)
  "Carry out ENTRY.  Return nil, or a string saying why it failed."
  (let* ((from (plist-get entry :from)) (to (plist-get entry :to))
         (buffer (find-buffer-visiting from)))
    (cond
     ((plist-get entry :skip) (plist-get entry :skip))
     ((and buffer (buffer-modified-p buffer)) "unsaved changes in its buffer")
     ((stringp (file-locked-p from)) "locked by another Emacs")
     (t
      (condition-case err
          (progn
            (when buffer (kill-buffer buffer))
            (when (plist-get entry :strip-identifier)
              (sp-notes-filing--strip-identifier from))
            (unless (file-equal-p from to)
              (make-directory (file-name-directory to) t)
              (rename-file from to nil))
            (when (fboundp 'vulpea-db--forget-file)
              (ignore-errors (vulpea-db--forget-file from)))
            (when-let* ((id (plist-get entry :id)))
              (ignore-errors (org-id-add-location id to)))
            (when (fboundp 'vulpea-db-update-file)
              (ignore-errors (vulpea-db-update-file to)))
            nil)
        (error (error-message-string err)))))))

(defun sp-notes-filing-apply (plan)
  "Back up, then carry out PLAN.  Return (:moved N :failed ((FILE . WHY)) :backup DIR)."
  (let* ((todo (seq-remove (lambda (e) (plist-get e :skip)) plan))
         (backup (when todo (sp-notes-filing--backup todo (format-time-string "%Y%m%d-%H%M%S"))))
         (moved 0) failed)
    (dolist (e todo)
      (if-let* ((why (sp-notes-filing--move e)))
          (push (cons (plist-get e :from) why) failed)
        (cl-incf moved)))
    (when (and (> moved 0) (fboundp 'org-id-locations-save)) (ignore-errors (org-id-locations-save)))
    (list :moved moved :failed (nreverse failed) :backup backup)))

(defun sp-notes-filing-restore (backup)
  "Undo a run: put each file of BACKUP back and remove the moved copy."
  (interactive (list (read-directory-name "Backup folder: " sp-notes-filing-backup-dir nil t)))
  (let ((root (file-name-as-directory (expand-file-name sp-notes-filing-root)))
        (n 0))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "manifest.tsv" backup))
      (dolist (line (split-string (buffer-string) "\n" t))
        (pcase-let ((`(,from ,to) (split-string line "\t")))
          (let ((src (expand-file-name from (expand-file-name "files/" backup)))
                (old (expand-file-name from root))
                (new (expand-file-name to root)))
            (make-directory (file-name-directory old) t)
            (copy-file src old t t)
            (unless (file-equal-p old new) (when (file-exists-p new) (delete-file new)))
            (cl-incf n)))))
    (message "Restored %d notes; run a vulpea rescan." n)
    n))

;;;; Rule tags must be registered

(declare-function sp-org-tag-lint-registered-tags "sp-org-tag-lint")
(declare-function sp-org-tag-add "sp-org-tag-lint")

(defun sp-notes-filing-unregistered-tags ()
  "The tags of `sp-notes-filing-rules' that are not in the tag registry."
  (when (require 'sp-org-tag-lint nil t)
    (let ((registered (sp-org-tag-lint-registered-tags)))
      (seq-remove (lambda (tag) (member tag registered))
                  (seq-uniq (apply #'append (mapcar #'car sp-notes-filing-rules))
                            #'string=)))))

(defun sp-notes-filing-check-rule-tags ()
  "Offer to register each rule tag that is not in the tag registry.
Ask once per tag; a tag that is refused stays unregistered and is reported.
Return the tags that are still unregistered."
  (dolist (tag (sp-notes-filing-unregistered-tags))
    (when (y-or-n-p (format "The filing rule tag %S is not in the tag registry.  Add it? " tag))
      (condition-case err
          (sp-org-tag-add tag)
        (user-error (message "%s" (error-message-string err))))))
  (let ((left (sp-notes-filing-unregistered-tags)))
    (when left
      (message "Unregistered filing rule tags: %s" (string-join left ", ")))
    left))

;;;; Report buffer

(defvar-local sp-notes-filing--current-plan nil)

(defvar sp-notes-filing-report-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'sp-notes-filing-convert)
    (define-key map (kbd "g") #'sp-notes-filing-dryrun)
    (define-key map (kbd "q") #'quit-window)
    map))

(define-derived-mode sp-notes-filing-report-mode sp-batch-report-mode "NotesFiling"
  "Dry-run report of `sp-notes-filing-dryrun'.  \\[sp-notes-filing-convert] applies it.")

(defun sp-notes-filing--render (plan)
  "Insert PLAN into the current buffer."
  (let ((root (file-name-as-directory (expand-file-name sp-notes-filing-root)))
        (counts (make-hash-table :test #'equal)))
    (dolist (e plan) (cl-incf (gethash (plist-get e :folder) counts 0)))
    (insert (format "#+title: Notes filing under %s: %d planned moves (dry run, nothing moved)\n"
                    sp-notes-filing-root (length plan))
            "Apply with C-c C-c (makes a backup first); g refreshes; q quits.\n\n"
            "* Per folder\n")
    (maphash (lambda (k v) (insert (format "- %s: %d\n" k v))) counts)
    (insert "\n* Moves\n")
    (dolist (e plan)
      (insert (format "- %s -> %s%s%s%s\n"
                      (sp-batch-report-file-link (plist-get e :from)
                                                 (file-relative-name (plist-get e :from) root))
                      (file-relative-name (plist-get e :to) root)
                      (if (plist-get e :fallback) "  [no matching tag]" "")
                      (if (plist-get e :strip-identifier) "  [drops #+identifier:]" "")
                      (if (plist-get e :skip) (format "  [SKIPPED: %s]" (plist-get e :skip)) ""))))))

;;;###autoload
(defun sp-notes-filing-dryrun ()
  "Show which notes would move where.  This moves nothing.
First offers to register the rule tags that the tag registry lacks."
  (interactive)
  (sp-notes-filing-check-rule-tags)
  (let ((plan (sp-notes-filing-plan)))
    (sp-batch-report-show "*Notes filing*"
                          (with-temp-buffer (sp-notes-filing--render plan) (buffer-string))
                          #'sp-notes-filing-dryrun #'sp-notes-filing-report-mode)
    (with-current-buffer "*Notes filing*"
      (setq sp-notes-filing--current-plan plan))))


(defun sp-notes-filing-convert ()
  "Apply the plan shown in this report, after confirmation."
  (interactive)
  (let ((plan sp-notes-filing--current-plan))
    (unless plan (user-error "Nothing to apply"))
    (when (yes-or-no-p (format "Move %d notes (a backup is taken first)? " (length plan)))
      (let ((res (sp-notes-filing-apply plan)))
        (message "Notes filing: %d moved, %d failed, backup in %s"
                 (plist-get res :moved) (length (plist-get res :failed))
                 (or (plist-get res :backup) "-"))
        (when (plist-get res :failed)
          (message "Failed: %S" (plist-get res :failed)))))))


;;;; Automatic placement

(defun sp-notes-filing-auto-place ()
  "File the current note if it sits at the top of the root and has tags.
Meant for `after-save-hook'.  An untagged note stays where it is."
  (when-let* ((file buffer-file-name)
              ((derived-mode-p 'org-mode))
              ((file-equal-p (file-name-directory file)
                             (file-name-as-directory (expand-file-name sp-notes-filing-root))))
              ((not (member (file-name-nondirectory file) sp-notes-filing-protected-files)))
              ((plist-get (sp-notes-filing--head file) :tags))
              (entry (sp-notes-filing--plan-file file))
              ((not (file-exists-p (plist-get entry :to)))))
    (let ((to (plist-get entry :to)))
      (make-directory (file-name-directory to) t)
      (rename-file file to)
      (set-visited-file-name to nil t)
      (set-buffer-modified-p nil)
      (when-let* ((id (plist-get entry :id))) (ignore-errors (org-id-add-location id to)))
      (when (fboundp 'vulpea-db--forget-file) (ignore-errors (vulpea-db--forget-file file)))
      (when (fboundp 'vulpea-db-update-file) (ignore-errors (vulpea-db-update-file to)))
      (message "Filed note in %s" (plist-get entry :folder)))))

;;;###autoload
(define-minor-mode sp-notes-filing-mode
  "File a note into its tag folder when it is saved."
  :global t :group 'sp-notes-filing
  (if sp-notes-filing-mode
      (add-hook 'after-save-hook #'sp-notes-filing-auto-place)
    (remove-hook 'after-save-hook #'sp-notes-filing-auto-place)))

;;;; Scheduling

;;;###autoload
(defun sp-notes-filing-run-scheduled ()
  "File the tagged notes waiting at the top of the root.  Safe for timers.
Untagged notes are left alone; only `sp-notes-filing-dryrun' sends them to other/."
  (interactive)
  (let ((plan (seq-filter (lambda (e) (and (plist-get e :tags) (not (plist-get e :skip))))
                          (sp-notes-filing-plan t))))
    (when plan (sp-notes-filing-apply plan))))

(defvar sp-notes-filing--timer nil)

(defun sp-notes-filing-schedule ()
  "(Re)start the timer according to `sp-notes-filing-schedule-interval'."
  (interactive)
  (when (timerp sp-notes-filing--timer) (cancel-timer sp-notes-filing--timer))
  (setq sp-notes-filing--timer
        (when sp-notes-filing-schedule-interval
          (run-with-timer sp-notes-filing-schedule-interval sp-notes-filing-schedule-interval
                          #'sp-notes-filing-run-scheduled))))

(sp-notes-filing-mode 1)

(provide 'sp-notes)
;;; sp-notes.el ends here
