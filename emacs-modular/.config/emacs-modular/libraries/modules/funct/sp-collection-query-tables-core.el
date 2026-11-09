;;; sp-collection-query-tables-core.el --- Query specs and rows for query tables -*- lexical-binding: t; -*-

;;; Commentary:

;; The data layer shared by every query table renderer (the `collection-query-table'
;; dynamic block, the exc grid, the vui table and the plain Org buffer).
;; A table is described by a "spec", a plist; `sp-collec-query-query'
;; turns it into notes, and `sp-collec-query-cell' into the text of one cell.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vulpea)
(require 'org)
(require 'sp-org-id-link)

(defgroup sp-collec-query nil
  "Tables of Vulpea notes."
  :group 'vulpea
  :prefix "sp-collec-query-")

;;;; Specs

(defconst sp-collec-query-spec-keys
  '(:tags :tags-any :tags-none :directories :todo :links :meta
    :parent-of :parent-prop :except-prop :level :title-match :fold-tag :fold-prop
    :flagged :columns :sort-by :sort-desc :column-widths :wrap)
  "Keys a table spec may carry.
:TAGS, :TAGS-ANY and :TAGS-NONE are lists of tags (all, at least one,
none of them); :DIRECTORIES a list of directories a note's file lies
under; :TODO a list of TODO states; :LINKS a list of note IDs, at least
one of which the note links to; :META a list of (KEY . VALUE) where a nil
VALUE only asks for KEY to be present; :PARENT-OF an ID or the string
\"self\", checked against the meta key :PARENT-PROP (default \"parents\");
:EXCEPT-PROP a meta key whose links to :PARENT-OF leave a note out (an
edited work whose editor is also its author);
:LEVEL nil, 0 (file-level notes) or `headings'; :TITLE-MATCH a regexp;
:FOLD-TAG a tag whose notes are left out of the table and counted on the
note their meta key :FOLD-PROP (default \"bib-parent\") links to, shown
in the :sections column (the parent is added when it is not a result);
:FLAGGED non-nil to keep only the notes `sp-collec-query-check' warns about;
:COLUMNS the columns to show and :SORT-BY the column to sort on, each a
keyword (see `sp-collec-query-builtin-columns') or the name of a meta key;
:CHECK the warning of `sp-collec-query-check';
:PAGES shows the pub-pages meta key; sorting on it (or on the meta key
pub-pages) compares the first number in the text (9-30 before 31-99);
:REFS shows the ROAM_REFS property, :PDF the files of its top-level citation
keys (opened in the default reader) and :DEVONTHINK their DEVONthink items;
:BIBTEX shows the citation keys of ROAM_REFS as links that open the BibTeX
entry (and offer the `embark-act' actions of citar); :DT-PAGE links to the
page of the top-level PDF in DEVONthink where the note's pub-pages start;
:SORT-DESC non-nil to sort descending.  :SORT-BY may also be a list of
columns, applied in order: the first is the primary key and each next
one breaks the ties of those before it.  An element may be (COLUMN . asc)
or (COLUMN . desc) to set its own direction, otherwise :SORT-DESC applies.
:COLUMN-WIDTHS an alist of \(COLUMN . WIDTH) giving the width in
characters of a column in the exc table, T standing for the columns not
listed; :WRAP `wrap' to wrap long text inside the width, or `fit' to size
a column to its text, up to `sp-collec-query-exc-max-width'.  The last
two only apply to the exc renderer and fall back to the options of the
same name.")

(defconst sp-collec-query-builtin-columns
  '(:title :tags :todo :level :priority :id :file :path :sections :pages :check
    :refs :pdf :devonthink :bibtex :dt-page)
  "Columns that are not meta keys.")

(defun sp-collec-query-spec-normalize (spec)
  "Return SPEC with only known keys, and :columns defaulting to (:title).
Tags, directories and the like are copied so callers may keep editing SPEC."
  (let (out)
    (dolist (key sp-collec-query-spec-keys)
      (when-let* ((cell (plist-member spec key)))
        (setq out (plist-put out key (copy-tree (cadr cell))))))
    (unless (plist-get out :columns)
      (setq out (plist-put out :columns (list :title))))
    out))

(defun sp-collec-query-resolve-parent-of (parent-of)
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

(defun sp-collec-query-resolve-spec (spec)
  "Return SPEC with a \"self\" :parent-of resolved against the current buffer.
Call this in the buffer the table was asked from, before a renderer
switches buffers."
  (let ((spec (sp-collec-query-spec-normalize spec)))
    (if (plist-get spec :parent-of)
        (plist-put spec :parent-of
                   (sp-collec-query-resolve-parent-of (plist-get spec :parent-of)))
      spec)))

;;;; Querying

(defun sp-collec-query--under-directory-p (path directories)
  "Non-nil if PATH lies under one of DIRECTORIES."
  (let ((path (expand-file-name path)))
    (seq-some (lambda (dir)
                (string-prefix-p (file-name-as-directory (expand-file-name dir))
                                 path))
              directories)))

(defun sp-collec-query--meta-match-p (note clause)
  "Non-nil if NOTE satisfies the meta CLAUSE, a (KEY . VALUE) cons."
  (let ((values (vulpea-note-meta-get-list note (car clause))))
    (if (cdr clause)
        (member (cdr clause) values)
      values)))

(defun sp-collec-query-note-matches-p (note spec)
  "Non-nil if NOTE satisfies every filter in SPEC.
:PARENT-OF in SPEC must already be a literal ID."
  (let ((tags (vulpea-note-tags note))
        (parent-of (plist-get spec :parent-of)))
    (and (seq-every-p (lambda (tag) (member tag tags)) (plist-get spec :tags))
         (or (null (plist-get spec :tags-any))
             (seq-some (lambda (tag) (member tag tags)) (plist-get spec :tags-any)))
         (not (seq-some (lambda (tag) (member tag tags)) (plist-get spec :tags-none)))
         (or (null (plist-get spec :directories))
             (sp-collec-query--under-directory-p (vulpea-note-path note)
                                                 (plist-get spec :directories)))
         (or (null (plist-get spec :todo))
             (member (vulpea-note-todo note) (plist-get spec :todo)))
         (or (null (plist-get spec :links))
             (let ((dests (mapcar (lambda (l) (plist-get l :dest))
                                  (vulpea-note-links note))))
               (seq-some (lambda (id) (member id dests)) (plist-get spec :links))))
         (seq-every-p (lambda (clause) (sp-collec-query--meta-match-p note clause))
                      (plist-get spec :meta))
         (or (null parent-of)
             (member parent-of
                     (vulpea-note-meta-get-list
                      note (or (plist-get spec :parent-prop) "parents") 'link)))
         (or (null parent-of) (null (plist-get spec :except-prop))
             (not (member parent-of
                          (vulpea-note-meta-get-list
                           note (plist-get spec :except-prop) 'link))))
         (or (not (plist-get spec :flagged))
             (not (string-empty-p (sp-collec-query-check note))))
         (pcase (plist-get spec :level)
           ('nil t)
           (0 (eql (vulpea-note-level note) 0))
           ('headings (> (or (vulpea-note-level note) 0) 0)))
         (or (null (plist-get spec :title-match))
             (let ((case-fold-search t))
               (string-match-p (plist-get spec :title-match)
                               (or (vulpea-note-title note) "")))))))

(defun sp-collec-query--property (note name)
  "Return the value of the file or heading property NAME of NOTE, or nil.
NAME is compared without regard to case."
  (cdr (seq-find (lambda (cell) (string-equal-ignore-case (car cell) name))
                 (vulpea-note-properties note))))

(defun sp-collec-query--citekeys (note)
  "Return the citation keys in the ROAM_REFS property of NOTE.
Both `@key' and `cite:key' are read; URLs are skipped."
  (and-let* ((refs (sp-collec-query--property note "ROAM_REFS")))
    (let ((pos 0) keys)
      (while (string-match "\\(?:@\\|\\<cite:&?\\)\\([^][:space:]\",;]+\\)" refs pos)
        (push (match-string 1 refs) keys)
        (setq pos (match-end 0)))
      (nreverse keys))))

(defun sp-collec-query--crossref-root (key)
  "Return the top-level key of KEY: the end of its `crossref' chain.
A book chapter points to its book; the book is the key whose file counts.
The chain stops at a key without a parent, with a parent that has no entry
in the bibliography, or when a key comes up twice."
  (let ((seen (list key)) (current key) parent)
    (while (and (fboundp 'citar-get-entry)
                (setq parent (cdr (assoc-string
                                   "crossref" (ignore-errors (citar-get-entry current)) t)))
                (stringp parent)
                (not (member parent seen))
                (ignore-errors (citar-get-entry parent)))
      (push parent seen)
      (setq current parent))
    current))

(defun sp-collec-query--root-keys (note)
  "Return the top-level citation keys of NOTE, each once."
  (delete-dups (mapcar #'sp-collec-query--crossref-root
                       (sp-collec-query--citekeys note))))

(defun sp-collec-query--root-files (note)
  "Return the files of NOTE's top-level keys, each once.
The files are those `citar-get-files' finds from the `file' field of the
BibTeX entry and `citar-library-paths'."
  (when (fboundp 'citar-get-files)
    (let (files)
      (dolist (key (sp-collec-query--root-keys note))
        (dolist (file (gethash key (citar-get-files key)))
          (push (expand-file-name file) files)))
      (delete-dups (nreverse files)))))

(defun sp-collec-query--open-file (path)
  "Open PATH with the default application of the system."
  (if (eq system-type 'darwin)
      (call-process "open" nil 0 nil path)
    (call-process "xdg-open" nil 0 nil path)))

(with-eval-after-load 'org
  (org-link-set-parameters "sp-open" :follow #'sp-collec-query--open-file))

(defun sp-collec-query--pdf-links (note)
  "Return the files of NOTE's top-level keys as links in the default reader.
A key that is a chapter of a book gives the book's file, once.  The text
is empty without citar or a file."
  (mapconcat (lambda (file)
               (format "[[sp-open:%s][%s]]" (org-link-escape file)
                       (file-name-nondirectory file)))
             (sp-collec-query--root-files note) ", "))

(defvar sp-collec-query--dt-uuids (make-hash-table :test 'equal)
  "File name to the UUID of its DEVONthink record, or :none.")

(defconst sp-collec-query--dt-script
  "const app = Application('DEVONthink'); const out = {};
for (const name of %s) { const found = app.lookupRecordsWithFile(name);
  if (found.length) out[name] = found[0].uuid(); }
JSON.stringify(out);"
  "JXA that maps file names to the UUIDs of DEVONthink records.")

(defun sp-collec-query--dt-running-p ()
  "Non-nil if DEVONthink runs, so that a lookup does not start it."
  (and (eq system-type 'darwin)
       (zerop (call-process "pgrep" nil nil nil "-f" "DEVONthink"))))

(defun sp-collec-query--dt-lookup (names)
  "Cache the DEVONthink UUIDs of the file NAMES in one call to DEVONthink."
  (setq names (seq-remove (lambda (n) (gethash n sp-collec-query--dt-uuids))
                          (delete-dups (copy-sequence names))))
  (when (and names (sp-collec-query--dt-running-p))
    (let ((found (ignore-errors
                   (with-temp-buffer
                     (call-process "osascript" nil t nil "-l" "JavaScript" "-e"
                                   (format sp-collec-query--dt-script
                                           (json-encode (vconcat names))))
                     (goto-char (point-min))
                     (json-parse-buffer :object-type 'alist)))))
      (dolist (name names)
        (puthash name (or (cdr (assq (intern name) found)) :none)
                 sp-collec-query--dt-uuids)))))

(defun sp-collec-query--dt-warm (notes)
  "Look up the DEVONthink records for the files of NOTES in one go."
  (sp-collec-query--dt-lookup
   (mapcar #'file-name-nondirectory
           (seq-mapcat #'sp-collec-query--root-files notes))))

(defun sp-collec-query--dt-record-uuids (note)
  "Return the DEVONthink UUIDs of NOTE's top-level files, each once.
Files DEVONthink does not know are left out."
  (let ((files (mapcar #'file-name-nondirectory (sp-collec-query--root-files note))))
    (sp-collec-query--dt-lookup files)
    (seq-uniq (seq-filter #'stringp
                          (mapcar (lambda (name) (gethash name sp-collec-query--dt-uuids))
                                  files)))))

(defun sp-collec-query--dt-links (note)
  "Return the DEVONthink item links of NOTE's top-level files, each once."
  (mapconcat (lambda (uuid) (format "[[x-devonthink-item://%s][x]]" uuid))
             (sp-collec-query--dt-record-uuids note) ", "))

(defcustom sp-collec-query-dt-page-offset 0
  "Pages of the PDF in front of the printed page 1.
Added to the first number of pub-pages to find the PDF page, so with a
preface of 12 pages the printed page 1 is page 13.  A book or collection
note may set its own with the meta key `sp-collec-query-dt-offset-prop'."
  :type 'integer
  :group 'sp-collec-query)

(defcustom sp-collec-query-dt-offset-prop "pdf-offset"
  "Meta key of a book or collection note that sets the page offset of its PDF.
It takes the place of `sp-collec-query-dt-page-offset' for the sections
whose bib-parent links to that note."
  :type 'string
  :group 'sp-collec-query)

(defvar sp-collec-query-check-parent-prop)

(defun sp-collec-query--dt-page-offset (note)
  "Return the page offset for the PDF of NOTE's parent, else the default."
  (or (ignore-errors
        (and-let* ((id (car (vulpea-note-meta-get-list
                             note sp-collec-query-check-parent-prop 'link)))
                   (parent (vulpea-db-get-by-id id))
                   (text (car (vulpea-note-meta-get-list
                               parent sp-collec-query-dt-offset-prop)))
                   ((string-match-p "\\`[-+]?[0-9]+\\'" (string-trim text))))
          (string-to-number text)))
      sp-collec-query-dt-page-offset))

