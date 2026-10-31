;;; sp-litnotes-refs.el --- Move litnote references to ROAM_REFS -*- lexical-binding: t; -*-

;;; Commentary:

;; `citar-denote' stored a note's citation key in a `#+reference:' keyword.
;; `citar-vulpea' reads `@key' values from a property, `ROAM_REFS'.  This module
;; reports what would change (`sp-litnotes-refs-report') and then converts the
;; notes (`sp-litnotes-refs-convert').  Nothing is written by the report.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar sp-notes-dir)
(defvar sp-var-dir)
(defvar sp-literature-dir)
(defvar sp-bibtex-files)

(defgroup sp-litnotes-refs nil
  "Convert literature note references to ROAM_REFS."
  :group 'sp-academic)

(defcustom sp-litnotes-refs-directory
  (expand-file-name "litnotes/" (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes"))
  "Folder with the literature notes."
  :type 'directory)

(defcustom sp-litnotes-refs-backup-directory
  (expand-file-name "litnote-refs-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Folder where `sp-litnotes-refs-convert' copies each note before changing it."
  :type 'directory)

(defconst sp-litnotes-refs--key-regexp "\\`[[:alnum:]_:-]+\\'"
  "Regexp for a citation key; the same characters `citar-vulpea' accepts.")

;;;; Reading references

(defun sp-litnotes-refs--tokens (string)
  "Split the reference STRING into (KEYS . OTHERS).
KEYS are citation keys without a prefix; OTHERS are values that are not keys
(URLs, DOIs) and are kept as they are.  `@key', `key', `cite:key' and
`[cite:@a;@b]' are all read."
  (let ((clean (replace-regexp-in-string "\\[cite[^:]*:\\|\\]" "" (or string "")))
        keys others)
    (dolist (token (split-string clean "[ \t;,]+" t))
      (let ((bare (replace-regexp-in-string "\\`\\(cite:\\)?@?" "" token)))
        (cond ((string-match-p "\\`https?:\\|\\`doi:\\|/" token) (push token others))
              ((string-match-p sp-litnotes-refs--key-regexp bare) (push bare keys))
              (t (push token others)))))
    (cons (nreverse keys) (nreverse others))))

(defun sp-litnotes-refs--parse (file)
  "Read the reference data of the note FILE as a plist.
The keys are :file, :id, :roam (the =ROAM_REFS= value), :keyword (the
=#+reference:= value) and :drawer (non-nil when the note starts with a
property drawer, which a file-level Vulpea node needs)."
  (with-temp-buffer
    (insert-file-contents file)
    (let (id roam keyword drawer-end (case-fold-search t))
      (goto-char (point-min))
      (when (looking-at ":PROPERTIES:[ \t]*$")
        (when (re-search-forward "^:END:[ \t]*$" nil t)
          (setq drawer-end (line-beginning-position))
          (goto-char (point-min))
          (when (re-search-forward "^:ID:[ \t]+\\(.+\\)$" drawer-end t)
            (setq id (match-string 1)))
          (goto-char (point-min))
          (when (re-search-forward "^:ROAM_REFS:[ \t]*\\(.*\\)$" drawer-end t)
            (setq roam (string-trim (match-string 1))))))
      (goto-char (point-min))
      (when (re-search-forward "^#\\+reference:[ \t]*\\(.*\\)$" nil t)
        (setq keyword (string-trim (match-string 1))))
      (list :file file :id id :roam roam :keyword keyword
            :drawer (and drawer-end t)))))

;;;; Planning

(defun sp-litnotes-refs--plan (parsed)
  "Say what to do with the note PARSED (see `sp-litnotes-refs--parse').
Returns PARSED plus :status and :refs, the new =ROAM_REFS= value.  The status is
one of `no-id', `no-reference', `ok', `normalise', `convert' and `merge'."
  (let* ((roam (and parsed (plist-get parsed :roam)))
         (roam (and roam (not (string-empty-p roam)) roam))
         (keyword (let ((k (plist-get parsed :keyword)))
                    (and k (not (string-empty-p k)) k)))
         (from-roam (sp-litnotes-refs--tokens roam))
         (from-key (sp-litnotes-refs--tokens keyword))
         (keys (delete-dups (append (car from-roam) (car from-key))))
         (others (delete-dups (append (cdr from-roam) (cdr from-key))))
         (refs (string-join (append (mapcar (lambda (k) (concat "@" k)) keys) others) " "))
         (status (cond ((not (and (plist-get parsed :drawer) (plist-get parsed :id))) 'no-id)
                       ((and (not roam) (not keyword)) 'no-reference)
                       ((not keyword) (if (equal roam refs) 'ok 'normalise))
                       (roam 'merge)
                       (t 'convert))))
    (append parsed (list :status status :keys keys :refs refs))))

;;;; Bibliography and PDFs

(defun sp-litnotes-refs--bib-index (files)
  "Read the BibTeX FILES into a hash table of key to crossref (or :none)."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (file files)
      (when (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward
                  "^@\\([[:alpha:]]+\\)[ \t]*[{(][ \t]*\\([^, \t\n]+\\)[ \t]*," nil t)
            (unless (member (downcase (match-string 1)) '("comment" "string" "preamble"))
              (let ((key (match-string 2))
                    (end (save-excursion (or (and (re-search-forward "^@" nil t)
                                                  (line-beginning-position))
                                             (point-max))))
                    crossref)
                (save-excursion
                  (when (re-search-forward
                         "^[ \t]*crossref[ \t]*=[ \t]*[{\"]\\([^}\"]+\\)" end t)
                    (setq crossref (match-string 1))))
                (puthash key (or crossref :none) table)))))))
    table))

(defun sp-litnotes-refs--pdf (key index)
  "Return how the PDF for KEY is found: `own', `crossref' or nil.
A book section often has no PDF of its own; its crossref entry (the book) does."
  (let ((dir (if (boundp 'sp-literature-dir) sp-literature-dir "~/Documents/literature/"))
        (parent (gethash key index)))
    (cond ((file-exists-p (expand-file-name (concat key ".pdf") dir)) 'own)
          ((and (stringp parent)
                (file-exists-p (expand-file-name (concat parent ".pdf") dir)))
           'crossref))))

;;;; Report

(defun sp-litnotes-refs--plans (&optional directory)
  "Plans for every note in DIRECTORY (default `sp-litnotes-refs-directory')."
  (mapcar (lambda (file) (sp-litnotes-refs--plan (sp-litnotes-refs--parse file)))
          (directory-files (or directory sp-litnotes-refs-directory) t "\\.org\\'")))

(defun sp-litnotes-refs--report-text (plans index)
  "Return the dry-run report for PLANS, looking keys up in INDEX."
  (let ((by-status (make-hash-table :test 'eq))
        (by-key (make-hash-table :test 'equal))
        (pdf-counts (list (cons 'own 0) (cons 'crossref 0) (cons nil 0)))
        unknown)
    (dolist (plan plans)
      (push plan (gethash (plist-get plan :status) by-status))
      (dolist (key (plist-get plan :keys))
        (push plan (gethash key by-key))
        (unless (gethash key index) (push (cons key plan) unknown))
        (cl-incf (alist-get (sp-litnotes-refs--pdf key index) pdf-counts nil nil #'eq))))
    (with-temp-buffer
      (insert (format "#+title: Litnote references: dry run\n\nFolder: =%s=\nNotes: %d\n\n"
                      sp-litnotes-refs-directory (length plans)))
      (insert "* Counts\n")
      (dolist (status '(convert merge normalise ok no-reference no-id))
        (insert (format "- %s: %d\n" status (length (gethash status by-status)))))
      (insert (format "- keys not in any registered .bib: %d\n" (length unknown)))
      (insert (format "- keys with a PDF of their own: %d; through crossref: %d; none: %d\n\n"
                      (alist-get 'own pdf-counts) (alist-get 'crossref pdf-counts)
                      (alist-get nil pdf-counts nil nil #'eq)))
      (dolist (spec '((convert "Would add ROAM_REFS and drop #+reference:")
                      (merge "Has both: would merge into ROAM_REFS and drop #+reference:")
                      (normalise "ROAM_REFS in another format: would rewrite as @key")
                      (no-id "No top-level :ID: drawer: not a Vulpea file node, skipped")))
        (when-let* ((items (reverse (gethash (car spec) by-status))))
          (insert (format "* %s (%d)\n" (cadr spec) (length items)))
          (dolist (plan items)
            (insert (format "- =%s=: %s -> %s\n"
                            (file-name-nondirectory (plist-get plan :file))
                            (or (plist-get plan :keyword) (plist-get plan :roam) "")
                            (plist-get plan :refs))))
          (insert "\n")))
      (when unknown
        (insert (format "* Keys that no registered .bib has (%d)\n" (length unknown)))
        (dolist (item (reverse unknown))
          (insert (format "- %s in =%s=\n" (car item)
                          (file-name-nondirectory (plist-get (cdr item) :file)))))
        (insert "\n"))
      (let (dups)
        (maphash (lambda (key notes) (when (cdr notes) (push (cons key notes) dups))) by-key)
        (when dups
          (insert (format "* Keys used by more than one note (%d)\n" (length dups)))
          (dolist (dup (sort dups (lambda (a b) (string< (car a) (car b)))))
            (insert (format "- %s: %s\n" (car dup)
                            (mapconcat (lambda (p) (file-name-nondirectory (plist-get p :file)))
                                       (cdr dup) ", "))))))
      (buffer-string))))

;;;###autoload
(defun sp-litnotes-refs-report ()
  "Show what `sp-litnotes-refs-convert' would do.  Writes nothing."
  (interactive)
  (let* ((plans (sp-litnotes-refs--plans))
         (index (sp-litnotes-refs--bib-index (if (boundp 'sp-bibtex-files) sp-bibtex-files nil)))
         (text (sp-litnotes-refs--report-text plans index)))
    (with-current-buffer (get-buffer-create "*litnote refs*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (org-mode)
        (goto-char (point-min))
        (read-only-mode 1)))
    (pop-to-buffer "*litnote refs*")
    plans))

;;;; Conversion

(defun sp-litnotes-refs--apply (file refs)
  "Set =ROAM_REFS= to REFS in the property drawer of FILE and drop =#+reference:=."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward "^:END:[ \t]*$")
    (let ((end (copy-marker (line-beginning-position))))
      (goto-char (point-min))
      (if (re-search-forward "^:ROAM_REFS:.*$" end t)
          (replace-match (concat ":ROAM_REFS: " refs) t t)
        (goto-char end)
        (insert ":ROAM_REFS: " refs "\n")))
    (goto-char (point-min))
    (let ((case-fold-search t))
      (while (re-search-forward "^#\\+reference:.*\n" nil t)
        (replace-match "" t t)))
    (write-region nil nil file nil 'silent)))

;;;###autoload
(defun sp-litnotes-refs-convert ()
  "Convert the notes of the report, after showing it and asking.
Each changed note is copied to `sp-litnotes-refs-backup-directory' first.  Notes
with no top-level :ID: drawer are left alone.  Running it again changes nothing."
  (interactive)
  (let* ((plans (sp-litnotes-refs-report))
         (todo (cl-remove-if-not
                (lambda (p) (memq (plist-get p :status) '(convert merge normalise)))
                plans)))
    (cond ((null todo) (message "Nothing to convert."))
          ((yes-or-no-p (format "Write %d notes (backups in %s)? "
                                (length todo) sp-litnotes-refs-backup-directory))
           (make-directory sp-litnotes-refs-backup-directory t)
           (dolist (plan todo)
             (let ((file (plist-get plan :file)))
               (copy-file file (expand-file-name (file-name-nondirectory file)
                                                 sp-litnotes-refs-backup-directory)
                          t)
               (sp-litnotes-refs--apply file (plist-get plan :refs))))
           (message "Converted %d notes." (length todo)))
          (t (message "Nothing written.")))))

(provide 'sp-litnotes-refs)
;; sp-litnotes-refs.el ends here
