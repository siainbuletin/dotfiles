;;; sp-devonthink-browse.el --- Browse the DEVONthink database from Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; One command, `sp-devonthink-browse', to browse and search DEVONthink: an
;; empty query lists the records of the database, grouped by their DEVONthink
;; group; a query searches DEVONthink or litdb.  Hits and records are Embark
;; candidates (open, PDF, note, link, tags, similar, preview); see also for a
;; record, and a text preview.  macOS only.
;; Literate source: docs/tangles/devonthink/sp-devonthink-browse.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'sp-reading)
(require 'sp-devonthink)
(require 'sp-devonthink-tags)
(require 'sp-pdf-reader)

(declare-function citar-open-notes "citar")
(declare-function sp-litdb-search "sp-litdb")
(defvar sp-litdb-default-mode)

(defvar embark-keymap-alist)
(defvar embark-multitarget-actions)
(defvar embark-default-action-overrides)

(defgroup sp-devonthink-browse nil
  "Browse the DEVONthink database from Emacs."
  :group 'sp-devonthink)

(defcustom sp-devonthink-browse-path-regexp "\\.pdf$"
  "JavaScript regular expression (case-insensitive) that a record's file path must match.
The default lists the PDFs; their names are citekeys."
  :type 'string :group 'sp-devonthink-browse)

(defcustom sp-devonthink-browse-limit 50
  "How many hits `sp-devonthink-browse' lists."
  :type 'integer :group 'sp-devonthink-browse)

(defcustom sp-devonthink-browse-preview-chars 3000
  "How many characters of a record's text the preview shows."
  :type 'integer :group 'sp-devonthink-browse)

;;;; The record list

(defvar sp-devonthink-browse--records nil
  "The records read from DEVONthink, or nil before the first browse.")

