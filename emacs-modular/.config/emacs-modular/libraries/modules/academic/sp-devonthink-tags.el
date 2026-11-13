;;; sp-devonthink-tags.el --- Read and set DEVONthink tags from Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; Reads and sets the tags of DEVONthink records through `osascript', for one
;; record or many, and splits the comma-joined tag of the literature database.
;; macOS only.
;; Literate source: docs/tangles/academic/sp-devonthink-tags.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'sp-reading)
(require 'sp-devonthink)

(declare-function sp-litnotes-meta--put "sp-litnotes-meta" (key value))

(defvar sp-devonthink-tags--known nil
  "Cache of the tags of the database, or nil before the first read.")

(defcustom sp-devonthink-keywords-key "keywords"
  "Meta key of the litnote line that mirrors the DEVONthink tags, or nil for none."
  :type '(choice (const :tag "No mirror" nil) string)
  :group 'sp-devonthink)

(defun sp-devonthink--list-literal (strings)
  "STRINGS as an AppleScript list literal."
  (concat "{" (mapconcat #'sp-reading--quote strings ", ") "}"))

(defun sp-devonthink--merge-tags (old tags mode)
  "The tags of a record that has OLD, after applying TAGS in MODE.
MODE is `add', `remove' or `set'."
  (let ((has (lambda (tag list) (seq-find (lambda (x) (string-equal-ignore-case x tag)) list))))
    (pcase mode
      ('set (seq-uniq tags #'string-equal-ignore-case))
      ('remove (seq-remove (lambda (x) (funcall has x tags)) old))
      (_ (append old (seq-remove (lambda (x) (funcall has x old))
                                 (seq-uniq tags #'string-equal-ignore-case)))))))

(defun sp-devonthink--split-tag (tag)
  "The parts of the comma-joined TAG, trimmed, without empty parts or repeats."
  (seq-uniq (seq-remove #'string-empty-p (mapcar #'string-trim (split-string tag ",")))
            #'string-equal-ignore-case))

(defun sp-devonthink--new-tags (tags known)
  "The members of TAGS that are not in KNOWN, ignoring case."
  (seq-remove (lambda (tag) (seq-find (lambda (k) (string-equal-ignore-case k tag)) known)) tags))

;;;; Reading

(defun sp-devonthink--tags-listing-script ()
  "The AppleScript that lists the names of the tags of the database."
  (format "tell application id \"DNtp\"
  set theNames to name of (children of (tags group of database %s))
  set AppleScript's text item delimiters to linefeed
  return theNames as text
end tell"
          (sp-reading--quote sp-reading-database)))

(defun sp-devonthink-database-tags (&optional refresh)
  "The tags of the database, from the cache unless REFRESH; nil if it cannot be read."
  (when (or refresh (null sp-devonthink-tags--known))
    (setq sp-devonthink-tags--known
          (condition-case err
              (split-string (sp-reading--osascript (sp-devonthink--tags-listing-script)) "\n" t)
            (error (message "sp-devonthink: cannot list the tags (%s)" (error-message-string err))
                   nil))))
  sp-devonthink-tags--known)

(defun sp-devonthink--read-tags-script (uuids)
  "The AppleScript that reads the tags of the records UUIDS."
  (format "tell application id \"DNtp\"
  set theOut to {}
  repeat with theId in %s
    set r to get record with uuid (theId as text)
    set theLine to uuid of r
    repeat with t in (tags of r)
      set theLine to theLine & tab & (t as text)
    end repeat
    set end of theOut to theLine
  end repeat
  set AppleScript's text item delimiters to linefeed
  return theOut as text
end tell"
          (sp-devonthink--list-literal uuids)))

(defun sp-devonthink--parse-tags (text)
  "An alist from UUID to its list of tags, read from TEXT (see the script)."
  (mapcar (lambda (line)
            (let ((parts (split-string line "\t")))
              (cons (car parts) (cdr parts))))
          (split-string text "\n" t)))

(defun sp-devonthink-record-tags (uuids)
  "An alist from each UUID in UUIDS to the tags of its record."
  (sp-devonthink--parse-tags (sp-reading--osascript (sp-devonthink--read-tags-script uuids))))

;;;; Setting

(defun sp-devonthink--set-tags-script (changes)
  "The AppleScript that sets the tags of records: CHANGES is ((UUID . TAGS) ...)."
  (format "tell application id \"DNtp\"\n%send tell"
          (mapconcat (lambda (change)
                       (format "  set tags of (get record with uuid %s) to %s\n"
                               (sp-reading--quote (car change))
                               (sp-devonthink--list-literal (cdr change))))
                     changes "")))

(defun sp-devonthink-apply-tags (uuids tags &optional mode)
  "Apply TAGS to the records UUIDS in MODE (`add', `remove' or `set').
Return the number of records that changed."
  (let (changes)
    (dolist (entry (sp-devonthink-record-tags uuids))
      (let ((new (sp-devonthink--merge-tags (cdr entry) tags mode)))
        (unless (equal new (cdr entry))
          (push (cons (car entry) new) changes))))
    (when changes
      (sp-reading--osascript (sp-devonthink--set-tags-script (nreverse changes)))
      (setq sp-devonthink-tags--known nil))
    (length changes)))

(defun sp-devonthink--confirm-new (tags known)
  "Show TAGS with the ones missing from KNOWN marked (new); ask whether to go on."
  (let ((new (sp-devonthink--new-tags tags known)))
    (or (null new) (null known)
        (y-or-n-p (format "Tags: %s.  Create the new ones? "
                          (mapconcat (lambda (tag) (if (member tag new) (concat tag " (new)") tag))
                                     tags ", "))))))

(defun sp-devonthink-read-tags (&optional prompt)
  "Read tags with PROMPT, completing from the database; confirm tags that are new."
  (let* ((known (sp-devonthink-database-tags))
         (input (completing-read-multiple (or prompt "Tags (comma-separated): ") known))
         (tags (seq-uniq (seq-remove #'string-empty-p (mapcar #'string-trim input))
                         #'string-equal-ignore-case)))
    (unless tags (user-error "No tags given"))
    (unless (sp-devonthink--confirm-new tags known) (user-error "Cancelled"))
    tags))

;;;###autoload
(defun sp-devonthink-tag-note (tags &optional remove)
  "Add TAGS to the DEVONthink record of the current litnote; with REMOVE, remove them."
  (interactive (list (sp-devonthink-read-tags) current-prefix-arg))
  (let ((uuid (or (sp-devonthink-note-record-uuid "tag")
                  (user-error "No DEVONthink record for this note (nor for its crossref)"))))
    (message "%s: %d record changed"
             (if remove "Removed" "Added")
             (sp-devonthink-apply-tags (list uuid) tags (if remove 'remove 'add)))
    (sp-devonthink--mirror-tags uuid)))

;;;; Mirror in the litnote

(defun sp-devonthink-keywords-value (tags)
  "The text of the litnote keywords line for TAGS: parts comma-joined, no repeats."
  (mapconcat #'identity
             (seq-uniq (mapcan #'sp-devonthink--split-tag tags) #'string-equal-ignore-case)
             ", "))

(defun sp-devonthink-write-keywords (tags)
  "Write TAGS as the `sp-devonthink-keywords-key' meta line of the current buffer.
