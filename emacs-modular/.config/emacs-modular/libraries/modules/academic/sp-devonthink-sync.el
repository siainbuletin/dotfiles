;;; sp-devonthink-sync.el --- Keep litnotes and DEVONthink records in step -*- lexical-binding: t; -*-

;;; Commentary:

;; A report of what is out of step between the litnotes, the DEVONthink PDF
;; records and the BibTeX files, a guarded backfill of the `#+devonthink:'
;; keyword, and the record-side link to the litnote.  macOS only.
;; Literate source: docs/tangles/devonthink/sp-devonthink-sync.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'sp-reading)
(require 'sp-devonthink)

(declare-function sp-litnotes-refs--bib-index "sp-litnotes-refs")
(defvar sp-notes-dir)
(defvar sp-var-dir)
(defvar sp-bibtex-files)
(defvar org-protocol-protocol-alist)

(defgroup sp-devonthink-sync nil
  "Keep litnotes and DEVONthink records in step."
  :group 'sp-devonthink)

(defcustom sp-devonthink-sync-directory
  (expand-file-name "litnotes/" (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes"))
  "Folder with the literature notes."
  :type 'directory :group 'sp-devonthink-sync)

(defcustom sp-devonthink-sync-backup-directory
  (expand-file-name "devonthink-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Folder where the backfill copies each note before changing it."
  :type 'directory :group 'sp-devonthink-sync)

(defcustom sp-devonthink-sync-url-template "org-protocol://devonthink-note?id=%s"
  "The value written into a record; %s is the :ID: of the litnote."
  :type 'string :group 'sp-devonthink-sync)

(defcustom sp-devonthink-sync-record-field "litnote"
  "Name of the custom metadata field (type URL) that holds the litnote link."
  :type 'string :group 'sp-devonthink-sync)

(defcustom sp-devonthink-sync-report-limit 50
  "How many entries each long section of the report lists."
  :type 'integer :group 'sp-devonthink-sync)

;;;; Reading the litnotes

(defun sp-devonthink-sync--read-note (file)
  "A plist (:file :key :uuid :id) read from the start of the litnote FILE, or nil."
  (with-temp-buffer
    (insert-file-contents file nil 0 8000)
    (when-let* ((key (sp-devonthink-note-citekey)))
      (list :file file :key key :uuid (sp-devonthink-note-uuid)
            :id (save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward "^[ \t]*:ID:[ \t]+\\(\\S-+\\)" nil t)
                    (match-string-no-properties 1)))))))

(defun sp-devonthink-sync--scan (directory)
  "The notes of DIRECTORY that have a citekey, as plists."
  (delq nil (mapcar #'sp-devonthink-sync--read-note
                    (seq-remove (lambda (file)
                                  (string-prefix-p ".#" (file-name-nondirectory file)))
                                (directory-files-recursively directory "\\.org\\'")))))

;;;; Comparing

(defun sp-devonthink-sync--compare (notes records &optional bib-keys parent-fn)
  "Compare NOTES (plists) with RECORDS (hash of citekey to UUID) and BIB-KEYS.
BIB-KEYS is a hash of keys, or nil when the .bib files are not known.
PARENT-FN maps a citekey to its crossref parent's key, or nil; a note with no
record of its own whose parent has one is covered by the parent (section
:via-parent) and, when it has no keyword, can be backfilled with the
parent's UUID (section :backfill-parent), not counted as a note with no PDF.
Return a plist of the sections of the report."
  (let ((uuids (make-hash-table :test 'equal))
        (note-keys (make-hash-table :test 'equal))
        pdf-no-note note-no-pdf pdf-not-bib dead differs backfill via-parent backfill-parent)
    (maphash (lambda (_key uuid) (puthash (upcase uuid) t uuids)) records)
    (dolist (note notes) (puthash (plist-get note :key) t note-keys))
    (maphash (lambda (key _uuid)
               (unless (gethash key note-keys) (push key pdf-no-note))
               (when (and bib-keys (not (gethash key bib-keys))) (push key pdf-not-bib)))
             records)
    (dolist (note notes)
      (let* ((key (plist-get note :key))
             (uuid (plist-get note :uuid))
             (record (gethash key records))
             (parent (and (not record) parent-fn (funcall parent-fn key)))
             (parent-record (and parent (gethash parent records))))
        (cond (parent-record
               (let ((covered (plist-put (copy-sequence note) :via parent)))
                 (push covered via-parent)
                 (unless uuid (push covered backfill-parent))))
              ((not record) (push note note-no-pdf)))
        (cond ((and uuid (not (gethash (upcase uuid) uuids))) (push note dead))
              ((and uuid record (not (string-equal-ignore-case uuid record))) (push note differs))
              ((and (not uuid) record) (push note backfill)))))
    (list :pdf-no-note (sort pdf-no-note #'string<)
          :note-no-pdf (nreverse note-no-pdf)
          :pdf-not-bib (sort pdf-not-bib #'string<)
          :dead (nreverse dead)
          :differs (nreverse differs)
          :backfill (nreverse backfill)
          :via-parent (nreverse via-parent)
          :backfill-parent (nreverse backfill-parent))))

(defun sp-devonthink-sync--bib-keys ()
  "A hash of the keys of the registered .bib files, or nil when they cannot be read."
  (when (and (boundp 'sp-bibtex-files) sp-bibtex-files
             (require 'sp-litnotes-refs nil t) (fboundp 'sp-litnotes-refs--bib-index))
    (sp-litnotes-refs--bib-index (if (listp sp-bibtex-files) sp-bibtex-files (list sp-bibtex-files)))))

(defun sp-devonthink-sync--records ()
  "A hash of citekey to UUID for the PDF records of the literature database."
  (sp-reading--parse-listing (sp-reading--osascript (sp-reading--listing-script))))

;;;; The report

(defun sp-devonthink-sync--section (title items &optional note-p)
  "Org text for a section TITLE listing ITEMS (strings, or note plists if NOTE-P)."
  (format "* %s (%d)\n%s\n" title (length items)
          (mapconcat (lambda (item)
                       (if note-p
                           (format "- [[file:%s][%s]]" (plist-get item :file) (plist-get item :key))
                         (concat "- " item)))
                     (seq-take items sp-devonthink-sync-report-limit) "\n")))

(defun sp-devonthink-sync--report-text (result &optional bib-known)
  "The Org text of the report for RESULT (see `sp-devonthink-sync--compare')."
  (concat "#+title: DEVONthink and litnotes\n\n"
          (sp-devonthink-sync--section "PDFs with no litnote" (plist-get result :pdf-no-note))
          (sp-devonthink-sync--section "Litnotes with no PDF" (plist-get result :note-no-pdf) t)
          (if bib-known
              (sp-devonthink-sync--section "PDFs not in any .bib" (plist-get result :pdf-not-bib))
            "* PDFs not in any .bib\nThe .bib files could not be read.\n\n")
          (sp-devonthink-sync--section "Litnotes with a dead UUID" (plist-get result :dead) t)
          (sp-devonthink-sync--section "Litnotes whose UUID differs" (plist-get result :differs) t)
          (sp-devonthink-sync--section "To backfill" (plist-get result :backfill) t)
          (sp-devonthink-sync--section "Covered by the record of the crossref parent"
                                       (plist-get result :via-parent) t)
          (sp-devonthink-sync--section "To backfill with the parent's record (asks first)"
                                       (plist-get result :backfill-parent) t)))

