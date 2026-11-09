;;; sp-litnotes-meta.el --- Fill literature note meta lines from BibTeX -*- lexical-binding: t; -*-

;;; Commentary:

;; A new literature note gets pub-author (linked to author notes, made when
;; missing), pub-title, pub-year, bib-parent (from the crossref) and
;; bib-project (picked) from its BibTeX entry.  It also sets read-status
;; and asks for relevance-factor and read-priority; `sp-litnotes-meta-status-report'
;; lists all statuses and changes several at once.  See the doc
;; docs/tangles/academic/sp-litnotes-meta.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'bibtex)
(require 'sp-author-notes)
(require 'sp-author-notes-bibtex)
(require 'sp-litnotes-titles)

(declare-function citar-create-note "citar")
(declare-function vulpea-db-query "vulpea-db")
(declare-function vulpea-db-query-by-tags-some "vulpea-db")
(declare-function vulpea-db-get-by-id "vulpea-db")
(declare-function vulpea-note-id "vulpea-note")
(declare-function vulpea-note-title "vulpea-note")
(declare-function vulpea-note-tags "vulpea-note")
(declare-function vulpea-note-level "vulpea-note")
(declare-function sp-org--write-note "sp-org-link-conversion")

(defgroup sp-litnotes-meta nil
  "Fill literature note meta lines from BibTeX."
  :group 'sp-author-notes
  :prefix "sp-litnotes-meta-")

(defcustom sp-litnotes-meta-auto t
  "Non-nil to fill every note that `citar-create-note' makes."
  :type 'boolean
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-default-project
  '("806b08ac-3ed1-4338-a26e-3af9e0e9328c" . "Devalorizarea artei în capitalismul de platformă")
  "The default of the bib-project picker, as (ID . TITLE)."
  :type '(cons string string)
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-project-tag "project"
  "The tag of the notes the bib-project picker offers."
  :type 'string
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-offer-parent t
  "Non-nil to offer to create the literature note of a crossref'd entry that has none."
  :type 'boolean
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-initial-read-status "02-preparing"
  "The read-status a new literature note gets, without asking."
  :type 'string
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-read-statuses
  '("01-current" "02-preparing" "03-review" "04-paused" "05-done")
  "The allowed values of read-status, in order.
Keep this in step with the schema in `sp-vulpea-schemas'."
  :type '(repeat string)
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-relevance-scale '("01" "02" "03" "04" "05")
  "The allowed values of relevance-factor; 01 is the most relevant."
  :type '(repeat string)
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-priority-scale '("01" "02" "03" "04" "05")
  "The allowed values of read-priority; 01 is read first."
  :type '(repeat string)
  :group 'sp-litnotes-meta)

(defvar sp-litnotes-meta--preset nil
  "An alist of meta key to value that `sp-litnotes-meta-fill' uses instead of asking.
A value of nil in it means: leave the line out, do not ask.")

(defvar sp-litnotes-meta--depth 0
  "How many parent notes are being made inside each other.")