Do nothing when that option is nil.  Return the line's value, or nil."
  (when sp-devonthink-keywords-key
    (require 'sp-litnotes-meta)
    (let ((value (sp-devonthink-keywords-value tags)))
      (sp-litnotes-meta--put sp-devonthink-keywords-key value)
      value)))

(defun sp-devonthink--own-record-p ()
  "Non-nil when the record of the current litnote is its own, not its parent's."
  (or (sp-devonthink-note-uuid)
      (when-let* ((key (sp-devonthink-note-citekey))
                  (rec (sp-devonthink-record key)))
        (null (plist-get rec :via)))))

(defun sp-devonthink--mirror-tags (uuid)
  "Refresh the keywords line of the current litnote from the tags of record UUID.
Skip, with a message, when the note's record is its crossref parent's."
  (cond ((not sp-devonthink-keywords-key) nil)
        ((not (sp-devonthink--own-record-p))
         (message "Keywords line not written: the tags belong to the parent's record")
         nil)
        (t (sp-devonthink-write-keywords
            (cdr (assoc uuid (sp-devonthink-record-tags (list uuid))))))))

;;;###autoload
(defun sp-devonthink-keywords-sync ()
  "Write the current DEVONthink tags of this litnote's record into its keywords line."
  (interactive)
  (let ((uuid (or (sp-devonthink-note-uuid)
                  (when-let* ((key (sp-devonthink-note-citekey))
                              (rec (sp-devonthink-record key)))
                    (plist-get rec :uuid))
                  (user-error "No DEVONthink record for this note")))
        (own (sp-devonthink--own-record-p)))
    (unless own
      (user-error "This note has no record of its own; sync in the litnote of its parent"))
    (sp-devonthink--mirror-tags uuid)
    (message "Keywords line updated (buffer not saved)")))