(defun sp-collec-query--dt-page-links (note)
  "Return links to the page of NOTE's top-level PDF where its pub-pages start.
The link is an x-devonthink-item URL with the page parameter, which counts
pages from 0; its text is the printed page.  Without a number in pub-pages
the link opens the PDF at its first page."
  (let ((printed (sp-collec-query-first-page
                  (car (vulpea-note-meta-get-list note "pub-pages"))))
        (offset (sp-collec-query--dt-page-offset note)))
    (mapconcat
     (lambda (uuid)
       (if printed
           (format "[[x-devonthink-item://%s?page=%d][p. %d]]"
                   uuid (max 0 (+ printed offset -1)) printed)
         (format "[[x-devonthink-item://%s][open]]" uuid)))
     (sp-collec-query--dt-record-uuids note) ", ")))

(defcustom sp-collec-query-check-rules
  '(("booksection" . "book") ("incollection" . "collection"))
  "Pairs (CHILD-TAG . PARENT-TAG) that `sp-collec-query-check' enforces.
A note with CHILD-TAG must link with `sp-collec-query-check-parent-prop'
to a note with PARENT-TAG, and a note that links to a PARENT-TAG note must
carry CHILD-TAG."
  :type '(alist :key-type string :value-type string)
  :group 'sp-collec-query)

(defcustom sp-collec-query-check-parent-prop "bib-parent"
  "Meta key `sp-collec-query-check' follows to the parent of a note."
  :type 'string
  :group 'sp-collec-query)

(defun sp-collec-query-check (note)
  "Return a warning for NOTE when its tags and its parent's do not fit, else \"\".
The rules are `sp-collec-query-check-rules': a booksection belongs to a
book, an incollection to a collection, and the other way round."
  (let* ((prop sp-collec-query-check-parent-prop)
         (parent (and-let* ((id (car (vulpea-note-meta-get-list note prop 'link))))
                   (ignore-errors (vulpea-db-get-by-id id))))
         (tags (vulpea-note-tags note))
         (parent-tags (and parent (vulpea-note-tags parent)))
         problems)
    (dolist (rule sp-collec-query-check-rules)
      (let ((child-tag (car rule)) (parent-tag (cdr rule)))
        (cond ((member child-tag tags)
               (cond ((null parent)
                      (push (format "%s without %s" child-tag prop) problems))
                     ((not (member parent-tag parent-tags))
                      (push (format "%s but the parent is not tagged %s"
                                    child-tag parent-tag)
                            problems))))
              ((and parent (member parent-tag parent-tags))
               (push (format "the parent is a %s but this is not tagged %s"
                             parent-tag child-tag)
                     problems)))))
    (if problems (concat "⚠ " (string-join (nreverse problems) "; ")) "")))

(defun sp-collec-query-first-page (text)
  "Return the first number in TEXT, such as \"pp. 12-34\", or nil.
Roman numerals and empty text give nil."
  (and (stringp text)
       (string-match "[0-9]+" text)
       (string-to-number (match-string 0 text))))

(defun sp-collec-query-cell (note column)
  "Return the text of COLUMN for NOTE.
COLUMN is a keyword from `sp-collec-query-builtin-columns', or a string
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
    (:refs (or (sp-collec-query--property note "ROAM_REFS") ""))
    (:pdf (sp-collec-query--pdf-links note))
    (:devonthink (sp-collec-query--dt-links note))
    (:dt-page (sp-collec-query--dt-page-links note))
    (:bibtex (mapconcat (lambda (key) (concat "@" key))
                        (sp-collec-query--citekeys note) " "))
    (:check (sp-collec-query-check note))
    (:pages (or (car (vulpea-note-meta-get-list note "pub-pages")) ""))
    (:sections (let ((n (gethash note sp-collec-query--folded 0)))
                 (if (> n 0) (number-to-string n) "")))
    ((pred stringp)
     (string-join (vulpea-note-meta-get-list note column) ", "))
    (_ "")))

