;;; sp-vulpea-table-core.el --- Query specs and rows for Vulpea tables -*- lexical-binding: t; -*-

;;; Commentary:

;; The data layer shared by every Vulpea table renderer (the `vulpea-table'
;; dynamic block, the exc grid, the vui table and the plain Org buffer).
;; A table is described by a "spec", a plist; `sp-vulpea-table-query'
;; turns it into notes, and `sp-vulpea-table-cell' into the text of one cell.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vulpea)

(defgroup sp-vulpea-table nil
  "Tables of Vulpea notes."
  :group 'vulpea
  :prefix "sp-vulpea-table-")

;;;; Specs

(defconst sp-vulpea-table-spec-keys
  '(:tags :tags-any :tags-none :directories :todo :links :meta
    :parent-of :parent-prop :level :title-match
    :columns :sort-by :sort-desc)
  "Keys a table spec may carry.
:TAGS, :TAGS-ANY and :TAGS-NONE are lists of tags (all, at least one,
none of them); :DIRECTORIES a list of directories a note's file lies
under; :TODO a list of TODO states; :LINKS a list of note IDs, at least
one of which the note links to; :META a list of (KEY . VALUE) where a nil
VALUE only asks for KEY to be present; :PARENT-OF an ID or the string
\"self\", checked against the meta key :PARENT-PROP (default \"parents\");
:LEVEL nil, 0 (file-level notes) or `headings'; :TITLE-MATCH a regexp;
:COLUMNS the columns to show and :SORT-BY the column to sort on, each a
keyword (see `sp-vulpea-table-builtin-columns') or the name of a meta key;
:SORT-DESC non-nil to sort descending.")

(defconst sp-vulpea-table-builtin-columns
  '(:title :tags :todo :level :priority :id :file :path)
  "Columns that are not meta keys.")

(defun sp-vulpea-table-spec-normalize (spec)
  "Return SPEC with only known keys, and :columns defaulting to (:title).
Tags, directories and the like are copied so callers may keep editing SPEC."
  (let (out)
    (dolist (key sp-vulpea-table-spec-keys)
      (when-let* ((cell (plist-member spec key)))
        (setq out (plist-put out key (copy-tree (cadr cell))))))
    (unless (plist-get out :columns)
      (setq out (plist-put out :columns (list :title))))
    out))

(defun sp-vulpea-table-resolve-parent-of (parent-of)
  "Resolve PARENT-OF to a literal note ID.
The string \"self\" (or the symbol `self') becomes the ID of the note the
current buffer visits, which `org-id-get-create' adds to the file when it
has none; anything else is returned unchanged."
  (if (member parent-of '("self" self))
      (progn
        (unless buffer-file-name
          (user-error "\"self\" needs a buffer that visits a note"))
        (save-excursion (goto-char (point-min)) (org-id-get-create)))
    parent-of))

(defun sp-vulpea-table-resolve-spec (spec)
  "Return SPEC with a \"self\" :parent-of resolved against the current buffer.
Call this in the buffer the table was asked from, before a renderer
switches buffers."
  (let ((spec (sp-vulpea-table-spec-normalize spec)))
    (if (plist-get spec :parent-of)
        (plist-put spec :parent-of
                   (sp-vulpea-table-resolve-parent-of (plist-get spec :parent-of)))
      spec)))

;;;; Querying

(defun sp-vulpea-table--under-directory-p (path directories)
  "Non-nil if PATH lies under one of DIRECTORIES."
  (let ((path (expand-file-name path)))
    (seq-some (lambda (dir)
                (string-prefix-p (file-name-as-directory (expand-file-name dir))
                                 path))
              directories)))

(defun sp-vulpea-table--meta-match-p (note clause)
  "Non-nil if NOTE satisfies the meta CLAUSE, a (KEY . VALUE) cons."
  (let ((values (vulpea-note-meta-get-list note (car clause))))
    (if (cdr clause)
        (member (cdr clause) values)
      values)))

(defun sp-vulpea-table-note-matches-p (note spec)
  "Non-nil if NOTE satisfies every filter in SPEC.
:PARENT-OF in SPEC must already be a literal ID."
  (let ((tags (vulpea-note-tags note))
        (parent-of (plist-get spec :parent-of)))
    (and (seq-every-p (lambda (tag) (member tag tags)) (plist-get spec :tags))
         (or (null (plist-get spec :tags-any))
             (seq-some (lambda (tag) (member tag tags)) (plist-get spec :tags-any)))
         (not (seq-some (lambda (tag) (member tag tags)) (plist-get spec :tags-none)))
         (or (null (plist-get spec :directories))
             (sp-vulpea-table--under-directory-p (vulpea-note-path note)
                                                 (plist-get spec :directories)))
         (or (null (plist-get spec :todo))
             (member (vulpea-note-todo note) (plist-get spec :todo)))
         (or (null (plist-get spec :links))
             (let ((dests (mapcar (lambda (l) (plist-get l :dest))
                                  (vulpea-note-links note))))
               (seq-some (lambda (id) (member id dests)) (plist-get spec :links))))
         (seq-every-p (lambda (clause) (sp-vulpea-table--meta-match-p note clause))
                      (plist-get spec :meta))
         (or (null parent-of)
             (member parent-of
                     (vulpea-note-meta-get-list
                      note (or (plist-get spec :parent-prop) "parents") 'link)))
         (pcase (plist-get spec :level)
           ('nil t)
           (0 (eql (vulpea-note-level note) 0))
           ('headings (> (or (vulpea-note-level note) 0) 0)))
         (or (null (plist-get spec :title-match))
             (let ((case-fold-search t))
               (string-match-p (plist-get spec :title-match)
                               (or (vulpea-note-title note) "")))))))

(defun sp-vulpea-table-cell (note column)
  "Return the text of COLUMN for NOTE.
COLUMN is a keyword from `sp-vulpea-table-builtin-columns', or a string
naming a meta key (several values are joined with \", \")."
  (pcase column
    (:title (or (vulpea-note-title note) ""))
    (:tags (string-join (vulpea-note-tags note) ", "))
    (:todo (or (vulpea-note-todo note) ""))
    (:level (number-to-string (or (vulpea-note-level note) 0)))
    (:priority (let ((p (vulpea-note-priority note))) (if p (format "%s" p) "")))
    (:id (or (vulpea-note-id note) ""))
    (:file (file-name-nondirectory (vulpea-note-path note)))
    (:path (abbreviate-file-name (vulpea-note-path note)))
    ((pred stringp)
     (string-join (vulpea-note-meta-get-list note column) ", "))
    (_ "")))

(defun sp-vulpea-table-header-label (column)
  "Return the heading text of COLUMN."
  (if (keywordp column)
      (capitalize (substring (symbol-name column) 1))
    column))

(defun sp-vulpea-table--sort-lessp (a b)
  "Non-nil if the cell text A sorts before B.
Numbers sort numerically and before text; empty cells go last."
  (let ((num-a (and (string-match-p "\\`-?[0-9]+\\(?:\\.[0-9]+\\)?\\'" a)
                    (string-to-number a)))
        (num-b (and (string-match-p "\\`-?[0-9]+\\(?:\\.[0-9]+\\)?\\'" b)
                    (string-to-number b))))
    (cond ((string-empty-p a) nil)
          ((string-empty-p b) t)
          ((and num-a num-b) (< num-a num-b))
          (num-a t)
          (num-b nil)
          (t (string-collate-lessp a b nil t)))))

(defun sp-vulpea-table-sort (notes column &optional descending)
  "Return NOTES sorted by COLUMN, reversed when DESCENDING."
  (if (null column)
      notes
    (let ((sorted (seq-sort-by (lambda (n) (sp-vulpea-table-cell n column))
                               #'sp-vulpea-table--sort-lessp notes)))
      (if descending (reverse sorted) sorted))))

(defun sp-vulpea-table-query (spec)
  "Return the notes SPEC asks for, sorted.
SPEC's :parent-of must be resolved already (see
`sp-vulpea-table-resolve-spec')."
  (let ((spec (sp-vulpea-table-spec-normalize spec)))
    (sp-vulpea-table-sort
     (vulpea-db-query (lambda (note) (sp-vulpea-table-note-matches-p note spec)))
     (plist-get spec :sort-by)
     (plist-get spec :sort-desc))))

(defun sp-vulpea-table-rows (notes columns)
  "Return one list of cell texts per note in NOTES, for COLUMNS."
  (mapcar (lambda (note)
            (mapcar (lambda (c) (sp-vulpea-table-cell note c)) columns))
          notes))

;;;; Describing a spec

(defun sp-vulpea-table-spec-summary (spec)
  "Return a one-line description of SPEC, for headers and prompts."
  (let (parts)
    (cl-flet ((add (label value)
                (when value
                  (push (format "%s %s" label
                                (if (listp value)
                                    (mapconcat (lambda (v) (format "%s" (if (consp v) (if (cdr v) (format "%s=%s" (car v) (cdr v)) (car v)) v)))
                                               value ", ")
                                  value))
                        parts))))
      (add "tags" (plist-get spec :tags))
      (add "any of" (plist-get spec :tags-any))
      (add "without" (plist-get spec :tags-none))
      (add "in" (mapcar #'abbreviate-file-name (plist-get spec :directories)))
      (add "todo" (plist-get spec :todo))
      (add "linking" (mapcar (lambda (id)
                               (if-let* ((n (ignore-errors (vulpea-db-get-by-id id))))
                                   (vulpea-note-title n)
                                 id))
                             (plist-get spec :links)))
      (add "meta" (plist-get spec :meta))
      (add "children of" (and (plist-get spec :parent-of)
                              (format "%s" (plist-get spec :parent-of))))
      (add "level" (pcase (plist-get spec :level) (0 "file-level") ('headings "headings")))
      (add "title ~" (plist-get spec :title-match)))
    (if parts (string-join (nreverse parts) "; ") "all notes")))

;;;; Choosing notes

(defun sp-vulpea-table--tag-annotation (note)
  "Return NOTE's tags as an annotation string, or \"\"."
  (if-let* ((tags (vulpea-note-tags note)))
      (propertize (format "  :%s:" (string-join tags ":")) 'face 'org-tag)
    ""))

(defun sp-vulpea-table-select-note (prompt)
  "Select a note with PROMPT; candidates are annotated with their tags.
Return the `vulpea-note'."
  (let* ((cands (mapcar (lambda (n) (cons (vulpea-note-title n) n)) (vulpea-db-query)))
         (completion-extra-properties
          (list :annotation-function
                (lambda (title)
                  (sp-vulpea-table--tag-annotation (cdr (assoc title cands)))))))
    (cdr (assoc (completing-read prompt cands nil t) cands))))

(defun sp-vulpea-table-read-parent (&optional allow-self)
  "Choose a :parent-of value: nil, \"self\" (when ALLOW-SELF) or a note ID."
  (let* ((choices (append '("None")
                          (when allow-self '("Current note (self)"))
                          '("Choose a note...")))
         (choice (completing-read "Filter to children of: " choices nil t)))
    (cond ((string= choice "None") nil)
          ((string= choice "Current note (self)") "self")
          (t (when-let* ((note (sp-vulpea-table-select-note "Parent note: ")))
               (vulpea-note-id note))))))

;;;; Writing a meta value back

(defvar sp-vulpea-table--last-write nil
  "Time of the last `sp-vulpea-table-write-meta', or nil.")

(defun sp-vulpea-table-write-meta (note key value)
  "Set the meta KEY of the file-level NOTE to VALUE, in NOTE's own file.
Replaces the first \"- KEY :: ...\" line before the first heading, or adds
one there (at the end of the file when it has no heading), then saves the
file.  A note for a heading has no meta of its own in this layout, so it
is refused rather than written to the wrong place."
  (unless (eql (vulpea-note-level note) 0)
    (user-error "Only file-level notes can be edited here (%s is a heading)"
                (vulpea-note-title note)))
  (with-current-buffer (find-file-noselect (vulpea-note-path note))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (let* ((case-fold-search nil)
               (limit (save-excursion
                        (if (re-search-forward "^\\*" nil t)
                            (line-beginning-position)
                          (point-max))))
               (re (format "^\\(-[ \t]+%s[ \t]+::[ \t]*\\).*$" (regexp-quote key))))
          (if (re-search-forward re limit t)
              (replace-match (concat "\\1" (replace-regexp-in-string
                                            "\\\\" "\\\\\\\\" value))
                             t)
            ;; After the last meta line of the file's own block, else at the limit.
            (goto-char (point-min))
            (let (last)
              (while (re-search-forward "^-[ \t]+[^ \t:]+[ \t]+::" limit t)
                (setq last (line-end-position)))
              (if last
                  (progn (goto-char last) (insert (format "\n- %s :: %s" key value)))
                (goto-char limit)
                (unless (bolp) (insert "\n"))
                (insert (format "- %s :: %s\n" key value))))))))
    (save-buffer)
    (setq sp-vulpea-table--last-write (current-time))))

;;;; Refreshing open tables

(defvar sp-vulpea-table-refresh-functions nil
  "Abnormal hook: functions called with no arguments when open tables
should run their query again.  A live table adds one while it is open.")

(defvar sp-vulpea-table--refresh-timer nil)

(defcustom sp-vulpea-table-refresh-delay 0.5
  "Seconds after saving a note before open tables run their query again.
The Vulpea database is updated by its own autosync; if tables sometimes
show stale data, lengthen this."
  :type 'number
  :group 'sp-vulpea-table)

(defun sp-vulpea-table-refresh-all ()
  "Tell every open live Vulpea table to run its query again."
  (interactive)
  (run-hooks 'sp-vulpea-table-refresh-functions))

(defun sp-vulpea-table--after-save ()
  "Schedule a refresh of open tables after an Org note is saved.
Skipped for two seconds after a table wrote a value itself, so the cell
just edited is not redrawn from a database that has not caught up."
  (when (and buffer-file-name
             (derived-mode-p 'org-mode)
             sp-vulpea-table-refresh-functions
             (not (and sp-vulpea-table--last-write
                       (< (float-time (time-since sp-vulpea-table--last-write)) 2))))
    (when (timerp sp-vulpea-table--refresh-timer)
      (cancel-timer sp-vulpea-table--refresh-timer))
    (setq sp-vulpea-table--refresh-timer
          (run-with-timer sp-vulpea-table-refresh-delay nil #'sp-vulpea-table-refresh-all))))

(add-hook 'after-save-hook #'sp-vulpea-table--after-save)

;;;; Old names

(define-obsolete-function-alias 'sia-vulpea--resolve-parent-of
  #'sp-vulpea-table-resolve-parent-of "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-select-note
  #'sp-vulpea-table-select-note "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-read-parent
  #'sp-vulpea-table-read-parent "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-refresh-all-tables
  #'sp-vulpea-table-refresh-all "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea--note-tag-annotation
  #'sp-vulpea-table--tag-annotation "2026-10-21")

(provide 'sp-vulpea-table-core)
;;; sp-vulpea-table-core.el ends here
