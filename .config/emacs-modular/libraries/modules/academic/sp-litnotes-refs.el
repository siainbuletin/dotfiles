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
(defvar sp-bibliography-dir)

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

(defcustom sp-litnotes-refs-inbox-bib
  (expand-file-name "master.bib"
                    (if (boundp 'sp-bibliography-dir) sp-bibliography-dir "~/Documents/bibliography/"))
  "BibTeX file, the inbox, where stub entries are added for keys that no .bib has."
  :type 'file)

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

(defconst sp-litnotes-refs--meta-keys '("pub-title" "pub-author" "pub-year" "pub-pages")
  "Metadata of a litnote that a stub BibTeX entry takes over.")

(defun sp-litnotes-refs--clean-value (value)
  "VALUE without quotes, and with Org links reduced to their text."
  (let* ((v (string-trim value))
         (v (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" v))
         (v (replace-regexp-in-string "\\[\\[[^]]*\\]\\]" "" v))
         (v (replace-regexp-in-string "\\`\"\\(.*\\)\"\\'" "\\1" v)))
    (string-trim v)))

(defun sp-litnotes-refs--parse (file)
  "Read the reference data of the note FILE as a plist.
The keys are :file, :id, :roam (the =ROAM_REFS= value), :keyword (the
=#+reference:= value) and :drawer (non-nil when the note starts with a
property drawer, which a file-level Vulpea node needs)."
  (with-temp-buffer
    (insert-file-contents file)
    (let (id roam keyword title tags meta drawer-end (case-fold-search t))
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
      (goto-char (point-min))
      (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" nil t)
        (setq title (string-trim (match-string 1))))
      (goto-char (point-min))
      (when (re-search-forward "^#\\+filetags:[ \t]*\\(.*\\)$" nil t)
        (setq tags (split-string (match-string 1) "[: \t]+" t)))
      (dolist (key sp-litnotes-refs--meta-keys)
        (goto-char (point-min))
        (when (re-search-forward
               (format "^\\(?:- +\\|:\\)%s\\(?: ?::\\|:\\)[ \t]*\\(.+\\)$" (regexp-quote key)) nil t)
          (push (cons key (sp-litnotes-refs--clean-value (match-string 1))) meta)))
      (list :file file :id id :roam roam :keyword keyword :title title :tags tags
            :meta meta :drawer (and drawer-end t)))))

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

;;;; Stub BibTeX entries

(defconst sp-litnotes-refs--entry-types
  '(("journalarticle" . "article") ("booksection" . "incollection")
    ("incollection" . "incollection") ("book" . "book") ("collection" . "collection")
    ("inreference" . "inreference") ("encyclopedia" . "inreference")
    ("phdthesis" . "phdthesis") ("thesis" . "thesis"))
  "BibTeX entry type for the file tag of a litnote; any other tag gives `misc'.")

(defun sp-litnotes-refs--entry-type (tags)
  "The BibTeX entry type for the file TAGS of a litnote."
  (or (cl-some (lambda (tag) (cdr (assoc (downcase tag) sp-litnotes-refs--entry-types))) tags)
      "misc"))

(defun sp-litnotes-refs--braced (value)
  "VALUE as a BibTeX field value, with no braces of its own."
  (concat "{" (replace-regexp-in-string "[{}]" "" value) "}"))

(defun sp-litnotes-refs--stub (plan key)
  "A stub BibTeX entry for KEY, from the litnote of PLAN."
  (let* ((meta (plist-get plan :meta))
         (title (or (cdr (assoc "pub-title" meta))
                    (let ((note-title (plist-get plan :title)))
                      (and note-title (not (equal note-title key)) note-title))))
         (dir (if (boundp 'sp-literature-dir) sp-literature-dir "~/Documents/literature/"))
         (fields
          (delq nil
                (list (and title (cons "title" title))
                      (and (assoc "pub-author" meta) (cons "author" (cdr (assoc "pub-author" meta))))
                      (and (assoc "pub-year" meta) (cons "year" (cdr (assoc "pub-year" meta))))
                      (and (assoc "pub-pages" meta) (cons "pages" (cdr (assoc "pub-pages" meta))))
                      (and (file-exists-p (expand-file-name (concat key ".pdf") dir))
                           (cons "file" (format "~/Documents/literature/%s.pdf" key)))
                      (cons "note" (format "Stub made from the litnote %s; complete it"
                                           (file-name-nondirectory (plist-get plan :file))))
                      (cons "DATE_ADDED" (current-time-string))))))
    (concat (format "@%s{%s,\n" (sp-litnotes-refs--entry-type (plist-get plan :tags)) key)
            (mapconcat (lambda (f) (format "  %-12s = %s,\n" (car f) (sp-litnotes-refs--braced (cdr f))))
                       fields "")
            "}\n")))

(defun sp-litnotes-refs--stubs (plans index)
  "Stub entries, as (KEY . TEXT), for the keys of PLANS that INDEX does not have.
A key used by several notes gets one entry, from the first note."
  (let (stubs seen)
    (dolist (plan plans)
      (dolist (key (plist-get plan :keys))
        (unless (or (gethash key index) (member key seen))
          (push key seen)
          (push (cons key (sp-litnotes-refs--stub plan key)) stubs))))
    (nreverse stubs)))

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
      (let ((stubs (sp-litnotes-refs--stubs plans index)))
        (when stubs
          (insert (format "* Would add to %s (%d stub entries)\n"
                          (file-name-nondirectory sp-litnotes-refs-inbox-bib) (length stubs)))
          (dolist (stub stubs)
            (insert (format "- %s: %s\n" (car stub)
                            (if (string-match "^@\\([[:alpha:]]+\\)" (cdr stub))
                                (match-string 1 (cdr stub)) ""))))
          (insert "\n")))
      (dolist (spec '((convert "Would add ROAM_REFS and drop #+reference:")
                      (merge "Has both: would merge into ROAM_REFS and drop #+reference:")
                      (normalise "ROAM_REFS in another format: would rewrite as @key")
                      (no-id "No top-level :ID: drawer: would get a new ID (and ROAM_REFS) if you agree; otherwise skipped")))
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

(defun sp-litnotes-refs--apply (file refs &optional create-id)
  "Set =ROAM_REFS= to REFS in the property drawer of FILE and drop =#+reference:=.
With CREATE-ID the note gets an =:ID:= (and a property drawer, when it has none).
An empty REFS leaves =ROAM_REFS= alone."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (when (and create-id (not (looking-at ":PROPERTIES:[ \t]*$")))
      (insert ":PROPERTIES:\n:END:\n"))
    (goto-char (point-min))
    (re-search-forward "^:END:[ \t]*$")
    (let ((end (copy-marker (line-beginning-position) t)))
      (when create-id
        (goto-char (point-min))
        (unless (re-search-forward "^:ID:" end t)
          (goto-char end)
          (insert ":ID:       " (org-id-uuid) "\n")))
      (unless (string-empty-p refs)
        (goto-char (point-min))
        (if (re-search-forward "^:ROAM_REFS:.*$" end t)
            (replace-match (concat ":ROAM_REFS: " refs) t t)
          (goto-char end)
          (insert ":ROAM_REFS: " refs "\n"))))
    (goto-char (point-min))
    (let ((case-fold-search t))
      (while (re-search-forward "^#\\+reference:.*\n" nil t)
        (replace-match "" t t)))
    (write-region nil nil file nil 'silent)))

(defun sp-litnotes-refs--backup (file)
  "Copy FILE to `sp-litnotes-refs-backup-directory', with a time stamp when needed."
  (make-directory sp-litnotes-refs-backup-directory t)
  (let ((target (expand-file-name (file-name-nondirectory file)
                                  sp-litnotes-refs-backup-directory)))
    (when (file-exists-p target)
      (setq target (concat target (format-time-string ".%Y%m%dT%H%M%S"))))
    (copy-file file target t)))

(defun sp-litnotes-refs--append-stubs (stubs)
  "Append the STUBS, from `sp-litnotes-refs--stubs', to `sp-litnotes-refs-inbox-bib'."
  (when (file-exists-p sp-litnotes-refs-inbox-bib)
    (sp-litnotes-refs--backup sp-litnotes-refs-inbox-bib))
  (with-temp-buffer
    (when (file-exists-p sp-litnotes-refs-inbox-bib)
      (insert-file-contents sp-litnotes-refs-inbox-bib))
    (goto-char (point-max))
    (unless (or (bobp) (bolp)) (insert "\n"))
    (dolist (stub stubs) (insert "\n" (cdr stub)))
    (write-region nil nil sp-litnotes-refs-inbox-bib nil 'silent)))

;;;###autoload
(defun sp-litnotes-refs-convert ()
  "Convert the notes of the report, after showing it and asking three times.
1. Move =#+reference:= to =ROAM_REFS= in the notes that have an ID.
2. Create an ID (and move the reference) in the notes that have none.
3. Add stub entries to `sp-litnotes-refs-inbox-bib' for the keys that no
   registered .bib file has.
Each question is asked only when there is something to do, and each changed note
and the inbox file is copied to `sp-litnotes-refs-backup-directory' first.
Running it again changes nothing."
  (interactive)
  (let* ((plans (sp-litnotes-refs-report))
         (index (sp-litnotes-refs--bib-index
                 (if (boundp 'sp-bibtex-files) sp-bibtex-files nil)))
         (todo (cl-remove-if-not
                (lambda (p) (memq (plist-get p :status) '(convert merge normalise)))
                plans))
         (no-id (cl-remove-if-not (lambda (p) (eq (plist-get p :status) 'no-id)) plans))
         (stubs (sp-litnotes-refs--stubs plans index))
         (written 0) (ids 0) (added 0))
    (when (and todo (yes-or-no-p (format "Move the reference of %d notes to ROAM_REFS (backups in %s)? "
                                         (length todo) sp-litnotes-refs-backup-directory)))
      (dolist (plan todo)
        (sp-litnotes-refs--backup (plist-get plan :file))
        (sp-litnotes-refs--apply (plist-get plan :file) (plist-get plan :refs))
        (cl-incf written)))
    (when (and no-id (yes-or-no-p (format "Create an ID for %d notes that have none? " (length no-id))))
      (dolist (plan no-id)
        (sp-litnotes-refs--backup (plist-get plan :file))
        (sp-litnotes-refs--apply (plist-get plan :file) (plist-get plan :refs) t)
        (cl-incf ids)))
    (when (and stubs (yes-or-no-p (format "Add %d stub entries to %s? " (length stubs)
                                          (file-name-nondirectory sp-litnotes-refs-inbox-bib))))
      (sp-litnotes-refs--append-stubs stubs)
      (setq added (length stubs)))
    (message "Converted %d notes, created %d IDs, added %d stub entries." written ids added)))

(provide 'sp-litnotes-refs)
;; sp-litnotes-refs.el ends here
