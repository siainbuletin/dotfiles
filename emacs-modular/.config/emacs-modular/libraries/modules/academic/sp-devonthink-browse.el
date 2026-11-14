;;; sp-devonthink-browse.el --- Browse the DEVONthink database from Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; A completion over the records of a DEVONthink database, grouped by their
;; DEVONthink group, with Embark actions: open, PDF, note, link and tags.
;; macOS only.
;; Literate source: docs/tangles/academic/sp-devonthink-browse.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'sp-reading)
(require 'sp-devonthink)
(require 'sp-devonthink-tags)

(declare-function citar-open-notes "citar")

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
        (when (= (length parts) 3)
          (push (list :uuid (nth 0 parts) :location (nth 1 parts) :name (nth 2 parts))
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
  "Open the file of the record CANDIDATE in Emacs."
  (interactive (list (sp-devonthink-browse--read)))
  (let ((path (sp-reading--osascript
               (sp-devonthink-browse--path-script
                (plist-get (sp-devonthink-browse--record candidate) :uuid)))))
    (if (and (not (string-empty-p path)) (file-exists-p path))
        (find-file path)
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

;;;###autoload
(defun sp-devonthink-browse ()
  "Browse the DEVONthink records, grouped by group; choosing one opens it.
Use Embark on a candidate for the other actions."
  (interactive)
  (sp-devonthink-record-open (sp-devonthink-browse--read)))

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

(keymap-set sp-devonthink-map "b" #'sp-devonthink-browse)

(provide 'sp-devonthink-browse)
;;; sp-devonthink-browse.el ends here