(defvar sp-litnotes-meta--created (make-hash-table :test #'equal)
  "Author notes made in this session: title key to (ID . TITLE).")

(defvar sp-litnotes-meta--index nil
  "Hash table of BibTeX key to entry, or nil to read the files for each key.
Made by `sp-litnotes-meta-build-index'.")

(defun sp-litnotes-meta--index-file (file table)
  "Add the entries of the .bib FILE to the hash TABLE (key to entry).
A key that is already in TABLE keeps its first entry."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
    (delay-mode-hooks (bibtex-mode))
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*@[[:alpha:]]+[ \t]*[{(]" nil t)
      (let ((beg (match-beginning 0)))
        (goto-char beg)
        (when-let* ((entry (ignore-errors (bibtex-parse-entry t)))
                    (key (cdr (assoc "=key=" entry))))
          (unless (gethash key table) (puthash key entry table)))
        (goto-char (min (point-max) (1+ beg)))))))

(defun sp-litnotes-meta-build-index ()
  "Read the registered .bib files once; set `sp-litnotes-meta--index' to the result.
Signal a `user-error' when there is no .bib file."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file (sp-author-notes-bibtex--files))
      (sp-litnotes-meta--index-file file table))
    (setq sp-litnotes-meta--index table)))

(defun sp-litnotes-meta--entry (key)
  "The BibTeX entry KEY from the registered files, as an alist, or nil."
  (if sp-litnotes-meta--index
      (gethash key sp-litnotes-meta--index)
    (sp-litnotes-meta--entry-from-files key)))

(defun sp-litnotes-meta--entry-from-files (key)
  "The BibTeX entry KEY, read from the registered files, or nil."
  (catch 'found
    (dolist (file (sp-author-notes-bibtex--files))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
        (delay-mode-hooks (bibtex-mode))
        (goto-char (point-min))
        (when (re-search-forward
               (format "^[ \t]*@[[:alpha:]]+[ \t]*[{(][ \t]*%s[ \t]*," (regexp-quote key)) nil t)
          (goto-char (match-beginning 0))
          (when-let* ((entry (ignore-errors (bibtex-parse-entry t))))
            (throw 'found entry)))))))

(defun sp-litnotes-meta--field (entry name)
  "The field NAME of ENTRY, braces removed and white space collapsed, or nil."
  (when-let* ((value (cdr (assoc-string name entry t)))
              (clean (string-trim (replace-regexp-in-string
                                   "[ \t\n]+" " "
                                   (replace-regexp-in-string
                                    "[{}]" "" (sp-author-notes-latex-to-unicode value))))))
    (and (not (string-empty-p clean)) clean)))

(defun sp-litnotes-meta--year (entry)
  "The year of ENTRY: its year, the year in its date, else that of its crossref."
  (or (when-let* ((year (sp-litnotes-meta--field entry "year")))
        (and (string-match "[0-9]\\{4\\}" year) (match-string 0 year)))
      (when-let* ((date (sp-litnotes-meta--field entry "date")))
        (and (string-match "\\`[0-9]\\{4\\}" date) (match-string 0 date)))
      (when-let* ((ref (sp-litnotes-meta--field entry "crossref"))
                  (parent (sp-litnotes-meta--entry ref)))
        (or (sp-litnotes-meta--field parent "year")
            (when-let* ((date (sp-litnotes-meta--field parent "date")))
              (and (string-match "\\`[0-9]\\{4\\}" date) (match-string 0 date)))))))

(defun sp-litnotes-meta--author-names (entry &optional field)
  "The names in the FIELD of ENTRY (default author), as First Last."
  (when-let* ((text (sp-litnotes-meta--field entry (or field "author"))))
    (sp-author-notes-bibtex--split-authors text)))

(defun sp-litnotes-meta--person-p (note)
  "Non-nil when the Vulpea NOTE has `sp-author-notes-person-tag'."
  (member sp-author-notes-person-tag (vulpea-note-tags note)))