(defun sp-devonthink-sync--show (text)
  "Show TEXT in the report buffer."
  (let ((buffer (get-buffer-create "*devonthink sync*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (org-mode)
        (goto-char (point-min))
        (read-only-mode 1)))
    (display-buffer buffer)))

;;;###autoload
(defun sp-devonthink-sync-report ()
  "Report what is out of step between litnotes, DEVONthink and the .bib files.
Nothing is written."
  (interactive)
  (let* ((records (sp-devonthink-sync--records))
         (bib (sp-devonthink-sync--bib-keys))
         (result (sp-devonthink-sync--compare
                  (sp-devonthink-sync--scan sp-devonthink-sync-directory) records bib
                  #'sp-devonthink--parent-key)))
    (sp-devonthink-sync--show (sp-devonthink-sync--report-text result bib))
    result))

;;;; The backfill

(defun sp-devonthink-sync--write-keyword (file uuid)
  "Write the keyword with UUID into the note FILE; return non-nil when it changed."
  (with-temp-buffer
    (insert-file-contents file)
    (unless (sp-devonthink-note-uuid)
      (goto-char (sp-devonthink--keyword-insert-point))
      (insert (format "#+%s: %s\n" sp-devonthink-keyword uuid))
      (write-region (point-min) (point-max) file nil 'silent)
      t)))

(defun sp-devonthink-sync--backup (file folder)
  "Copy FILE into FOLDER, keeping its name."
  (make-directory folder t)
  (copy-file file (expand-file-name (file-name-nondirectory file) folder) t))

;;;###autoload
(defun sp-devonthink-sync-backfill (&optional limit)
  "Write `#+devonthink:' into the litnotes that lack it, after a plan and a yes.
LIMIT, a prefix argument, limits how many notes are done."
  (interactive "P")
  (let* ((records (sp-devonthink-sync--records))
         (result (sp-devonthink-sync--compare
                  (sp-devonthink-sync--scan sp-devonthink-sync-directory) records nil
                  #'sp-devonthink--parent-key))
         (todo (append (plist-get result :backfill)
                       (let ((chapters (plist-get result :backfill-parent)))
                         (when (and chapters
                                    (y-or-n-p (format "%d note%s have no record of their own; their crossref parent has one. Also write the PARENT's UUID into them (each then points at a whole book)? "
                                                      (length chapters) (if (cdr chapters) "s" ""))))
                           chapters))))
         (todo (if (integerp limit) (seq-take todo limit)
                 (if (and limit (listp limit)) (seq-take todo (car limit)) todo)))
         (folder (expand-file-name (format-time-string "%Y%m%d-%H%M%S/")
                                   sp-devonthink-sync-backup-directory))
         (done 0) skipped)
    (unless todo (user-error "Nothing to backfill"))
    (sp-devonthink-sync--show (sp-devonthink-sync--section "To backfill" todo t))
    (when (y-or-n-p (format "Write #+%s: into %d note%s (backups in %s)? "
                            sp-devonthink-keyword (length todo) (if (cdr todo) "s" "") folder))
      (dolist (note todo)
        (let* ((file (plist-get note :file))
               (buffer (find-buffer-visiting file)))
          (if (and buffer (buffer-modified-p buffer))
              (push file skipped)
            (sp-devonthink-sync--backup file folder)
            (when (sp-devonthink-sync--write-keyword
                       file (gethash (or (plist-get note :via) (plist-get note :key)) records))
              (cl-incf done)
              (when buffer (with-current-buffer buffer (revert-buffer t t t)))))))
      (message "Wrote the keyword into %d note%s%s" done (if (= done 1) "" "s")
               (if skipped (format "; skipped %d with unsaved changes" (length skipped)) "")))))

;;;; The link in the record

(defun sp-devonthink-sync--probe-script (uuid)
  "The AppleScript that sets, reads and clears the metadata field on the record UUID."
  (format "tell application id \"DNtp\"
  set r to get record with uuid %s
  try
    add custom meta data %s for %s to r
    set v to get custom meta data for %s from r
    add custom meta data \"\" for %s to r
    return \"ok: \" & v
  on error m
    return \"error: \" & m
  end try
end tell"
          (sp-reading--quote uuid)
          (sp-reading--quote (format sp-devonthink-sync-url-template "probe"))
          (sp-reading--quote sp-devonthink-sync-record-field)
          (sp-reading--quote sp-devonthink-sync-record-field)
          (sp-reading--quote sp-devonthink-sync-record-field)))

;;;###autoload
(defun sp-devonthink-sync-probe-field (uuid)
  "Try the metadata field on the record UUID: set a value, read it back, clear it."
  (interactive (list (or (sp-devonthink-note-record-uuid "write the test value on")
                         (read-string "Record UUID: "))))
  (let ((answer (sp-reading--osascript (sp-devonthink-sync--probe-script uuid))))
    (message "DEVONthink field %s: %s" sp-devonthink-sync-record-field answer)
    answer))

(defun sp-devonthink-sync--link-plan (notes records)
  "The (UUID . ID) pairs for NOTES whose keyword UUID is a live record of RECORDS."
  (let ((uuids (make-hash-table :test 'equal)) plan)
    (maphash (lambda (_ uuid) (puthash (upcase uuid) t uuids)) records)
    (dolist (note notes)
      (when (and (plist-get note :uuid) (plist-get note :id)
                 (gethash (upcase (plist-get note :uuid)) uuids))
        (push (cons (plist-get note :uuid) (plist-get note :id)) plan)))
    (nreverse plan)))

(defun sp-devonthink-sync--link-script (plan)
  "The AppleScript that writes the link of each (UUID . ID) of PLAN into its record."
  (format "tell application id \"DNtp\"
  set theErrors to 0
%s  return theErrors as text
end tell"
          (mapconcat
           (lambda (pair)
             (format "  try\n    add custom meta data %s for %s to (get record with uuid %s)\n  on error\n    set theErrors to theErrors + 1\n  end try\n"
                     (sp-reading--quote (format sp-devonthink-sync-url-template (cdr pair)))
                     (sp-reading--quote sp-devonthink-sync-record-field)
                     (sp-reading--quote (car pair))))
           plan "")))

;;;###autoload
(defun sp-devonthink-sync-record-links (&optional limit)
  "Write the litnote link into the records of the notes that have a live keyword.
Shows the plan and asks first; a prefix argument LIMIT limits how many."
  (interactive "P")
  (let* ((records (sp-devonthink-sync--records))
         (plan (sp-devonthink-sync--link-plan
                (sp-devonthink-sync--scan sp-devonthink-sync-directory) records))
         (plan (if (integerp limit) (seq-take plan limit)
                 (if (and limit (listp limit)) (seq-take plan (car limit)) plan))))
    (unless plan (user-error "No note with a live #+%s: keyword" sp-devonthink-keyword))
    (sp-devonthink-sync--show
     (concat "#+title: Links to write into DEVONthink\n\n"
             (mapconcat (lambda (pair)
                          (format "- %s :: %s" (car pair)
                                  (format sp-devonthink-sync-url-template (cdr pair))))
                        (seq-take plan sp-devonthink-sync-report-limit) "\n")
             (format "\n\n%d record%s in all.\n" (length plan) (if (cdr plan) "s" ""))))
    (when (y-or-n-p (format "Write the %s field of %d record%s? "
                            sp-devonthink-sync-record-field (length plan) (if (cdr plan) "s" "")))
      (message "Done; %s record%s failed"
               (sp-reading--osascript (sp-devonthink-sync--link-script plan))
               "s"))))

(defun sp-devonthink-protocol-note (info)
  "Open the litnote of an org-protocol request INFO (a plist with :id, or the id)."
  (let ((id (cond ((listp info) (plist-get info :id))
                  ((string-match "\\(?:id=\\)?\\([^&]+\\)\\'" info) (match-string 1 info)))))
    (unless id (user-error "No note id in the request"))
    (require 'org-id)
    (org-id-open id nil)
    nil))

(with-eval-after-load 'org-protocol
  (add-to-list 'org-protocol-protocol-alist
               '("devonthink-note" :protocol "devonthink-note"
                 :function sp-devonthink-protocol-note)))

;;;; Keys

(keymap-set sp-devonthink-map "y" #'sp-devonthink-sync-report)

(provide 'sp-devonthink-sync)
;;; sp-devonthink-sync.el ends here
