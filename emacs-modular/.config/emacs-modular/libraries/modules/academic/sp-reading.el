;;; sp-reading.el --- Read a cited work in DEVONthink, or index it first -*- lexical-binding: t; -*-

;;; Commentary:

;; Looks a citekey up in DEVONthink and opens the record, or offers to index
;; the PDF or open it in Preview.  macOS only.
;; Literate source: docs/tangles/academic/sp-reading.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)

(declare-function citar-get-files "citar")

(defgroup sp-reading nil
  "Read cited works in DEVONthink."
  :group 'convenience)

(defcustom sp-reading-database "literature"
  "Name of the DEVONthink database that holds the literature."
  :type 'string :group 'sp-reading)

(defcustom sp-reading-index-group nil
  "Name of the group in `sp-reading-database' that new indexed files go to.
Nil means the root of the database."
  :type '(choice (const nil) string) :group 'sp-reading)

(defcustom sp-reading-preview-command '("open" "-a" "Preview")
  "Command (a list) that opens a PDF in the fallback reader; the file is appended."
  :type '(repeat string) :group 'sp-reading)

(defun sp-reading--quote (string)
  "STRING as an AppleScript string literal."
  (concat "\""
          (replace-regexp-in-string "\"" "\\\\\"" (replace-regexp-in-string "\\\\" "\\\\\\\\" string))
          "\""))

(defun sp-reading--osascript (script)
  "Run the AppleScript SCRIPT and return its output without the final newline."
  (with-temp-buffer
    (let ((status (call-process "osascript" nil t nil "-e" script)))
      (unless (eql status 0)
        (error "osascript failed: %s" (string-trim (buffer-string))))
      (string-trim-right (buffer-string) "\n"))))

(defun sp-reading--jxa (script)
  "Run the JavaScript for Automation SCRIPT and return its output without the final newline."
  (with-temp-buffer
    (let ((status (call-process "osascript" nil t nil "-l" "JavaScript" "-e" script)))
      (unless (eql status 0)
        (error "osascript failed: %s" (string-trim (buffer-string))))
      (string-trim-right (buffer-string) "\n"))))

(defvar sp-reading-index nil
  "Hash table from citekey to DEVONthink UUID, or nil before the first refresh.")

(defun sp-reading--parse-listing (text)
  "A hash table from citekey to UUID, read from TEXT (lines of UUID, tab, name)."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (line (split-string text "\n" t))
      (let ((parts (split-string line "\t")))
        (when (and (= (length parts) 2) (string-suffix-p ".pdf" (cadr parts) t))
          (puthash (substring (cadr parts) 0 -4) (car parts) table))))
    table))

(defun sp-reading--listing-script ()
  "The JavaScript for Automation that lists UUID and name of every PDF in the database.
It reads the fields of all records in bulk, as `tools/devonthink-to-litdb.py' does."
  (format "const app = Application(\"DEVONthink\");
const c = app.databases.byName(%s).contents;
const ids = c.uuid(), names = c.name();
const out = [];
for (let i = 0; i < ids.length; i++)
  if (names[i].toLowerCase().endsWith(\".pdf\")) out.push(ids[i] + \"\\t\" + names[i]);
out.join(\"\\n\");"
          (json-encode-string sp-reading-database)))

(defun sp-reading-refresh ()
  "Read the citekeys and UUIDs of the PDFs in DEVONthink into `sp-reading-index'."
  (interactive)
  (setq sp-reading-index
        (sp-reading--parse-listing (sp-reading--jxa (sp-reading--listing-script))))
  (message "sp-reading: %d PDFs in %s" (hash-table-count sp-reading-index) sp-reading-database)
  sp-reading-index)

(defun sp-reading--lookup-script (key)
  "The AppleScript that finds the UUID of the record named KEY.pdf."
  (format "tell application id \"DNtp\"
  set theRecords to search %s in root of database %s
  repeat with r in theRecords
    if (name of r) is %s then return uuid of r
  end repeat
  return \"\"
end tell"
          (sp-reading--quote (concat "name:" key ".pdf"))
          (sp-reading--quote sp-reading-database)
          (sp-reading--quote (concat key ".pdf"))))