(defun sp-litnotes-meta--find-person (name)
  "The note for NAME as (ID . TITLE), or nil.  Several are an error to resolve by asking."
  (let* ((key (sp-author-notes--title-key name))
         (hits (vulpea-db-query
                (lambda (note)
                  (let ((title (vulpea-note-title note)))
                    (and (stringp title)
                         (eql 0 (vulpea-note-level note))
                         (equal (sp-author-notes--title-key title) key))))))
         (persons (seq-filter #'sp-litnotes-meta--person-p hits))
         (pool (or persons hits)))
    (cond
     ((null pool) (gethash key sp-litnotes-meta--created))
     ((null (cdr pool)) (cons (vulpea-note-id (car pool)) (vulpea-note-title (car pool))))
     (t (let* ((alist (mapcar (lambda (n) (cons (format "%s [%s]" (vulpea-note-title n)
                                                       (vulpea-note-id n))
                                                n))
                              pool))
               (pick (cdr (assoc (completing-read (format "Which note is %s? " name)
                                                  (mapcar #'car alist) nil t)
                                 alist))))
          (cons (vulpea-note-id pick) (vulpea-note-title pick)))))))

(defun sp-litnotes-meta--author-note (name)
  "The author note of NAME as (ID . TITLE); make it when there is none."
  (or (sp-litnotes-meta--find-person name)
      (progn
        (require 'sp-org-link-conversion)
        (let ((id (sp-org--write-note name (list sp-author-notes-person-tag))))
          (message "Made the author note %s" name)
          (puthash (sp-author-notes--title-key name) (cons id name)
                   sp-litnotes-meta--created)))))

(defun sp-litnotes-meta--link (target)
  "The Org link for TARGET, (ID . TITLE)."
  (format "[[id:%s][%s]]" (car target) (cdr target)))

(defun sp-litnotes-meta--authors-value (entry &optional field)
  "The links to the people in the FIELD of ENTRY (default author), or nil."
  (when-let* ((names (sp-litnotes-meta--author-names entry field)))
    (mapconcat (lambda (name) (sp-litnotes-meta--link (sp-litnotes-meta--author-note name)))
               names ", ")))

(defun sp-litnotes-meta--note-for-key (key)
  "The literature note of the citation KEY as (ID . TITLE), or nil."
  (when-let* ((file (gethash key (sp-author-notes-bibtex--covered)))
              (head (sp-author-notes--file-head file))
              (id (plist-get head :id)))
    (cons id (or (plist-get head :title) key))))

(defun sp-litnotes-meta--parent-value (entry)
  "The bib-parent value for ENTRY: a link to the note of its crossref, or nil."
  (when-let* ((ref (sp-litnotes-meta--field entry "crossref")))
    (or (when-let* ((target (sp-litnotes-meta--note-for-key ref)))
          (sp-litnotes-meta--link target))
        (when (and sp-litnotes-meta-offer-parent
                   (< sp-litnotes-meta--depth 3)
                   (y-or-n-p (format "%s has no literature note.  Create it? " ref)))
          (let ((sp-litnotes-meta--depth (1+ sp-litnotes-meta--depth)))
            (citar-create-note ref)
            ;; The advice fills it; fill it here when the advice is off.
            (unless sp-litnotes-meta-auto
              (ignore-errors (sp-litnotes-meta-fill ref))))
          (when-let* ((target (sp-litnotes-meta--note-for-key ref)))
            (sp-litnotes-meta--link target)))
        (progn (message "sp-litnotes-meta: %s has no literature note, bib-parent left empty" ref)
               nil))))

(defun sp-litnotes-meta--read-project ()
  "Pick a project in the minibuffer; return its link.  The default is the thesis."
  (let* ((default (let ((id (car sp-litnotes-meta-default-project)))
                    (or (when-let* ((note (vulpea-db-get-by-id id)))
                          (cons id (vulpea-note-title note)))
                        sp-litnotes-meta-default-project)))
         (alist (mapcar (lambda (n) (cons (vulpea-note-title n) (cons (vulpea-note-id n) (vulpea-note-title n))))
                        (vulpea-db-query-by-tags-some (list sp-litnotes-meta-project-tag))))
         (alist (if (assoc (cdr default) alist) alist (cons (cons (cdr default) default) alist)))
         (choice (completing-read (format "bib-project (default %s): " (cdr default))
                                  (mapcar #'car alist) nil t nil nil (cdr default))))
    (sp-litnotes-meta--link (cdr (assoc choice alist)))))

(defun sp-litnotes-meta--read-scale (prompt scale)
  "Ask PROMPT for one of SCALE; return the answer, or nil when empty."
  (let ((answer (string-trim (completing-read prompt scale nil t))))
    (and (not (string-empty-p answer)) answer)))

(defun sp-litnotes-meta--read-relevance ()
  "Ask for the relevance-factor."
  (sp-litnotes-meta--read-scale "relevance-factor (01 = most relevant, empty to skip): "
                                sp-litnotes-meta-relevance-scale))

(defun sp-litnotes-meta--read-priority ()
  "Ask for the read-priority."
  (sp-litnotes-meta--read-scale "read-priority (01 = read first, empty to skip): "
                                sp-litnotes-meta-priority-scale))

(defconst sp-litnotes-meta--line-re "^-[ \t]+%s[ \t]+::\\(.*\\)$")

(defun sp-litnotes-meta--has-value-p (key)
  "Non-nil when the first section of the buffer has a KEY line with a value."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t))
      (and (re-search-forward (format sp-litnotes-meta--line-re (regexp-quote key))
                              (sp-author-notes--first-heading) t)
           (not (string-empty-p (string-trim (match-string 1))))))))

(defun sp-litnotes-meta--set (key value)
  "Set the meta line KEY to VALUE in the first section of the buffer.
Return `added' or `filled', or nil when the line already has a value."
  (save-excursion
    (save-restriction
      (widen)
      (let ((limit (sp-author-notes--first-heading))
            (case-fold-search t))
        (goto-char (point-min))
        (cond
         ((re-search-forward (format sp-litnotes-meta--line-re (regexp-quote key)) limit t)
          (when (string-empty-p (string-trim (match-string 1)))
            (replace-match (concat " " value) t t nil 1)
            'filled))
         (t
          (goto-char (point-min))
          (if (re-search-forward "^-[ \t]+[^ \t\n:]+[ \t]+::.*$" limit t)
              (progn (while (re-search-forward "^-[ \t]+[^ \t\n:]+[ \t]+::.*$" limit t))
                     (end-of-line)
                     (insert "\n"))
            (goto-char limit)
            (unless (bolp) (insert "\n"))
            (insert "\n"))
          (insert (format "- %s :: %s" key value))
          (unless (eq (char-after) ?\n) (insert "\n"))
          'added))))))

(defun sp-litnotes-meta--buffer-key ()
  "The first citation key of the ROAM_REFS of the current buffer, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^:ROAM_REFS:[ \t]*\\(.*\\)$" (sp-author-notes--first-heading) t)
      (car (sp-litnotes-titles--keys (match-string 1))))))

;;;###autoload
(defun sp-litnotes-meta-fill (key &optional file)
  "Fill the meta lines of the literature note of KEY from its BibTeX entry.
FILE is the note; by default the current buffer's file, else the note
found for KEY.  Lines that have a value are left alone.  Return the
lines that were changed."
  (interactive (list (or (sp-litnotes-meta--buffer-key)
                         (user-error "No citation key in the ROAM_REFS of this buffer"))
                     buffer-file-name))
  (let* ((entry (or (sp-litnotes-meta--entry key)
                    (user-error "No BibTeX entry %s in the registered files" key)))
         (file (or file (gethash key (sp-author-notes-bibtex--covered))
                   (user-error "No literature note found for %s" key)))
         (buf (find-buffer-visiting file)))
    (when (and buf (buffer-modified-p buf))
      (user-error "%s has unsaved changes; save it first" (file-name-nondirectory file)))
    (with-current-buffer (or buf (find-file-noselect file))
      (let (changed)
        ;; Ask and look up only what the note still lacks.
        (dolist (spec `(("pub-author" . ,(lambda () (sp-litnotes-meta--authors-value entry)))
                        ("pub-editor" . ,(lambda () (sp-litnotes-meta--authors-value entry "editor")))
                        ("pub-title" . ,(lambda () (sp-litnotes-meta--field entry "title")))
                        ("pub-year" . ,(lambda () (sp-litnotes-meta--year entry)))
                        ("bib-parent" . ,(lambda () (sp-litnotes-meta--parent-value entry)))
                        ("bib-project" . ,#'sp-litnotes-meta--read-project)
                        ("read-status" . ,(lambda () sp-litnotes-meta-initial-read-status))
                        ("relevance-factor" . ,#'sp-litnotes-meta--read-relevance)
                        ("read-priority" . ,#'sp-litnotes-meta--read-priority)))
          (unless (sp-litnotes-meta--has-value-p (car spec))
            (when-let* ((value (if-let* ((preset (assoc (car spec) sp-litnotes-meta--preset)))
                                   (cdr preset)
                                 (funcall (cdr spec))))
                        (how (sp-litnotes-meta--set (car spec) value)))
              (push (car spec) changed))))
        (when changed (save-buffer))
        (unless buf (kill-buffer))
        (nreverse changed)))))

;;;; Read-status report

(defvar sp-litnotes-meta--status-keys '("read-status" "read-priority" "relevance-factor")
  "The meta keys the status report shows, in column order.")

(defun sp-litnotes-meta--file-meta (file)
  "The title and the status keys of the litnote FILE, as a plist.
The values are strings (empty when missing)."
  (with-temp-buffer
    (sp-author-notes--insert-file file 4096)
    (let ((case-fold-search t)
          (limit (sp-author-notes--first-heading))
          (title ""))
      (goto-char (point-min))
      (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" limit t)
        (setq title (string-trim (match-string 1))))
      (cons :title
            (cons title
                  (mapcan (lambda (key)
                            (goto-char (point-min))
                            (list (intern (concat ":" key))
                                  (if (re-search-forward (format sp-litnotes-meta--line-re (regexp-quote key))
                                                         limit t)
                                      (string-trim (match-string 1))
                                    "")))
                          sp-litnotes-meta--status-keys))))))

(defun sp-litnotes-meta--put (key value)
  "Set the meta line KEY to VALUE in the current buffer, replacing any value."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (if (re-search-forward (format sp-litnotes-meta--line-re (regexp-quote key))
                               (sp-author-notes--first-heading) t)
            (replace-match (concat " " value) t t nil 1)
          (sp-litnotes-meta--set key value))))))

(defun sp-litnotes-meta-set-status (file status)
  "Set the read-status of the litnote FILE to STATUS and save it."
  (let ((buf (find-buffer-visiting file)))
    (when (and buf (buffer-modified-p buf))
      (user-error "%s has unsaved changes; save it first" (file-name-nondirectory file)))
    (with-current-buffer (or buf (find-file-noselect file))
      (sp-litnotes-meta--put "read-status" status)
      (save-buffer)
      (unless buf (kill-buffer)))))

(defun sp-litnotes-meta--status-files ()
  "The litnote files the report lists."
  (directory-files sp-author-notes-litnotes-directory t "\\.org\\'" t))

(defvar-local sp-litnotes-meta--marked nil
  "The files marked in the status report.")

(defun sp-litnotes-meta--status-entries ()
  "The `tabulated-list-entries' of the status report."
  (mapcar
   (lambda (file)
     (let* ((meta (sp-litnotes-meta--file-meta file))
            (status (plist-get meta :read-status))
            (bad (not (member status sp-litnotes-meta-read-statuses))))
       (list file
             (vector (if (member file sp-litnotes-meta--marked) "*" "")
                     (if bad (propertize (if (string-empty-p status) "(none)" status)
                                         'face 'warning)
                       status)
                     (plist-get meta :read-priority)
                     (plist-get meta :relevance-factor)
                     (plist-get meta :title)))))
   (sp-litnotes-meta--status-files)))

(defun sp-litnotes-meta--status-header ()
  "The header line: how many notes have each status."
  (let ((counts (make-hash-table :test #'equal)) (other 0))
    (dolist (entry tabulated-list-entries)
      (let ((status (substring-no-properties (aref (cadr entry) 1))))
        (if (member status sp-litnotes-meta-read-statuses)
            (cl-incf (gethash status counts 0))
          (cl-incf other))))
    (concat (mapconcat (lambda (s) (format "%s: %d" s (gethash s counts 0)))
                       sp-litnotes-meta-read-statuses "  ")
            (format "  other: %d  marked: %d" other (length sp-litnotes-meta--marked)))))

;; Shift-selecting lines (or any active region) acts on every note in it.
(defun sp-litnotes-meta--region-files ()
  "The files of the notes on the lines of the active region, or nil.
A region ending at the start of a line does not include that line."
  (when (use-region-p)
    (let ((beg (region-beginning)) (end (region-end)) files)
      (save-excursion
        (goto-char beg)
        (beginning-of-line)
        (while (and (not (eobp)) (< (point) end))
          (when-let* ((file (tabulated-list-get-id)))
            (push file files))
          (forward-line 1)))
      (nreverse files))))

(defun sp-litnotes-meta--status-set-marks (add)
  "Mark (when ADD) or unmark the notes in the region, else the note at point."
  (let ((files (or (sp-litnotes-meta--region-files)
                   (and (tabulated-list-get-id) (list (tabulated-list-get-id))))))
    (when files
      (dolist (file files)
        (if add
            (cl-pushnew file sp-litnotes-meta--marked :test #'equal)
          (setq sp-litnotes-meta--marked (delete file sp-litnotes-meta--marked))))
      (deactivate-mark)
      (sp-litnotes-meta-status-refresh)
      (forward-line 1))))

(defun sp-litnotes-meta-status-mark ()
  "Mark the note at point, or all notes in the active region, and move down."
  (interactive)
  (sp-litnotes-meta--status-set-marks t))

(defun sp-litnotes-meta-status-unmark ()
  "Unmark the note at point, or all notes in the active region, and move down."
  (interactive)
  (sp-litnotes-meta--status-set-marks nil))

(defun sp-litnotes-meta-status-mark-status (status)
  "Mark every listed note whose read-status is STATUS."
  (interactive (list (completing-read "Mark notes with status: "
                                      (append sp-litnotes-meta-read-statuses '("(none)")) nil t)))
  (dolist (entry tabulated-list-entries)
    (when (equal (substring-no-properties (aref (cadr entry) 1)) status)
      (cl-pushnew (car entry) sp-litnotes-meta--marked :test #'equal)))
  (sp-litnotes-meta-status-refresh))

(defun sp-litnotes-meta-status-unmark-all ()
  "Remove all marks."
  (interactive)
  (setq sp-litnotes-meta--marked nil)
  (sp-litnotes-meta-status-refresh))

(defun sp-litnotes-meta-status-change (status)
  "Set the read-status to STATUS on the marked notes.
Without marks, use the notes in the active region, else the note at point."
  (interactive (list (completing-read "New read-status: " sp-litnotes-meta-read-statuses nil t)))
  (let ((files (or sp-litnotes-meta--marked
                   (sp-litnotes-meta--region-files)
                   (and (tabulated-list-get-id) (list (tabulated-list-get-id))))))
    (unless files (user-error "No note at point"))
    (dolist (file files) (sp-litnotes-meta-set-status file status))
    (setq sp-litnotes-meta--marked nil)
    (deactivate-mark)
    (sp-litnotes-meta-status-refresh)
    (message "Set read-status %s on %d note%s" status (length files)
             (if (cdr files) "s" ""))))

(defun sp-litnotes-meta-status-visit ()
  "Open the note at point."
  (interactive)
  (when-let* ((file (tabulated-list-get-id)))
    (find-file file)))

(defun sp-litnotes-meta-status-refresh ()
  "Rescan the notes."
  (interactive)
  (let ((line (line-number-at-pos)))
    (setq tabulated-list-entries (sp-litnotes-meta--status-entries))
    (tabulated-list-print t)
    (setq header-line-format (sp-litnotes-meta--status-header))
    (goto-char (point-min))
    (forward-line (1- line))))

(defvar sp-litnotes-meta-status-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map "m" #'sp-litnotes-meta-status-mark)
    (define-key map "u" #'sp-litnotes-meta-status-unmark)
    (define-key map "M" #'sp-litnotes-meta-status-mark-status)
    (define-key map "U" #'sp-litnotes-meta-status-unmark-all)
    (define-key map "s" #'sp-litnotes-meta-status-change)
    (define-key map "g" #'sp-litnotes-meta-status-refresh)
    (define-key map (kbd "RET") #'sp-litnotes-meta-status-visit)
    map)
  "Keys of `sp-litnotes-meta-status-mode'.")

(define-derived-mode sp-litnotes-meta-status-mode tabulated-list-mode "LitStatus"
  "List the litnotes with their read-status; mark several and change them.
\\{sp-litnotes-meta-status-mode-map}"
  (setq tabulated-list-format [("" 1 nil) ("read-status" 12 t) ("priority" 8 t)
                               ("relevance" 9 t) ("title" 0 t)]
        tabulated-list-sort-key '("read-status")
        tabulated-list-padding 1)
  (tabulated-list-init-header))

;;;###autoload
(defun sp-litnotes-meta-status-report ()
  "Show every litnote with its read-status, priority and relevance.
Statuses outside `sp-litnotes-meta-read-statuses' are shown as a warning.
Mark notes with \\`m' (or all of one status with \\`M'), then press \\`s' to change their
read-status.  Shift-select several lines (or set any region) and \\`m', \\`u' or \\`s'
act on all of them."
  (interactive)
  (with-current-buffer (get-buffer-create "*litnote status*")
    (sp-litnotes-meta-status-mode)
    (sp-litnotes-meta-status-refresh)
    (pop-to-buffer (current-buffer))))

;;;; Backfill the chapters of a book

(defun sp-litnotes-meta--children (key)
  "The BibTeX entries whose crossref is KEY, as plists (:key :title :type).
Entries that already have a litnote are left out."
  (let ((covered (sp-author-notes-bibtex--covered))
        (seen (make-hash-table :test #'equal))
        found)
    (dolist (file (sp-author-notes-bibtex--files))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
        (delay-mode-hooks (bibtex-mode))
        (goto-char (point-min))
        (while (re-search-forward "^[ \t]*@[[:alpha:]]+[ \t]*[{(]" nil t)
          (goto-char (match-beginning 0))
          (let ((entry (ignore-errors (bibtex-parse-entry t))))
            (when-let* ((child (and entry (cdr (assoc "=key=" entry))))
                        (ref (sp-litnotes-meta--field entry "crossref")))
              (when (and (string-equal-ignore-case ref key)
                         (not (gethash child covered))
                         (not (gethash child seen)))
                (puthash child t seen)
                (push (list :key child
                            :type (cdr (assoc "=type=" entry))
                            :title (or (sp-litnotes-meta--field entry "title") ""))
                      found))))
          (goto-char (min (point-max) (1+ (point)))))))
    (nreverse found)))

(defun sp-litnotes-meta--buffer-meta (key)
  "The raw value of the meta line KEY in the current buffer, or nil."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t))
      (when (re-search-forward (format sp-litnotes-meta--line-re (regexp-quote key))
                               (sp-author-notes--first-heading) t)
        (let ((value (string-trim (match-string 1))))
          (and (not (string-empty-p value)) value))))))

;;;; Clean up a note made by `citar-create-note'

(declare-function sp-litnotes-titles-format "sp-litnotes-titles")
(defvar citar-notes-sources)
(defvar citar-notes-source)

(defcustom sp-litnotes-meta-new-title 'standard
  "What the title of a litnote made by the backfill is.
`title' is the title of the BibTeX entry alone.  `standard' is the
Chicago-style \"Last (Year) Title\" that `sp-litnotes-titles-convert' writes."
  :type '(choice (const :tag "The title only" title)
                 (const :tag "Last (Year) Title" standard))
  :group 'sp-litnotes-meta)

(defun sp-litnotes-meta--new-title (entry)
  "The title for a new note of the BibTeX ENTRY, per `sp-litnotes-meta-new-title'."
  (let ((title (sp-litnotes-meta--field entry "title")))
    (if (and title (eq sp-litnotes-meta-new-title 'standard))
        (let ((names (mapcar #'sp-litnotes-titles--split-name
                             (sp-litnotes-meta--author-names entry)))
              (year (sp-litnotes-meta--year entry)))
          (if (and names year)
              (sp-litnotes-titles-format names year title)
            title))
      title)))

(defun sp-litnotes-meta--tidy-new-note (key)
  "Give the note just made for KEY a plain title and drop the bibliography block.
Citar's own note template writes \"#+title: Notes on ...\" and a
\"#+print_bibliography:\" line (the Org-cite marker that prints the
bibliography of the note, of no use in a litnote).  Return non-nil if the
note changed."
  (when-let* ((file (gethash key (sp-author-notes-bibtex--covered)))
              (entry (sp-litnotes-meta--entry key))
              (title (sp-litnotes-meta--new-title entry)))
    (let* ((buf (find-buffer-visiting file))
           (changed nil))
      (with-current-buffer (or buf (find-file-noselect file))
        (save-excursion
          (save-restriction
            (widen)
            (let ((case-fold-search t))
              (goto-char (point-min))
              (when (re-search-forward "^#\\+title:[ \t]*\\(Notes on .*\\)$" nil t)
                (replace-match title t t nil 1)
                (setq changed t))
              (goto-char (point-min))
              (while (re-search-forward "^#\\+print_bibliography:.*\n?" nil t)
                (replace-match "" t t)
                (setq changed t)))))
        (when changed (save-buffer))
        (unless buf (kill-buffer)))
      changed)))

;;;; Show the children in the table of the book

(declare-function sp-collec-query-dblock-has-block-p "sp-collection-query-tables-org")
(declare-function sp-collec-query-dblock-update-buffer "sp-collection-query-tables-org")
(declare-function org-create-dblock "org")
(declare-function org-update-dblock "org")
(declare-function vulpea-db-update-file "vulpea-db")

(defconst sp-litnotes-meta--collection-types
  '("collection" "mvcollection" "proceedings" "mvproceedings")
  "BibTeX entry types that get the \"collection-articles\" view; others get \"book-sections\".")

(defun sp-litnotes-meta--table-view (key)
  "The built-in view name for the table of the children of KEY."
  (let ((type (cdr (assoc "=type=" (let ((bibtex-dialect 'biblatex)) ; knows @collection
                                     (sp-litnotes-meta--entry key))))))
    (if (and type (member-ignore-case type sp-litnotes-meta--collection-types))
        "collection-articles"
      "book-sections")))

(defun sp-litnotes-meta--ensure-table (key made)
  "Make the current note show a table of its children, and refresh it.
KEY is the citation key of the note; MADE the keys of the notes just made,
which are put in the Vulpea database first.  Insert a
`collection-query-table' block with the view for KEY, above the first
heading, when the note has none.  Return `inserted', `updated' or nil."
  (when (and (derived-mode-p 'org-mode)
             (require 'sp-collection-query-tables-org nil t)
             (fboundp 'sp-collec-query-dblock-update-buffer))
    (let ((covered (ignore-errors (sp-author-notes-bibtex--covered)))
          (was-modified (buffer-modified-p))
          (how 'updated))
      (when (fboundp 'vulpea-db-update-file)
        (dolist (child made)
          (when-let* ((file (and covered (gethash child covered))))
            (ignore-errors (vulpea-db-update-file file)))))
      (unless (sp-collec-query-dblock-has-block-p)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (sp-author-notes--first-heading))
            (unless (or (eobp) (bolp)) (insert "\n"))
            (if (eobp)
                (unless (or (bobp) (bolp)) (insert "\n"))
              (insert "\n")
              (forward-line -1))
            (org-create-dblock (list :name "collection-query-table"
                                     :view (sp-litnotes-meta--table-view key)))))
        (setq how 'inserted))
      (sp-collec-query-dblock-update-buffer)
      (when (and buffer-file-name (not was-modified) (buffer-modified-p))
        (save-buffer))
      how)))

;;;###autoload
(defun sp-litnotes-meta-backfill-children (key &optional children all)
  "Make the litnotes of the BibTeX entries that have KEY as their crossref.
Interactively KEY is the citation key of the note you are in, a book or
a collection, and you pick the entries in the minibuffer (an empty answer
takes all of them).  With a prefix argument, or ALL, every entry without a
note is taken and nothing is picked.  Each new note goes through
`citar-create-note', so it is filled like any other, with the parent
linked in bib-parent.  bib-project is copied from this note;
relevance-factor and read-priority are asked once for the whole batch.
CHILDREN, a list of keys, skips the questions.

When this is an Org buffer, it then makes sure the note has a
`collection-query-table' block (view \"book-sections\", or
\"collection-articles\" for a collection) and updates it, so the new
notes show in the table.  Return the keys that got a note."
  (interactive (list (or (sp-litnotes-meta--buffer-key)
                         (user-error "No citation key in the ROAM_REFS of this buffer"))
                     nil current-prefix-arg))
  (let* ((candidates (sp-litnotes-meta--children key))
         (_ (unless (or candidates all)
              (user-error "No BibTeX entry without a note has crossref %s" key)))
         (labels (mapcar (lambda (c) (cons (format "%s  %s" (plist-get c :key) (plist-get c :title)) c))
                         candidates))
         (keys (cond (children children)
                     (all (mapcar (lambda (c) (plist-get c :key)) candidates))
                     (t (let ((picked (completing-read-multiple
                                       (format "Make notes for (%d without one; empty = all): " (length labels))
                                       (mapcar #'car labels) nil t)))
                          (mapcar (lambda (l) (plist-get (cdr (assoc l labels)) :key))
                                  (or picked (mapcar #'car labels)))))))
         (project (and (derived-mode-p 'org-mode) (sp-litnotes-meta--buffer-meta "bib-project")))
         (preset (append (and project `(("bib-project" . ,project)))
                         (unless (or children (null keys))
                           (list (cons "relevance-factor" (sp-litnotes-meta--read-relevance))
                                 (cons "read-priority" (sp-litnotes-meta--read-priority))))))
         (sp-litnotes-meta--preset preset)
         (origin (current-buffer))
         made)
    (dolist (child keys)
      (condition-case err
          (progn
            ;; Always the Vulpea source, so citar's own file template
            ;; ("Notes on ...", a bibliography block) is not used.
            (let ((citar-notes-source (if (and (boundp 'citar-notes-sources)
                                               (assq 'citar-vulpea citar-notes-sources))
                                          'citar-vulpea
                                        (bound-and-true-p citar-notes-source))))
              (citar-create-note child))
            ;; The advice fills it; fill it here when the advice is off.
            (unless sp-litnotes-meta-auto
              (sp-litnotes-meta-fill child))
            (sp-litnotes-meta--tidy-new-note child)
            (push child made))
        (error (message "sp-litnotes-meta: %s: %s" child (error-message-string err)))))
    (setq made (nreverse made))
    ;; citar may have shown a new note; the table belongs in the book's note.
    (let ((table (with-current-buffer origin
                   (condition-case err
                       (sp-litnotes-meta--ensure-table key made)
                     (error (message "sp-litnotes-meta: table: %s" (error-message-string err))
                            nil)))))
      (message "Made %d of %d notes for the entries that cross-reference %s%s"
               (length made) (length keys) key
               (pcase table ('inserted ", table added") ('updated ", table updated") (_ ""))))
    made))

;;;###autoload
(defun sp-litnotes-meta-backfill-all-children (key)
  "Make the notes of all BibTeX entries that cross-reference KEY, picking none.
Same as `sp-litnotes-meta-backfill-children' with a prefix argument; the
table in the note is created or refreshed afterwards."
  (interactive (list (or (sp-litnotes-meta--buffer-key)
                         (user-error "No citation key in the ROAM_REFS of this buffer"))))
  (sp-litnotes-meta-backfill-children key nil t))

(defun sp-litnotes-meta--after-create (key &rest _)
  "Fill the note `citar-create-note' made for KEY, when `sp-litnotes-meta-auto'."
  (when (and sp-litnotes-meta-auto (stringp key))
    (condition-case err
        (sp-litnotes-meta-fill key)
      (error (message "sp-litnotes-meta: %s: %s" key (error-message-string err))))))

(advice-add 'citar-create-note :after #'sp-litnotes-meta--after-create)

(provide 'sp-litnotes-meta)
;; sp-litnotes-meta.el ends here
