;;; sp-vulpea-dblock.el --- Dataview-style property tables, backed by Vulpea -*- lexical-binding: t; -*-

(require 'vulpea)
(require 'org-table)

(defun sp-vulpea-dblock--cell (note column)
  "Return a display string for COLUMN of NOTE.
COLUMN is either a keyword naming a built-in field:
  :title  :tags  :id  :file
or a string naming a Vulpea meta key -- i.e. a \"KEY :: value\"
description-list entry in the note, read via
`vulpea-note-meta-get-list'. Multiple values for the same key are
joined with \", \"."
  (pcase column
    (:title (or (vulpea-note-title note) ""))
    (:tags (mapconcat #'identity (vulpea-note-tags note) ", "))
    (:id (vulpea-note-id note))
    (:file (file-name-nondirectory (vulpea-note-path note)))
    ((pred stringp)
     (mapconcat #'identity
                (or (vulpea-note-meta-get-list note column) '(""))
                ", "))
    (_ "")))

(defun sp-vulpea-dblock--header-label (column)
  "Return a display label for COLUMN (see `sp-vulpea-dblock--cell')."
  (if (keywordp column) (capitalize (substring (symbol-name column) 1)) column))

(defun sia-vulpea--resolve-parent-of (parent-of)
  "Resolve PARENT-OF to a literal note ID.
If PARENT-OF is the string \"self\" or the symbol `self', resolve
it to the ID of the note visited by the *current buffer*
(creating one via `org-id-get-create' at the top of the file if
it doesn't have one yet). Any other value -- nil, or an actual
ID string -- is returned unchanged."
  (if (member parent-of '("self" self))
      (save-excursion (goto-char (point-min)) (org-id-get-create))
    parent-of))

(defun sia-vulpea--note-matches-p (note tags parent-of parent-prop)
  "Non-nil if NOTE matches TAGS and, if given, PARENT-OF.
TAGS is a list NOTE's tags must all include (nil matches
everything). PARENT-OF, if non-nil, must already be a resolved
literal ID (see `sia-vulpea--resolve-parent-of') -- NOTE matches
only if its PARENT-PROP meta property (default \"parents\")
links to that ID."
  (and (or (null tags)
           (seq-every-p (lambda (tag) (seq-contains-p (vulpea-note-tags note) tag)) tags))
       (or (null parent-of)
           (seq-contains-p (vulpea-note-meta-get-list note (or parent-prop "parents") 'link)
                            parent-of))))

(defun sia-vulpea--note-tag-annotation (note)
  "Return a tag annotation string for NOTE, or \"\" if it has none.
`vulpea-note-tags' already reflects the right source depending on
NOTE's level -- filetags for a file-level note, heading tags for
a heading-level one -- so this shows the correct tags either way
without needing to special-case it, mirroring the sort of
tag-annotated candidates `org-node' shows in its completion."
  (let ((tags (vulpea-note-tags note)))
    (if tags
        (propertize (format "  :%s:" (mapconcat #'identity tags ":"))
                    'face 'org-tag)
      "")))

(defun sia-vulpea-select-note (prompt)
  "Select a Vulpea note via completion, annotated with its tags.
Built directly on `vulpea-db-query' and `completing-read' with a
plain `:annotation-function' -- standard completion metadata that
Vertico (and other UIs) already understand -- rather than
`vulpea-select', since I couldn't confirm that function exposes
a documented hook for customizing candidate display; this gets
the same practical result (see PROMPT; tags shown per
candidate) without depending on unconfirmed internals. Returns
the selected `vulpea-note', or nil if PROMPT was aborted."
  (let* ((notes (vulpea-db-query))
         (cands (mapcar (lambda (n) (cons (vulpea-note-title n) n)) notes))
         (completion-extra-properties
          (list :annotation-function
                (lambda (title) (sia-vulpea--note-tag-annotation (cdr (assoc title cands)))))))
    (cdr (assoc (completing-read prompt cands nil t) cands))))

(defun sia-vulpea-read-parent (&optional allow-self)
  "Interactively choose a parent-of value, returning nil/\"self\"/an ID.
Offers: no filtering, the current note itself (only if
ALLOW-SELF), or `sia-vulpea-select-note' to pick any note (tags
shown per candidate, to disambiguate same-titled notes). \"self\"
is returned literally, unresolved -- callers that need it
resolved immediately should still run it through
`sia-vulpea--resolve-parent-of'."
  (let* ((choices (append '("None")
                           (when allow-self '("Current note (self)"))
                           '("Choose a note...")))
         (choice (completing-read "Filter to children of: " choices nil t)))
    (cond
     ((string= choice "None") nil)
     ((string= choice "Current note (self)") "self")
     (t (let ((note (sia-vulpea-select-note "Parent note: ")))
          (and note (vulpea-note-id note)))))))

(defun org-dblock-write:vulpea-table (params)
  "Write a Dataview-style table of Vulpea notes into the current dynamic block.
Recognized PARAMS:

  :tags      List of tags to filter by; a note must have ALL of
             them to be included. Omit (or nil) for every note.

  :columns   List of columns to show, in order. Each entry is
             either a keyword (:title, :tags, :id, :file) or a
             string naming a Vulpea meta key (e.g. \"status\",
             \"author\", \"rating\"). Defaults to just (:title).

  :sort-by   A single column (same shape as above) to sort rows
             by, ascending, as a string comparison. Optional.

  :parent-of An ID, or the literal string \"self\", to filter
             by: only notes whose :parent-prop meta property
             links to this ID are included. \"self\" resolves
             dynamically, on every write, to the ID of the note
             this dblock itself lives in -- so a block placed in
             a parent note always shows its current children.
             Optional; omit for no such filtering.

  :parent-prop  Which meta property to check for :parent-of.
             Defaults to \"parents\".

Example block, written by hand or via `org-create-dblock':

  #+BEGIN: vulpea-table :tags (\"book\") :columns (:title \"author\" \"rating\") :sort-by \"rating\"
  #+END:

  #+BEGIN: vulpea-table :parent-of self :columns (:title)
  #+END:

Regenerate with `org-dblock-update' (C-c C-c on the #+BEGIN
line) or `org-update-all-dblocks' for every block in the buffer."
  (let* ((tags (plist-get params :tags))
         (columns (or (plist-get params :columns) '(:title)))
         (sort-by (plist-get params :sort-by))
         (parent-of (sia-vulpea--resolve-parent-of (plist-get params :parent-of)))
         (parent-prop (plist-get params :parent-prop))
         (notes (vulpea-db-query
                 (lambda (note)
                   (sia-vulpea--note-matches-p note tags parent-of parent-prop))))
         (notes (if sort-by
                    (seq-sort-by (lambda (n) (sp-vulpea-dblock--cell n sort-by))
                                 #'string< notes)
                  notes)))
    (insert "| " (mapconcat #'sp-vulpea-dblock--header-label columns " | ") " |\n")
    (insert "|-\n")
    (dolist (note notes)
      (insert "| "
              (mapconcat (lambda (c) (sp-vulpea-dblock--cell note c)) columns " | ")
              " |\n"))
    (when notes
      (delete-char -1))
    (org-table-align)))

(defun sia-insert-vulpea-table ()
  "Insert a new vulpea-table dynamic block at point, prompting for params.
A quick way to get a starting block without hand-typing the
#+BEGIN: line; edit the params afterwards as needed."
  (interactive)
  (let* ((tags (split-string (read-string "Filter by tags (space-separated, blank for all): ") nil t))
         (columns-raw (split-string
                       (read-string "Columns (space-separated; :title/:tags/:id/:file or meta keys): "
                                    ":title")
                       nil t))
         (columns (mapcar (lambda (c) (if (string-prefix-p ":" c) (intern c) c)) columns-raw))
         (sort-by (let ((s (read-string "Sort by column (blank for none): ")))
                    (unless (string-empty-p s)
                      (if (string-prefix-p ":" s) (intern s) s)))))
    (org-create-dblock
     (list :name "vulpea-table"
           :tags tags
           :columns columns
           :sort-by sort-by))
    (org-update-dblock)))

(provide 'sp-vulpea-dblock)
;;; sp-vulpea-dblock.el ends here