(defun sp-reading-uuid (key)
  "The DEVONthink UUID of the record for the citekey KEY, or nil."
  (or (and sp-reading-index (gethash key sp-reading-index))
      (let ((uuid (sp-reading--osascript (sp-reading--lookup-script key))))
        (unless (string-empty-p uuid)
          (unless sp-reading-index
            (setq sp-reading-index (make-hash-table :test 'equal)))
          (puthash key uuid sp-reading-index)
          uuid))))

(defun sp-reading--url (uuid &optional page)
  "The DEVONthink item URL for UUID, at PAGE (counted from 0) if given."
  (concat "x-devonthink-item://" uuid (if page (format "?page=%d" page) "")))

(defun sp-reading--index-script (file key)
  "The AppleScript that indexes FILE in DEVONthink under the name KEY.pdf."
  (format "tell application id \"DNtp\"
  set theDb to database %s
  set theGroup to %s
  set theRecord to index path %s to theGroup
  set name of theRecord to %s
  return uuid of theRecord
end tell"
          (sp-reading--quote sp-reading-database)
          (if sp-reading-index-group
              (format "get record at %s in theDb"
                      (sp-reading--quote (concat "/" sp-reading-index-group)))
            "root of theDb")
          (sp-reading--quote (expand-file-name file))
          (sp-reading--quote (concat key ".pdf"))))

(defun sp-reading-index-file (key file)
  "Index the PDF FILE in DEVONthink as KEY.pdf and return the new UUID."
  (let ((uuid (sp-reading--osascript (sp-reading--index-script file key))))
    (when (string-empty-p uuid) (error "DEVONthink did not index %s" file))
    (unless sp-reading-index (setq sp-reading-index (make-hash-table :test 'equal)))
    (puthash key uuid sp-reading-index)
    uuid))

(defun sp-reading--pdf (key)
  "The first existing PDF file for the citekey KEY, from citar, or nil."
  (when (fboundp 'citar-get-files)
    (let* ((files (ignore-errors (citar-get-files (list key))))
           (list (and (hash-table-p files) (gethash key files))))
      (seq-find (lambda (f) (and (string-suffix-p ".pdf" f t) (file-exists-p f))) list))))

(defun sp-reading--run (program &rest args)
  "Start PROGRAM with ARGS without waiting for it."
  (apply #'call-process program nil 0 nil args))

(defun sp-reading--open-url (url)
  "Open URL with the system."
  (sp-reading--run "open" url))

(defun sp-reading--ask (key)
  "Ask what to do with the PDF of KEY, which is not in DEVONthink."
  (completing-read (format "%s is not in DEVONthink: " key)
                   '("Index in DEVONthink" "Open in Preview" "Cancel") nil t))

;;;###autoload
(defun sp-reading-open (key &optional page)
  "Open the work KEY for reading: in DEVONthink, or after asking what to do.
PAGE (counted from 0) is the page to open; interactively a prefix argument asks."
  (interactive
   (list (if (fboundp 'citar-select-ref) (citar-select-ref) (read-string "Citekey: "))
         (when current-prefix-arg (1- (read-number "Page: ")))))
  (let ((uuid (sp-reading-uuid key)))
    (if uuid
        (sp-reading--open-url (sp-reading--url uuid page))
      (let ((file (sp-reading--pdf key)))
        (if (not file)
            (progn (message "sp-reading: no PDF for %s (try sp-fetch-academic)" key) nil)
          (pcase (sp-reading--ask key)
            ("Index in DEVONthink"
             (sp-reading--open-url (sp-reading--url (sp-reading-index-file key file) page)))
            ("Open in Preview"
             (apply #'sp-reading--run (append sp-reading-preview-command (list file))))))))))

;;; Provide

(provide 'sp-reading)
;;; sp-reading.el ends here