(defvar sp-devonthink-browse--candidates (make-hash-table :test 'equal)
  "Candidate string to record, for the current list.")

(defun sp-devonthink-browse--script ()
  "The JavaScript for Automation that lists UUID, location and name of the records to browse.
The fields of all records are read in bulk; AppleScript could not read them from a
list of records (-1728)."
  (format "const app = Application(\"DEVONthink\");
const c = app.databases.byName(%s).contents;
const ids = c.uuid(), names = c.name(), locations = c.location(), paths = c.path();
const wanted = new RegExp(%s, \"i\");
const out = [];
for (let i = 0; i < ids.length; i++)
  if (paths[i] && wanted.test(paths[i])) out.push([ids[i], locations[i], names[i]].join(\"\\t\"));
out.join(\"\\n\");"
          (json-encode-string sp-reading-database)
          (json-encode-string sp-devonthink-browse-path-regexp)))

(defun sp-devonthink-browse--parse (text)
  "The list of record plists read from TEXT (see the script)."
  (let (records)
    (dolist (line (split-string text "\n" t))
      (let ((parts (split-string line "\t")))
        (when (>= (length parts) 3)
          (push (list :uuid (nth 0 parts) :location (nth 1 parts) :name (nth 2 parts)
                      :kind (nth 3 parts) :pages (nth 4 parts))
                records))))
    (nreverse records)))

(defun sp-devonthink-browse--make-candidates (records)
  "Fill `sp-devonthink-browse--candidates' from RECORDS and return the candidates."
  (clrhash sp-devonthink-browse--candidates)
  (let ((seen (make-hash-table :test 'equal)) names)
    (dolist (record records)
      (puthash (plist-get record :name) (1+ (gethash (plist-get record :name) seen 0)) seen))
    (dolist (record records)
      (let ((cand (if (> (gethash (plist-get record :name) seen) 1)
                      (format "%s [%s]" (plist-get record :name) (plist-get record :location))
                    (plist-get record :name))))
        (puthash cand record sp-devonthink-browse--candidates)
        (push cand names)))
    (nreverse names)))

(defun sp-devonthink-browse-refresh ()
  "Read the records from DEVONthink again."
  (interactive)
  (setq sp-devonthink-browse--records
        (sp-devonthink-browse--parse (sp-reading--jxa (sp-devonthink-browse--script))))
  (message "sp-devonthink: %d records" (length sp-devonthink-browse--records))
  sp-devonthink-browse--records)

(defun sp-devonthink-browse--record (candidate)
  "The record of CANDIDATE, or an error when the list is out of date."
  (or (gethash (substring-no-properties candidate) sp-devonthink-browse--candidates)
      (user-error "Unknown record %s; browse again" candidate)))

(defun sp-devonthink-browse--table (candidates)
  "A completion table for CANDIDATES, grouped by location, of category `sp-devonthink-record'."
  (lambda (string pred action)
    (if (eq action 'metadata)
        `(metadata (category . sp-devonthink-record)
                   (group-function
                    . ,(lambda (cand transform)
                         (if transform
                             cand
                           (plist-get (gethash cand sp-devonthink-browse--candidates) :location)))))
      (complete-with-action action candidates string pred))))

(defun sp-devonthink-browse--read (&optional multiple)
  "Read a record candidate, or several with MULTIPLE; load the list first if needed."
  (unless sp-devonthink-browse--records (sp-devonthink-browse-refresh))
  (let ((table (sp-devonthink-browse--table
                (sp-devonthink-browse--make-candidates sp-devonthink-browse--records))))
    (if multiple
        (completing-read-multiple "Records: " table nil t)
      (completing-read "DEVONthink: " table nil t))))

;;;; Actions

(defun sp-devonthink-browse--key (record)
  "The citekey of RECORD: its name without `.pdf'."
  (replace-regexp-in-string "\\.pdf\\'" "" (plist-get record :name) t t))

;;;###autoload
(defun sp-devonthink-record-open (candidate)
  "Open the record CANDIDATE in DEVONthink."
  (interactive (list (sp-devonthink-browse--read)))
  (sp-reading--open-url (sp-reading--url (plist-get (sp-devonthink-browse--record candidate) :uuid))))

(defun sp-devonthink-browse--path-script (uuid)
  "The AppleScript that returns the file path of the record UUID."
  (format "tell application id \"DNtp\"
  return path of (get record with uuid %s)
end tell"
          (sp-reading--quote uuid)))

(defun sp-devonthink-record-pdf (candidate)
  "Open the file of the record CANDIDATE in Emacs, in emureader (see `sp-pdf-open')."
  (interactive (list (sp-devonthink-browse--read)))
  (let ((path (sp-reading--osascript
               (sp-devonthink-browse--path-script
                (plist-get (sp-devonthink-browse--record candidate) :uuid)))))
    (if (and (not (string-empty-p path)) (file-exists-p path))
        (sp-pdf-open path)
      (user-error "No file on disk for %s" candidate))))

(defun sp-devonthink-record-note (candidate)
  "Go to the litnote of the record CANDIDATE, or create it."
  (interactive (list (sp-devonthink-browse--read)))
  (unless (fboundp 'citar-open-notes) (user-error "citar is not loaded"))
  (let ((key (sp-devonthink-browse--key (sp-devonthink-browse--record candidate))))
    (when (and (fboundp 'sp-litnotes-meta--entry) (not (sp-litnotes-meta--entry key)))
      (user-error "%s is not a citekey with a BibTeX entry; file it first (M-x sp-fetch-inbox)" key))
    (citar-open-notes (list key))))

(defun sp-devonthink-record-link (candidate)
  "Insert a `devonthink:' link to the record CANDIDATE."
  (interactive (list (sp-devonthink-browse--read)))
  (let ((record (sp-devonthink-browse--record candidate)))
    (insert (org-link-make-string
             (concat "devonthink:" (sp-devonthink-link-path (plist-get record :uuid)))
             (sp-devonthink-browse--key record)))))

(defun sp-devonthink-record-tag (candidates)
  "Add tags, which you type next, to the records CANDIDATES (one or several)."
  (interactive (list (sp-devonthink-browse--read t)))
  (let* ((records (mapcar #'sp-devonthink-browse--record candidates))
         (tags (sp-devonthink-read-tags
                (format "Tags for %d record%s: " (length records) (if (cdr records) "s" "")))))
    (message "Added tags to %d of %d records"
             (sp-devonthink-apply-tags (mapcar (lambda (r) (plist-get r :uuid)) records) tags 'add)
             (length records))))

;;;; DEVONthink search

(defconst sp-devonthink-browse--hit-jxa
  "const lines = records.slice(0, LIMIT).map(r => [r.uuid(), r.location(), r.name(), r.kind(), r.pageCount()].join(\"\\t\"));
lines.join(\"\\n\");"
  "JavaScript that prints one line for each record of `records'; LIMIT is replaced.")

(defun sp-devonthink-browse--hit-lines ()
  "The JavaScript lines that print the first records of `records'."
  (replace-regexp-in-string "LIMIT" (number-to-string sp-devonthink-browse-limit)
                            sp-devonthink-browse--hit-jxa t t))

(defun sp-devonthink-browse--search-script (query)
  "The JavaScript for Automation that searches the database for QUERY."
  (format "const app = Application(\"DEVONthink\");
const db = app.databases.byName(%s);
const records = app.search(%s, {in: db.root()});
%s"
          (json-encode-string sp-reading-database) (json-encode-string query)
          (sp-devonthink-browse--hit-lines)))

(defun sp-devonthink-browse--annotate (candidate)
  "Kind and page count of CANDIDATE, for the completion list."
  (when-let* ((record (gethash (substring-no-properties candidate)
                               sp-devonthink-browse--candidates)))
    (let ((kind (plist-get record :kind)) (pages (plist-get record :pages)))
      (concat "  "
              (string-join (delq nil (list (and kind (not (string-empty-p kind)) kind)
                                           (and pages (not (member pages '("" "0" "missing value")))
                                                (format "%s pages" pages))))
                           ", ")))))

(defun sp-devonthink-browse--ranked-table (candidates)
  "A completion table for CANDIDATES in rank order, of category `sp-devonthink-record'."
  (lambda (string pred action)
    (if (eq action 'metadata)
        '(metadata (category . sp-devonthink-record)
                   (display-sort-function . identity)
                   (cycle-sort-function . identity)
                   (annotation-function . sp-devonthink-browse--annotate))
      (complete-with-action action candidates string pred))))

(defun sp-devonthink-browse--choose (script prompt)
  "Run SCRIPT, list its records with PROMPT and open the one you choose."
  (let ((records (sp-devonthink-browse--parse (sp-reading--jxa script))))
    (unless records (user-error "No records found"))
    (sp-devonthink-record-open
     (completing-read prompt
                      (sp-devonthink-browse--ranked-table
                       (sp-devonthink-browse--make-candidates records))
                      nil t))))

;;;; The front end

(defconst sp-devonthink-browse--engines
  '(("devonthink" . devonthink)
    ("litdb: meaning" . vector)
    ("litdb: words" . fulltext)
    ("litdb: both" . hybrid))
  "Engine names for the prompt, with the litdb mode or `devonthink'.")

;;;###autoload
(defun sp-devonthink-browse (query &optional choose-engine)
  "Browse the records, or search for QUERY, and open the one you choose.
An empty QUERY browses all the records, grouped by DEVONthink group.
With a prefix argument CHOOSE-ENGINE, choose the engine first (DEVONthink or litdb)."
  (interactive
   (let ((engine (when current-prefix-arg
                   (cdr (assoc (completing-read "Engine: " sp-devonthink-browse--engines nil t)
                               sp-devonthink-browse--engines)))))
     (list (read-string (format "%s (empty: browse): "
                                (if (memq engine '(vector fulltext hybrid)) engine "DEVONthink"))
                        (when (use-region-p)
                          (buffer-substring-no-properties (region-beginning) (region-end))))
           (or engine (and current-prefix-arg 'devonthink)))))
  (cond
   ((memq choose-engine '(vector fulltext hybrid))
    (when (string-empty-p (string-trim query))
      (user-error "litdb needs a query"))
    (let ((sp-litdb-default-mode choose-engine))
      (require 'sp-litdb)
      (sp-litdb-search query)))
   ((string-empty-p (string-trim query))
    (sp-devonthink-record-open (sp-devonthink-browse--read)))
   (t
    (sp-devonthink-browse--choose (sp-devonthink-browse--search-script query)
                                  (format "DEVONthink %s: " query)))))

;;;; Similar records

(defun sp-devonthink-browse--similar-script (uuid)
  "The JavaScript for Automation that lists the records similar to the record UUID."
  (format "const app = Application(\"DEVONthink\");
const db = app.databases.byName(%s);
const records = app.compare({record: app.getRecordWithUuid(%s), to: db});
%s"
          (json-encode-string sp-reading-database) (json-encode-string uuid)
          (sp-devonthink-browse--hit-lines)))

(defun sp-devonthink-similar (candidate)
  "List the records similar to the record CANDIDATE, and open the one you choose."
  (interactive (list (sp-devonthink-browse--read)))
  (let ((record (sp-devonthink-browse--record candidate)))
    (sp-devonthink-browse--choose
     (sp-devonthink-browse--similar-script (plist-get record :uuid))
     (format "Similar to %s: " (plist-get record :name)))))

;;;###autoload
(defun sp-devonthink-similar-to-note ()
  "List the records similar to the record of the current litnote."
  (interactive)
  (let ((uuid (or (sp-devonthink-note-record-uuid)
                  (user-error "No DEVONthink record for this note (nor for its crossref)"))))
    (sp-devonthink-browse--choose (sp-devonthink-browse--similar-script uuid)
                                  "Similar records: ")))

;;;; Preview

(defun sp-devonthink-browse--preview-script (uuid)
  "The JavaScript for Automation that returns the start of the text of the record UUID."
  (format "const app = Application(\"DEVONthink\");
app.getRecordWithUuid(%s).plainText().slice(0, %d);"
          (json-encode-string uuid) sp-devonthink-browse-preview-chars))

(defun sp-devonthink-preview (candidate)
  "Show the start of the text of the record CANDIDATE in a buffer."
  (interactive (list (sp-devonthink-browse--read)))
  (let* ((record (sp-devonthink-browse--record candidate))
         (text (sp-reading--jxa
                (sp-devonthink-browse--preview-script (plist-get record :uuid))))
         (buffer (get-buffer-create "*devonthink preview*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (plist-get record :name) "\n\n" text)
        (goto-char (point-min))
        (special-mode)
        (visual-line-mode 1)))
    (display-buffer buffer)))

;;;; Keys and Embark

(defvar-keymap sp-devonthink-record-map
  :doc "Embark actions for records of `sp-devonthink-browse'."
  "o" #'sp-devonthink-record-open
  "p" #'sp-devonthink-record-pdf
  "n" #'sp-devonthink-record-note
  "l" #'sp-devonthink-record-link
  "t" #'sp-devonthink-record-tag)

(with-eval-after-load 'embark
  (add-to-list 'embark-keymap-alist '(sp-devonthink-record . sp-devonthink-record-map))
  (add-to-list 'embark-multitarget-actions 'sp-devonthink-record-tag)
  (add-to-list 'embark-default-action-overrides
               '(sp-devonthink-record . sp-devonthink-record-open)))

(keymap-set sp-devonthink-map "f" #'sp-devonthink-browse)
(keymap-set sp-devonthink-map "a" #'sp-devonthink-similar-to-note)
(keymap-set sp-devonthink-record-map "s" #'sp-devonthink-similar)
(keymap-set sp-devonthink-record-map "v" #'sp-devonthink-preview)

(provide 'sp-devonthink-browse)
;;; sp-devonthink-browse.el ends here