(defconst sp-collec-query--key-regexp
  "\\(?:@\\|\\<cite:&?\\)\\([^][:space:]\",;]+\\)"
  "Regexp for a citation key in a ROAM_REFS value; group 1 is the key.")

(defcustom sp-collec-query-note-link-columns '("pub-title")
  "Meta columns whose text is shown as a link to the note itself.
Following the link opens the note in Org, like the :title column does."
  :type '(repeat string)
  :group 'sp-collec-query)

(defun sp-collec-query--open-bib-entry (key)
  "Open the BibTeX entry KEY in its .bib file."
  (if (fboundp 'citar-open-entry)
      (citar-open-entry key)
    (user-error "citar is not available to open %s" key)))

(with-eval-after-load 'org
  (org-link-set-parameters "sp-bib" :follow #'sp-collec-query--open-bib-entry))

(defvar embark-target-finders)

(defun sp-collec-query--bib-key-at-point ()
  "Return an embark target for the sp-bib: link at point, or nil.
The target is a `citar-key', so `embark-act' offers the actions of citar
\(open the entry, the files, the notes, the links, copy the reference).
The link is found by its text property in the vui and exc tables and as
an Org link in the dynamic block and the Org buffer."
  (let ((link (or (get-text-property (point) 'sp-org-link) ; already unescaped
                  (and (derived-mode-p 'org-mode)
                       (let ((context (org-element-context)))
                         (and (eq (org-element-type context) 'link)
                              (org-link-unescape
                               (org-element-property :raw-link context))))))))
    (when (and (stringp link) (string-prefix-p "sp-bib:" link))
      (cons 'citar-key (substring link (length "sp-bib:"))))))

(with-eval-after-load 'embark
  (require 'citar-embark nil t)
  (add-hook 'embark-target-finders #'sp-collec-query--bib-key-at-point))

(defun sp-collec-query--refs-links (text)
  "Return TEXT with each citation key in it written as an sp-bib: link."
  (replace-regexp-in-string
   sp-collec-query--key-regexp
   (lambda (match)
     (string-match sp-collec-query--key-regexp match)
     (let ((key (match-string 1 match)))
       (format "[[sp-bib:%s][@%s]]" (org-link-escape key) key)))
   text t t))

(defun sp-collec-query--note-link (note text)
  "Return TEXT as a link to NOTE, or TEXT when it is empty or NOTE has no ID."
  (if (or (string-empty-p text) (null (vulpea-note-id note)))
      text
    (format "[[id:%s][%s]]" (vulpea-note-id note)
            (replace-regexp-in-string "[][]" "" text))))

(defun sp-collec-query-display-cell (note column)
  "Return the text of COLUMN for NOTE, with note IDs written as links.
This covers the :id column and meta values that are an ID; :refs keys
open their BibTeX entry and the columns of `sp-collec-query-note-link-columns'
open the note.  Sorting
keeps using `sp-collec-query-cell', so it still compares the plain text."
  (let ((text (sp-collec-query-cell note column)))
    (cond ((memq column '(:refs :bibtex)) (sp-collec-query--refs-links text))
          ((and (stringp column) (member column sp-collec-query-note-link-columns))
           (sp-collec-query--note-link note text))
          ((or (eq column :id) (stringp column))
           (sp-org-link-link-ids text))
          (t text))))

(defun sp-collec-query-header-label (column)
  "Return the heading text of COLUMN."
  (cond ((eq column :devonthink) "DT")
        ((eq column :dt-page) "DT page")
        ((eq column :bibtex) "BibTeX")
        ((keywordp column) (capitalize (substring (symbol-name column) 1)))
        (t column)))

(defun sp-collec-query--sort-lessp (a b)
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

(defun sp-collec-query-sort-keys (sort-by &optional descending)
  "Return SORT-BY as a list of (COLUMN . DESCENDING) keys, primary first.
SORT-BY is nil, one column, or a list of columns, each optionally
(COLUMN . asc) or (COLUMN . desc); a plain column is descending when
DESCENDING is non-nil."
  (mapcar (lambda (key)
            (if (consp key)
                (cons (car key) (and (memq (cdr key) '(desc t)) t))
              (cons key (and descending t))))
          (if (listp sort-by) sort-by (list sort-by))))

(defun sp-collec-query--keys-lessp (cells-a cells-b keys)
  "Non-nil if the row CELLS-A sorts before CELLS-B under KEYS.
Each key decides unless both cells are equal under it; then the next does."
  (let (result decided)
    (while (and keys (not decided))
      (let* ((a (pop cells-a)) (b (pop cells-b)) (desc (cdr (pop keys))))
        (cond ((sp-collec-query--sort-lessp a b)
               (setq decided t result (not desc)))
              ((sp-collec-query--sort-lessp b a)
               (setq decided t result desc)))))
    result))

(defun sp-collec-query--sort-cell (note column)
  "Return the text NOTE is compared on when sorting by COLUMN.
That is the text of the cell, except for pages (:pages or the meta key
\"pub-pages\"), where it is the first number in the text, or empty."
  (if (member column '(:pages "pub-pages"))
      (if-let* ((n (sp-collec-query-first-page
                    (car (vulpea-note-meta-get-list note "pub-pages")))))
          (number-to-string n)
        "")
    (sp-collec-query-cell note column)))

(defun sp-collec-query-sort (notes sort-by &optional descending)
  "Return NOTES sorted by SORT-BY, descending when DESCENDING.
SORT-BY is a column or a list of keys, see `sp-collec-query-sort-keys'.
The sort is stable, so notes equal under every key keep their order."
  (if-let* ((keys (sp-collec-query-sort-keys sort-by descending)))
      (let ((rows (mapcar (lambda (n)
                            (cons n (mapcar (lambda (k) (sp-collec-query--sort-cell n (car k)))
                                            keys)))
                          notes)))
        (mapcar #'car (sort rows (lambda (a b)
                                   (sp-collec-query--keys-lessp (cdr a) (cdr b) keys)))))
    notes))

(defvar sp-collec-query--folded (make-hash-table :test #'eq :weakness 'key)
  "Number of folded notes per note object returned by `sp-collec-query-query'.")

(defun sp-collec-query--fold (notes spec)
  "Return NOTES without the notes tagged :fold-tag of SPEC.
Each one is counted in `sp-collec-query--folded' on the note its meta key
:fold-prop links to; that parent is added when NOTES lack it, and is
dropped from the count when no note has the ID."
  (if-let* ((tag (plist-get spec :fold-tag)))
      (let* ((prop (or (plist-get spec :fold-prop) "bib-parent"))
             (kept (seq-remove (lambda (n) (member tag (vulpea-note-tags n))) notes))
             (by-id (make-hash-table :test #'equal))
             (counts (make-hash-table :test #'equal)))
        (dolist (n kept) (puthash (vulpea-note-id n) n by-id))
        (dolist (n notes)
          (when (member tag (vulpea-note-tags n))
            (dolist (id (delete-dups (vulpea-note-meta-get-list n prop 'link)))
              (cl-incf (gethash id counts 0))
              (unless (gethash id by-id)
                (when-let* ((parent (ignore-errors (vulpea-db-get-by-id id))))
                  (puthash id parent by-id)
                  (push parent kept))))))
        (maphash (lambda (id count)
                   (when-let* ((parent (gethash id by-id)))
                     (puthash parent count sp-collec-query--folded)))
                 counts)
        kept)
    notes))

(defun sp-collec-query--warm (notes spec)
  "Return NOTES, after looking up what the columns of SPEC need in one go."
  (when (seq-intersection '(:devonthink :dt-page) (plist-get spec :columns))
    (sp-collec-query--dt-warm notes))
  notes)

(defun sp-collec-query-query (spec)
  "Return the notes SPEC asks for, sorted.
SPEC's :parent-of must be resolved already (see
`sp-collec-query-resolve-spec')."
  (let ((spec (sp-collec-query-spec-normalize spec)))
    (sp-collec-query-sort
     (sp-collec-query--warm
      (sp-collec-query--fold
       (vulpea-db-query (lambda (note) (sp-collec-query-note-matches-p note spec)))
       spec)
      spec)
     (plist-get spec :sort-by)
     (plist-get spec :sort-desc))))

(defun sp-collec-query-title-label (note)
  "Return the title of NOTE with the emoji of its tags in front, if any.
The emoji come from `sp-org-tag-groups'; without it the plain title."
  (if (fboundp 'sp-org-tag-groups-describe-note)
      (sp-org-tag-groups-describe-note note)
    (sp-collec-query-cell note :title)))

(defun sp-collec-query-rows (notes columns)
  "Return one list of cell texts per note in NOTES, for COLUMNS.
Links in the texts are shown by their description, see `sp-org-link-linkify'.
The title column carries the emoji of the note's tags; IDs are links."
  (mapcar (lambda (note)
            (mapcar (lambda (c)
                      (sp-org-link-linkify
                       (if (eq c :title)
                           (sp-collec-query-title-label note)
                         (sp-collec-query-display-cell note c))))
                    columns))
          notes))

;;;; Describing a spec

(defun sp-collec-query-spec-summary (spec)
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
      (add "title ~" (plist-get spec :title-match))
      (add "folding" (plist-get spec :fold-tag))
      (add "sorted by" (mapcar (lambda (k)
                                 (format "%s%s"
                                         (if (keywordp (car k)) (substring (symbol-name (car k)) 1) (car k))
                                         (if (cdr k) " desc" "")))
                               (sp-collec-query-sort-keys (plist-get spec :sort-by)
                                                          (plist-get spec :sort-desc)))))
    (if parts (string-join (nreverse parts) "; ") "all notes")))

;;;; Choosing notes

(defun sp-collec-query--tag-annotation (note)
  "Return NOTE's tags as an annotation string, or \"\"."
  (if-let* ((tags (vulpea-note-tags note)))
      (propertize (format "  :%s:" (string-join tags ":")) 'face 'org-tag)
    ""))

(defun sp-collec-query-select-note (prompt)
  "Select an existing note with PROMPT, with `sp-select-note'.
Return the `vulpea-note'."
  (sp-select-note prompt :require-match t))

(defun sp-collec-query-read-parent (&optional allow-self)
  "Choose a :parent-of value: nil, \"self\" (when ALLOW-SELF) or a note ID."
  (let* ((choices (append '("None")
                          (when allow-self '("Current note (self)"))
                          '("Choose a note...")))
         (choice (completing-read "Filter to children of: " choices nil t)))
    (cond ((string= choice "None") nil)
          ((string= choice "Current note (self)") "self")
          (t (when-let* ((note (sp-collec-query-select-note "Parent note: ")))
               (vulpea-note-id note))))))

;;;; Writing a meta value back

(defvar sp-collec-query--last-write nil
  "Time of the last `sp-collec-query-write-meta', or nil.")

(defun sp-collec-query-write-meta (note key value)
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
    (setq sp-collec-query--last-write (current-time))))

;;;; Refreshing open tables

(defvar sp-collec-query-refresh-functions nil
  "Abnormal hook: functions called with no arguments when open tables
should run their query again.  A live table adds one while it is open.")

(defvar sp-collec-query--refresh-timer nil)

(defcustom sp-collec-query-refresh-delay 0.5
  "Seconds after saving a note before open tables run their query again.
The Vulpea database is updated by its own autosync; if tables sometimes
show stale data, lengthen this."
  :type 'number
  :group 'sp-collec-query)

(defun sp-collec-query-refresh-all ()
  "Tell every open live query table to run its query again."
  (interactive)
  (run-hooks 'sp-collec-query-refresh-functions))

(defun sp-collec-query--after-save ()
  "Schedule a refresh of open tables after an Org note is saved.
Skipped for two seconds after a table wrote a value itself, so the cell
just edited is not redrawn from a database that has not caught up."
  (when (and buffer-file-name
             (derived-mode-p 'org-mode)
             sp-collec-query-refresh-functions
             (not (and sp-collec-query--last-write
                       (< (float-time (time-since sp-collec-query--last-write)) 2))))
    (when (timerp sp-collec-query--refresh-timer)
      (cancel-timer sp-collec-query--refresh-timer))
    (setq sp-collec-query--refresh-timer
          (run-with-timer sp-collec-query-refresh-delay nil #'sp-collec-query-refresh-all))))

(add-hook 'after-save-hook #'sp-collec-query--after-save)

;;;; Old names

(define-obsolete-function-alias 'sia-vulpea--resolve-parent-of
  #'sp-collec-query-resolve-parent-of "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-select-note
  #'sp-collec-query-select-note "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-read-parent
  #'sp-collec-query-read-parent "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-refresh-all-tables
  #'sp-collec-query-refresh-all "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea--note-tag-annotation
  #'sp-collec-query--tag-annotation "2026-10-21")

(provide 'sp-collection-query-tables-core)
;;; sp-collection-query-tables-core.el ends here