;;;; Splitting a comma-joined tag

(defun sp-devonthink--lookup-tag-script (tag)
  "The AppleScript that lists the UUIDs of the records tagged TAG."
  (format "tell application id \"DNtp\"
  set theRecords to lookup records with tags {%s} in root of database %s
  set AppleScript's text item delimiters to linefeed
  return (uuid of every item of theRecords) as text
end tell"
          (sp-reading--quote tag) (sp-reading--quote sp-reading-database)))

(defun sp-devonthink--split-plan (tag uuids)
  "The text of the plan to split TAG on the records UUIDS."
  (format "Split tag:\n  %s\ninto:\n%s\non %d record%s.\nThe old tag is kept; delete it in DEVONthink once checked.\n"
          (sp-reading--quote tag)
          (mapconcat (lambda (part) (format "  - %s" part)) (sp-devonthink--split-tag tag) "\n")
          (length uuids) (if (= (length uuids) 1) "" "s")))

;;;###autoload
(defun sp-devonthink-split-comma-tags (tag)
  "Split the comma-joined tag TAG into separate tags on every record that has it."
  (interactive
   (list (completing-read "Tag with commas: "
                          (seq-filter (lambda (tag) (string-search "," tag))
                                      (sp-devonthink-database-tags t))
                          nil t)))
  (let* ((parts (sp-devonthink--split-tag tag))
         (uuids (split-string
                 (sp-reading--osascript (sp-devonthink--lookup-tag-script tag)) "\n" t))
         (buffer (get-buffer-create "*devonthink tag split*")))
    (when (null parts) (user-error "Nothing left of %s after splitting" tag))
    (with-current-buffer buffer (erase-buffer) (insert (sp-devonthink--split-plan tag uuids)))
    (display-buffer buffer)
    (when (and uuids (y-or-n-p "Apply this plan? "))
      (let ((changes
             (mapcar (lambda (entry)
                       (cons (car entry)
                             (sp-devonthink--merge-tags
                              (sp-devonthink--merge-tags (cdr entry) (list tag) 'remove)
                              parts 'add)))
                     (sp-devonthink-record-tags uuids))))
        (sp-reading--osascript (sp-devonthink--set-tags-script changes))
        (setq sp-devonthink-tags--known nil)
        (message "Split %s on %d records" tag (length changes))))))

;;;; Keys

(keymap-set sp-devonthink-map "t" #'sp-devonthink-tag-note)
(keymap-set sp-devonthink-map "T" #'sp-devonthink-keywords-sync)

(provide 'sp-devonthink-tags)
;;; sp-devonthink-tags.el ends here
