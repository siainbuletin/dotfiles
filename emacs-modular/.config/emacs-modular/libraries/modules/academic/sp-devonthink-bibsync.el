;;; sp-devonthink-bibsync.el --- Copy BibTeX author, title and keywords to the DEVONthink record -*- lexical-binding: t; -*-

;;; Commentary:

;; Writes the author and title of a BibTeX entry to the custom metadata of the
;; DEVONthink record with the same citekey, and its keywords to the record's
;; tags (added, never removed).  macOS only.
;; Literate source: docs/tangles/devonthink/sp-devonthink-bibsync.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'bibtex)
(require 'sp-reading)
(require 'sp-devonthink)
(require 'sp-devonthink-tags)

(defvar sp-bibtex-files)
(declare-function sp-devonthink-browse--record "sp-devonthink-browse")
(declare-function sp-devonthink-browse--key "sp-devonthink-browse")
(declare-function sp-devonthink-browse--read "sp-devonthink-browse")

(defgroup sp-devonthink-bibsync nil
  "Copy BibTeX metadata to DEVONthink records."
  :group 'sp-devonthink)

(defcustom sp-devonthink-bibsync-author-id "bibauthor"
  "Identifier of the DEVONthink custom metadata field that gets the author."
  :type 'string :group 'sp-devonthink-bibsync)

(defcustom sp-devonthink-bibsync-title-id "bibtitle"
  "Identifier of the DEVONthink custom metadata field that gets the title."
  :type 'string :group 'sp-devonthink-bibsync)

(defcustom sp-devonthink-bibsync-keywords t
  "Non-nil to add the BibTeX keywords to the tags of the record."
  :type 'boolean :group 'sp-devonthink-bibsync)

(defcustom sp-devonthink-bibsync-author-separator "; "
  "The string that replaces BibTeX's `and' between the authors."
  :type 'string :group 'sp-devonthink-bibsync)

(defun sp-devonthink-bibsync--clean (value)
  "VALUE as one plain line: no braces, no backslash before & % _ #, one space between words."
  (when (stringp value)
    (let ((s (replace-regexp-in-string "\\\\\\([&%_#$]\\)" "\\1" value)))
      (setq s (replace-regexp-in-string "[{}]" "" s))
      (setq s (string-trim (replace-regexp-in-string "[ \t\n]+" " " s)))
      (and (not (string-empty-p s)) s))))

(defun sp-devonthink-bibsync--authors (value)
  "The author field VALUE with the authors joined by `sp-devonthink-bibsync-author-separator'."
  (when-let* ((s (sp-devonthink-bibsync--clean value)))
    (mapconcat #'identity
               (split-string s "[ \t]+and[ \t]+" t)
               sp-devonthink-bibsync-author-separator)))

(defun sp-devonthink-bibsync--keywords (value)
  "The list of keywords in VALUE, split on commas and semicolons, without repeats."
  (when-let* ((s (sp-devonthink-bibsync--clean value)))
    (seq-uniq (seq-remove #'string-empty-p (mapcar #'string-trim (split-string s "[,;]")))
              #'string-equal-ignore-case)))

(defun sp-devonthink-bibsync--fields ()
  "The fields of the BibTeX entry at point, as a plist (:key :author :title :keywords)."
  (let ((entry (bibtex-parse-entry t)))
    (cl-flet ((get (name) (cdr (assoc-string name entry t))))
      (list :key (cdr (assoc "=key=" entry))
            :author (sp-devonthink-bibsync--authors (get "author"))
            :title (sp-devonthink-bibsync--clean (get "title"))
            :keywords (sp-devonthink-bibsync--keywords (get "keywords"))))))

(defconst sp-devonthink-bibsync--entry-start
  "^[ \t]*@[[:alpha:]]+[ \t]*[{(][ \t]*\\([^, \t\n]+\\)[ \t]*,"
  "Regexp for the start of a BibTeX entry; group 1 is the key.")

(defun sp-devonthink-bibsync-entry-fields (text)
  "The fields of the first BibTeX entry in the string TEXT (see `sp-devonthink-bibsync--fields')."
  (with-temp-buffer
    (insert text)
    (delay-mode-hooks (bibtex-mode))
    (goto-char (point-min))
    (when (re-search-forward sp-devonthink-bibsync--entry-start nil t)
      (goto-char (match-beginning 0))
      (sp-devonthink-bibsync--fields))))

(defun sp-devonthink-bibsync--read-files (keys &optional files)
  "An alist from each of KEYS found in FILES to its fields.
FILES defaults to `sp-bibtex-files'.  Each file is read once; a key found
in an earlier file is not looked for again."
  (let ((wanted (make-hash-table :test 'equal)) found)
    (dolist (key keys) (puthash key t wanted))
    (dolist (file (or files (bound-and-true-p sp-bibtex-files)))
      (when (and (file-readable-p file) (> (hash-table-count wanted) 0))
        (with-temp-buffer
          (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
          (delay-mode-hooks (bibtex-mode))
          (goto-char (point-min))
          (while (re-search-forward sp-devonthink-bibsync--entry-start nil t)
            (let ((key (match-string-no-properties 1)))
              (when (gethash key wanted)
                (save-excursion
                  (goto-char (match-beginning 0))
                  (push (cons key (sp-devonthink-bibsync--fields)) found))
                (remhash key wanted)))))))
    (nreverse found)))

(defun sp-devonthink-bibsync--metadata-script (items)
  "The AppleScript that writes author and title of ITEMS, a list of (UUID . FIELDS)."
  (format "tell application id \"DNtp\"
  set theOut to {}
%s  set AppleScript's text item delimiters to linefeed
  return theOut as text
end tell"
          (mapconcat
           (lambda (item)
             (let ((uuid (car item)) (fields (cdr item)))
               (format "  try
    set r to get record with uuid %s
%s    set end of theOut to \"ok\" & tab & %s
  on error theMessage
    set end of theOut to \"error\" & tab & %s & tab & theMessage
  end try
"
                       (sp-reading--quote uuid)
                       (mapconcat
                        (lambda (pair)
                          (if (cdr pair)
                              (format "    add custom meta data %s for %s to r\n"
                                      (sp-reading--quote (cdr pair)) (sp-reading--quote (car pair)))
                            ""))
                        (list (cons sp-devonthink-bibsync-author-id (plist-get fields :author))
                              (cons sp-devonthink-bibsync-title-id (plist-get fields :title)))
                        "")
                       (sp-reading--quote uuid) (sp-reading--quote uuid))))
           items "")))

(defun sp-devonthink-bibsync--parse-result (text)
  "The failed lines of the script output TEXT, as ((UUID . MESSAGE) ...)."
  (delq nil
        (mapcar (lambda (line)
                  (let ((parts (split-string line "\t")))
                    (when (equal (car parts) "error")
                      (cons (nth 1 parts) (or (nth 2 parts) "")))))
                (split-string text "\n" t))))

(defun sp-devonthink-bibsync--tag-changes (items)
  "The tag changes ((UUID . TAGS) ...) that ITEMS need, from the records' current tags."
  (let ((wanted (delq nil (mapcar (lambda (item)
                                    (and (plist-get (cdr item) :keywords) item))
                                  items))))
    (when wanted
      (delq nil
            (mapcar (lambda (entry)
                      (let* ((keywords (plist-get (cdr (assoc (car entry) wanted)) :keywords))
                             (new (sp-devonthink--merge-tags (cdr entry) keywords 'add)))
                        (and (not (equal new (cdr entry))) (cons (car entry) new))))
                    (sp-devonthink-record-tags (mapcar #'car wanted)))))))

(defun sp-devonthink-bibsync-apply (items)
  "Write the fields of ITEMS to DEVONthink; ITEMS is a list of (UUID . FIELDS).
FIELDS is a plist as of `sp-devonthink-bibsync-entry-fields'.  Return a plist:
:records (how many), :tagged (records whose tags changed) and :failed
\((UUID . MESSAGE) ...) for the records whose metadata could not be written."
  (let (failed (tagged 0))
    (when items
      (setq failed (sp-devonthink-bibsync--parse-result
                    (sp-reading--osascript (sp-devonthink-bibsync--metadata-script items))))
      (when sp-devonthink-bibsync-keywords
        (when-let* ((changes (sp-devonthink-bibsync--tag-changes items)))
          (sp-reading--osascript (sp-devonthink--set-tags-script changes))
          (setq sp-devonthink-tags--known nil)
          (setq tagged (length changes)))))
    (list :records (length items) :tagged tagged :failed failed)))

(defun sp-devonthink-bibsync--report (result)
  "Tell the outcome RESULT of `sp-devonthink-bibsync-apply' in the echo area."
  (let ((failed (plist-get result :failed)))
    (message "BibTeX metadata: %d record%s synced, tags changed on %d%s"
             (- (plist-get result :records) (length failed))
             (if (= (- (plist-get result :records) (length failed)) 1) "" "s")
             (plist-get result :tagged)
             (if failed
                 (format "; %d failed (%s: %s)" (length failed)
                         (caar failed) (cdar failed))
               ""))))

(defun sp-devonthink-bibsync--item (key fields)
  "(UUID . FIELDS) for the citekey KEY, or nil when KEY has no record of its own."
  (when-let* ((rec (sp-devonthink-record key))
              ((null (plist-get rec :via))))
    (cons (plist-get rec :uuid) fields)))

(defun sp-devonthink-bibsync-keys (keys)
  "Copy the BibTeX metadata of the citekeys KEYS to their DEVONthink records.
Return the plist of `sp-devonthink-bibsync-apply' plus :no-entry and :no-record
\(the keys that lacked each)."
  (let* ((entries (sp-devonthink-bibsync--read-files keys))
         (no-entry (seq-remove (lambda (k) (assoc k entries)) keys))
         items no-record)
    (dolist (entry entries)
      (if-let* ((item (sp-devonthink-bibsync--item (car entry) (cdr entry))))
          (push item items)
        (push (car entry) no-record)))
    (append (sp-devonthink-bibsync-apply (nreverse items))
            (list :no-entry no-entry :no-record (nreverse no-record)))))

(defun sp-devonthink-bibsync-entry (key text)
  "Copy the author, title and keywords in the entry TEXT to the record of KEY.
Return the result of `sp-devonthink-bibsync-apply', or nil when KEY has no record."
  (when-let* ((fields (sp-devonthink-bibsync-entry-fields text))
              (item (sp-devonthink-bibsync--item key fields)))
    (sp-devonthink-bibsync-apply (list item))))

(defun sp-devonthink-bibsync--summary (result)
  "Tell the outcome RESULT of `sp-devonthink-bibsync-keys' in the echo area."
  (sp-devonthink-bibsync--report result)
  (let ((no-entry (plist-get result :no-entry)) (no-record (plist-get result :no-record)))
    (when (or no-entry no-record)
      (message "%s%s%s"
               (current-message)
               (if no-entry (format "; no BibTeX entry: %s" (string-join (seq-take no-entry 3) ", ")) "")
               (if no-record (format "; no own record: %s" (string-join (seq-take no-record 3) ", ")) "")))))

(defun sp-devonthink-bibsync--indexed-keys ()
  "The citekeys that have a record in the index of `sp-reading', loading it if needed."
  (unless sp-reading-index (sp-reading-refresh))
  (let (keys)
    (maphash (lambda (key _uuid) (push key keys)) sp-reading-index)
    (sort keys #'string<)))

;;;###autoload
(defun sp-devonthink-bibsync (key)
  "Copy the BibTeX author, title and keywords of KEY to its DEVONthink record.
In a litnote KEY is its citekey; otherwise it is asked."
  (interactive
   (list (or (and (fboundp 'sp-devonthink-note-citekey) (ignore-errors (sp-devonthink-note-citekey)))
             (completing-read "Citekey: " (sp-devonthink-bibsync--indexed-keys) nil t))))
  (let ((result (sp-devonthink-bibsync-keys (list key))))
    (when (plist-get result :no-entry) (user-error "No BibTeX entry %s" key))
    (when (plist-get result :no-record) (user-error "%s has no DEVONthink record of its own" key))
    (sp-devonthink-bibsync--summary result)))

;;;###autoload
(defun sp-devonthink-bibsync-many (keys)
  "Copy the BibTeX metadata of the citekeys KEYS to their DEVONthink records."
  (interactive (list (completing-read-multiple "Citekeys: " (sp-devonthink-bibsync--indexed-keys) nil t)))
  (sp-devonthink-bibsync--summary (sp-devonthink-bibsync-keys keys)))

;;;###autoload
(defun sp-devonthink-bibsync-all ()
  "Copy the BibTeX metadata to every DEVONthink record that has an entry, after asking."
  (interactive)
  (let ((keys (sp-devonthink-bibsync--indexed-keys)))
    (when (and keys (y-or-n-p (format "Write BibTeX author, title and keywords to up to %d DEVONthink records? "
                                      (length keys))))
      (sp-devonthink-bibsync--summary (sp-devonthink-bibsync-keys keys)))))

;;;###autoload
(defun sp-devonthink-bibsync-record (candidate)
  "Copy the BibTeX metadata to the DEVONthink record CANDIDATE (Embark action of the browser)."
  (interactive (list (sp-devonthink-browse--read)))
  (sp-devonthink-bibsync
   (sp-devonthink-browse--key (sp-devonthink-browse--record candidate))))

(keymap-set sp-devonthink-map "y" #'sp-devonthink-bibsync)

(with-eval-after-load 'sp-devonthink-browse
  (keymap-set sp-devonthink-record-map "y" #'sp-devonthink-bibsync-record))

(provide 'sp-devonthink-bibsync)
;;; sp-devonthink-bibsync.el ends here
