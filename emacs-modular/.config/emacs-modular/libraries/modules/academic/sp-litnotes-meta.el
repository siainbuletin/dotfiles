;;; sp-litnotes-meta.el --- Fill literature note meta lines from BibTeX -*- lexical-binding: t; -*-

;;; Commentary:

;; A new literature note gets pub-author (linked to author notes, made when
;; missing), pub-title, pub-year, pub-pages, bib-parent (from the crossref) and
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
(require 'sp-batch-report)
(require 'sp-echo-hints)
(require 'sp-bibtex-types)
(require 'sp-vulpea-meta-order)

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

(defcustom sp-litnotes-meta-create-parent t
  "Non-nil to make the literature note of a crossref'd entry that has none.
The note is made like those of `sp-litnotes-meta-backfill-children', filled
from BibTeX, and linked in bib-parent.  Nil leaves bib-parent out instead."
  :type 'boolean
  :group 'sp-litnotes-meta)

(define-obsolete-variable-alias 'sp-litnotes-meta-offer-parent
  'sp-litnotes-meta-create-parent "2026-11-09")

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

(defcustom sp-litnotes-meta-order-meta t
  "Non-nil to order the meta lines by key (`sp-vulpea-meta-order') after a fill.
This is for `sp-litnotes-meta-fill' and the batch commands."
  :type 'boolean
  :group 'sp-litnotes-meta)

(defvar sp-litnotes-meta--preset nil
  "An alist of meta key to value that `sp-litnotes-meta-fill' uses instead of asking.
A value of nil in it means: leave the line out, do not ask.")

(defvar sp-litnotes-meta--made-parents nil
  "A hash table of citation key to (ID . TITLE) for the parent notes made in this run, or nil.
The batch binds it: its table of existing notes is read once, so it does not see them.")

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

(defconst sp-litnotes-meta--quote-pairs
  '((?\" . ?\") (?\u201C . ?\u201D) (?\u201E . ?\u201C) (?\u2018 . ?\u2019) (?\' . ?\'))
  "Opening and closing quote characters that `sp-litnotes-meta--unquote' strips.
Straight and curly, double and single, and the German low-high pair.")

(defun sp-litnotes-meta--wrapped-p (value)
  "Non-nil when the first character of VALUE is a quote closed by its last character.
The quote must enclose the whole value: in `\"A\" and \"B\"' the first one closes
after the A, so it does not."
  (let* ((open (aref value 0))
         (close (cdr (assq open sp-litnotes-meta--quote-pairs)))
         (last (1- (length value)))
         (depth 0) (ok t) (i 0))
    (while (and ok (<= i last))
      (let ((c (aref value i)))
        (cond ((eq open close)
               (when (and (eq c open) (> i 0) (< i last)) (setq ok nil)))
              ((eq c open) (cl-incf depth))
              ((eq c close)
               (cl-decf depth)
               (when (and (<= depth 0) (< i last)) (setq ok nil)))))
      (cl-incf i))
    (and ok close (eq (aref value last) close) (or (eq open close) (= depth 0)))))

(defun sp-litnotes-meta--unquote (value)
  "VALUE without the quotes that enclose all of it, or nil when it has none.
Only quotes around the whole value go; quotes inside stay.  Quotes around quotes
(`\"\u201CA\u201D\"') are all removed.  A value that is only quotes gives nil."
  (let ((value (string-trim value)) result)
    (while (and (>= (length value) 2)
                (sp-litnotes-meta--wrapped-p value)
                (not (string-empty-p (string-trim (substring value 1 -1)))))
      (setq value (string-trim (substring value 1 -1))
            result value))
    result))

(defun sp-litnotes-meta--field (entry name)
  "The field NAME of ENTRY, braces removed and white space collapsed, or nil.
A title that BibTeX holds inside quotes (`{\"Title\"}') loses them."
  (when-let* ((value (cdr (assoc-string name entry t)))
              (clean (string-trim (replace-regexp-in-string
                                   "[ \t\n]+" " "
                                   (replace-regexp-in-string
                                    "[{}]" "" (sp-author-notes-latex-to-unicode value))))))
    (and (not (string-empty-p clean))
         (if (string-equal-ignore-case name "title")
             (or (sp-litnotes-meta--unquote clean) clean)
           clean))))

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

(defun sp-litnotes-meta--pages (entry)
  "The pages of ENTRY, with every kind of dash between the numbers made a single hyphen.
So `9--30' and `9–30' both give `9-30'.  Nil without a pages field."
  (when-let* ((pages (sp-litnotes-meta--field entry "pages")))
    (string-trim (replace-regexp-in-string "[ \t]*\\(?:-+\\|\u2013\\|\u2014\\)[ \t]*" "-" pages))))

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

(defun sp-litnotes-meta--crossref-chain (entry)
  "The keys of a crossref chain below ENTRY that is deeper than two levels, or nil.
That is (PARENT GRANDPARENT ...) when the entry the crossref of ENTRY names has a
crossref itself.  A loop, and an entry that crosses to itself, count: the
chain is followed until a key repeats, or has no crossref or no BibTeX entry.
A parent that has no crossref, the normal case, gives nil."
  (let ((ref (sp-litnotes-meta--field entry "crossref"))
        chain)
    (while (and ref (not (member ref chain)))
      (push ref chain)
      (setq ref (when-let* ((parent (sp-litnotes-meta--entry ref)))
                  (sp-litnotes-meta--field parent "crossref"))))
    ;; One key and no crossref after it is the normal case.  REF left over
    ;; means a loop (it is in CHAIN already), which counts, a self-reference too.
    (and (or (cdr chain) ref) (nreverse chain))))

(defvar sp-litnotes-meta--errors nil
  "Messages about what failed in the last convert, newest first.
The convert command clears it; the report lists it.")

(defun sp-litnotes-meta--note-error (format-string &rest args)
  "Say what failed and keep it for the report."
  (let ((text (apply #'format format-string args)))
    (push text sp-litnotes-meta--errors)
    (message "sp-litnotes-meta: %s" text)))

(defun sp-litnotes-meta--make-parent-note (ref)
  "Make the literature note of the crossref'd key REF; return (ID . TITLE), or nil.
The note is made by `sp-litnotes-meta-create-function' (the way the backfill
of the chapters makes notes), filled from BibTeX, given a plain title and put
in the Vulpea database.  Nothing is made, and a message says why, when REF
has no BibTeX entry.  Callers have checked `sp-litnotes-meta--crossref-chain',
so REF has no crossref of its own."
  (cond
   ((null (sp-litnotes-meta--entry ref))
    (message "sp-litnotes-meta: no BibTeX entry %s, bib-parent left empty" ref)
    nil)
   (t
    (condition-case err
        (let ((file (funcall sp-litnotes-meta-create-function ref)))
          ;; Not `citar-create-note', so its advice does not fill the note.
          ;; The parent follows the normal rules, whatever the child was allowed.
          (let ((sp-litnotes-meta--allow-chain nil))
            (sp-litnotes-meta-fill ref file)
            (sp-litnotes-meta--tidy-new-note ref file))
          (when (fboundp 'vulpea-db-update-file)
            (ignore-errors (vulpea-db-update-file file)))
          (when-let* ((head (sp-author-notes--file-head file))
                      (id (plist-get head :id)))
            (let ((target (cons id (or (plist-get head :title) ref))))
              (when sp-litnotes-meta--made-parents
                (puthash ref target sp-litnotes-meta--made-parents))
              (message "Made the parent note %s" ref)
              target)))
      (error (sp-litnotes-meta--note-error "parent %s: %s" ref (error-message-string err))
             nil)))))

(defvar sp-litnotes-meta--allow-chain nil
  "Non-nil when a crossref chain deeper than two levels is converted anyway.
`sp-litnotes-meta-fill-deep-chain' binds it; a parent note made then is
filled with it off.")

(defun sp-litnotes-meta--flag-chain (ref entry)
  "Non-nil, with a message, when the crossref REF of ENTRY starts a deep chain.
Always nil while `sp-litnotes-meta--allow-chain' is non-nil."
  (when-let* (((not sp-litnotes-meta--allow-chain))
              (chain (sp-litnotes-meta--crossref-chain entry)))
    (message "sp-litnotes-meta: crossref chain %s is deeper than two levels, bib-parent left empty (%s)"
             (string-join chain " -> ") ref)
    t))

(defun sp-litnotes-meta--parent-value (entry)
  "The bib-parent value for ENTRY: a link to the note of its crossref, or nil.
A crossref without a note gets one (`sp-litnotes-meta--make-parent-note')
unless `sp-litnotes-meta-create-parent' is nil.  A crossref chain deeper
than two levels (parent -> child -> grandchild) is left out and flagged by
a message, whether or not the notes exist."
  (when-let* ((ref (sp-litnotes-meta--field entry "crossref")))
    (or (when-let* (((not (sp-litnotes-meta--flag-chain ref entry)))
                    (target (or (sp-litnotes-meta--note-for-key ref)
                                (and sp-litnotes-meta--made-parents
                                     (gethash ref sp-litnotes-meta--made-parents))
                                (and sp-litnotes-meta-create-parent
                                     (sp-litnotes-meta--make-parent-note ref)))))
          (sp-litnotes-meta--link target))
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

(defconst sp-litnotes-meta--none "(none)"
  "The explicit choice that leaves a scale property empty.")

(defun sp-litnotes-meta--read-scale (prompt scale)
  "Ask PROMPT for one of SCALE; return the answer, or nil to leave it empty.
\"(none)\" is offered as the first candidate and the default, because a
required-match prompt will not accept an empty answer."
  (let ((answer (string-trim
                 (completing-read prompt (cons sp-litnotes-meta--none scale)
                                  nil t nil nil sp-litnotes-meta--none))))
    (and (not (string-empty-p answer))
         (not (equal answer sp-litnotes-meta--none))
         answer)))

(defun sp-litnotes-meta--read-relevance ()
  "Ask for the relevance-factor."
  (sp-litnotes-meta--read-scale "relevance-factor (01 = most relevant, (none) to skip): "
                                sp-litnotes-meta-relevance-scale))

(defun sp-litnotes-meta--read-priority ()
  "Ask for the read-priority."
  (sp-litnotes-meta--read-scale "read-priority (01 = read first, (none) to skip): "
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
(defun sp-litnotes-meta-fill (key &optional file overwrite)
  "Fill the meta lines of the literature note of KEY from its BibTeX entry.
FILE is the note; by default the current buffer's file, else the note
found for KEY.  Lines that have a value are left alone, except the pub-author,
pub-editor, pub-title, pub-year and pub-pages ones when OVERWRITE is non-nil (a prefix
argument).  A note without a type tag gets the tag of the BibTeX entry type
(`sp-bibtex-types').  Return the lines that were changed, and \"tag\" when the
tag was added.  A pub-title with quotes around all of it loses them, with or
without OVERWRITE.  A crossref'd entry without a note gets one (see
`sp-litnotes-meta-create-parent'), linked in bib-parent."
  (interactive (list (or (sp-litnotes-meta--buffer-key)
                         (user-error "No citation key in the ROAM_REFS of this buffer"))
                     buffer-file-name current-prefix-arg))
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
                        ("pub-pages" . ,(lambda () (sp-litnotes-meta--pages entry)))
                        ("bib-parent" . ,(lambda () (sp-litnotes-meta--parent-value entry)))
                        ("bib-project" . ,#'sp-litnotes-meta--read-project)
                        ("read-status" . ,(lambda () sp-litnotes-meta-initial-read-status))
                        ("relevance-factor" . ,#'sp-litnotes-meta--read-relevance)
                        ("read-priority" . ,#'sp-litnotes-meta--read-priority)))
          (let ((has (sp-litnotes-meta--has-value-p (car spec))))
            (when (or (not has)
                      (and overwrite (member (car spec) sp-litnotes-meta--overwritable)
                           (sp-litnotes-meta--differs-p (car spec) entry)))
              (when-let* ((value (if-let* ((preset (assoc (car spec) sp-litnotes-meta--preset)))
                                     (cdr preset)
                                   ;; One failing line must not lose the others.
                                   (condition-case err
                                       (funcall (cdr spec))
                                     (error (sp-litnotes-meta--note-error
                                             "%s of %s: %s" (car spec)
                                             (file-name-nondirectory file)
                                             (error-message-string err))
                                            nil)))))
                (cond ((not has)
                       (when (sp-litnotes-meta--set (car spec) value)
                         (push (car spec) changed)))
                      ((not (equal value (sp-litnotes-meta--buffer-meta (car spec))))
                       (sp-litnotes-meta--put (car spec) value)
                       (push (car spec) changed)))))))
        ;; A quoted pub-title that was not replaced above loses its quotes.
        (when-let* (((not (member "pub-title" changed)))
                    (raw (sp-litnotes-meta--buffer-meta "pub-title"))
                    (new (sp-litnotes-meta--unquote raw)))
          (sp-litnotes-meta--put "pub-title" new)
          (push "pub-title" changed))
        (when (sp-litnotes-meta--ensure-type-tag entry) (push "tag" changed))
        (when (and sp-litnotes-meta-order-meta (sp-vulpea-meta-order-buffer))
          (push "order" changed))
        (when changed (save-buffer))
        (unless buf (kill-buffer))
        (nreverse changed)))))

(defun sp-litnotes-meta--deep-chain-p (key)
  "The crossref chain of the BibTeX entry KEY when it is deeper than two levels, or nil."
  (when-let* ((entry (sp-litnotes-meta--entry key)))
    (sp-litnotes-meta--crossref-chain entry)))

;;;###autoload
(defun sp-litnotes-meta-fill-deep-chain (key &optional file)
  "Fill the note of KEY although its crossref chain is deeper than two levels.
`sp-litnotes-meta-fill' and the batch leave such a note's bib-parent out and
make no parent note.  This command is the way to convert one anyway: it shows
the chain, asks once, then fills the note of KEY (the current buffer's file
unless FILE) like `sp-litnotes-meta-fill' and links or makes its direct parent.
The parent is then filled with the normal rules, so a loop is cut there and the
grandparent is made only when the parent's chain is no deeper.  Return what
`sp-litnotes-meta-fill' returns."
  (interactive (list (or (sp-litnotes-meta--buffer-key)
                         (user-error "No citation key in the ROAM_REFS of this buffer"))
                     buffer-file-name))
  (let ((chain (or (sp-litnotes-meta--deep-chain-p key)
                   (user-error "%s has no crossref chain deeper than two levels; use sp-litnotes-meta-fill"
                               key))))
    (when (yes-or-no-p (format "%s -> %s: fill it anyway and link or make its parent? "
                               key (string-join chain " -> ")))
      (let ((sp-litnotes-meta--allow-chain t))
        (sp-litnotes-meta-fill key file)))))

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
  (let ((buf (progn (sp-batch-report-flush-file file)
                    (find-buffer-visiting file))))
    (when (and buf (buffer-modified-p buf))
      (user-error "%s has unsaved changes; save it first" (file-name-nondirectory file)))
    (with-current-buffer (or buf (find-file-noselect file))
      (sp-litnotes-meta--put "read-status" status)
      (save-buffer))
    (if sp-batch-report-save-and-kill
        (sp-batch-report-close-file file)
      (unless buf (kill-buffer (find-buffer-visiting file))))))

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
        tabulated-list-padding 1
        sp-echo-hints-list '(("RET" . "visit") ("m/u" . "mark/unmark") ("M" . "mark a status")
                             ("U" . "unmark all") ("s" . "set status") ("g" . "refresh")
                             ("q" . "quit")))
  (tabulated-list-init-header)
  (sp-echo-hints-mode 1))

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

(defun sp-litnotes-meta--tidy-new-note (key &optional file)
  "Give the note just made for KEY a plain title and drop the bibliography block.
FILE is the note, by default the one the litnotes folder has for KEY.
Citar's own note template writes \"#+title: Notes on ...\" and a
\"#+print_bibliography:\" line (the Org-cite marker that prints the
bibliography of the note, of no use in a litnote).  Return non-nil if the
note changed."
  (when-let* ((file (or file (gethash key (sp-author-notes-bibtex--covered))))
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

;;;; Make a litnote

(declare-function vulpea-create "vulpea-create")
(declare-function vulpea-note-path "vulpea-note")
(declare-function sp-org-created-stamp "sp-org-link-conversion")
(declare-function sp-notes-ensure-created "sp-notes")
(defvar citar-vulpea-notes-directory)
(defvar citar-vulpea-keyword)

(defcustom sp-litnotes-meta-create-function #'sp-litnotes-meta-create-note
  "Function that makes the note of a citation key for the backfill.
It is called with the key and returns the file of the new note."
  :type 'function
  :group 'sp-litnotes-meta)

(defun sp-litnotes-meta-create-note (key)
  "Make the litnote of the citation KEY with `vulpea-create' and return its file.
This does what the `citar-vulpea' source does (the `litnote' tag plus the
tag of the BibTeX type, from `sp-bibtex-types', ROAM_REFS,
the litnotes folder) but without going through citar, so the note always has:
- an :ID: and a file name that is the key, from `vulpea-create';
- :CREATED:, from `sp-org-created-stamp' (the advice of `sp-notes' on
  `vulpea-create' adds it too, and `sp-notes-ensure-created' checks);
- the title of `sp-litnotes-meta-new-title'.
The note is in the Vulpea database when this returns."
  (require 'vulpea)
  (require 'sp-org-link-conversion)
  (let* ((entry (or (sp-litnotes-meta--entry key)
                    (user-error "No BibTeX entry %s in the registered files" key)))
         (title (or (sp-litnotes-meta--new-title entry) key))
         (dir (file-name-as-directory
               (expand-file-name (or (bound-and-true-p citar-vulpea-notes-directory)
                                     sp-author-notes-litnotes-directory))))
         (note (vulpea-create
                title
                (concat dir key ".org")
                :tags (list (or (bound-and-true-p citar-vulpea-keyword) "litnote")
                             (sp-bibtex-types-entry-tag entry))
                :properties (list (cons "ROAM_REFS" (concat "@" key))
                                  (cons "CREATED" (sp-org-created-stamp)))))
         (file (and note (vulpea-note-path note))))
    (unless (and file (file-exists-p file))
      (error "vulpea-create made no file for %s" key))
    (when (require 'sp-notes nil t)
      (sp-notes-ensure-created file))
    file))

;;;; Show the children in the table of the book

(declare-function sp-collec-query-dblock-has-block-p "sp-collection-query-org")
(declare-function sp-collec-query-dblock-update-buffer "sp-collection-query-org")
(declare-function org-create-dblock "org")
(declare-function org-update-dblock "org")
(declare-function vulpea-db-update-file "vulpea-db")

(defcustom sp-litnotes-meta-parent-views
  '(("book" . "book-sections")
    ("collection" . "collection-articles")
    ("reference" . "reference-entries")
    ("encyclopedia" . "encyclopedia-articles"))
  "The table view of a parent note, by the tag of the parent.
Elements are (PARENT-TAG . VIEW), see `sp-collec-query-views-defaults'.
The first tag the note carries wins."
  :type '(alist :key-type string :value-type string)
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-chapter-views
  '(("booksection" . "book-sections")
    ("incollection" . "collection-articles")
    ("inreference" . "reference-entries")
    ("encyclopedia" . "encyclopedia-articles"))
  "The table view for the children of a parent, by the tag of a child.
Elements are (CHILD-TAG . VIEW).  The tags are the ones that
`sp-litnotes-meta-refresh-all-tables' follows from a child to its
bib-parent; a parent tag that `sp-litnotes-meta-parent-views' knows is
used before this."
  :type '(alist :key-type string :value-type string)
  :group 'sp-litnotes-meta)

(defun sp-litnotes-meta--table-view (key)
  "The built-in view name for the table of the children of KEY.
It follows the BibTeX type of KEY through `sp-bibtex-types-tag' and
`sp-litnotes-meta-parent-views'; a type they do not know gives
\"book-sections\"."
  (let* ((type (cdr (assoc "=type=" (let ((bibtex-dialect 'biblatex)) ; knows @collection
                                      (sp-litnotes-meta--entry key)))))
         (tag (sp-bibtex-types-tag type)))
    (or (cdr (assoc tag sp-litnotes-meta-parent-views))
        "book-sections")))

(defconst sp-litnotes-meta-sections-heading "Sections"
  "Title of the heading the chapter table block sits under.")

(defconst sp-litnotes-meta--block-regexp
  "^\\([ \t]*\\)#\\+BEGIN:[ \t]+\\(collection-query-table\\|vulpea-table\\)\\_>\\(.*\\)$"
  "Begin line of a query table block: the indent, the block name, the parameters.")

(defun sp-litnotes-meta--sections-regexp ()
  "Regexp of a Sections heading line (any level, tags allowed)."
  (format "^\\*+[ \t]+%s\\(?:[ \t]+:[^ \t\n]+:\\)?[ \t]*$"
          (regexp-quote sp-litnotes-meta-sections-heading)))

(defun sp-litnotes-meta--sections-heading ()
  "Start of the line of the first Sections heading of the buffer, or nil."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search nil))
        (and (re-search-forward (sp-litnotes-meta--sections-regexp) nil t)
             (match-beginning 0))))))

(defun sp-litnotes-meta--parse-params (text)
  "The plist written in TEXT, the parameters of a block, or `:unreadable'."
  (condition-case nil
      (let ((params (car (read-from-string (concat "(" text ")")))))
        (if (and (listp params) (cl-evenp (length params))) params :unreadable))
    (error :unreadable)))

(defun sp-litnotes-meta--blocks ()
  "The query table blocks of the buffer, in order, as plists.
Keys: :beg (start of the begin line), :end (after the end line), :indent,
:name, :rest (the text after the name) and :params (see
`sp-litnotes-meta--parse-params')."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t) out)
        (while (re-search-forward sp-litnotes-meta--block-regexp nil t)
          (let ((beg (match-beginning 0))
                (indent (match-string 1))
                (name (match-string 2))
                (rest (match-string 3)))
            (when (re-search-forward "^[ \t]*#\\+END:?[ \t]*$" nil t)
              (push (list :beg beg :end (min (point-max) (1+ (point)))
                          :indent indent :name name :rest rest
                          :params (sp-litnotes-meta--parse-params rest))
                    out))))
        (nreverse out)))))

(defun sp-litnotes-meta--note-id ()
  "The ID of the note in the buffer, from the property drawer above its first heading."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (and (re-search-forward "^[ \t]*:ID:[ \t]+\\(\\S-+\\)" (sp-author-notes--first-heading) t)
             (match-string 1))))))

(defun sp-litnotes-meta--chapter-view-names ()
  "The names of the views that `sp-litnotes-meta-parent-views' and `-chapter-views' use."
  (delete-dups (append (mapcar #'cdr sp-litnotes-meta-parent-views)
                       (mapcar #'cdr sp-litnotes-meta-chapter-views))))

(defun sp-litnotes-meta--view-for-params (params)
  "The name of the view whose spec is exactly PARAMS, or nil.
PARAMS has no :view.  The views of the chapter tables are tried first."
  (when (and (require 'sp-collection-query-views nil t)
             (fboundp 'sp-collec-query-views-names)
             (fboundp 'sp-collec-query-spec-normalize))
    (let ((want (sp-collec-query-spec-normalize params))
          (chapter (sp-litnotes-meta--chapter-view-names)))
      (seq-find (lambda (name)
                  (let ((spec (sp-collec-query-views-get name)))
                    (and spec (equal want (sp-collec-query-spec-normalize spec)))))
                (append chapter
                        (seq-remove (lambda (name) (member name chapter))
                                    (sp-collec-query-views-names)))))))

(defun sp-litnotes-meta--self-parent-p (params id)
  "Non-nil when the :parent-of of PARAMS is the note itself, as \"self\" or as its ID."
  (let ((parent (plist-get params :parent-of)))
    (and parent (member parent (delq nil (list "self" 'self id))))))

(defun sp-litnotes-meta--saved-format (view)
  "The begin line of a block in the saved template format, with VIEW."
  (format "#+BEGIN: collection-query-table :view %S" view))

(defun sp-litnotes-meta--migrated-line (block view id)
  "The begin line BLOCK should have, or nil when it is right already.
The saved template format is `#+BEGIN: collection-query-table :view NAME':
- the old name `vulpea-table' becomes `collection-query-table';
- a block without :view whose parameters are exactly those of a view gets
  `:view' with that name;
- a block without :view that lists the notes pointing at the note itself
  (\\=:parent-of \"self\" or the ID of the note) gets VIEW, the view of this note;
- a block with :view, or other parameters, keeps them.
ID is the ID of the note."
  (let* ((params (plist-get block :params))
         (renamed (not (string-equal-ignore-case (plist-get block :name) "collection-query-table")))
         (indent (plist-get block :indent))
         (name (and (listp params) (null (plist-get params :view))
                    (or (sp-litnotes-meta--view-for-params params)
                        (and view (sp-litnotes-meta--self-parent-p params id) view)))))
    (cond (name (concat indent (sp-litnotes-meta--saved-format name)))
          (renamed (concat indent "#+BEGIN: collection-query-table" (plist-get block :rest))))))

(defun sp-litnotes-meta--migrate-blocks (view)
  "Rewrite the begin lines of the query table blocks to the saved template format.
See `sp-litnotes-meta--migrated-line'; VIEW is the view of this note.
Return the (OLD . NEW) lines, in the order of the buffer."
  (let ((id (sp-litnotes-meta--note-id)) changes)
    (save-excursion
      (save-restriction
        (widen)
        (dolist (block (reverse (sp-litnotes-meta--blocks)))
          (when-let* ((new (sp-litnotes-meta--migrated-line block view id)))
            (goto-char (plist-get block :beg))
            (let ((old (buffer-substring (line-beginning-position) (line-end-position))))
              (delete-region (line-beginning-position) (line-end-position))
              (insert new)
              (push (cons (string-trim old) (string-trim new)) changes))))))
    changes))

(defun sp-litnotes-meta--chapter-block-p (block id)
  "Non-nil when BLOCK is the chapter table of the note with ID.
It has the view of a chapter table, or no view and lists the notes that point at the note."
  (let ((params (plist-get block :params)))
    (and (listp params)
         (let ((view (plist-get params :view)))
           (if view
               (member view (sp-litnotes-meta--chapter-view-names))
             (sp-litnotes-meta--self-parent-p params id))))))

(defun sp-litnotes-meta--skip-blank-lines ()
  "Move point over blank lines."
  (while (and (not (eobp)) (looking-at-p "[ \t]*$"))
    (forward-line 1)))

(defun sp-litnotes-meta--section-start (heading)
  "Where the content of the heading starting at HEADING begins.
That is after the heading line, its planning line and its property drawer."
  (save-excursion
    (goto-char heading)
    (forward-line 1)
    (when (looking-at-p "[ \t]*\\(?:CLOSED\\|SCHEDULED\\|DEADLINE\\):")
      (forward-line 1))
    (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
      (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
        (forward-line 1)))
    (point)))

(defun sp-litnotes-meta--blocks-in-place-p (heading blocks)
  "Non-nil when BLOCKS are the first content under the heading at HEADING.
Only blank lines may sit between the heading and the first block, and
between the blocks."
  (save-excursion
    (goto-char (sp-litnotes-meta--section-start heading))
    (sp-litnotes-meta--skip-blank-lines)
    (let ((expect (point)))
      (seq-every-p (lambda (block)
                     (and (= (plist-get block :beg) expect)
                          (progn (goto-char (plist-get block :end))
                                 (sp-litnotes-meta--skip-blank-lines)
                                 (setq expect (point))
                                 t)))
                   blocks))))

(defun sp-litnotes-meta--block-text (block)
  "The text of BLOCK, ending in a newline."
  (let ((text (buffer-substring (plist-get block :beg) (plist-get block :end))))
    (if (string-suffix-p "\n" text) text (concat text "\n"))))

(defun sp-litnotes-meta--cut-block (block)
  "Delete BLOCK and the blank lines after it.
When blank lines followed it, one is kept between the text before and after."
  (goto-char (plist-get block :beg))
  (delete-region (plist-get block :beg) (plist-get block :end))
  (when (and (sp-litnotes-meta--delete-blank-lines)
             (not (or (bobp) (eobp)
                      (save-excursion (forward-line -1) (looking-at-p "[ \t]*$")))))
    (insert "\n")))

(defun sp-litnotes-meta--delete-blank-lines ()
  "Delete the blank lines that start at point; return non-nil when there were some."
  (let (deleted)
    (while (and (not (eobp)) (looking-at-p "[ \t]*$"))
      (delete-region (point) (min (point-max) (1+ (line-end-position))))
      (setq deleted t))
    deleted))

(defun sp-litnotes-meta--insert-blocks (texts)
  "Insert the block TEXTS at point, with a blank line before, between and after them."
  (unless (bolp) (insert "\n"))
  (sp-litnotes-meta--delete-blank-lines)
  (insert "\n" (mapconcat #'identity texts "\n") "\n"))

(defun sp-litnotes-meta--normalize-tables (view &optional create)
  "Put the chapter table of the current note under its Sections heading.
The current buffer is an Org note; nothing is updated here.  Safe to run
again, it changes only what is not in place:
- every table block gets the saved template format
  (see `sp-litnotes-meta--migrated-line');
- the chapter table blocks sit at the start of the content of the
  `* Sections' heading, set off by blank lines.  One that sits elsewhere
  (above the first heading, under another heading, or after other text
  under Sections) is moved there; an existing Sections heading is reused,
  else it is added above the first heading;
- with CREATE, a note without a chapter table gets a block with VIEW.
Return the actions, in order, as a list of (SYMBOL . DETAIL):
`migrated' (DETAIL is (OLD . NEW) begin lines), `moved', `heading'
\(a Sections heading was added) and `inserted' (a block was added)."
  (let (actions)
    (save-excursion
      (save-restriction
        (widen)
        (let ((case-fold-search nil))
          (dolist (change (sp-litnotes-meta--migrate-blocks view))
            (push (cons 'migrated change) actions))
          (let* ((id (sp-litnotes-meta--note-id))
                 (chapters (seq-filter (lambda (block) (sp-litnotes-meta--chapter-block-p block id))
                                       (sp-litnotes-meta--blocks)))
                 (heading (sp-litnotes-meta--sections-heading)))
            (unless (or (and (null chapters) (not create))
                        (and chapters heading
                             (sp-litnotes-meta--blocks-in-place-p heading chapters)))
              (let* ((first (sp-author-notes--first-heading))
                     (texts (or (mapcar #'sp-litnotes-meta--block-text chapters)
                                (list (format "%s\n#+END:\n" (sp-litnotes-meta--saved-format view)))))
                     (above-first (and (null heading) chapters
                                       (seq-every-p (lambda (block) (< (plist-get block :beg) first))
                                                    chapters))))
                (dolist (block (reverse chapters))
                  (sp-litnotes-meta--cut-block block))
                (cond ((null chapters) (push (cons 'inserted nil) actions))
                      ((not above-first) (push (cons 'moved nil) actions)))
                (if (setq heading (sp-litnotes-meta--sections-heading))
                    (goto-char (sp-litnotes-meta--section-start heading))
                  (goto-char (sp-author-notes--first-heading))
                  (unless (or (bobp) (bolp)) (insert "\n"))
                  (unless (or (bobp) (save-excursion (forward-line -1) (looking-at-p "[ \t]*$")))
                    (insert "\n"))
                  (insert (format "* %s\n" sp-litnotes-meta-sections-heading))
                  (push (cons 'heading nil) actions))
                (sp-litnotes-meta--insert-blocks texts)))))))
    (nreverse actions)))

(defun sp-litnotes-meta--truncate (text)
  "TEXT cut to fit a report line."
  (truncate-string-to-width text 60 nil nil "…"))

(defun sp-litnotes-meta--actions-text (actions)
  "A sentence about the ACTIONS of `sp-litnotes-meta--normalize-tables'."
  (mapconcat
   (lambda (action)
     (pcase (car action)
       ('inserted "table added")
       ('heading (format "* %s heading added" sp-litnotes-meta-sections-heading))
       ('moved (format "table moved under * %s" sp-litnotes-meta-sections-heading))
       ('migrated (format "~%s~ becomes ~%s~"
                          (sp-litnotes-meta--truncate (cadr action))
                          (sp-litnotes-meta--truncate (cddr action))))
       (other (format "%s" other))))
   actions "; "))

(defun sp-litnotes-meta--ensure-table (key files &optional view)
  "Make the current note show a table of its children, and refresh it.
KEY is the citation key of the note; FILES the files of the notes just made,
which are put in the Vulpea database first.  Put a `collection-query-table'
block with VIEW (by default the view for KEY) under the Sections heading when
the note has none, and bring an old block into the saved template format
\(see `sp-litnotes-meta--normalize-tables').  Return `inserted', `updated' or nil."
  (when (derived-mode-p 'org-mode)
    (unless (and (require 'sp-collection-query-org nil t)
                 (fboundp 'sp-collec-query-dblock-update-buffer))
      (user-error "The query table module (sp-collection-query-org) did not load"))
    (let ((was-modified (buffer-modified-p))
          (how 'updated))
      (when (fboundp 'vulpea-db-update-file)
        (dolist (file files)
          (ignore-errors (vulpea-db-update-file file))))
      (when (assq 'inserted (sp-litnotes-meta--normalize-tables
                             (or view (sp-litnotes-meta--table-view key)) t))
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
note is taken and nothing is picked.  Each new note is made by
`sp-litnotes-meta-create-function' (an ID, :CREATED:, the litnote tag and
ROAM_REFS) and filled from BibTeX like `sp-litnotes-meta-fill' does, with
the parent linked in bib-parent.  bib-project is copied from this note;
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
         made made-files)
    (dolist (child keys)
      (condition-case err
          (let ((file (funcall sp-litnotes-meta-create-function child)))
            ;; Not `citar-create-note', so its advice does not fill the note.
            (sp-litnotes-meta-fill child file)
            (sp-litnotes-meta--tidy-new-note child file)
            (when (fboundp 'vulpea-db-update-file)
              (ignore-errors (vulpea-db-update-file file)))
            (push child made)
            (push file made-files))
        (error (message "sp-litnotes-meta: %s: %s" child (error-message-string err)))))
    (setq made (nreverse made))
    ;; citar may have shown a new note; the table belongs in the book's note.
    (let ((table (with-current-buffer origin
                   (condition-case err
                       (sp-litnotes-meta--ensure-table key (nreverse made-files))
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

;;;; Refresh the chapter tables of the whole vault

(declare-function vulpea-db-sync-full-scan "vulpea-db-sync")
(declare-function vulpea-db-get-by-id "vulpea-db")
(declare-function vulpea-note-meta-get-list "vulpea-note")

(defcustom sp-litnotes-meta-refresh-sync t
  "Non-nil: `sp-litnotes-meta-refresh-all-tables' syncs the Vulpea database first."
  :type 'boolean
  :group 'sp-litnotes-meta)

(defconst sp-litnotes-meta--refresh-buffer "*litnote tables*")

(defun sp-litnotes-meta--chapter-notes ()
  "The notes tagged with a key of `sp-litnotes-meta-chapter-views'."
  (vulpea-db-query-by-tags-some (mapcar #'car sp-litnotes-meta-chapter-views)))

(defun sp-litnotes-meta--parent-view (parent chapters)
  "The view for the table of the note PARENT, whose CHAPTERS are notes.
The tags of PARENT decide, see `sp-litnotes-meta-parent-views'; else the
first tag of a chapter, see `sp-litnotes-meta-chapter-views'."
  (or (seq-some (lambda (cell)
                  (and (member (car cell) (vulpea-note-tags parent)) (cdr cell)))
                sp-litnotes-meta-parent-views)
      (seq-some (lambda (note)
                  (seq-some (lambda (cell)
                              (and (member (car cell) (vulpea-note-tags note)) (cdr cell)))
                            sp-litnotes-meta-chapter-views))
                chapters)
      "book-sections"))

(defcustom sp-litnotes-meta-parent-tags '("book" "collection" "reference" "encyclopedia")
  "Tags of the litnotes that `sp-litnotes-meta-add-all-tables' gives a table."
  :type '(repeat string)
  :group 'sp-litnotes-meta)

(defun sp-litnotes-meta--table-parents (&optional all-parents)
  "The notes that should show a chapter table, as a plist.
With ALL-PARENTS, every litnote tagged with one of `sp-litnotes-meta-parent-tags'
is a parent, with its chapters or none.
:PARENTS is a list of (NOTE . CHAPTERS) for every note some chapter points
at with bib-parent, and for every tagged note of
`sp-litnotes-meta-parent-views'; :MISSING lists the ids a bib-parent
names that are not in the database."
  (let ((by-id (make-hash-table :test #'equal)) order missing)
    (dolist (chapter (sp-litnotes-meta--chapter-notes))
      (dolist (id (vulpea-note-meta-get-list chapter "bib-parent" 'link))
        (let ((parent (and (stringp id) (ignore-errors (vulpea-db-get-by-id id)))))
          (cond ((null parent)
                 (cl-pushnew (cons id (vulpea-note-title chapter)) missing :test #'equal))
                (t (unless (gethash id by-id) (push id order))
                   (push chapter (gethash id by-id)))))))
    (let ((parents (mapcar (lambda (id)
                             (cons (vulpea-db-get-by-id id) (nreverse (gethash id by-id))))
                           (nreverse order))))
      ;; tagged notes without chapters count when they have a block
      (dolist (note (vulpea-db-query-by-tags-some
                     (if all-parents
                         sp-litnotes-meta-parent-tags
                       (mapcar #'car sp-litnotes-meta-parent-views))))
        (when (and (not (gethash (vulpea-note-id note) by-id))
                   (or (not all-parents)
                       (member sp-litnotes-meta-batch-tag (vulpea-note-tags note))))
          (push (list note) parents)))
      (list :parents (nreverse parents) :missing (nreverse missing)))))

(declare-function sp-litnotes-meta--backup "sp-litnotes-meta")
(defvar sp-litnotes-meta-backup-directory)

(defvar sp-litnotes-meta--table-stamp nil
  "Name of the backup sub-folder of the running table command, or nil for no backup.")

(defvar sp-litnotes-meta--table-backups 0
  "How many notes the running table command has copied to its backup folder.")

(defun sp-litnotes-meta--refresh-file (file view create)
  "Put the chapter table in FILE in order and update it.
See `sp-litnotes-meta--normalize-tables': a block with VIEW is added when
CREATE, the blocks are moved under the Sections heading and brought into
the saved template format.  Return (STATUS . ACTIONS); STATUS is
`inserted', `changed', `unchanged' or `skipped' (no block and not CREATE).
The file is saved when it changed, after a copy to the backup folder named
by `sp-litnotes-meta--table-stamp'; its buffer is killed when it was not open
(and saved and killed with `sp-batch-report-save-and-kill')."
  (let* ((flushed (sp-batch-report-flush-file
                   file (lambda (f)
                          (when sp-litnotes-meta--table-stamp
                            (sp-litnotes-meta--backup f sp-litnotes-meta--table-stamp)))))
         (open (find-buffer-visiting file))
         (buffer (or open (find-file-noselect file))))
    (when flushed (error "%s: %s" (file-name-nondirectory file) flushed))
    (unwind-protect
        (with-current-buffer buffer
          (unless (and (require 'sp-collection-query-org nil t)
                       (fboundp 'sp-collec-query-dblock-update-buffer))
            (user-error "The query table module (sp-collection-query-org) did not load"))
          (if (and (not create) (null (sp-litnotes-meta--blocks)))
              (list 'skipped)
            (let* ((was-modified (buffer-modified-p))
                   (before (buffer-hash))
                   (actions (sp-litnotes-meta--normalize-tables view create)))
              (sp-collec-query-dblock-update-buffer)
              (when (and buffer-file-name (not was-modified) (buffer-modified-p))
                (when sp-litnotes-meta--table-stamp
                  (sp-litnotes-meta--backup buffer-file-name sp-litnotes-meta--table-stamp)
                  (cl-incf sp-litnotes-meta--table-backups))
                (save-buffer))
              (cons (cond ((assq 'inserted actions) 'inserted)
                          ((or actions (not (equal before (buffer-hash)))) 'changed)
                          (t 'unchanged))
                    actions))))
      (if sp-batch-report-save-and-kill
          (sp-batch-report-close-file file)
        (unless (or open (buffer-modified-p buffer))
          (kill-buffer buffer))))))

(defun sp-litnotes-meta--plan-file (file view create)
  "The actions `sp-litnotes-meta--refresh-file' would take on FILE, writing nothing."
  (with-temp-buffer
    (insert-file-contents file)
    (and (or create (sp-litnotes-meta--blocks))
         (sp-litnotes-meta--normalize-tables view create))))

;;;###autoload
(defun sp-litnotes-meta-refresh-all-tables (&optional dry-run all-parents)
  "Add and refresh the chapter table of every book, collection and the like.
See the doc for which notes get one.  The Vulpea database is synced first
when `sp-litnotes-meta-refresh-sync' is non-nil.  With a prefix argument,
or DRY-RUN, only list what would be added, moved or migrated and write
nothing.  With ALL-PARENTS, a litnote tagged `sp-litnotes-meta-parent-tags'
gets a block even when no chapter note exists yet.

Each table block ends up under a `* Sections' heading in the saved
template format, `#+BEGIN: collection-query-table :view NAME'; see
`sp-litnotes-meta--normalize-tables'.  A note is copied to a time-stamped
folder in `sp-litnotes-meta-backup-directory' before it is written.  Show a
summary in `sp-litnotes-meta--refresh-buffer' and return the plist
\\(:inserted :changed :unchanged :skipped :failed :missing :backup).  The
:inserted and :changed items are (TITLE FILE [WHAT])."
  (interactive "P")
  (when (and sp-litnotes-meta-refresh-sync (not dry-run)
             (fboundp 'vulpea-db-sync-full-scan))
    (message "Syncing the Vulpea database...")
    (vulpea-db-sync-full-scan))
  (let* ((found (sp-litnotes-meta--table-parents all-parents))
         (stamp (format-time-string "%Y%m%d-%H%M%S"))
         (sp-litnotes-meta--table-stamp (unless dry-run stamp))
         (sp-litnotes-meta--table-backups 0)
         inserted changed unchanged skipped failed)
    (dolist (entry (plist-get found :parents))
      (let* ((parent (car entry))
             (chapters (cdr entry))
             (view (sp-litnotes-meta--parent-view parent chapters))
             (file (vulpea-note-path parent))
             (create (and (or chapters all-parents) t))
             (label (list (vulpea-note-title parent) file)))
        (condition-case err
            (let* ((outcome (if dry-run
                                (let ((actions (sp-litnotes-meta--plan-file file view create)))
                                  (cons (cond ((assq 'inserted actions) 'inserted)
                                              (actions 'changed)
                                              (t 'unchanged))
                                        actions))
                              (sp-litnotes-meta--refresh-file file view create)))
                   (note (and (if (eq (car outcome) 'inserted)
                                  (seq-some (lambda (a) (memq (car a) '(moved migrated))) (cdr outcome))
                                (cdr outcome))
                              (list (sp-litnotes-meta--actions-text (cdr outcome))))))
              (pcase (car outcome)
                ('inserted (push (append label note) inserted))
                ('changed (push (append label note) changed))
                ('unchanged (push label unchanged))
                (_ (push label skipped))))
          (error (push (append label (list (error-message-string err))) failed)))))
    (let* ((dir (expand-file-name (concat stamp "/") sp-litnotes-meta-backup-directory))
           (result (list :inserted (nreverse inserted) :changed (nreverse changed)
                         :unchanged (nreverse unchanged) :skipped (nreverse skipped)
                         :failed (nreverse failed) :missing (plist-get found :missing)
                         :backup (and (> sp-litnotes-meta--table-backups 0) dir))))
      (sp-litnotes-meta--show-refresh result dry-run)
      result)))

;;;###autoload
(defun sp-litnotes-meta-add-all-tables (&optional dry-run)
  "Give every book, collection, reference and encyclopedia litnote its chapter table.
Like `sp-litnotes-meta-refresh-all-tables', but a litnote tagged with one of
`sp-litnotes-meta-parent-tags' gets the block even before it has a chapter
note, so the table is there when the first chapter is added.  The block sits
at the start of the content of the `* Sections' heading, with a blank line
before and after the heading and after the block.  Safe to run again, it
also repairs the notes it ran on before:
- an existing Sections heading is reused;
- a table block that sits elsewhere is moved under it;
- an old block (`vulpea-table', or written out with columns instead of
  :view) is brought into the saved template format.
With a prefix argument, or DRY-RUN, only list what would change."
  (interactive "P")
  (sp-litnotes-meta-refresh-all-tables dry-run t))

(defun sp-litnotes-meta--refresh-lines (heading items)
  "Org text for HEADING and the (TITLE FILE [NOTE]) ITEMS under it, or nil."
  (when items
    (concat (format "* %s (%d)\n" heading (length items))
            (mapconcat (lambda (item)
                         (format "- [[file:%s][%s]]%s\n" (nth 1 item) (car item)
                                 (if (nth 2 item) (format ": %s" (nth 2 item)) "")))
                       items ""))))

(defun sp-litnotes-meta--show-refresh (result dry-run)
  "Show RESULT of `sp-litnotes-meta-refresh-all-tables' in a buffer."
  (with-current-buffer (get-buffer-create sp-litnotes-meta--refresh-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "#+title: Chapter tables%s\n\n" (if dry-run " (dry run, nothing written)" "")))
      (insert (format "%d added, %d changed, %d unchanged, %d failed\n\n"
                      (length (plist-get result :inserted)) (length (plist-get result :changed))
                      (length (plist-get result :unchanged)) (length (plist-get result :failed))))
      (when-let* ((backup (plist-get result :backup)))
        (insert (format "Copies of the notes before they changed: [[file:%s][%s]]\n\n" backup backup)))
      (insert (or (sp-litnotes-meta--refresh-lines (if dry-run "Would get a table" "Table added")
                                                   (plist-get result :inserted)) "")
              (or (sp-litnotes-meta--refresh-lines (if dry-run "Would be fixed" "Table changed")
                                                   (plist-get result :changed)) "")
              (or (sp-litnotes-meta--refresh-lines "Failed" (plist-get result :failed)) ""))
      (when-let* ((missing (plist-get result :missing)))
        (insert (format "* bib-parent not in the database (%d)\n" (length missing)))
        (dolist (cell missing)
          (insert (format "- %s: =%s=\n" (cdr cell) (car cell)))))
      (delay-mode-hooks (org-mode))
      (goto-char (point-min))
      (set-buffer-modified-p nil))
    (display-buffer (current-buffer)))
  (message "Chapter tables: %d added, %d changed, %d unchanged%s"
           (length (plist-get result :inserted)) (length (plist-get result :changed))
           (length (plist-get result :unchanged))
           (if (plist-get result :failed)
               (format ", %d failed" (length (plist-get result :failed))) "")))

(defcustom sp-litnotes-meta-update-changed t
  "Non-nil when the batch also updates pub-* values that differ from the BibTeX entry.
The dry run lists each as \"update\", with the old and the new value; the
convert command lets you drop or skip any of them.  bib-parent is never
updated by the batch; `sp-litnotes-meta-parent-lint-convert' fixes it."
  :type 'boolean
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-batch-tag "litnote"
  "The tag of the notes `sp-litnotes-meta-fill-all-dryrun' and `-convert' go through."
  :type 'string
  :group 'sp-litnotes-meta)

(defcustom sp-litnotes-meta-backup-directory
  (expand-file-name "litnote-meta-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Folder where `sp-litnotes-meta-fill-all-convert' copies each note before changing it.
Every run makes a sub-folder named with the time."
  :type 'directory
  :group 'sp-litnotes-meta)

(defconst sp-litnotes-meta--bib-keys '("pub-author" "pub-editor" "pub-title" "pub-year" "pub-pages" "bib-parent")
  "The meta lines that come from the BibTeX entry.")

(defconst sp-litnotes-meta--overwritable '("pub-author" "pub-editor" "pub-title" "pub-year" "pub-pages")
  "The meta lines a prefix argument replaces.  bib-parent is a link to a note and stays.")

(defconst sp-litnotes-meta--default-keys '("bib-project" "read-status" "relevance-factor" "read-priority")
  "The meta lines the batch never asks per note; it asks once, or leaves them.")

(defconst sp-litnotes-meta--batch-buffer "*litnote meta fill*")

(defun sp-litnotes-meta--batch-files ()
  "The files of the top-level notes tagged `sp-litnotes-meta-batch-tag', sorted."
  (let (files)
    (dolist (note (vulpea-db-query-by-tags-some (list sp-litnotes-meta-batch-tag)))
      (when-let* ((path (vulpea-note-path note)))
        (when (and (eql 0 (vulpea-note-level note)) (file-exists-p path))
          (push path files))))
    (sort (delete-dups files) #'string<)))

(defun sp-litnotes-meta--filetags ()
  "The tags of the #+filetags line of the current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t))
      (when (re-search-forward "^#\\+filetags:[ \t]*\\(.*\\)$" (sp-author-notes--first-heading) t)
        (split-string (match-string 1) "[: \t]+" t)))))

(defun sp-litnotes-meta--preview-value (key entry)
  "What the meta line KEY would get from ENTRY, as plain text, or nil.
Authors are names here, not links; looking up or making the author notes
is for the convert step."
  (pcase key
    ("pub-author" (when-let* ((names (sp-litnotes-meta--author-names entry)))
                    (string-join names ", ")))
    ("pub-editor" (when-let* ((names (sp-litnotes-meta--author-names entry "editor")))
                    (string-join names ", ")))
    ("pub-title" (sp-litnotes-meta--field entry "title"))
    ("pub-year" (sp-litnotes-meta--year entry))
    ("pub-pages" (sp-litnotes-meta--pages entry))
    ("bib-parent" (sp-litnotes-meta--field entry "crossref"))))

(defconst sp-litnotes-meta--person-keys '("pub-author" "pub-editor")
  "The meta lines whose value is links to person notes.")

(defun sp-litnotes-meta--differs-p (key entry)
  "Non-nil when the meta line KEY of the current buffer differs from ENTRY.
Only a value the entry has counts; the note's links are compared as their text.
The names of the people are compared without accents, case and extra spaces: the
link text is the title of the person note, which may spell the name another
way than BibTeX (Andre or André), and the write keeps the link, so an exact
comparison would list the same update on every run."
  (when-let* ((value (sp-litnotes-meta--preview-value key entry)))
    (let ((old (sp-litnotes-titles--clean (or (sp-litnotes-meta--buffer-meta key) ""))))
      (not (if (member key sp-litnotes-meta--person-keys)
               (equal (sp-author-notes--title-key old) (sp-author-notes--title-key value))
             (equal old value))))))

(defun sp-litnotes-meta--parent-linkable-p (entry covered)
  "Non-nil when the bib-parent of ENTRY can be written: its note exists or would be made.
COVERED is the table of `sp-author-notes-bibtex--covered'.  A crossref whose key
has no note and no BibTeX entry (a typo, a truncated key) cannot be linked."
  (when-let* ((ref (sp-litnotes-meta--field entry "crossref")))
    (or (when-let* ((file (gethash ref covered))
                    (head (sp-author-notes--file-head file)))
          (and (plist-get head :id) t))
        (and sp-litnotes-meta-create-parent (sp-litnotes-meta--entry ref) t))))

(defun sp-litnotes-meta--missing-parents (entry covered)
  "The crossref key of ENTRY as a list when it has a BibTeX entry but no note, else nil.
COVERED is the table of `sp-author-notes-bibtex--covered'.  A chain deeper
than two levels gives nil: nothing is made for it."
  (let ((ref (sp-litnotes-meta--field entry "crossref")))
    (and ref
         (not (sp-litnotes-meta--crossref-chain entry))
         (not (gethash ref covered))
         (sp-litnotes-meta--entry ref)
         (list ref))))

(defun sp-litnotes-meta--plan-buffer (entry overwrite &optional covered)
  "Plan the changes to the current buffer from ENTRY; a plist.
:fill and :replace are alists of meta key to preview value, :missing lists
the default keys (project, status, relevance, priority) the note lacks,
:new-parents lists the crossref key when it would get a new note (see
`sp-litnotes-meta--missing-parents'; COVERED is the table of existing notes,
read when nil), :old holds the current value of each :replace key, :chain is a crossref chain deeper than two levels (see
`sp-litnotes-meta--crossref-chain'; bib-parent is not planned then), :no-parent
is the crossref key when it has neither a note nor a BibTeX entry (bib-parent is
not planned then either, so the note does not stay in the report), :tag
is (add . TAG) or (mismatch FOUND . EXPECTED), or nil, and :unquote is
\(OLD . NEW) when the pub-title has quotes around all of it and is not replaced
anyway, else nil."
  (let* ((chain (sp-litnotes-meta--crossref-chain entry))
         (covered (and (not chain)
                       (sp-litnotes-meta--field entry "crossref")
                       (not (sp-litnotes-meta--has-value-p "bib-parent"))
                       (or covered (sp-author-notes-bibtex--covered))))
         (unlinkable (and covered (not (sp-litnotes-meta--parent-linkable-p entry covered))))
         (no-parent (and unlinkable (sp-litnotes-meta--field entry "crossref")))
         fill replace old missing tag new-parents unquote)
    (dolist (key sp-litnotes-meta--bib-keys)
      (when-let* (((not (and (equal key "bib-parent") (or chain unlinkable))))
                  (value (sp-litnotes-meta--preview-value key entry)))
        (cond
         ((not (sp-litnotes-meta--has-value-p key))
          (push (cons key value) fill))
         ((and overwrite (member key sp-litnotes-meta--overwritable)
               (sp-litnotes-meta--differs-p key entry))
          (push (cons key value) replace)
          (push (cons key (sp-litnotes-meta--buffer-meta key)) old)))))
    (when-let* (((not (assoc "pub-title" replace)))
                (raw (sp-litnotes-meta--buffer-meta "pub-title"))
                (new (sp-litnotes-meta--unquote raw)))
      (setq unquote (cons raw new)))
    (when (and sp-litnotes-meta-create-parent (assoc "bib-parent" fill))
      (setq new-parents (sp-litnotes-meta--missing-parents entry covered)))
    (dolist (key sp-litnotes-meta--default-keys)
      (unless (sp-litnotes-meta--has-value-p key) (push key missing)))
    (let* ((expected (sp-bibtex-types-entry-tag entry))
           (known (seq-filter (lambda (tag) (member tag (sp-bibtex-types-all-tags)))
                              (sp-litnotes-meta--filetags))))
      (cond ((null known) (setq tag (cons 'add expected)))
            ((not (member expected known)) (setq tag (cons 'mismatch (cons known expected))))))
    (list :fill (nreverse fill) :replace (nreverse replace) :old (nreverse old)
          :missing (nreverse missing) :new-parents new-parents :chain chain :tag tag
          :unquote unquote :no-parent no-parent
          :order (and sp-litnotes-meta-order-meta
                      (let ((old (sp-vulpea-meta-order-block-keys)))
                        (not (sp-vulpea-meta-order-sorted-p
                              (append old (seq-remove
                                           (lambda (key) (seq-some (lambda (k) (string-equal-ignore-case key k)) old))
                                           (mapcar #'car fill))))))))))

(defun sp-litnotes-meta--planned-parents (plans)
  "The parent notes PLANS would make, once each, as a list of (REF . REQUESTERS).
REQUESTERS are the keys of the notes (or parents) that link REF."
  (let (alist)
    (dolist (plan plans)
      (let ((from (plist-get plan :key)))
        (dolist (ref (plist-get plan :new-parents))
          (if-let* ((cell (assoc ref alist)))
              (cl-pushnew from (cdr cell) :test #'equal)
            (push (list ref from) alist))
          (setq from ref))))
    (nreverse alist)))

(defun sp-litnotes-meta--batch-plan (file overwrite &optional covered)
  "What the batch would do to the note FILE, as a plist; nothing is written.
:status is `ok', `no-key' (no citation key in the note) or `no-entry' (none
of its keys is in the registered .bib files).  COVERED is the table of
existing notes, to read once for all files."
  (let* ((keys (plist-get (sp-litnotes-titles--parse file) :keys))
         (key (seq-find #'sp-litnotes-meta--entry keys))
         (plan (list :file file :keys keys :key key)))
    (cond
     ((null keys) (append plan (list :status 'no-key)))
     ((null key) (append plan (list :status 'no-entry)))
     (t (append plan (list :status 'ok)
                (with-temp-buffer
                  (insert-file-contents file)
                  (sp-litnotes-meta--plan-buffer (sp-litnotes-meta--entry key) overwrite covered)))))))

(defun sp-litnotes-meta--actionable-p (plan)
  "Non-nil when the batch would change the note of PLAN."
  (and (eq (plist-get plan :status) 'ok)
       (or (plist-get plan :fill) (plist-get plan :replace) (plist-get plan :order)
           (plist-get plan :unquote)
           (eq (car (plist-get plan :tag)) 'add))))

(defun sp-litnotes-meta--unquote-only-p (plan)
  "Non-nil when the only change of PLAN is removing the quotes of the pub-title."
  (and (plist-get plan :unquote)
       (not (or (plist-get plan :fill) (plist-get plan :replace) (plist-get plan :order)
                (eq (car (plist-get plan :tag)) 'add)))))

(defun sp-litnotes-meta--batch-plans (overwrite)
  "The plans of all notes tagged `sp-litnotes-meta-batch-tag'.
The .bib files are read once for all of them."
  (let ((sp-litnotes-meta--index nil))
    (sp-litnotes-meta-build-index)
    (let* ((files (sp-litnotes-meta--batch-files))
           (covered (sp-author-notes-bibtex--covered))
           (progress (make-progress-reporter "Planning litnote meta lines..." 0 (length files)))
           (n 0) plans)
      (dolist (file files)
        (push (sp-litnotes-meta--batch-plan file overwrite covered) plans)
        (progress-reporter-update progress (cl-incf n)))
      (progress-reporter-done progress)
      (nreverse plans))))

(defun sp-litnotes-meta--name (plan)
  "The file name of PLAN without its folder."
  (file-name-nondirectory (plist-get plan :file)))

(defun sp-litnotes-meta--file-link (plan)
  "An Org link that visits the file of PLAN."
  (sp-batch-report-file-link (plist-get plan :file)))

(defun sp-litnotes-meta--batch-report-text (plans overwrite)
  "The report of PLANS as text.  OVERWRITE says whether a prefix argument was given."
  (let* ((ok (seq-filter (lambda (p) (eq (plist-get p :status) 'ok)) plans))
         (todo (seq-filter #'sp-litnotes-meta--actionable-p plans))
         (listed (seq-remove #'sp-litnotes-meta--unquote-only-p todo))
         (quoted (seq-filter (lambda (p) (plist-get p :unquote)) ok))
         (no-key (seq-filter (lambda (p) (eq (plist-get p :status) 'no-key)) plans))
         (no-entry (seq-filter (lambda (p) (eq (plist-get p :status) 'no-entry)) plans))
         (mismatch (seq-filter (lambda (p) (eq (car (plist-get p :tag)) 'mismatch)) ok))
         (parents (sp-litnotes-meta--planned-parents todo))
         (chains (seq-filter (lambda (p) (plist-get p :chain)) ok))
         (orphans (seq-filter (lambda (p) (plist-get p :no-parent)) ok)))
    (with-temp-buffer
      (insert (format "Litnote meta fill: %d notes tagged %s%s\n\n"
                      (length plans) sp-litnotes-meta-batch-tag
                      (if overwrite ", updating pub-* values that differ from the .bib" "")))
      (insert (format "- To change: %d\n- Already complete: %d\n- Quoted pub-title: %d\n- No citation key: %d\n- Key not in the .bib files: %d\n- Parent notes to make: %d\n- Crossref chains deeper than two levels: %d\n- Crossref without a note or a BibTeX entry: %d\n- Problems in the last convert: %d\n\n"
                      (length listed) (- (length ok) (length todo)) (length quoted)
                      (length no-key) (length no-entry) (length parents) (length chains)
                      (length orphans) (length sp-litnotes-meta--errors)))
      (insert "* To change\n")
      (dolist (plan listed)
        (insert (format "- %s (%s)\n" (sp-litnotes-meta--file-link plan) (plist-get plan :key)))
        (dolist (item (plist-get plan :fill))
          (insert (format "  - fill %s :: %s%s\n" (car item) (cdr item)
                          (if (and (equal (car item) "bib-parent")
                                   (member (cdr item) (plist-get plan :new-parents)))
                              " (new note)" ""))))
        (dolist (item (plist-get plan :replace))
          (insert (format "  - update %s :: %s -> %s\n" (car item)
                          (or (cdr (assoc (car item) (plist-get plan :old))) "") (cdr item))))
        (when-let* ((q (plist-get plan :unquote)))
          (insert (format "  - unquote pub-title :: %s -> %s\n" (car q) (cdr q))))
        (when (eq (car (plist-get plan :tag)) 'add)
          (insert (format "  - add the tag %s\n" (cdr (plist-get plan :tag)))))
        (when (plist-get plan :order)
          (insert "  - order the meta lines\n")))
      (insert "\n* Quoted pub-title (the enclosing quotes are removed)\n")
      (dolist (plan quoted)
        (insert (format "- %s: %s -> %s\n" (sp-litnotes-meta--file-link plan)
                        (car (plist-get plan :unquote)) (cdr (plist-get plan :unquote)))))
      (insert "\n* Parent notes to make (each once, from the crossref)\n")
      (dolist (parent parents)
        (insert (format "- %s: %s (linked from %s)\n" (car parent)
                        (or (when-let* ((entry (sp-litnotes-meta--entry (car parent))))
                              (sp-litnotes-meta--new-title entry))
                            "")
                        (string-join (reverse (cdr parent)) ", "))))
      (insert "\n* Crossref chains deeper than two levels (flagged: left alone; convert one with M-x sp-litnotes-meta-fill-deep-chain)\n")
      (dolist (plan chains)
        (insert (format "- %s: %s -> %s\n" (sp-litnotes-meta--file-link plan) (plist-get plan :key)
                        (string-join (plist-get plan :chain) " -> "))))
      (insert "\n* Crossref without a note or a BibTeX entry (bib-parent left empty; fix the crossref key in the .bib file)\n")
      (dolist (plan orphans)
        (insert (format "- %s: crossref %s\n" (sp-litnotes-meta--file-link plan) (plist-get plan :no-parent))))
      (insert "\n* Problems in the last convert\n")
      (dolist (err (reverse sp-litnotes-meta--errors))
        (insert (format "- %s\n" err)))
      (insert "\n* Left empty (asked once by the convert command, or filled by hand)\n")
      (dolist (key sp-litnotes-meta--default-keys)
        (let ((lacking (seq-filter (lambda (p) (member key (plist-get p :missing))) ok)))
          (insert (format "- %s: %d notes\n" key (length lacking)))))
      (insert "\n* Skipped: no citation key\n")
      (dolist (plan no-key) (insert (format "- %s\n" (sp-litnotes-meta--file-link plan))))
      (insert "\n* Skipped: key not in the .bib files\n")
      (dolist (plan no-entry)
        (insert (format "- %s (%s)\n" (sp-litnotes-meta--file-link plan)
                        (string-join (plist-get plan :keys) ", "))))
      (insert "\n* Type tag differs from the BibTeX entry type (not changed)\n")
      (dolist (plan mismatch)
        (let ((tag (plist-get plan :tag)))
          (insert (format "- %s: has %s, the entry type says %s\n" (sp-litnotes-meta--file-link plan)
                          (string-join (cadr tag) ", ") (cddr tag)))))
      (buffer-string))))

(defvar sp-litnotes-meta--excluded nil
  "The notes (files) dropped from the report with `d'; the commands leave them out.")

(defun sp-litnotes-meta--without-excluded (plans)
  "PLANS minus the notes dropped from the report."
  (sp-batch-report-without-excluded plans (lambda (p) (plist-get p :file))
                                    sp-litnotes-meta--excluded))

(defun sp-litnotes-meta--show-report (plans overwrite)
  "Show the report of PLANS in its own buffer, without the dropped notes."
  (let ((excluded sp-litnotes-meta--excluded))
    (sp-batch-report-open
     sp-litnotes-meta--batch-buffer
     (concat (sp-batch-report-key-entries
              (sp-litnotes-meta--batch-report-text (sp-litnotes-meta--without-excluded plans) overwrite))
             (and excluded (concat "\n" (sp-batch-report-dropped-section excluded))))
     :refresh (lambda () (sp-litnotes-meta-fill-all-dryrun overwrite sp-litnotes-meta--excluded))
     :redraw (lambda (excl)
               (setq sp-litnotes-meta--excluded excl)
               (sp-litnotes-meta--show-report plans overwrite))
     :apply (lambda (excl) (sp-litnotes-meta-fill-all-convert overwrite excl))
     :excluded excluded)))

;;;###autoload
(defun sp-litnotes-meta-fill-all-dryrun (&optional overwrite excluded)
  "Show what `sp-litnotes-meta-fill-all-convert' would do; write nothing.
Every note tagged `sp-litnotes-meta-batch-tag' is checked against its BibTeX
entry.  The report lists the lines that would be filled, the notes without a
citation key or without a .bib entry (skipped), the default lines nobody
filled, and notes whose type tag differs from the entry type.  With a prefix
argument (OVERWRITE), or when `sp-litnotes-meta-update-changed' is non-nil (the
default), it also lists the pub-* values that differ from the BibTeX entry, with
the old and the new value, as \"update\".
EXCLUDED lists notes (files) to leave out; the report's \\`d' sets it.
Return the plans."
  (interactive "P")
  (setq sp-litnotes-meta--excluded excluded)
  (let* ((overwrite (or overwrite sp-litnotes-meta-update-changed))
         (plans (sp-litnotes-meta--batch-plans overwrite)))
    (sp-litnotes-meta--show-report plans overwrite)
    (sp-litnotes-meta--without-excluded plans)))

(defun sp-litnotes-meta--ask-defaults (plans)
  "Ask once for each default line some of PLANS lack; return the preset alist.
Every key of `sp-litnotes-meta--default-keys' is in it; an empty answer gives
nil, which leaves the line alone."
  (let ((preset nil))
    (dolist (key sp-litnotes-meta--default-keys)
      (let* ((n (+ (seq-count (lambda (p) (member key (plist-get p :missing))) plans)
                   (length (sp-litnotes-meta--planned-parents plans))))
             (value
              (when (> n 0)
                (pcase key
                  ("bib-project"
                   (when (y-or-n-p (format "Give the %d notes without bib-project the same project? " n))
                     (sp-litnotes-meta--read-project)))
                  ("read-status"
                   (sp-litnotes-meta--read-scale
                    (format "read-status for the %d notes without one ((none) to leave): " n)
                    sp-litnotes-meta-read-statuses))
                  ("relevance-factor"
                   (sp-litnotes-meta--read-scale
                    (format "relevance-factor for the %d notes without one ((none) to leave): " n)
                    sp-litnotes-meta-relevance-scale))
                  ("read-priority"
                   (sp-litnotes-meta--read-scale
                    (format "read-priority for the %d notes without one ((none) to leave): " n)
                    sp-litnotes-meta-priority-scale))))))
        (push (cons key value) preset)))
    (nreverse preset)))

(defun sp-litnotes-meta--describe-plan (plan)
  "One line about PLAN for the question that picks the notes of a batch."
  (format "%s: %s?" (sp-litnotes-meta--name plan)
          (string-join (append (mapcar (lambda (i) (concat "fill " (car i))) (plist-get plan :fill))
                               (mapcar (lambda (i) (format "update %s (%s -> %s)" (car i)
                                                           (or (cdr (assoc (car i) (plist-get plan :old))) "")
                                                           (cdr i)))
                                       (plist-get plan :replace))
                               (and (plist-get plan :unquote)
                                    (list (format "unquote pub-title (%s -> %s)"
                                                  (car (plist-get plan :unquote))
                                                  (cdr (plist-get plan :unquote)))))
                               (and (plist-get plan :order) '("order the meta lines"))
                               (and (eq (car (plist-get plan :tag)) 'add)
                                    (list (concat "add the tag " (cdr (plist-get plan :tag))))))
                       ", ")))

(defun sp-litnotes-meta--ensure-type-tag (entry)
  "Give the current note the tag of the type of ENTRY when it has no type tag.
Type tags are those of `sp-bibtex-types-all-tags'.  A note that has one, even
another one, is left alone.  The tag goes in the #+filetags line, which is
made after #+title when missing.  Return non-nil when the buffer changed."
  (let ((expected (sp-bibtex-types-entry-tag entry))
        (tags (sp-litnotes-meta--filetags)))
    (unless (seq-some (lambda (tag) (member tag (sp-bibtex-types-all-tags))) tags)
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (let ((case-fold-search t)
                (limit (sp-author-notes--first-heading)))
            (if (re-search-forward "^#\\+filetags:[ \t]*\\(.*\\)$" limit t)
                (replace-match (concat ":" (string-join (append tags (list expected)) ":") ":")
                               t t nil 1)
              (goto-char (point-min))
              (if (re-search-forward "^#\\+title:.*$" limit t)
                  (progn (end-of-line) (insert "\n"))
                (goto-char limit)
                (unless (bolp) (insert "\n")))
              (insert (format "#+filetags: :%s:%s:" sp-litnotes-meta-batch-tag expected))
              (unless (eq (char-after) ?\n) (insert "\n"))))))
      t)))

(defun sp-litnotes-meta--backup (file stamp)
  "Copy FILE to the STAMP sub-folder of `sp-litnotes-meta-backup-directory'."
  (let ((dir (expand-file-name (concat stamp "/") sp-litnotes-meta-backup-directory)))
    (make-directory dir t)
    ;; The first copy of a run is kept: it is the text from before any save of a buffer.
    (let ((target (expand-file-name (file-name-nondirectory file) dir)))
      (unless (file-exists-p target) (copy-file file target nil t)))))

(defun sp-litnotes-meta--apply-plan (plan stamp overwrite)
  "Back up and fill the note of PLAN; return the lines (and \"tag\") that changed."
  (let ((file (plist-get plan :file)))
    (sp-litnotes-meta--backup file stamp)
    (let ((changed (sp-litnotes-meta-fill (plist-get plan :key) file overwrite)))
      (when (and changed (fboundp 'vulpea-db-update-file))
        (ignore-errors (vulpea-db-update-file file)))
      changed)))

;;;###autoload
(defun sp-litnotes-meta-fill-all-convert (&optional overwrite excluded)
  "Fill the meta lines of every note tagged `sp-litnotes-meta-batch-tag' from BibTeX.
Run `sp-litnotes-meta-fill-all-dryrun' first.  This makes the same plan, asks
once before writing, then copies each note to a time-stamped folder in
`sp-litnotes-meta-backup-directory' and fills it like `sp-litnotes-meta-fill'.

- A line that has a value is left alone, except the pub-author, pub-editor,
  pub-title, pub-year and pub-pages ones that differ from the BibTeX entry: they are
  updated while `sp-litnotes-meta-update-changed' is non-nil (the default) or
  with a prefix argument (OVERWRITE).  bib-parent is never replaced here; see
  `sp-litnotes-meta-parent-lint-convert'.
- The notes go in batches of `sp-batch-report-batch-size' (50).  Before each
  batch (when there is more than one) you apply it all, choose the notes one
  by one, skip it or quit; what was not reached stays as it was, so you can
  stop after a few batches and run the command again later.
- Nothing is asked per note.  bib-project, read-status, relevance-factor and
  read-priority are asked once, for the notes that lack them; an empty or (none) answer
  leaves them empty.  A parent note that is missing (the crossref entry) is
  made once, filled from BibTeX and linked, and counted in those questions.
- A note with no citation key, or whose key is not in the .bib files, is skipped.
- A note without a type tag gets the one of `sp-bibtex-types' (`sp-litnotes-meta-fill' does that).
- A note with unsaved changes is skipped, and the error is listed.
After the run the report is shown again with what is still left.  EXCLUDED
lists notes (files) to leave out; the report's \\`A' passes the ones dropped
with \\`d'.  Return an alist of file to the lines changed (or the error)."
  (interactive "P")
  (setq sp-litnotes-meta--excluded excluded
        sp-litnotes-meta--errors nil)
  (let* ((overwrite (or overwrite sp-litnotes-meta-update-changed))
         (plans (sp-litnotes-meta--batch-plans overwrite))
         (todo (seq-filter #'sp-litnotes-meta--actionable-p
                           (sp-litnotes-meta--without-excluded plans))))
    (sp-litnotes-meta--show-report plans overwrite)
    (if (null todo)
        (progn (message "Nothing to change.") nil)
      (when (yes-or-no-p (format "Change %d litnotes, %d at a time (backups in %s)? "
                                 (length todo) (or sp-batch-report-batch-size (length todo))
                                 sp-litnotes-meta-backup-directory))
        (let* ((stamp (format-time-string "%Y%m%d-%H%M%S"))
               (sp-litnotes-meta--preset (sp-litnotes-meta--ask-defaults todo))
               (sp-litnotes-meta--made-parents (make-hash-table :test #'equal))
               (sp-litnotes-meta--index nil)
               (covered (progn (sp-litnotes-meta-build-index)
                               (sp-author-notes-bibtex--covered)))
               run results)
          (cl-letf (((symbol-function 'sp-author-notes-bibtex--covered) (lambda () covered)))
            (setq run (sp-batch-report-run-batches
                       todo
                       (lambda (plan _decision)
                         (push (cons (plist-get plan :file)
                                     (condition-case err
                                         (sp-litnotes-meta--apply-plan plan stamp overwrite)
                                       (error (sp-litnotes-meta--note-error
                                               "%s: %s" (file-name-nondirectory (plist-get plan :file))
                                               (error-message-string err))
                                              (error-message-string err))))
                               results))
                       :label "Litnote meta fill"
                       :describe #'sp-litnotes-meta--describe-plan)))
          (setq results (nreverse results))
          (message "Changed %d of %d notes; %d failed; %d parent notes made%s"
                   (seq-count #'consp (mapcar #'cdr results)) (length todo)
                   (seq-count #'stringp (mapcar #'cdr results))
                   (hash-table-count sp-litnotes-meta--made-parents)
                   (sp-batch-report-batches-note run))
          (sp-litnotes-meta--show-report (sp-litnotes-meta--batch-plans overwrite) overwrite)
          results)))))

;;;; Lint bib-parent

(defconst sp-litnotes-meta--parent-buffer "*litnote bib-parent lint*")

(defvar sp-litnotes-meta--parent-excluded nil
  "The notes (files) dropped from the bib-parent report with `d'.")

(defun sp-litnotes-meta--link-ids (value)
  "The ids of the id: links in the text VALUE, in order."
  (let ((value (or value "")) (start 0) ids)
    (while (string-match "\\[\\[id:\\([^]]+\\)\\]" value start)
      (push (match-string 1 value) ids)
      (setq start (match-end 0)))
    (nreverse ids)))

(defun sp-litnotes-meta--parent-plan (file)
  "What is wrong with the bib-parent line of the note FILE, as a plist, or nil.
:kind is `self' (it links the note itself), `no-crossref' (the BibTeX entry
has no crossref), `no-note' (the crossref has no note) or `wrong' (it links
another note than the one of the crossref).  :expected is the link it should
have, or nil when the line should be empty.  A note without bib-parent, or
with the right one, gives nil."
  (let* ((keys (plist-get (sp-litnotes-titles--parse file) :keys))
         (key (seq-find #'sp-litnotes-meta--entry keys))
         (entry (and key (sp-litnotes-meta--entry key)))
         (current (and entry (with-temp-buffer
                               (insert-file-contents file)
                               (sp-litnotes-meta--buffer-meta "bib-parent")))))
    (when current
      (let* ((ids (sp-litnotes-meta--link-ids current))
             (own (plist-get (sp-author-notes--file-head file) :id))
             (crossref (sp-litnotes-meta--field entry "crossref"))
             (target (and crossref (sp-litnotes-meta--note-for-key crossref)))
             (kind (cond ((and own (member own ids)) 'self)
                         ((null crossref) 'no-crossref)
                         ((null target) 'no-note)
                         ((not (equal ids (list (car target)))) 'wrong))))
        (when kind
          (list :file file :key key :kind kind :crossref crossref :current current
                :expected (and target (not (eq kind 'no-note))
                               (sp-litnotes-meta--link target))))))))

(defun sp-litnotes-meta--parent-plans ()
  "The bib-parent problems of all notes tagged `sp-litnotes-meta-batch-tag'."
  (let ((sp-litnotes-meta--index nil))
    (sp-litnotes-meta-build-index)
    (let* ((covered (sp-author-notes-bibtex--covered)) plans)
      (cl-letf (((symbol-function 'sp-author-notes-bibtex--covered) (lambda () covered)))
        (dolist (file (sp-litnotes-meta--batch-files))
          (when-let* ((plan (sp-litnotes-meta--parent-plan file)))
            (push plan plans))))
      (nreverse plans))))

(defconst sp-litnotes-meta--parent-kinds
  '((self . "Links the note itself")
    (wrong . "Links another note than the one of the crossref")
    (no-crossref . "The BibTeX entry has no crossref")
    (no-note . "The crossref has no note (make it, then run the meta fill)"))
  "The kinds of bib-parent problems and their report headings.")

(defun sp-litnotes-meta--parent-item (plan)
  "The report item of PLAN."
  (sp-batch-report-item
   (format "%s" (plist-get plan :key))
   :file (plist-get plan :file)
   :children (list (format "now :: %s" (sp-litnotes-titles--clean (plist-get plan :current)))
                   (format "should be :: %s"
                           (if-let* ((expected (plist-get plan :expected)))
                               (sp-litnotes-titles--clean expected)
                             "(empty)")))))

(defun sp-litnotes-meta--parent-report (plans excluded)
  "The report text of PLANS without the dropped notes EXCLUDED."
  (sp-batch-report-key-entries
   (sp-batch-report-text
    "Litnote bib-parent lint"
    (mapcar (lambda (kind)
              (sp-batch-report-section
               (cdr kind)
               (mapcar #'sp-litnotes-meta--parent-item
                       (seq-filter (lambda (p) (eq (plist-get p :kind) (car kind))) plans))))
            sp-litnotes-meta--parent-kinds)
    :intro (format "- A fix sets bib-parent to the note of the crossref, or empties it when there is none.\n- =d= drops a note for later, =u= brings it back, =A= fixes the rest (%d at a time)."
                   (or sp-batch-report-batch-size (length plans)))
    :excluded excluded)))

(defun sp-litnotes-meta--parent-show (plans)
  "Show the report of PLANS; the notes dropped with `d' are left out."
  (let ((excluded sp-litnotes-meta--parent-excluded))
    (sp-batch-report-open
     sp-litnotes-meta--parent-buffer
     (sp-litnotes-meta--parent-report plans excluded)
     :refresh (lambda () (sp-litnotes-meta-parent-lint-dryrun sp-litnotes-meta--parent-excluded))
     :redraw (lambda (excl)
               (setq sp-litnotes-meta--parent-excluded excl)
               (sp-litnotes-meta--parent-show plans))
     :apply (lambda (excl) (sp-litnotes-meta-parent-lint-convert excl))
     :excluded excluded)))

;;;###autoload
(defun sp-litnotes-meta-parent-lint-dryrun (&optional excluded)
  "List the notes whose bib-parent is wrong; write nothing.
Looks at every note tagged `sp-litnotes-meta-batch-tag' that has a bib-parent
and compares it with the crossref of its BibTeX entry.  Four kinds are listed:
the line links the note itself, links another note than the crossref's, the
entry has no crossref, or the crossref has no note.  EXCLUDED lists notes
(files) to leave out; the report's \\`d' drops one, \\`u' brings it back and
\\`A' runs `sp-litnotes-meta-parent-lint-convert'.  Return the plans."
  (interactive)
  (setq sp-litnotes-meta--parent-excluded excluded)
  (let ((plans (sp-litnotes-meta--parent-plans)))
    (sp-litnotes-meta--parent-show plans)
    (sp-batch-report-without-excluded plans (lambda (p) (plist-get p :file)) excluded)))

(defun sp-litnotes-meta--parent-choose (plan)
  "Ask what to do with the bib-parent of PLAN: `fix', `remove' or nil to skip."
  (let ((expected (plist-get plan :expected)))
    (pcase (read-char-choice
            (format "%s: bib-parent %s (%s).  %s[r]emove, [s]kip? "
                    (file-name-nondirectory (plist-get plan :file))
                    (sp-litnotes-titles--clean (plist-get plan :current))
                    (alist-get (plist-get plan :kind) sp-litnotes-meta--parent-kinds)
                    (if expected
                        (format "[f]ix to %s, " (sp-litnotes-titles--clean expected))
                      ""))
            (if expected '(?f ?r ?s) '(?r ?s)))
      (?f 'fix) (?r 'remove) (_ nil))))

(defun sp-litnotes-meta--parent-apply (plan decision stamp)
  "Back up the note of PLAN and fix its bib-parent as DECISION says.
DECISION is `remove' to empty the line; anything else sets the expected link,
or empties the line when there is none.  Return `fixed' or `removed'."
  (let* ((file (plist-get plan :file))
         (value (and (not (eq decision 'remove)) (plist-get plan :expected)))
         (buf (progn (sp-batch-report-flush-file
                      file (lambda (f) (sp-litnotes-meta--backup f stamp)))
                     (find-buffer-visiting file))))
    (when (and buf (buffer-modified-p buf))
      (user-error "%s has unsaved changes" (file-name-nondirectory file)))
    (sp-litnotes-meta--backup file stamp)
    (with-current-buffer (or buf (find-file-noselect file))
      (sp-litnotes-meta--put "bib-parent" (or value ""))
      (save-buffer))
    (if sp-batch-report-save-and-kill
        (sp-batch-report-close-file file)
      (unless buf (kill-buffer (find-buffer-visiting file))))
    (when (fboundp 'vulpea-db-update-file)
      (ignore-errors (vulpea-db-update-file file)))
    (if value 'fixed 'removed)))

;;;###autoload
(defun sp-litnotes-meta-parent-lint-convert (&optional excluded)
  "Fix the bib-parent of the notes `sp-litnotes-meta-parent-lint-dryrun' lists.
Asks once, then goes through the notes in batches of `sp-batch-report-batch-size'
(50).  Before each batch you fix it all (a note gets the link to the note of its
crossref, or an empty line when it has none), choose note by note (fix,
remove the link, skip), skip it or quit; what was not reached stays as it
was, so you can stop after a few batches.  Each note is copied to a
time-stamped folder in `sp-litnotes-meta-backup-directory' first; a note with
unsaved changes is skipped and listed.  EXCLUDED lists notes (files) to leave
out; the report's \\`A' passes the ones dropped with \\`d'.  Return an alist of
file to `fixed', `removed' or the error text."
  (interactive)
  (setq sp-litnotes-meta--parent-excluded excluded)
  (let* ((plans (sp-litnotes-meta--parent-plans))
         (todo (sp-batch-report-without-excluded plans (lambda (p) (plist-get p :file)) excluded)))
    (sp-litnotes-meta--parent-show plans)
    (if (null todo)
        (progn (message "No bib-parent to fix.") nil)
      (when (yes-or-no-p (format "Fix the bib-parent of %d litnotes, %d at a time (backups in %s)? "
                                 (length todo) (or sp-batch-report-batch-size (length todo))
                                 sp-litnotes-meta-backup-directory))
        (let* ((stamp (format-time-string "%Y%m%d-%H%M%S"))
               results
               (run (sp-batch-report-run-batches
                     todo
                     (lambda (plan decision)
                       (push (cons (plist-get plan :file)
                                   (condition-case err
                                       (sp-litnotes-meta--parent-apply plan decision stamp)
                                     (error (error-message-string err))))
                             results))
                     :label "bib-parent lint"
                     :choose #'sp-litnotes-meta--parent-choose)))
          (setq results (nreverse results))
          (message "bib-parent: %d fixed, %d emptied, %d failed%s"
                   (seq-count (lambda (r) (eq (cdr r) 'fixed)) results)
                   (seq-count (lambda (r) (eq (cdr r) 'removed)) results)
                   (seq-count (lambda (r) (stringp (cdr r))) results)
                   (sp-batch-report-batches-note run))
          (sp-litnotes-meta--parent-show (sp-litnotes-meta--parent-plans))
          results)))))

;;;; Lint pub-title

(defconst sp-litnotes-meta--title-buffer "*litnote pub-title lint*")

(defvar sp-litnotes-meta--title-excluded nil
  "The notes (files) dropped from the pub-title report with `d'.")

(defun sp-litnotes-meta--title-plan (file)
  "The quotes problem of the pub-title of the note FILE, as a plist, or nil.
:current is the line as written, :expected the title without the quotes that
enclose all of it.  A note without pub-title, or without such quotes, gives nil."
  (let ((current (with-temp-buffer
                   (insert-file-contents file)
                   (sp-litnotes-meta--buffer-meta "pub-title"))))
    (when-let* ((current)
                (expected (sp-litnotes-meta--unquote current)))
      (list :file file :current current :expected expected))))

(defun sp-litnotes-meta--title-plans ()
  "The quoted pub-titles of all notes tagged `sp-litnotes-meta-batch-tag'."
  (delq nil (mapcar #'sp-litnotes-meta--title-plan (sp-litnotes-meta--batch-files))))

(defun sp-litnotes-meta--title-item (plan)
  "The report item of PLAN."
  (sp-batch-report-item
   (file-name-nondirectory (plist-get plan :file))
   :file (plist-get plan :file)
   :children (list (format "now :: %s" (plist-get plan :current))
                   (format "should be :: %s" (plist-get plan :expected)))))

(defun sp-litnotes-meta--title-report (plans excluded)
  "The report text of PLANS without the dropped notes EXCLUDED."
  (sp-batch-report-key-entries
   (sp-batch-report-text
    "Litnote pub-title lint"
    (list (sp-batch-report-section
           "The pub-title has quotes around all of it"
           (mapcar #'sp-litnotes-meta--title-item plans)))
    :intro (format "- A fix removes the enclosing quotes (straight or curly) and keeps the ones inside.\n- =d= drops a note for later, =u= brings it back, =A= fixes the rest (%d at a time)."
                   (or sp-batch-report-batch-size (length plans)))
    :excluded excluded)))

(defun sp-litnotes-meta--title-show (plans)
  "Show the report of PLANS; the notes dropped with `d' are left out."
  (let ((excluded sp-litnotes-meta--title-excluded))
    (sp-batch-report-open
     sp-litnotes-meta--title-buffer
     (sp-litnotes-meta--title-report plans excluded)
     :refresh (lambda () (sp-litnotes-meta-title-lint-dryrun sp-litnotes-meta--title-excluded))
     :redraw (lambda (excl)
               (setq sp-litnotes-meta--title-excluded excl)
               (sp-litnotes-meta--title-show plans))
     :apply (lambda (excl) (sp-litnotes-meta-title-lint-convert excl))
     :excluded excluded)))

;;;###autoload
(defun sp-litnotes-meta-title-lint-dryrun (&optional excluded)
  "List the notes whose pub-title has quotes around all of it; write nothing.
Looks at every note tagged `sp-litnotes-meta-batch-tag', with or without a
BibTeX entry.  EXCLUDED lists notes (files) to leave out; the report's \\`d'
drops one, \\`u' brings it back and \\`A' runs `sp-litnotes-meta-title-lint-convert'.
Return the plans."
  (interactive)
  (setq sp-litnotes-meta--title-excluded excluded)
  (let ((plans (sp-litnotes-meta--title-plans)))
    (sp-litnotes-meta--title-show plans)
    (sp-batch-report-without-excluded plans (lambda (p) (plist-get p :file)) excluded)))

(defun sp-litnotes-meta--title-choose (plan)
  "Ask what to do with the pub-title of PLAN: `fix' or nil to skip."
  (pcase (read-char-choice
          (format "%s: pub-title %s -> %s.  [f]ix, [s]kip? "
                  (file-name-nondirectory (plist-get plan :file))
                  (plist-get plan :current) (plist-get plan :expected))
          '(?f ?s))
    (?f 'fix) (_ nil)))

(defun sp-litnotes-meta--title-apply (plan stamp)
  "Back up the note of PLAN and remove the quotes of its pub-title; return `fixed'."
  (let* ((file (plist-get plan :file))
         (buf (progn (sp-batch-report-flush-file
                      file (lambda (f) (sp-litnotes-meta--backup f stamp)))
                     (find-buffer-visiting file))))
    (when (and buf (buffer-modified-p buf))
      (user-error "%s has unsaved changes" (file-name-nondirectory file)))
    (sp-litnotes-meta--backup file stamp)
    (with-current-buffer (or buf (find-file-noselect file))
      (sp-litnotes-meta--put "pub-title" (plist-get plan :expected))
      (save-buffer))
    (if sp-batch-report-save-and-kill
        (sp-batch-report-close-file file)
      (unless buf (kill-buffer (find-buffer-visiting file))))
    (when (fboundp 'vulpea-db-update-file)
      (ignore-errors (vulpea-db-update-file file)))
    'fixed))

;;;###autoload
(defun sp-litnotes-meta-title-lint-convert (&optional excluded)
  "Remove the quotes around the pub-title of the notes the dry run lists.
Asks once, then goes through the notes in batches of `sp-batch-report-batch-size'
\(50).  Before each batch you fix it all, choose note by note (fix or skip),
skip it or quit; what was not reached stays as it was.  Each note is copied to
a time-stamped folder in `sp-litnotes-meta-backup-directory' first; a note with
unsaved changes is skipped and listed.  EXCLUDED lists notes (files) to leave
out; the report's \\`A' passes the ones dropped with \\`d'.  Return an alist of
file to `fixed' or the error text."
  (interactive)
  (setq sp-litnotes-meta--title-excluded excluded)
  (let* ((plans (sp-litnotes-meta--title-plans))
         (todo (sp-batch-report-without-excluded plans (lambda (p) (plist-get p :file)) excluded)))
    (sp-litnotes-meta--title-show plans)
    (if (null todo)
        (progn (message "No quoted pub-title to fix.") nil)
      (when (yes-or-no-p (format "Remove the quotes of the pub-title of %d litnotes, %d at a time (backups in %s)? "
                                 (length todo) (or sp-batch-report-batch-size (length todo))
                                 sp-litnotes-meta-backup-directory))
        (let* ((stamp (format-time-string "%Y%m%d-%H%M%S"))
               results
               (run (sp-batch-report-run-batches
                     todo
                     (lambda (plan _decision)
                       (push (cons (plist-get plan :file)
                                   (condition-case err
                                       (sp-litnotes-meta--title-apply plan stamp)
                                     (error (error-message-string err))))
                             results))
                     :label "pub-title lint"
                     :choose #'sp-litnotes-meta--title-choose)))
          (setq results (nreverse results))
          (message "pub-title: %d fixed, %d failed%s"
                   (seq-count (lambda (r) (eq (cdr r) 'fixed)) results)
                   (seq-count (lambda (r) (stringp (cdr r))) results)
                   (sp-batch-report-batches-note run))
          (sp-litnotes-meta--title-show (sp-litnotes-meta--title-plans))
          results)))))

(defun sp-litnotes-meta--after-create (key &rest _)
  "Fill the note `citar-create-note' made for KEY, when `sp-litnotes-meta-auto'."
  (when (and sp-litnotes-meta-auto (stringp key) (sp-litnotes-meta--entry key))
    (condition-case err
        (sp-litnotes-meta-fill key)
      (error (message "sp-litnotes-meta: %s: %s" key (error-message-string err))))))

(defcustom sp-litnotes-meta-citar-create t
  "Non-nil to make the notes that `citar-create-note' is asked for ourselves.
The note is made by `sp-litnotes-meta-create-function' (an ID, :CREATED:, the
litnote and BibTeX type tags, ROAM_REFS, the title of
`sp-litnotes-meta-new-title'), filled from BibTeX, and visited.  Nil leaves
the note to citar (and its `citar-vulpea-note-title-template')."
  :type 'boolean
  :group 'sp-litnotes-meta)

(defun sp-litnotes-meta--around-create (orig-fun key &rest args)
  "Make the note of KEY with `sp-litnotes-meta-create-function', not citar.
ORIG-FUN is `citar-create-note', called with KEY and ARGS when
`sp-litnotes-meta-citar-create' is nil, KEY has no BibTeX entry or already has
a note, or the note could not be made; the note is then filled afterwards."
  (let ((file (when (and sp-litnotes-meta-citar-create (stringp key)
                         (sp-litnotes-meta--entry key)
                         (not (gethash key (sp-author-notes-bibtex--covered))))
                (condition-case err
                    (funcall sp-litnotes-meta-create-function key)
                  (error (message "sp-litnotes-meta: %s: %s, using citar"
                                  key (error-message-string err))
                         nil)))))
    (if (not file)
        (prog1 (apply orig-fun key args)
          (sp-litnotes-meta--after-create key))
      (when sp-litnotes-meta-auto
        (condition-case err
            (sp-litnotes-meta-fill key file)
          (error (message "sp-litnotes-meta: %s: %s" key (error-message-string err)))))
      (find-file file))))

(advice-remove 'citar-create-note #'sp-litnotes-meta--after-create)
(advice-add 'citar-create-note :around #'sp-litnotes-meta--around-create)

(provide 'sp-litnotes-meta)
;; sp-litnotes-meta.el ends here
