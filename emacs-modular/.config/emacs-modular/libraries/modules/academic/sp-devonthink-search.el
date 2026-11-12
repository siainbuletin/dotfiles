;;; sp-devonthink-search.el --- Search DEVONthink from Emacs, and find similar records -*- lexical-binding: t; -*-

;;; Commentary:

;; One search command over DEVONthink's own search and litdb, hits that
;; Embark can act on, "see also" for a record, and a text preview.  macOS only.
;; Literate source: docs/tangles/academic/sp-devonthink-search.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'sp-reading)
(require 'sp-devonthink)
(require 'sp-devonthink-browse)

(declare-function sp-litdb-search "sp-litdb")
(defvar sp-litdb-default-mode)

(defgroup sp-devonthink-search nil
  "Search DEVONthink from Emacs."
  :group 'sp-devonthink)

(defcustom sp-devonthink-search-limit 50
  "How many hits `sp-devonthink-search' lists."
  :type 'integer :group 'sp-devonthink-search)

(defcustom sp-devonthink-search-preview-chars 3000
  "How many characters of a record's text the preview shows."
  :type 'integer :group 'sp-devonthink-search)

;;;; DEVONthink search

(defconst sp-devonthink-search--record-fields
  "set theOut to {}
  repeat with r in theRecords
    set theLine to (uuid of r) & tab & (location of r) & tab & (name of r) & tab & (kind of r) & tab & ((page count of r) as text)
    set end of theOut to theLine
  end repeat
  set AppleScript's text item delimiters to linefeed
  return theOut as text"
  "AppleScript lines that print one line for each of `theRecords'.")

(defun sp-devonthink-search--script (query)
  "The AppleScript that searches the database for QUERY."
  (format "tell application id \"DNtp\"
  set theRecords to search %s in root of database %s
  if (count of theRecords) > %d then set theRecords to items 1 thru %d of theRecords
  %s
end tell"
          (sp-reading--quote query) (sp-reading--quote sp-reading-database)
          sp-devonthink-search-limit sp-devonthink-search-limit
          sp-devonthink-search--record-fields))

(defun sp-devonthink-search--annotate (candidate)
  "Kind and page count of CANDIDATE, for the completion list."
  (when-let* ((record (gethash (substring-no-properties candidate)
                               sp-devonthink-browse--candidates)))
    (let ((kind (plist-get record :kind)) (pages (plist-get record :pages)))
      (concat "  "
              (string-join (delq nil (list (and kind (not (string-empty-p kind)) kind)
                                           (and pages (not (member pages '("" "0" "missing value")))
                                                (format "%s pages" pages))))
                           ", ")))))

(defun sp-devonthink-search--table (candidates)
  "A completion table for CANDIDATES in rank order, of category `sp-devonthink-record'."
  (lambda (string pred action)
    (if (eq action 'metadata)
        '(metadata (category . sp-devonthink-record)
                   (display-sort-function . identity)
                   (cycle-sort-function . identity)
                   (annotation-function . sp-devonthink-search--annotate))
      (complete-with-action action candidates string pred))))

(defun sp-devonthink-search--choose (script prompt)
  "Run SCRIPT, list its records with PROMPT and open the one you choose."
  (let ((records (sp-devonthink-browse--parse (sp-reading--osascript script))))
    (unless records (user-error "No records found"))
    (sp-devonthink-record-open
     (completing-read prompt
                      (sp-devonthink-search--table
                       (sp-devonthink-browse--make-candidates records))
                      nil t))))

;;;; The front end

(defconst sp-devonthink-search--engines
  '(("devonthink" . devonthink)
    ("litdb: meaning" . vector)
    ("litdb: words" . fulltext)
    ("litdb: both" . hybrid))
  "Engine names for the prompt, with the litdb mode or `devonthink'.")

;;;###autoload
(defun sp-devonthink-search (query &optional choose-engine)
  "Search for QUERY in DEVONthink and open the hit you choose.
With a prefix argument CHOOSE-ENGINE, choose the engine first (DEVONthink or litdb)."
  (interactive
   (let ((engine (when current-prefix-arg
                   (cdr (assoc (completing-read "Engine: " sp-devonthink-search--engines nil t)
                               sp-devonthink-search--engines)))))
     (list (read-string (format "%s: " (if engine (if (eq engine 'devonthink) "DEVONthink" engine) "DEVONthink"))
                        (when (use-region-p)
                          (buffer-substring-no-properties (region-beginning) (region-end))))
           (or engine (and current-prefix-arg 'devonthink)))))
  (if (memq choose-engine '(vector fulltext hybrid))
      (let ((sp-litdb-default-mode choose-engine))
        (require 'sp-litdb)
        (sp-litdb-search query))
    (sp-devonthink-search--choose (sp-devonthink-search--script query)
                                  (format "DEVONthink %s: " query))))

;;;; Similar records

(defun sp-devonthink-search--similar-script (uuid)
  "The AppleScript that lists the records similar to the record UUID."
  (format "tell application id \"DNtp\"
  set theRecord to get record with uuid %s
  set theRecords to compare record theRecord to database %s
  if (count of theRecords) > %d then set theRecords to items 1 thru %d of theRecords
  %s
end tell"
          (sp-reading--quote uuid) (sp-reading--quote sp-reading-database)
          sp-devonthink-search-limit sp-devonthink-search-limit
          sp-devonthink-search--record-fields))

(defun sp-devonthink-similar (candidate)
  "List the records similar to the record CANDIDATE, and open the one you choose."
  (interactive (list (sp-devonthink-browse--read)))
  (let ((record (sp-devonthink-browse--record candidate)))
    (sp-devonthink-search--choose
     (sp-devonthink-search--similar-script (plist-get record :uuid))
     (format "Similar to %s: " (plist-get record :name)))))

;;;###autoload
(defun sp-devonthink-similar-to-note ()
  "List the records similar to the record of the current litnote."
  (interactive)
  (let ((uuid (or (sp-devonthink-note-uuid)
                  (when-let* ((key (sp-devonthink-note-citekey))) (sp-reading-uuid key))
                  (user-error "No DEVONthink record for this note"))))
    (sp-devonthink-search--choose (sp-devonthink-search--similar-script uuid)
                                  "Similar records: ")))

;;;; Preview

(defun sp-devonthink-search--preview-script (uuid)
  "The AppleScript that returns the start of the text of the record UUID."
  (format "tell application id \"DNtp\"
  set theText to plain text of (get record with uuid %s)
  if (count of theText) > %d then set theText to text 1 thru %d of theText
  return theText
end tell"
          (sp-reading--quote uuid)
          sp-devonthink-search-preview-chars sp-devonthink-search-preview-chars))

(defun sp-devonthink-preview (candidate)
  "Show the start of the text of the record CANDIDATE in a buffer."
  (interactive (list (sp-devonthink-browse--read)))
  (let* ((record (sp-devonthink-browse--record candidate))
         (text (sp-reading--osascript
                (sp-devonthink-search--preview-script (plist-get record :uuid))))
         (buffer (get-buffer-create "*devonthink preview*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (plist-get record :name) "\n\n" text)
        (goto-char (point-min))
        (special-mode)
        (visual-line-mode 1)))
    (display-buffer buffer)))

;;;; Keys

(keymap-set sp-devonthink-map "f" #'sp-devonthink-search)
(keymap-set sp-devonthink-map "a" #'sp-devonthink-similar-to-note)
(keymap-set sp-devonthink-record-map "s" #'sp-devonthink-similar)
(keymap-set sp-devonthink-record-map "v" #'sp-devonthink-preview)

(provide 'sp-devonthink-search)
;;; sp-devonthink-search.el ends here
