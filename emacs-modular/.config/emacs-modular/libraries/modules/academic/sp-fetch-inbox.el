;;; sp-fetch-inbox.el --- File new articles from the inbox with their BibTeX entry -*- lexical-binding: t; -*-

;;; Commentary:

;; Takes an article from the DEVONthink inbox group or the inbox folder,
;; fetches its BibTeX entry, shows the PDF beside an editable entry, and on
;; confirmation files the PDF as KEY.pdf, updates DEVONthink and appends the
;; entry to a .bib file.  Literate source: docs/tangles/academic/sp-fetch-inbox.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'bibtex)
(require 'sp-reading)
(require 'sp-interaction)

(defvar sp-literature-dir)
(defvar sp-bibtex-files)
(declare-function sp--fetch-academic-attach "sp-fetch-academic")
(declare-function doi-utils-doi-to-bibtex-string "doi-utils")
(declare-function sp-devonthink-bibsync-entry "sp-devonthink-bibsync")

(defgroup sp-fetch-inbox nil
  "File new articles from the inbox."
  :group 'sp-academic)

(defcustom sp-fetch-inbox-dir (expand-file-name "inbox" sp-literature-dir)
  "Folder where downloaded articles wait."
  :type 'directory :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-exclude "\\`mac-bibdesk/"
  "Regexp; files of the inbox whose relative path matches are skipped."
  :type 'regexp :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-sort 'added
  "How the picker of `sp-fetch-inbox' orders the articles.
`added' puts the newest first, `alphabetical' sorts by name.
While picking, C-c s switches between the two."
  :type '(choice (const :tag "Last added first" added)
                 (const :tag "Alphabetical" alphabetical))
  :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-group t
  "Non-nil to group the picker by sub-directory of the inbox."
  :type 'boolean :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-devonthink t
  "Non-nil to list and update records in DEVONthink (macOS only)."
  :type 'boolean :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-devonthink-depth 8
  "How many levels of sub-groups of the inbox group the picker lists.
0 lists only the records directly in the group, which is the quickest."
  :type 'integer :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-profile nil
  "Non-nil to message how long each step of building the picker takes."
  :type 'boolean :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-devonthink-group "inbox"
  "Name of the inbox group in `sp-reading-database'."
  :type 'string :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-index-new t
  "Non-nil to index in DEVONthink a file that had no record, after filing it."
  :type 'boolean :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-sync-metadata t
  "Non-nil to copy author, title and keywords to the DEVONthink record after filing.
See `sp-devonthink-bibsync-entry'."
  :type 'boolean :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-pdf-function #'sp-fetch-inbox-show-pdf
  "Function taking a PDF file and returning the buffer that shows it."
  :type 'function :group 'sp-fetch-inbox)

(defcustom sp-fetch-inbox-pdftotext "pdftotext"
  "Program that writes the text of a PDF to standard output."
  :type 'string :group 'sp-fetch-inbox)

(defconst sp-fetch-inbox--placeholder-key "newkey"
  "The key of an entry that has none yet.")

(defvar sp-fetch-inbox--last-bibfile nil
  "The .bib file chosen last time.")

(defun sp-fetch-inbox--dt-p ()
  "Non-nil when DEVONthink can be used."
  (and sp-fetch-inbox-devonthink (eq system-type 'darwin) (executable-find "osascript")))

(defun sp-fetch-inbox--list-script ()
  "The JavaScript that lists the PDFs in the inbox group and its sub-groups.
One line per PDF: UUID, name, path, seconds since the epoch of the addition
date, and the sub-group below the inbox group (empty for the group itself),
separated by tabs.  Each group is read with one Apple Event per field for
all its children, never one per record; sub-groups are entered down to
`sp-fetch-inbox-devonthink-depth' levels."
  (format "const app = Application(\"DEVONthink\");
const db = app.databases.byName(%s);
const group = app.getRecordAt(%s, {in: db});
const maxDepth = %d;
const out = [];
function walk(g, rel, depth) {
  const c = g.children;
  const ids = c.uuid(), names = c.name(), paths = c.path(), kinds = c.kind(),
        types = c.type(), added = c.additionDate(), created = c.creationDate();
  for (let i = 0; i < ids.length; i++) {
    const name = names[i], path = paths[i] || \"\", kind = String(kinds[i] || \"\");
    if (String(types[i]) === \"group\") {
      if (depth < maxDepth) walk(c[i], rel ? rel + \"/\" + name : name, depth + 1);
    } else if (/pdf/i.test(kind) || /\\.pdf$/i.test(path) || /\\.pdf$/i.test(name)) {
      const d = added[i] || created[i];
      out.push([ids[i], name, path, d ? Math.floor(d.getTime() / 1000) : \"\", rel].join(\"\\t\"));
    }
  }
}
if (group) walk(group, \"\", 0);
out.join(\"\\n\");"
          (json-encode-string sp-reading-database)
          (json-encode-string (concat "/" sp-fetch-inbox-devonthink-group))
          (max 0 sp-fetch-inbox-devonthink-depth)))

(defun sp-fetch-inbox--parse-records (text)
  "Items from TEXT, lines of UUID, name, path, added and sub-group separated by tabs.
The last two fields may be missing."
  (delq nil
        (mapcar (lambda (line)
                  (let ((parts (split-string line "\t")))
                    (when (>= (length parts) 2)
                      (list :uuid (nth 0 parts) :name (nth 1 parts)
                            :file (let ((p (nth 2 parts))) (and p (not (string-empty-p p)) p))
                            :imported (let ((p (nth 2 parts))) (or (null p) (string-empty-p p)))
                            :added (sp-fetch-inbox--epoch (nth 3 parts))
                            :subdir (let ((s (nth 4 parts))) (and s (not (string-empty-p s)) s))))))
                (split-string text "\n" t))))

(defun sp-fetch-inbox--epoch (string)
  "The time for STRING, a count of seconds since the epoch, or nil."
  (and string (string-match-p "\\`[0-9]+\\'" string)
       (string-to-number string)))

(defun sp-fetch-inbox--folder-files ()
  "The PDF files of `sp-fetch-inbox-dir', without the excluded ones."
  (when (file-directory-p sp-fetch-inbox-dir)
    (seq-filter
     (lambda (f)
       (not (and sp-fetch-inbox-exclude
                 (string-match-p sp-fetch-inbox-exclude
                                 (file-relative-name f sp-fetch-inbox-dir)))))
     (directory-files-recursively sp-fetch-inbox-dir "\\.pdf\\'" nil nil))))

(defun sp-fetch-inbox--subdir (file)
  "The directory of FILE relative to `sp-fetch-inbox-dir', nil for the folder itself."
  (let ((d (file-name-directory (file-relative-name file sp-fetch-inbox-dir))))
    (and d (not (string-empty-p d)) (directory-file-name d))))

(defun sp-fetch-inbox--merge (records files)
  "Items from RECORDS and FILES; a file that a record points at is not repeated.
The files the records point at are looked up in a hash table, once each."
  (let ((known (make-hash-table :test 'equal)))
    (dolist (r records)
      (when (plist-get r :file)
        (puthash (file-truename (plist-get r :file)) t known)))
    (append records
            (mapcar (lambda (f) (list :file f :name (file-name-nondirectory f)
                                      :added (file-attribute-modification-time (file-attributes f))
                                      :subdir (sp-fetch-inbox--subdir f)))
                    (seq-remove (lambda (f) (gethash (file-truename f) known)) files)))))

(defmacro sp-fetch-inbox--timed (label &rest body)
  "Run BODY; with `sp-fetch-inbox-profile' non-nil, message how long it took as LABEL."
  (declare (indent 1))
  `(let ((start (float-time)))
     (prog1 (progn ,@body)
       (when sp-fetch-inbox-profile
         (message "sp-fetch-inbox profile: %s %.3fs" ,label (- (float-time) start))))))

(defun sp-fetch-inbox-items ()
  "All articles waiting in the inbox, from DEVONthink and the inbox folder."
  (let* ((records (when (sp-fetch-inbox--dt-p)
                    (condition-case err
                        (let ((text (sp-fetch-inbox--timed "DEVONthink script"
                                      (sp-reading--jxa (sp-fetch-inbox--list-script)))))
                          (sp-fetch-inbox--timed "parse records"
                            (sp-fetch-inbox--parse-records text)))
                      (error (message "sp-fetch-inbox: DEVONthink: %s" (error-message-string err))
                             nil))))
         (files (sp-fetch-inbox--timed "folder scan" (sp-fetch-inbox--folder-files)))
         (items (sp-fetch-inbox--timed "merge" (sp-fetch-inbox--merge records files))))
    (when sp-fetch-inbox-profile
      (message "sp-fetch-inbox profile: %d records, %d files, %d items"
               (length records) (length files) (length items)))
    items))

(defconst sp-fetch-inbox--root-label "(inbox)"
  "The name of the folder of the articles that are not in a sub-directory.")

(defun sp-fetch-inbox--folder (item)
  "The sub-directory of ITEM, or `sp-fetch-inbox--root-label'."
  (or (plist-get item :subdir) sp-fetch-inbox--root-label))

(defun sp-fetch-inbox--added (item)
  "The time ITEM was added, or 0 when unknown."
  (or (plist-get item :added) 0))

(defun sp-fetch-inbox--item< (order a b)
  "Non-nil when item A comes before item B in ORDER.
ORDER is `added' (newest first, name as tie-break) or `alphabetical'."
  (let ((ta (sp-fetch-inbox--added a))
        (tb (sp-fetch-inbox--added b)))
    (if (and (eq order 'added) (not (time-equal-p ta tb)))
        (time-less-p tb ta)
      (string< (downcase (plist-get a :name)) (downcase (plist-get b :name))))))

(defun sp-fetch-inbox--arrange (items order group)
  "ITEMS sorted in ORDER; with GROUP non-nil, the items of a folder stay together.
The folders follow ORDER too: by the newest item they hold for `added',
by name, the root first, for `alphabetical'."
  (let* ((sorted (sort (copy-sequence items)
                       (lambda (a b) (sp-fetch-inbox--item< order a b))))
         (folders (delete-dups (mapcar #'sp-fetch-inbox--folder sorted))))
    (when (eq order 'alphabetical)
      (setq folders (sort folders
                          (lambda (a b)
                            (cond ((equal a sp-fetch-inbox--root-label) (not (equal b a)))
                                  ((equal b sp-fetch-inbox--root-label) nil)
                                  (t (string< a b)))))))
    (if (not group)
        sorted
      ;; One pass into a bucket per folder; scanning the list once per folder
      ;; is quadratic with thousands of articles in hundreds of folders.
      (let ((buckets (make-hash-table :test 'equal)))
        (dolist (i sorted)
          (push i (gethash (sp-fetch-inbox--folder i) buckets)))
        (mapcan (lambda (f) (nreverse (gethash f buckets))) folders)))))

(defun sp-fetch-inbox--candidates (items)
  "An alist of (STRING . ITEM) for ITEMS, in order, with unique strings."
  (let ((seen (make-hash-table :test 'equal))
        out)
    (dolist (i items)
      (let* ((base (format "%s%s" (plist-get i :name)
                           (if (plist-get i :uuid) "  [DEVONthink]" "")))
             (s base)
             (n 1))
        (when (gethash s seen)
          (setq s (format "%s  (%s)" base (sp-fetch-inbox--folder i))))
        (while (gethash s seen)
          (setq n (1+ n)
                s (format "%s  (%s) #%d" base (sp-fetch-inbox--folder i) n)))
        (puthash s t seen)
        (push (cons s i) out)))
    (nreverse out)))

(defun sp-fetch-inbox--table (alist &optional group-function)
  "A completion table over ALIST that keeps its order.
GROUP-FUNCTION, when given, is the `group-function' of the completion metadata.
`display-sort-function' and `cycle-sort-function' are set so that Vertico,
Consult and the default UI do not re-sort the candidates."
  (lambda (string pred action)
    (if (eq action 'metadata)
        `(metadata (category . sp-fetch-inbox)
                   (display-sort-function . identity)
                   (cycle-sort-function . identity)
                   ,@(and group-function `((group-function . ,group-function))))
      (complete-with-action action alist string pred))))

(defun sp-fetch-inbox--read-folder (items)
  "Ask for one of the sub-directories of ITEMS; nil means all of them."
  (let* ((counts (make-hash-table :test 'equal))
         (_ (dolist (i items) (cl-incf (gethash (sp-fetch-inbox--folder i) counts 0))))
         (folders (sort (hash-table-keys counts) #'string<))
         (alist (cons (cons "All folders" nil)
                      (mapcar (lambda (f) (cons (format "%s (%d)" f (gethash f counts)) f))
                              folders))))
    (cdr (assoc (completing-read "Folder: " (sp-fetch-inbox--table alist) nil t nil nil
                                 "All folders")
                alist))))

(defun sp-fetch-inbox-picker-sort ()
  "Leave the picker and show it again with the other sort order."
  (interactive)
  (unless (minibufferp) (user-error "Only in the inbox picker"))
  (throw 'sp-fetch-inbox--again (list 'sort (minibuffer-contents))))

(defun sp-fetch-inbox-picker-folder ()
  "Leave the picker, choose a sub-directory and show it again with that one only."
  (interactive)
  (unless (minibufferp) (user-error "Only in the inbox picker"))
  (throw 'sp-fetch-inbox--again (list 'folder (minibuffer-contents))))

(defvar-keymap sp-fetch-inbox-picker-map
  :doc "Keys added to the minibuffer while picking an article of the inbox."
  "C-c s" #'sp-fetch-inbox-picker-sort
  "C-c d" #'sp-fetch-inbox-picker-folder)

(defun sp-fetch-inbox--prompt (order folder)
  "The prompt of the picker, with the sort ORDER, the FOLDER and the keys."
  (format "Article [%s%s | C-c s sort, C-c d folder]: "
          (if (eq order 'added) "newest first" "A-Z")
          (if folder (format ", only %s" folder) "")))

(defun sp-fetch-inbox--read (items order folder initial)
  "Read one of ITEMS in ORDER, restricted to FOLDER, starting with INITIAL.
Return (choose ITEM), or (sort INPUT) or (folder INPUT) when the user asked
for another order or folder."
  (let* ((alist (sp-fetch-inbox--timed "arrange and candidates"
                  (sp-fetch-inbox--candidates
                   (sp-fetch-inbox--arrange items order sp-fetch-inbox-group))))
         (folders (make-hash-table :test 'equal))
         (group-function
          (and sp-fetch-inbox-group
               (lambda (candidate transform)
                 (if transform candidate (gethash candidate folders))))))
    (dolist (c alist)
      (puthash (car c) (sp-fetch-inbox--folder (cdr c)) folders))
    (catch 'sp-fetch-inbox--again
      (minibuffer-with-setup-hook
          (lambda ()
            (use-local-map (make-composed-keymap sp-fetch-inbox-picker-map
                                                 (current-local-map))))
        (let ((choice (completing-read (sp-fetch-inbox--prompt order folder)
                                       (sp-fetch-inbox--table alist group-function)
                                       nil t initial)))
          (list 'choose (cdr (assoc choice alist))))))))

(defun sp-fetch-inbox--select (items &optional folder)
  "Choose one of ITEMS, restricted to the sub-directory FOLDER when given.
With a single item, that one.  The order starts as `sp-fetch-inbox-sort'."
  (if (null (cdr items))
      (car items)
    (let ((order sp-fetch-inbox-sort)
          (initial nil)
          result)
      (while (not result)
        (let ((shown (if folder
                         (seq-filter (lambda (i) (equal (sp-fetch-inbox--folder i) folder))
                                     items)
                       items)))
          (unless shown (user-error "Nothing in %s" folder))
          (pcase (sp-fetch-inbox--read shown order folder initial)
            (`(choose ,item) (setq result item))
            (`(sort ,input)
             (setq order (if (eq order 'added) 'alphabetical 'added)
                   initial input))
            (`(folder ,input)
             (setq folder (sp-fetch-inbox--read-folder items)
                   initial input)))))
      result)))

(defun sp-fetch-inbox--pdf-text (file)
  "The text of the first two pages of FILE, or an empty string without pdftotext."
  (if (executable-find sp-fetch-inbox-pdftotext)
      (with-temp-buffer
        (call-process sp-fetch-inbox-pdftotext nil '(t nil) nil "-l" "2" (expand-file-name file) "-")
        (buffer-string))
    ""))

(defun sp-fetch-inbox--find-doi (text)
  "The first DOI in TEXT, or nil."
  (when (string-match "10\\.[0-9]\\{4,9\\}/[^ \t\n\"<>{}]+" text)
    (string-trim-right (match-string 0 text) "[.,;:)]+")))

(defun sp-fetch-inbox--doi-bibtex (doi)
  "The BibTeX string for DOI, or nil when the look-up fails."
  (require 'doi-utils)
  (condition-case err
      (let ((s (doi-utils-doi-to-bibtex-string doi)))
        (and (stringp s) (string-match-p "@" s) s))
    (error (message "sp-fetch-inbox: DOI %s: %s" doi (error-message-string err)) nil)))

(defun sp-fetch-inbox--skeleton (file)
  "An empty article entry for FILE, with the file name as title guess."
  (format "@article{%s,\n  author = {},\n  title = {%s},\n  journal = {},\n  year = {},\n}\n"
          sp-fetch-inbox--placeholder-key
          (replace-regexp-in-string "[-_]+" " " (file-name-base file))))

(defun sp-fetch-inbox--entry-key ()
  "The key of the entry in the current buffer, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "@[A-Za-z]+[ \t]*{[ \t]*\\([^, \t\n]*\\)" nil t)
      (match-string-no-properties 1))))

(defun sp-fetch-inbox--set-key (key)
  "Make KEY the key of the entry in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "@[A-Za-z]+[ \t]*{[ \t]*\\([^, \t\n]*\\)" nil t)
      (replace-match key t t nil 1))))

(defun sp-fetch-inbox--key-taken-p (key)
  "Non-nil when KEY is the key of an entry in one of `sp-bibtex-files'."
  (let ((re (format "^[ \t]*@[A-Za-z]+[ \t]*{[ \t]*%s[ \t]*," (regexp-quote key))))
    (seq-some (lambda (f)
                (and (file-readable-p f)
                     (with-temp-buffer
                       (insert-file-contents f)
                       (re-search-forward re nil t))))
              (bound-and-true-p sp-bibtex-files))))

(defun sp-fetch-inbox--unique-key (key taken-p)
  "KEY, or KEY with a letter appended, the first for which TAKEN-P is nil."
  (if (not (funcall taken-p key))
      key
    (or (seq-some (lambda (c) (let ((k (concat key (string c)))) (and (not (funcall taken-p k)) k)))
                  (number-sequence ?a ?z))
        (user-error "No free key based on %s" key))))

(defun sp-fetch-inbox--make-key ()
  "Generate the key of the entry in the current buffer with `bibtex-autokey'."
  (save-excursion
    (goto-char (point-min))
    (bibtex-beginning-of-entry)
    (let ((key (condition-case nil
                   (let ((bibtex-autokey-edit-before-use nil))
                     (bibtex-clean-entry t)
                     (sp-fetch-inbox--entry-key))
                 (error nil))))
      (when (or (null key) (string-empty-p key))
        (user-error "Fill in author, year and title first"))
      (sp-fetch-inbox--set-key
       (sp-fetch-inbox--unique-key key #'sp-fetch-inbox--key-taken-p)))))

(defvar-local sp-fetch-inbox--item nil "The item being filed.")
(defvar-local sp-fetch-inbox--bibfile nil "The .bib file the entry goes to.")
(defvar-local sp-fetch-inbox--pdf-buffer nil "The buffer showing the PDF.")
(defvar-local sp-fetch-inbox--config nil "The window configuration before the layout.")

(defvar-keymap sp-fetch-inbox-edit-mode-map
  :doc "Keys of `sp-fetch-inbox-edit-mode'."
  "C-c C-c" #'sp-fetch-inbox-confirm
  "C-c C-k" #'sp-fetch-inbox-abort
  "C-c C-r" #'sp-fetch-inbox-regenerate-key
  "C-c C-d" #'sp-fetch-inbox-fetch-doi)

(define-derived-mode sp-fetch-inbox-edit-mode bibtex-mode "Inbox-BibTeX"
  "BibTeX entry of an article of the inbox, beside its PDF.")

(defun sp-fetch-inbox--check-buffer ()
  "Signal a `user-error' unless the current buffer is an inbox edit buffer."
  (unless (and (derived-mode-p 'sp-fetch-inbox-edit-mode) sp-fetch-inbox--item)
    (user-error "Not an inbox BibTeX buffer")))

(defconst sp-fetch-inbox--hints
  '(("C-c C-c" "File it" t)
    ("C-c C-k" "Abort" t)
    ("C-c C-r" "New key")
    ("C-c C-d" "Fetch DOI"))
  "The key hints of the BibTeX buffer, see `sp-echo-help-set'.")

(defun sp-fetch-inbox--set-hints (note)
  "Show NOTE and the keys as hints in the echo area."
  (sp-echo-help-set sp-fetch-inbox--hints note))

(defun sp-fetch-inbox--insert-entry (string)
  "Replace the buffer with the entry STRING, cleaned and keyed."
  (erase-buffer)
  (insert string)
  (goto-char (point-min))
  (when (and (not (equal (sp-fetch-inbox--entry-key) sp-fetch-inbox--placeholder-key)))
    (condition-case nil (sp-fetch-inbox--make-key)
      (user-error (sp-fetch-inbox--set-key sp-fetch-inbox--placeholder-key))))
  (goto-char (point-min)))

(defun sp-fetch-inbox-fetch-doi (doi)
  "Replace the entry with the one for DOI."
  (interactive (list (read-string "DOI: ")))
  (sp-fetch-inbox--check-buffer)
  (let ((bib (sp-fetch-inbox--doi-bibtex (string-trim doi))))
    (unless bib (user-error "No entry found for %s" doi))
    (sp-fetch-inbox--insert-entry bib)
    (sp-fetch-inbox--set-hints (format "DOI %s" doi))))

(defun sp-fetch-inbox-regenerate-key ()
  "Make the key again from the author, year and title in the buffer."
  (interactive)
  (sp-fetch-inbox--check-buffer)
  (sp-fetch-inbox--make-key)
  (message "Key: %s" (sp-fetch-inbox--entry-key)))

(defun sp-fetch-inbox-show-pdf (file)
  "Return the buffer showing FILE: with `sp-pdf-open' when defined, else `find-file'."
  (if (fboundp 'sp-pdf-open)
      (save-window-excursion (funcall 'sp-pdf-open file) (current-buffer))
    (find-file-noselect file)))

(defun sp-fetch-inbox--layout (pdf-buffer edit-buffer)
  "Show PDF-BUFFER on the left and EDIT-BUFFER on the right; select the latter."
  (delete-other-windows)
  (switch-to-buffer pdf-buffer)
  (let ((right (split-window-right)))
    (set-window-buffer right edit-buffer)
    (select-window right)))

(defun sp-fetch-inbox--read-bibfile ()
  "Ask which .bib file the entry goes to."
  (let ((files (bound-and-true-p sp-bibtex-files)))
    (cond ((null files) (user-error "No BibTeX file(s) defined"))
          ((null (cdr files)) (car files))
          (t (let ((choice (completing-read
                            "BibTeX file: "
                            (mapcar #'abbreviate-file-name files) nil t nil nil
                            (and sp-fetch-inbox--last-bibfile
                                 (abbreviate-file-name sp-fetch-inbox--last-bibfile)))))
               (setq sp-fetch-inbox--last-bibfile (expand-file-name choice)))))))

(defun sp-fetch-inbox--export-script (uuid dir)
  "The JavaScript that exports the record UUID into DIR and returns the file path."
  (format "const app = Application(\"DEVONthink\");
const r = app.getRecordWithUuid(%s);
app.exportRecord(r, {to: %s});
r.name();"
          (json-encode-string uuid) (json-encode-string dir)))

(defun sp-fetch-inbox--ensure-file (item)
  "ITEM with a :file; an imported record is exported to a temporary folder."
  (if (plist-get item :file)
      item
    (let* ((dir (make-temp-file "sp-fetch-inbox" t))
           (name (sp-reading--jxa (sp-fetch-inbox--export-script (plist-get item :uuid) dir)))
           (file (or (car (directory-files dir t "\\.pdf\\'"))
                     (expand-file-name name dir))))
      (unless (file-exists-p file) (user-error "Could not export %s" (plist-get item :name)))
      (plist-put (copy-sequence item) :file file))))

(defun sp-fetch-inbox--start (item)
  "Set up the side-by-side view for ITEM."
  (let* ((item (sp-fetch-inbox--ensure-file item))
         (file (plist-get item :file))
         (bibfile (sp-fetch-inbox--read-bibfile))
         (config (current-window-configuration))
         (doi (sp-fetch-inbox--find-doi
               (concat (file-name-base file) "\n" (sp-fetch-inbox--pdf-text file))))
         (bib (and doi (sp-fetch-inbox--doi-bibtex doi)))
         (pdf (funcall sp-fetch-inbox-pdf-function file))
         (edit (generate-new-buffer (format "*inbox: %s*" (file-name-nondirectory file)))))
    (with-current-buffer edit
      (sp-fetch-inbox-edit-mode)
      (setq sp-fetch-inbox--item item
            sp-fetch-inbox--bibfile bibfile
            sp-fetch-inbox--pdf-buffer pdf
            sp-fetch-inbox--config config)
      (sp-fetch-inbox--insert-entry (or bib (sp-fetch-inbox--skeleton file)))
      (sp-fetch-inbox--set-hints
       (cond (bib (format "DOI %s" doi))
             (doi (format "DOI %s found, no entry" doi))
             (t "no DOI found: fill the entry from the PDF"))))
    (sp-fetch-inbox--layout pdf edit)
    edit))

;;;###autoload
(defun sp-fetch-inbox (&optional pick-folder)
  "Pick an article of the inbox and open its PDF beside an editable BibTeX entry.
With a prefix argument PICK-FOLDER, first choose one sub-directory to restrict to."
  (interactive "P")
  (let ((items (sp-fetch-inbox-items)))
    (unless items (user-error "The inbox is empty"))
    (sp-fetch-inbox--start
     (sp-fetch-inbox--select
      items (and pick-folder (sp-fetch-inbox--read-folder items))))))

;;;###autoload
(defun sp-fetch-inbox-record (candidate)
  "File the DEVONthink record CANDIDATE (an Embark action of `sp-devonthink-browse')."
  (interactive (list (sp-devonthink-browse--read)))
  (let* ((record (sp-devonthink-browse--record candidate))
         (uuid (plist-get record :uuid))
         (item (or (seq-find (lambda (i) (equal (plist-get i :uuid) uuid))
                             (sp-fetch-inbox--parse-records
                              (sp-reading--jxa (sp-fetch-inbox--uuid-script uuid))))
                   (user-error "No such record"))))
    (sp-fetch-inbox--start item)))

(defun sp-fetch-inbox--uuid-script (uuid)
  "The JavaScript that returns UUID, name and path of the record UUID."
  (format "const app = Application(\"DEVONthink\");
const r = app.getRecordWithUuid(%s);
[r.uuid(), r.name(), r.path() || \"\"].join(\"\\t\");"
          (json-encode-string uuid)))

(defun sp-fetch-inbox--file-script (uuid key group)
  "The JavaScript that renames the record UUID to KEY.pdf, moves it into GROUP, returns its path.
GROUP nil means the root of `sp-reading-database'."
  (format "const app = Application(\"DEVONthink\");
const db = app.databases.byName(%s);
const r = app.getRecordWithUuid(%s);
r.name = %s;
const dest = %s;
app.move({record: r, to: dest});
r.path();"
          (json-encode-string sp-reading-database)
          (json-encode-string uuid)
          (json-encode-string (concat key ".pdf"))
          (if group
              (format "app.getRecordAt(%s, {in: db})" (json-encode-string (concat "/" group)))
            "db.root()")))

(defun sp-fetch-inbox--trash-script (uuid)
  "The JavaScript that moves the record UUID to the trash."
  (format "const app = Application(\"DEVONthink\");
app.delete({record: app.getRecordWithUuid(%s)});\"done\";" (json-encode-string uuid)))

(defun sp-fetch-inbox--same-file-p (a b)
  "Non-nil when A and B are the same existing file."
  (and a b (file-exists-p a) (file-exists-p b)
       (equal (file-truename a) (file-truename b))))

(defun sp-fetch-inbox--file-pdf (item key dest)
  "Move the PDF of ITEM to DEST as KEY.pdf and update DEVONthink.  Return DEST."
  (let ((uuid (plist-get item :uuid))
        (file (plist-get item :file))
        (dt (sp-fetch-inbox--dt-p)))
    (make-directory (file-name-directory dest) t)
    (cond
     ((and uuid dt (not (plist-get item :imported)))
      (let ((path (string-trim
                   (sp-reading--jxa
                    (sp-fetch-inbox--file-script uuid key sp-reading-index-group)))))
        (unless (sp-fetch-inbox--same-file-p path dest)
          (error "DEVONthink did not move the file to %s (it reports %s); the record is now named %s.pdf"
                 dest path key))
        (when sp-reading-index (puthash key uuid sp-reading-index))))
     (t
      (rename-file file dest)
      (when (and dt (or uuid sp-fetch-inbox-index-new))
        (sp-reading-index-file key dest)
        (when (and uuid (y-or-n-p (format "Move the imported record %s to the DEVONthink trash? "
                                          (plist-get item :name))))
          (sp-reading--jxa (sp-fetch-inbox--trash-script uuid))))))
    dest))

(defun sp-fetch-inbox--append (bibfile text)
  "Append the entry TEXT to BIBFILE and save it."
  (with-current-buffer (find-file-noselect bibfile)
    (save-excursion
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "\n" (string-trim text) "\n")
      (save-buffer))))

(defun sp-fetch-inbox--sync-metadata (key text)
  "Copy author, title and keywords of the entry TEXT to the DEVONthink record of KEY.
A failure is reported, not signalled: the article is already filed."
  (when (and sp-fetch-inbox-sync-metadata (sp-fetch-inbox--dt-p))
    (condition-case err
        (progn
          (require 'sp-devonthink-bibsync)
          (unless (sp-devonthink-bibsync-entry key text)
            (message "No DEVONthink record of its own for %s: metadata not copied" key)))
      (error (message "Filed, but the DEVONthink metadata was not copied: %s"
                      (error-message-string err))))))

(defun sp-fetch-inbox--finish (edit)
  "Restore the windows and kill the edit buffer EDIT."
  (let ((config (buffer-local-value 'sp-fetch-inbox--config edit)))
    (kill-buffer edit)
    (when (window-configuration-p config) (set-window-configuration config))))

(defun sp-fetch-inbox-confirm ()
  "File the PDF as KEY.pdf, update DEVONthink and append the entry to the .bib file."
  (interactive)
  (sp-fetch-inbox--check-buffer)
  (let* ((edit (current-buffer))
         (item sp-fetch-inbox--item)
         (bibfile sp-fetch-inbox--bibfile)
         (pdf sp-fetch-inbox--pdf-buffer)
         (key (sp-fetch-inbox--entry-key)))
    (when (or (null key) (string-empty-p key) (equal key sp-fetch-inbox--placeholder-key))
      (user-error "Give the entry a key first (C-c C-r makes one from author, year and title)"))
    (when (sp-fetch-inbox--key-taken-p key)
      (user-error "The key %s is already in a .bib file; change it or press C-c C-r" key))
    (let ((dest (expand-file-name (concat key ".pdf") sp-literature-dir)))
      (when (file-exists-p dest) (user-error "%s already exists" dest))
      (unless (y-or-n-p (format "Move %s to %s, update DEVONthink, add %s to %s? "
                                (plist-get item :name) (abbreviate-file-name dest) key
                                (file-name-nondirectory bibfile)))
        (user-error "Nothing changed"))
      (when (buffer-live-p pdf) (kill-buffer pdf))
      (sp-fetch-inbox--file-pdf item key dest)
      (unless (fboundp 'sp--fetch-academic-attach) (require 'sp-fetch-academic))
      (goto-char (point-min))
      (sp--fetch-academic-attach dest)
      (sp-fetch-inbox--append bibfile (buffer-string))
      (sp-fetch-inbox--sync-metadata key (buffer-string))
      (sp-fetch-inbox--finish edit)
      (message "Filed %s in %s" key (abbreviate-file-name dest))
      (when (and (sp-fetch-inbox-items) (y-or-n-p "Next article? "))
        (sp-fetch-inbox)))))

(defun sp-fetch-inbox-abort ()
  "Forget this article for now; nothing is changed."
  (interactive)
  (sp-fetch-inbox--check-buffer)
  (let ((pdf sp-fetch-inbox--pdf-buffer)
        (edit (current-buffer)))
    (when (and (buffer-live-p pdf) (not (buffer-modified-p pdf))) (kill-buffer pdf))
    (sp-fetch-inbox--finish edit)
    (message "Left in the inbox")))

(global-set-key (kbd "C-c w b a") #'sp-fetch-inbox)

(with-eval-after-load 'sp-devonthink-browse
  (keymap-set sp-devonthink-record-map "f" #'sp-fetch-inbox-record))

(declare-function sp-devonthink-browse--read "sp-devonthink-browse")
(declare-function sp-devonthink-browse--record "sp-devonthink-browse")

(provide 'sp-fetch-inbox)
;;; sp-fetch-inbox.el ends here
