;;; sp-bibtex-biblatex.el --- Convert the .bib files to BibLaTeX conventions -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-bibtex-lint-fix-biblatex' renames BibTeX-only field names to the BibLaTeX
;; ones and writes BibTeX accents as Unicode.  Dates, citekeys and file names are
;; never touched.  See docs/tangles/academic/sp-bibtex-biblatex.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'bibtex)

(defvar sp-var-dir)
(declare-function sp-author-notes-latex-to-unicode "sp-author-notes")
(declare-function sp-bibtex-ascii-key "sp-bibprocess")
(declare-function sp-bibtex-lint--files "sp-bibprocess")
(declare-function sp-bibtex-lint--read-file "sp-bibprocess")
(declare-function sp-bibtex-lint--unsaved-check "sp-bibprocess")
(declare-function sp-bibtex-lint--signature "sp-bibprocess")
(declare-function sp-bibtex-lint--save "sp-bibprocess")

(defgroup sp-bibtex-biblatex nil
  "Convert the .bib files to BibLaTeX conventions."
  :group 'sp-bibtex
  :prefix "sp-bibtex-biblatex-")

(defcustom sp-bibtex-biblatex-renames
  '(("journal" . "journaltitle") ("address" . "location") ("place" . "location")
    ("school" . "institution") ("archiveprefix" . "eprinttype")
    ("primaryclass" . "eprintclass"))
  "Field names to rename, as (BIBTEX-NAME . BIBLATEX-NAME)."
  :type '(alist :key-type string :value-type string)
  :group 'sp-bibtex-biblatex)

(defcustom sp-bibtex-biblatex-type-renames
  '(("electronic" . "online") ("webpage" . "online"))
  "Entry types to rename, as (OLD-TYPE . BIBLATEX-TYPE).
`@electronic' is a BibLaTeX alias of `@online'; `@webpage' is not known to
BibLaTeX or Typst, which both read it as `@misc'."
  :type '(alist :key-type string :value-type string)
  :group 'sp-bibtex-biblatex)

(defconst sp-bibtex-biblatex--known-types
  '("article" "book" "mvbook" "inbook" "bookinbook" "suppbook" "booklet" "collection"
    "mvcollection" "incollection" "suppcollection" "dataset" "manual" "misc" "online"
    "patent" "periodical" "suppperiodical" "proceedings" "mvproceedings" "inproceedings"
    "reference" "mvreference" "inreference" "report" "set" "software" "thesis"
    "unpublished" "xdata" "artwork" "audio" "bibnote" "commentary" "image" "jurisdiction"
    "legal" "legislation" "letter" "movie" "music" "performance" "review" "standard" "video"
    "phdthesis" "mastersthesis" "techreport" "conference" "electronic" "www")
  "Entry types of BibLaTeX, with its non-standard types and BibTeX aliases.")

(defcustom sp-bibtex-biblatex-unicode t
  "Non-nil: the conversion writes BibTeX accents as Unicode.
`f{\\\"u}r' becomes `für'.  Fields of `sp-bibtex-biblatex-ascii-fields' are left alone."
  :type 'boolean
  :group 'sp-bibtex-biblatex)

(defcustom sp-bibtex-biblatex-ascii-fields
  '("file" "pdf" "crossref" "xref" "xdata" "related" "ids" "url" "doi" "eprint"
    "isbn" "issn" "groups" "keywords" "timestamp" "date_added" "date-added" "date-modified")
  "Fields whose text is never decoded: names of files, links and keys."
  :type '(repeat string)
  :group 'sp-bibtex-biblatex)

(defcustom sp-bibtex-biblatex-backup-directory
  (expand-file-name "bibtex-biblatex-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Folder where each run keeps the .bib files as they were, one sub-folder for each run."
  :type 'directory
  :group 'sp-bibtex-biblatex)

(defconst sp-bibtex-biblatex--buffer "*BibLaTeX conversion*")

(defconst sp-bibtex-biblatex--command-re
  (concat "\\\\\\(?:['`^\"~=.][ ]*\\(?:{[[:alpha:]]}\\|[[:alpha:]]\\)"
          "\\|[uvcHkr]\\(?:{[[:alpha:]]}\\| [[:alpha:]]\\)"
          "\\|\\(?:oe\\|OE\\|ae\\|AE\\|aa\\|AA\\|ss\\|o\\|O\\|l\\|L\\|i\\|j\\)\\_>\\)")
  "One accent or letter command of BibTeX.")

(defun sp-bibtex-biblatex--unicode (text)
  "TEXT with the BibTeX accents written as Unicode; TEXT itself without a backslash."
  (if (not (string-search "\\" text))
      text
    (require 'sp-author-notes)
    (let* ((cmd sp-bibtex-biblatex--command-re)
           (text (replace-regexp-in-string
                  "\\(\\\\['`^\"~=.]\\)[ ]*\\(?:{\\\\i}\\|\\\\i\\_>\\)" "\\1i" text))
           (decode (lambda (fragment)
                     (sp-author-notes-latex-to-unicode fragment))))
      (replace-regexp-in-string
       (concat "{\\(" cmd "\\)}\\|\\(" cmd "\\)")
       (lambda (m)
         ;; the decoder runs regexps itself; keep our match data for the caller
         (save-match-data
           (funcall decode (if (string-prefix-p "{" m) (substring m 1 -1) m))))
       text t t))))

(defun sp-bibtex-biblatex--entry-end ()
  "The end of the entry at point."
  (save-excursion (bibtex-end-of-entry) (point)))

(defun sp-bibtex-biblatex--all-fields ()
  "The bounds of every field of the entry at point, first to last."
  (save-excursion
    (bibtex-beginning-of-entry)
    (let ((end (sp-bibtex-biblatex--entry-end)) fields bounds)
      (while (and (setq bounds (bibtex-search-forward-field "[[:alnum:]_-]+" end))
                  (not (memq bounds fields)))
        (push bounds fields)
        (goto-char (max (point) (nth 3 bounds)))
        (unless (> (point) (nth 1 (car bounds))) (goto-char (1+ (point)))))
      (nreverse fields))))

(defun sp-bibtex-biblatex--name (bounds)
  "The name of the field with BOUNDS, in lower case."
  (downcase (buffer-substring-no-properties (nth 1 (car bounds)) (nth 2 (car bounds)))))

(defun sp-bibtex-biblatex--text (bounds)
  "The text of the field with BOUNDS, delimiters included."
  (buffer-substring-no-properties (nth 1 bounds) (nth 2 bounds)))

(defun sp-bibtex-biblatex--find (name)
  "The bounds of the first field called NAME in the entry at point, or nil."
  (seq-find (lambda (b) (equal (sp-bibtex-biblatex--name b) name))
            (sp-bibtex-biblatex--all-fields)))

(defun sp-bibtex-biblatex--mentions-p (name)
  "Non-nil when the entry at point seems to have a field NAME.
A cheap search of the text, to skip the slow search of the field bounds."
  (save-excursion
    (let ((case-fold-search t)
          (end (progn (bibtex-beginning-of-entry) (sp-bibtex-biblatex--entry-end))))
      (bibtex-beginning-of-entry)
      (re-search-forward (concat "^[ \t]*" (regexp-quote name) "[ \t]*=") end t))))

(defun sp-bibtex-biblatex--same-text (a b)
  "Non-nil when the field texts A and B say the same: delimiters and blanks do not count."
  (let ((norm (lambda (s)
                (string-trim (replace-regexp-in-string
                              "[ \t\n]+" " "
                              (replace-regexp-in-string "\\`[{\"]\\|[}\"]\\'" "" (string-trim s)))))))
    (equal (funcall norm a) (funcall norm b))))

(defun sp-bibtex-biblatex--delete-field (bounds)
  "Delete the field with BOUNDS, with its line."
  (let ((beg (nth 1 (car bounds))) (end (nth 3 bounds)))
    (save-excursion
      (goto-char beg) (beginning-of-line) (setq beg (point))
      (goto-char end)
      (when (looking-at "[ \t]*,?[ \t]*\n") (goto-char (match-end 0)))
      (delete-region beg (point)))))

(defun sp-bibtex-biblatex--rename (from to)
  "Rename the field FROM of the entry at point to TO; return (KIND . TEXT) or nil."
  (when-let* (((sp-bibtex-biblatex--mentions-p from))
              (old (sp-bibtex-biblatex--find from)))
    (if-let* ((new (sp-bibtex-biblatex--find to)))
        (if (sp-bibtex-biblatex--same-text (sp-bibtex-biblatex--text old)
                                           (sp-bibtex-biblatex--text new))
            (progn (sp-bibtex-biblatex--delete-field old)
                   (cons 'change (format "%s dropped, %s has the same text" from to)))
          (cons 'problem (format "%s and %s differ; both left as they are" from to)))
      (goto-char (nth 1 (car old)))
      (delete-region (nth 1 (car old)) (nth 2 (car old)))
      (insert to)
      ;; keep the = aligned: a longer name takes the blanks that were before it
      (let ((delta (- (length to) (length from))))
        (when (and (> delta 0) (looking-at (format " \\{%d\\}" (1+ delta))))
          (delete-char delta)))
      (cons 'change (format "%s → %s" from to)))))

(defun sp-bibtex-biblatex--decode-fields ()
  "Write the accents of the entry at point as Unicode; return the changed field names."
  (let (changed)
    (dolist (bounds (reverse (sp-bibtex-biblatex--all-fields)))
      (let ((name (sp-bibtex-biblatex--name bounds)))
        (unless (member name sp-bibtex-biblatex-ascii-fields)
          (let* ((old (sp-bibtex-biblatex--text bounds))
                 (new (sp-bibtex-biblatex--unicode old)))
            (unless (equal old new)
              (goto-char (nth 1 bounds))
              (delete-region (nth 1 bounds) (nth 2 bounds))
              (insert new)
              (push name changed))))))
    changed))

(defun sp-bibtex-biblatex--checks (key)
  "The lines of the report for the entry KEY at point; nothing is changed."
  (let (lines)
    (when (string-match-p "[^[:ascii:]]" key)
      (push (format "citekey %s has a non-ASCII letter%s" key
                    (if (fboundp 'sp-bibtex-ascii-key)
                        (format " (ASCII: %s)" (sp-bibtex-ascii-key key))
                      ""))
            lines))
    (dolist (bounds (sp-bibtex-biblatex--all-fields))
      (let ((name (sp-bibtex-biblatex--name bounds))
            (text (sp-bibtex-biblatex--text bounds)))
        (when (and (member name '("file" "pdf")) (string-match-p "[^[:ascii:]]" text))
          (push "file name with a non-ASCII character, left as it is" lines))
        (when (string-match-p "&amp;\\|&lt;\\|&gt;" text)
          (push (format "%s has an HTML entity (write \\& for &)" name) lines))
        (when (and (equal name "date") (string-match-p "[0-9]T[0-9]" text))
          (push (format "date %s has a time; Typst reads it as text" text) lines))))
    (nreverse lines)))

(defun sp-bibtex-biblatex--convert-type (type)
  "Rename the TYPE of the entry at point when `sp-bibtex-biblatex-type-renames' says so.
Return the change line or nil.  Point must be at the `@' of the entry."
  (when-let* ((new (cdr (assoc-string type sp-bibtex-biblatex-type-renames t)))
              ((looking-at "[ \t]*@\\([[:alpha:]]+\\)")))
    (replace-match new t t nil 1)
    (format "@%s → @%s" (downcase type) new)))

(defun sp-bibtex-biblatex--convert-entry (key type)
  "Convert the entry KEY of TYPE at point; return (CHANGES . PROBLEMS).
Point must be at the `@' of the entry."
  (let (changes problems)
    (when-let* ((done (sp-bibtex-biblatex--convert-type type)))
      (push done changes)
      (setq type (cdr (assoc-string type sp-bibtex-biblatex-type-renames t))))
    (unless (member-ignore-case type sp-bibtex-biblatex--known-types)
      (push (format "@%s is not a BibLaTeX type; Typst and biber read it as @misc" (downcase type))
            problems))
    (dolist (rename sp-bibtex-biblatex-renames)
      (when-let* ((done (sp-bibtex-biblatex--rename (car rename) (cdr rename))))
        (push (cdr done) (if (eq (car done) 'change) changes problems))))
    (when sp-bibtex-biblatex-unicode
      (when-let* ((fields (sp-bibtex-biblatex--decode-fields)))
        (push (format "accents as Unicode in %s" (string-join (nreverse fields) ", ")) changes)))
    (cons (nreverse changes)
          (append (nreverse problems) (sp-bibtex-biblatex--checks key)))))

(defun sp-bibtex-biblatex--set-dialect ()
  "Give the current buffer the `biblatex' dialect, extended by the types it uses.
`bibtex-mode' finds the bounds of an entry only for the types of its dialect, so
`@video', `@webpage' or `@news' would be unreadable; each type of the buffer that
the dialect lacks is added, with the fields of `@misc'."
  (let* ((misc (assoc-string "misc" bibtex-biblatex-entry-alist t))
         (types (let (found)
                  (save-excursion
                    (goto-char (point-min))
                    (while (re-search-forward "^[ \t]*@\\([[:alpha:]]+\\)[ \t]*[{(]" nil t)
                      (cl-pushnew (downcase (match-string 1)) found :test #'equal)))
                  found))
         (extra (mapcar (lambda (ty) (cons (capitalize ty) (cons ty (nthcdr 2 misc))))
                        (seq-remove (lambda (ty) (assoc-string ty bibtex-biblatex-entry-alist t))
                                    (seq-difference types '("string" "preamble" "comment")))))
         (bibtex-biblatex-entry-alist (append bibtex-biblatex-entry-alist extra)))
    (bibtex-set-dialect 'biblatex t)))

(defun sp-bibtex-biblatex--convert-buffer ()
  "Convert every entry of the current `bibtex-mode' buffer in place.
Return a list of (KEY CHANGES PROBLEMS) for the entries that have changes or problems."
  (sp-bibtex-biblatex--set-dialect)
  (goto-char (point-min))
  (let (results)
    (while (re-search-forward "^[ \t]*@[[:alpha:]]+[ \t]*[{(]" nil t)
      (let ((beg (match-beginning 0)) (header (downcase (match-string 0))))
        (goto-char beg)
        (if (string-match-p "@[ \t]*\\(string\\|preamble\\|comment\\)" header)
            (goto-char (min (point-max) (1+ (match-end 0))))
          (let* ((entry (ignore-errors (bibtex-parse-entry)))
                 (key (cdr (assoc "=key=" entry)))
                 (end (and entry (ignore-errors (sp-bibtex-biblatex--entry-end)))))
            (cond
             ((not (and key end))
              (push (list (or key "?") nil '("could not be read, left as it is")) results)
              (goto-char (min (point-max) (1+ beg))))
             ((save-excursion (goto-char beg) (re-search-forward "^[ \t]*%" end t))
              (push (list key nil '("has a comment inside, left as it is")) results)
              (goto-char end))
             (t
              (let ((done (save-excursion (goto-char beg)
                                          (sp-bibtex-biblatex--convert-entry key (cdr (assoc "=type=" entry))))))
                (when (or (car done) (cdr done))
                  (push (list key (car done) (cdr done)) results))
                (goto-char (sp-bibtex-biblatex--entry-end)))))))))
    (nreverse results)))

(defun sp-bibtex-biblatex--keys ()
  "The entry keys of the current buffer, in order."
  (let (keys)
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*@\\([[:alpha:]]+\\)[ \t]*[{(][ \t]*\\([^, \t\n]+\\)," nil t)
      (unless (member (downcase (match-string 1)) '("string" "preamble" "comment"))
        (push (match-string 2) keys)))
    (nreverse keys)))

(defun sp-bibtex-biblatex--unreadable (file)
  "Why FILE is not a UTF-8 text file, or nil when it is one."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (cond
     ((search-forward "\0" nil t) "binary file (a macOS alias?), skipped")
     ((progn (set-buffer-multibyte t)
             (let ((coding-system-for-read 'utf-8))
               (erase-buffer) (insert-file-contents file))
             (re-search-forward "[\x3fff80-\x3fffff]" nil t))
      "not valid UTF-8, skipped"))))

(defun sp-bibtex-biblatex--convert-file (file)
  "Convert the .bib FILE in a temporary buffer; the file itself is not changed."
  (if-let* ((why (sp-bibtex-biblatex--unreadable file)))
      (list :file file :results nil :text nil :changed nil :skipped why)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents file))
      (let ((coding buffer-file-coding-system))
        (delay-mode-hooks (bibtex-mode))
        (let* ((before (progn (goto-char (point-min)) (sp-bibtex-biblatex--keys)))
               (original (buffer-string))
               (results (sp-bibtex-biblatex--convert-buffer))
               (after (sp-bibtex-biblatex--keys)))
          (unless (equal before after)
            (error "%s: the entries differ after the conversion, nothing written"
                   (file-name-nondirectory file)))
          (list :file file :results results :text (buffer-string) :coding coding
                :changed (not (equal original (buffer-string)))))))))

(defun sp-bibtex-biblatex--rule-counts (runs)
  "An alist from the kind of change to how often it happened in RUNS."
  (let (counts)
    (dolist (run runs)
      (dolist (result (plist-get run :results))
        (dolist (change (nth 1 result))
          (let* ((kind (if (string-match "\\`\\([[:alpha:]]+\\) →" change)
                           change
                         (replace-regexp-in-string " in .*\\'" "" (replace-regexp-in-string " dropped.*\\'" " dropped" change))))
                 (cell (assoc kind counts)))
            (if cell (cl-incf (cdr cell)) (push (cons kind 1) counts))))))
    (sort counts (lambda (a b) (> (cdr a) (cdr b))))))

(defun sp-bibtex-biblatex--report-text (runs)
  "The text of the report for RUNS, the plists of `sp-bibtex-biblatex--convert-file'."
  (let ((changed (cl-count-if (lambda (r) (nth 1 r)) (apply #'append (mapcar (lambda (r) (plist-get r :results)) runs))))
        (problems (cl-count-if (lambda (r) (nth 2 r)) (apply #'append (mapcar (lambda (r) (plist-get r :results)) runs)))))
    (with-temp-buffer
      (insert (format "BibLaTeX conversion: %d file%s, %d entr%s change, %d with a problem\n"
                      (length runs) (if (= 1 (length runs)) "" "s")
                      changed (if (= 1 changed) "y" "ies") problems)
              "A applies it (after one question and a backup), q closes.  Dates, citekeys and file names are never changed.\n\n")
      (insert "Changes by rule:\n")
      (pcase-dolist (`(,kind . ,n) (sp-bibtex-biblatex--rule-counts runs))
        (insert (format "  %5d  %s\n" n kind)))
      (dolist (run runs)
        (when (plist-get run :skipped)
          (insert (format "\n%s: %s\n" (file-name-nondirectory (plist-get run :file))
                          (plist-get run :skipped)))))
      (dolist (run runs)
        (when (plist-get run :results)
          (insert (format "\n%s\n" (file-name-nondirectory (plist-get run :file))))
          (pcase-dolist (`(,key ,changes ,problems) (plist-get run :results))
            (dolist (c changes) (insert (format "  %s: %s\n" key c)))
            (dolist (p problems) (insert (format "  %s: ! %s\n" key p))))))
      (buffer-string))))

(defvar sp-bibtex-biblatex-report-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map "A" #'sp-bibtex-biblatex-report-apply)
    map))

(define-derived-mode sp-bibtex-biblatex-report-mode special-mode "BibLaTeX"
  "Report of `sp-bibtex-lint-biblatex-dryrun'.  \\`A' applies the conversion.")

(defvar-local sp-bibtex-biblatex--report-files nil
  "The files of the report in this buffer.")

(defun sp-bibtex-biblatex--show (files runs)
  "Show the report of RUNS, made for FILES."
  (with-current-buffer (get-buffer-create sp-bibtex-biblatex--buffer)
    (sp-bibtex-biblatex-report-mode)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (sp-bibtex-biblatex--report-text runs))
      (goto-char (point-min)))
    (setq sp-bibtex-biblatex--report-files files)
    (pop-to-buffer (current-buffer))))

(defun sp-bibtex-biblatex--files (&optional ask)
  "The .bib files to convert: all of them, or one read with completion when ASK."
  (if ask
      (list (sp-bibtex-lint--read-file t))
    (or (sp-bibtex-lint--files) (user-error "No .bib file is registered"))))

;;;###autoload
(defun sp-bibtex-lint-biblatex-dryrun (&optional ask)
  "Report what the BibLaTeX conversion would change in all .bib files; write nothing.
With a prefix argument ASK, read one file with completion.  See
`sp-bibtex-lint-fix-biblatex'.  Return the plists of the conversion."
  (interactive "P")
  (let* ((files (sp-bibtex-biblatex--files ask))
         (runs (mapcar #'sp-bibtex-biblatex--convert-file files)))
    (sp-bibtex-biblatex--show files runs)
    runs))

(defun sp-bibtex-biblatex--sha (file)
  "The SHA-1 of the bytes of FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha1 (current-buffer))))

(defun sp-bibtex-biblatex--write-manifest (dir manifest)
  "Write MANIFEST to the run folder DIR."
  (with-temp-file (expand-file-name "manifest.eld" dir)
    (let ((print-length nil) (print-level nil))
      (prin1 manifest (current-buffer)))))

;;;###autoload
(defun sp-bibtex-lint-fix-biblatex (&optional ask)
  "Convert all .bib files to BibLaTeX conventions, after one question and a backup.
With a prefix argument ASK, read one file with completion.  Run
`sp-bibtex-lint-biblatex-dryrun' first to see what changes.

- Renames BibTeX-only fields (`sp-bibtex-biblatex-renames') and writes accents
  as Unicode (`sp-bibtex-biblatex-unicode').
- Never changes dates, citekeys or file names.
- Copies each file to `sp-bibtex-biblatex-backup-directory' first;
  `sp-bibtex-lint-biblatex-restore' puts them back."
  (interactive "P")
  (let* ((files (sp-bibtex-biblatex--files ask)))
    (dolist (f files) (sp-bibtex-lint--unsaved-check f))
    (let* ((runs (mapcar #'sp-bibtex-biblatex--convert-file files))
           (todo (seq-filter (lambda (r) (plist-get r :changed)) runs)))
      (sp-bibtex-biblatex--show files runs)
      (cond
       ((null todo) (message "Nothing to convert") nil)
       ((yes-or-no-p (format "Convert %d .bib file%s to BibLaTeX conventions (backups in %s)? "
                             (length todo) (if (= 1 (length todo)) "" "s")
                             (abbreviate-file-name sp-bibtex-biblatex-backup-directory)))
        (let* ((stamp (format-time-string "%Y%m%dT%H%M%S"))
               (dir (expand-file-name (concat stamp "/") sp-bibtex-biblatex-backup-directory))
               written)
          (make-directory dir t)
          (dolist (run todo)
            (let ((file (plist-get run :file)))
              (copy-file file (expand-file-name (file-name-nondirectory file) dir) t)))
          (sp-bibtex-biblatex--write-manifest
           dir (list :time stamp :files (mapcar (lambda (r) (list (plist-get r :file))) todo)))
          (dolist (run todo)
            (let ((file (plist-get run :file)) (work (generate-new-buffer " *sp-bibtex-biblatex*")))
              (unwind-protect
                  (progn
                    (with-current-buffer work (insert (plist-get run :text)))
                    (let ((coding-system-for-write (or (plist-get run :coding) 'utf-8)))
                      (sp-bibtex-lint--save work file))
                    (push (list file (sp-bibtex-biblatex--sha file)) written))
                (kill-buffer work))))
          (sp-bibtex-biblatex--write-manifest
           dir (list :time stamp :files (nreverse written)))
          (message "BibLaTeX conversion: %d file%s written; backups in %s"
                   (length written) (if (= 1 (length written)) "" "s") (abbreviate-file-name dir))
          (sp-bibtex-biblatex--show files (mapcar #'sp-bibtex-biblatex--convert-file files))
          written))))))

(defun sp-bibtex-biblatex-report-apply ()
  "Apply the conversion of the report in this buffer."
  (interactive)
  (let ((files sp-bibtex-biblatex--report-files))
    (cl-letf (((symbol-function 'sp-bibtex-biblatex--files) (lambda (&optional _) files)))
      (sp-bibtex-lint-fix-biblatex))))

(defun sp-bibtex-biblatex--runs ()
  "The run folders of the backup directory that have a manifest, newest first."
  (when (file-directory-p sp-bibtex-biblatex-backup-directory)
    (seq-filter (lambda (d) (file-exists-p (expand-file-name "manifest.eld" d)))
                (sort (seq-filter #'file-directory-p
                                  (directory-files sp-bibtex-biblatex-backup-directory t "\\`[0-9]"))
                      #'string>))))

;;;###autoload
(defun sp-bibtex-lint-biblatex-restore (&optional dir)
  "Put back the .bib files of a run of `sp-bibtex-lint-fix-biblatex'.
DIR is the run folder; it is read with completion (newest first) when nil.  A
file that changed after the run is kept in `before-restore/' of the run folder."
  (interactive)
  (let* ((runs (or (sp-bibtex-biblatex--runs) (user-error "No run to restore")))
         (dir (or dir (completing-read "Restore the run: "
                                       (mapcar #'file-name-nondirectory runs) nil t nil nil
                                       (file-name-nondirectory (car runs)))))
         (dir (file-name-as-directory
               (if (file-name-absolute-p dir) dir
                 (expand-file-name dir sp-bibtex-biblatex-backup-directory))))
         (manifest (with-temp-buffer
                     (insert-file-contents (expand-file-name "manifest.eld" dir))
                     (read (current-buffer))))
         (files (plist-get manifest :files)))
    (dolist (entry files)
      (when-let* ((b (find-buffer-visiting (car entry)))
                  ((buffer-modified-p b)))
        (user-error "Save or close %s first" (file-name-nondirectory (car entry)))))
    (when (yes-or-no-p (format "Put back %d .bib file%s from %s? "
                               (length files) (if (= 1 (length files)) "" "s")
                               (file-name-nondirectory (directory-file-name dir))))
      (dolist (entry files)
        (let* ((file (car entry))
               (saved (expand-file-name (file-name-nondirectory file) dir)))
          (when (file-exists-p saved)
            (when (and (cadr entry) (file-exists-p file)
                       (not (equal (cadr entry) (sp-bibtex-biblatex--sha file))))
              (make-directory (expand-file-name "before-restore/" dir) t)
              (copy-file file (expand-file-name (file-name-nondirectory file)
                                                (expand-file-name "before-restore/" dir)) t))
            (copy-file saved file t)
            (when-let* ((b (find-buffer-visiting file)))
              (with-current-buffer b (revert-buffer t t t))))))
      (message "Put back %d file%s from %s" (length files) (if (= 1 (length files)) "" "s")
               (abbreviate-file-name dir)))))

(provide 'sp-bibtex-biblatex)
;;; sp-bibtex-biblatex.el ends here
