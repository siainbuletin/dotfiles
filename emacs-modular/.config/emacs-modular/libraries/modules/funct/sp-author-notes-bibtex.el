;;; sp-author-notes-bibtex.el --- Works of an author that only exist in BibTeX -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-author-notes-bibtex' lists, for every :person: note, the entries of
;; the registered BibTeX files whose author field names that person and
;; that have no literature note yet, and offers to create the note.  See the
;; doc docs/tangles/funct/sp-org-lint.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'bibtex)
(require 'sp-async-work)
(require 'sp-author-notes)

(defvar sp-bibtex-files)
(defvar sp-bibliography-dir)

(declare-function citar-create-note "citar")

(defcustom sp-author-notes-bibtex-create-function #'citar-create-note
  "Function of one argument, the BibTeX key, that creates its literature note."
  :type 'function
  :group 'sp-author-notes)

(defcustom sp-author-notes-bibtex-link-author t
  "Non-nil to add a pub-author line to a literature note made for an author note."
  :type 'boolean
  :group 'sp-author-notes)

(defconst sp-author-notes-bibtex--buffer-name "*Author works (BibTeX)*")

(defun sp-author-notes-bibtex--files ()
  "The readable .bib files: `sp-bibtex-files', else those of `sp-bibliography-dir'.
Signal a `user-error' that says what is wrong when there is none.  A file
of the list that is missing is reported with `message' and skipped."
  (let* ((listed (cond ((and (boundp 'sp-bibtex-files) sp-bibtex-files) sp-bibtex-files)
                       ((and (boundp 'sp-bibliography-dir) sp-bibliography-dir
                             (file-directory-p sp-bibliography-dir))
                        (directory-files sp-bibliography-dir t "\\`[[:alnum:]].*\\.bib\\'"))))
         (readable (seq-filter #'file-readable-p listed))
         (missing (seq-remove #'file-readable-p listed)))
    (cond
     ((null listed)
      (user-error "No BibTeX files: `sp-bibtex-files' is empty and `sp-bibliography-dir' (%s) has no .bib file; run `sp-bibtex-register'"
                  (if (boundp 'sp-bibliography-dir) sp-bibliography-dir "unset")))
     ((null readable)
      (user-error "None of the BibTeX files can be read: %s" (string-join missing ", ")))
     (t (when missing
          (message "sp-author-notes-bibtex: skipping unreadable BibTeX file%s: %s"
                   (if (cdr missing) "s" "") (string-join missing ", ")))
        readable))))

(defun sp-author-notes-bibtex--split-authors (field)
  "The names in the BibTeX author FIELD, flipped to First Last, braces removed.
A name in double braces, `{{Endnotes}}', is an organisation: it is kept as
it is, and an `and' inside it does not split it."
  (mapcar #'sp-author-notes--clean-name
          (sp-author-notes--split-outside-braces
           (replace-regexp-in-string "[ \t\n]+" " " field) "[ \t]+and[ \t]+")))

(defun sp-author-notes-bibtex--parse-some (file limit)
  "Parse the entries of FILE from point in the current buffer, at most LIMIT of them.
LIMIT nil means all.  Return (ENTRIES . MORE); MORE is non-nil when LIMIT
was reached, so that the end of the buffer may not be."
  (let ((count 0) entries)
    (while (and (or (null limit) (< count limit))
                (re-search-forward "^[ \t]*@[[:alpha:]]+[ \t]*[{(]" nil t))
      (cl-incf count)
      (let ((beg (match-beginning 0)))
        (goto-char beg)
        (when-let* ((entry (ignore-errors (bibtex-parse-entry t)))
                    (key (cdr (assoc "=key=" entry)))
                    (_ (or (assoc "author" entry) (assoc "editor" entry))))
          (push (list :key key
                      :title (replace-regexp-in-string
                              "[{}]" "" (or (cdr (assoc "title" entry)) ""))
                      :year (or (cdr (assoc "year" entry)) "")
                      :authors (when-let* ((author (cdr (assoc "author" entry))))
                                 (sp-author-notes-bibtex--split-authors author))
                      :editors (when-let* ((editor (cdr (assoc "editor" entry))))
                                 (sp-author-notes-bibtex--split-authors editor))
                      :file file :pos beg)
                entries))
        (goto-char (min (point-max) (1+ beg)))))
    (cons (nreverse entries) (and limit (>= count limit)))))

(defun sp-author-notes-bibtex--entries (files)
  "The entries of the .bib FILES as plists (:key :title :year :authors :editors :file :pos)."
  (let (entries)
    (dolist (file files)
      (when (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (delay-mode-hooks (bibtex-mode))
          (goto-char (point-min))
          (setq entries (append entries (car (sp-author-notes-bibtex--parse-some file nil)))))))
    entries))

(defun sp-author-notes-bibtex--match (person author)
  "How the name AUTHOR matches the title PERSON: `exact', `possible' or nil."
  (let ((p (sp-author-notes--title-key (sp-author-notes--clean-name person)))
        (a (sp-author-notes--title-key author)))
    (cond
     ((equal p a) 'exact)
     ;; An organisation matches by its whole name only.
     ((or (sp-author-notes--organisation-p person)
          (sp-author-notes--organisation-p author))
      nil)
     (t
      (let ((pw (split-string p "[ .]+" t))
            (aw (split-string a "[ .]+" t)))
        (when (and (cdr pw) (cdr aw)
                   (equal (car (last pw)) (car (last aw)))
                   (eq (aref (car pw) 0) (aref (car aw) 0)))
          'possible))))))

(defun sp-author-notes-bibtex--person-p (head)
  "Non-nil when HEAD, from `sp-author-notes--file-head', is a :person: note."
  (and (plist-get head :title) (plist-get head :id)
       (sp-author-notes--person-tags-p (plist-get head :tags))))

(defun sp-author-notes-bibtex--people ()
  "The :person: notes of the vault, as plists from `sp-author-notes--file-head'."
  (seq-filter
   #'sp-author-notes-bibtex--person-p
   (mapcar #'sp-author-notes--file-head
           (sp-author-notes--org-files sp-author-notes-directory))))

(defun sp-author-notes-bibtex--cover-file (table file)
  "Add the words in the head and the file name of the litnote FILE to TABLE, as FILE."
  (with-temp-buffer
    (sp-author-notes--insert-file file 4096)
    (let ((text (concat (file-name-nondirectory file) "\n"
                        (buffer-substring (point-min) (sp-author-notes--first-heading)))))
      (dolist (word (split-string text "[^[:alnum:]_.-]+" t))
        (unless (gethash word table) (puthash word file table)))
      ;; Keys may hold a colon (marx1966cartea-i:-), which splits them above.
      ;; `cite:' and `@' in front of a key are not part of it.
      (dolist (word (split-string text "[^[:alnum:]_.:-]+" t))
        (let ((key (replace-regexp-in-string "\\`\\(?:cite:\\)?@?" "" word)))
          (when (and (string-match-p "[[:alnum:]_.-]:[[:alnum:]_.-]" key) (not (gethash key table)))
            (puthash key file table)))))))

(defun sp-author-notes-bibtex--covered ()
  "A hash table: every word in the head or the file name of a litnote to its file.
A BibTeX key is covered when it is such a word, which holds for
REFERENCES, ROAM_REFS, #+reference: and @key alike."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file (sp-author-notes--org-files sp-author-notes-litnotes-directory))
      (sp-author-notes-bibtex--cover-file table file))
    table))

(defun sp-author-notes-bibtex--possible-key (name)
  "The key under which the author NAME can be a possible match, or nil.
It is the last word and the first letter of the first word, as
`sp-author-notes-bibtex--match' compares them."
  (let ((words (split-string (sp-author-notes--title-key
                              (sp-author-notes--clean-name name))
                             "[ .]+" t)))
    (when (and (cdr words) (not (sp-author-notes--organisation-p name)))
      (cons (car (last words)) (aref (car words) 0)))))

(defun sp-author-notes-bibtex--index-entry (index entry covered)
  "Add ENTRY to INDEX unless its key is in COVERED.
INDEX is (EXACT POSSIBLE . ORDER): two hash tables from the name key and
from the possible key of an author to the entries, and a hash table from an
entry to its number.  Looking a person up in them replaces comparing the
person with every author of every entry, which took hours with thousands of
people and tens of thousands of entries."
  (let ((exact (car index)) (possible (cadr index)) (order (cddr index)))
    (puthash entry (hash-table-count order) order)
    (unless (gethash (plist-get entry :key) covered)
      (dolist (author (append (plist-get entry :authors) (plist-get entry :editors)))
        (push entry (gethash (sp-author-notes--title-key author) exact))
        (when-let* ((key (sp-author-notes-bibtex--possible-key author)))
          (push entry (gethash key possible)))))))

(defun sp-author-notes-bibtex--make-index ()
  "An empty index for `sp-author-notes-bibtex--index-entry'."
  (cl-list* (make-hash-table :test #'equal :size 4096)
         (make-hash-table :test #'equal :size 4096)
         (make-hash-table :test #'eq :size 4096)))

(defun sp-author-notes-bibtex--matches (person index)
  "The matches of PERSON in INDEX: a list of (ENTRY . CONFIDENCE).
INDEX is the one `sp-author-notes-bibtex--index-entry' fills with the entries
that have no litnote.  Only the entries that share the name or the last name
and initial with PERSON are compared."
  (let ((title (plist-get person :title))
        (candidates (make-hash-table :test #'eq))
        (order (cddr index))
        matches)
    (dolist (entry (gethash (sp-author-notes--title-key
                             (sp-author-notes--clean-name title))
                            (car index)))
      (puthash entry t candidates))
    (when-let* ((key (sp-author-notes-bibtex--possible-key title)))
      (dolist (entry (gethash key (cadr index)))
        (puthash entry t candidates)))
    (maphash
     (lambda (entry _)
       (when-let* ((conf (cl-loop for a in (append (plist-get entry :authors) (plist-get entry :editors))
                                  for m = (sp-author-notes-bibtex--match title a)
                                  when (eq m 'exact) return 'exact
                                  when m collect m into found
                                  finally return (car found))))
         (push (cons entry conf) matches)))
     candidates)
    (when matches
      ;; In the order of the files, then by year (`sort' is stable).
      (setq matches (sort matches (lambda (a b) (< (gethash (car a) order)
                                                   (gethash (car b) order)))))
      (sort matches
            (lambda (a b)
              (string< (or (plist-get (car a) :year) "")
                       (or (plist-get (car b) :year) "")))))))

(defun sp-author-notes-bibtex--bib-step (item job add)
  "Read some entries of the .bib file ITEM, and call ADD with them.
ITEM is a file name, or (FILE . BUFFER) for one that is half read; the rest
of a big file is pushed to JOB, so that no slice parses it all."
  (let* ((file (if (consp item) (car item) item))
         (buffer (if (consp item)
                     (cdr item)
                   (when (file-readable-p file)
                     (let ((b (generate-new-buffer " *sp-author-works bib*")))
                       (sp-async-work-on-cleanup job (lambda () (kill-buffer b)))
                       (with-current-buffer b
                         (insert-file-contents file)
                         (delay-mode-hooks (bibtex-mode))
                         (goto-char (point-min)))
                       b)))))
    (when buffer
      (let ((result (with-current-buffer buffer
                      (sp-author-notes-bibtex--parse-some file 200))))
        (funcall add (car result))
        (if (cdr result)
            (sp-async-work-push job (cons file buffer))
          (kill-buffer buffer))))))

(defun sp-author-notes-bibtex--compute-job (callback)
  "Find the additional works in slices and call CALLBACK with the list.
The list is the one `sp-author-notes-bibtex--compute' returns.  Return the job."
  (let ((files (sp-author-notes-bibtex--files)) ; a user-error here reaches the command
        (index (sp-author-notes-bibtex--make-index))
        entries people result
        (covered (make-hash-table :test #'equal)))
    (sp-async-work-run
     "Author works"
     (list (list "reading BibTeX" (lambda () files)
                 (lambda (item job)
                   (sp-author-notes-bibtex--bib-step
                    item job (lambda (found) (dolist (e found) (push e entries))))))
           (list "reading litnotes"
                 (lambda () (sp-author-notes--org-files sp-author-notes-litnotes-directory))
                 (lambda (file _job) (sp-author-notes-bibtex--cover-file covered file)))
           (list "reading authors"
                 (lambda () (sp-author-notes--org-files sp-author-notes-directory))
                 (lambda (file _job)
                   (let ((head (sp-author-notes--file-head file)))
                     (when (sp-author-notes-bibtex--person-p head) (push head people)))))
           (list "indexing"
                 (lambda () (nreverse entries))
                 (lambda (entry _job)
                   (sp-author-notes-bibtex--index-entry index entry covered)))
           (list "matching"
                 (lambda () (nreverse people))
                 (lambda (person _job)
                   (when-let* ((matches (sp-author-notes-bibtex--matches person index)))
                     (push (cons person matches) result)))))
     :done (lambda (_job) (funcall callback (nreverse result))))))

(defun sp-author-notes-bibtex--compute ()
  "The additional works: a list of (PERSON . MATCHES), found all at once.
MATCHES is a list of (ENTRY . CONFIDENCE).  Only people with at least one entry that has no literature note are listed.  `sp-author-notes-bibtex' finds them in slices instead."
  (let ((sp-async-work-synchronous t) groups)
    (sp-author-notes-bibtex--compute-job (lambda (found) (setq groups found)))
    groups))

(defun sp-author-notes-bibtex--role-key (person entry)
  "The meta key for PERSON in ENTRY: `pub-editor' if PERSON only edited it, else `pub-author'."
  (let ((title (plist-get person :title)))
    (if (and (null (cl-some (lambda (a) (sp-author-notes-bibtex--match title a))
                            (plist-get entry :authors)))
             (cl-some (lambda (a) (sp-author-notes-bibtex--match title a))
                      (plist-get entry :editors)))
        "pub-editor"
      sp-author-notes-key)))

(defun sp-author-notes-bibtex--add-author (file person &optional meta-key)
  "Add a META-KEY line (default pub-author) for the PERSON plist to the litnote FILE.
Nothing is added if the file has such a line.  Return non-nil when it was added."
  (let ((buf (find-buffer-visiting file)))
    (unless (and buf (buffer-modified-p buf))
      (with-current-buffer (or buf (find-file-noselect file))
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (let ((limit (sp-author-notes--first-heading))
                  (case-fold-search t))
              (unless (re-search-forward
                       (format "^-[ \t]+%s[ \t]+::" (regexp-quote (or meta-key sp-author-notes-key))) limit t)
                (goto-char (point-min))
                (if (re-search-forward "^-[ \t]+[^ \t\n:]+[ \t]+::.*$" limit t)
                    (progn (while (re-search-forward "^-[ \t]+[^ \t\n:]+[ \t]+::.*$" limit t))
                           (end-of-line)
                           (insert "\n"))
                  (goto-char limit)
                  (unless (bolp) (insert "\n"))
                  (insert "\n"))
                (insert (format "- %s :: [[id:%s][%s]]"
                                (or meta-key sp-author-notes-key) (plist-get person :id)
                                (plist-get person :title)))
                (unless (eq (char-after) ?\n) (insert "\n"))
                (save-buffer)
                (unless buf (kill-buffer))
                t))))))))

(defun sp-author-notes-bibtex--create (person entry)
  "Create the litnote for ENTRY under the PERSON plist; return its file or nil."
  (let ((key (plist-get entry :key)))
    (funcall sp-author-notes-bibtex-create-function key)
    (let ((file (gethash key (sp-author-notes-bibtex--covered))))
      (cond
       ((null file)
        (message "Created no note for %s that I can find; add pub-author by hand" key)
        nil)
       (t
        (when sp-author-notes-bibtex-link-author
          (unless (sp-author-notes-bibtex--add-author
                 file person (sp-author-notes-bibtex--role-key person entry))
            (message "%s: unsaved changes or a pub-author/pub-editor line already, left alone"
                     (file-name-nondirectory file))))
        file)))))

(defcustom sp-author-notes-bibtex-apply-possible nil
  "Non-nil to let `A' in the one-author report add the possible matches too.
Possible matches only agree on the surname and the initials, so by default
only the exact ones are added."
  :type 'boolean
  :group 'sp-author-notes)

(defconst sp-author-notes-bibtex--author-buffer-name "*Author works (this note)*")

(declare-function sp-bibtex--initials-compatible-p "sp-bibprocess")
(declare-function sp-bibtex--surname-key "sp-bibprocess")
(declare-function sp-bibtex--name-parts "sp-bibprocess")
(declare-function sp-batch-report-open "sp-batch-report")
(declare-function sp-batch-report-text "sp-batch-report")
(declare-function sp-batch-report-item "sp-batch-report")
(declare-function sp-batch-report-section "sp-batch-report")
(declare-function sp-batch-report-file-link "sp-batch-report")

(defun sp-author-notes-bibtex--note-aliases (file)
  "The aliases in the head of the note FILE (its ROAM_ALIASES), as a list of strings."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (sp-author-notes--insert-file file 4096)
      (let ((case-fold-search t) aliases)
        (goto-char (point-min))
        (while (re-search-forward "^\\(?:#\\+\\|[ \t]*:\\)ROAM_ALIASES:?[ \t]*\\(.*\\)$" nil t)
          (setq aliases (append aliases (ignore-errors
                                          (split-string-and-unquote (match-string-no-properties 1))))))
        aliases))))

(defun sp-author-notes-bibtex--current-person ()
  "The author note in the current buffer, as a plist.
It has :file :id :title :buffer and :forms, the title and the aliases
cleaned like BibTeX names.  Signal a `user-error' when the buffer is not an
author note, or the note has no ID."
  (let* ((file (sp-author-notes--works-target))
         (head (sp-author-notes--file-head file)))
    (unless (plist-get head :id)
      (user-error "This author note has no :ID:"))
    (unless (plist-get head :title)
      (user-error "This author note has no #+title:"))
    (append head
            (list :buffer (current-buffer)
                  :forms (delete-dups
                          (mapcar #'sp-author-notes--clean-name
                                  (cons (plist-get head :title)
                                        (sp-author-notes-bibtex--note-aliases file))))))))

(defun sp-author-notes-bibtex--last-first (name)
  "The name NAME (First Last) as \"Last, First\", or nil when it has one word."
  (let ((words (split-string name "[ \t]+" t)))
    (when (cdr words)
      (format "%s, %s" (car (last words)) (string-join (butlast words) " ")))))

(defun sp-author-notes-bibtex--given-compatible-p (form author)
  "Non-nil when AUTHOR has the surname of FORM and compatible given names.
That needs `sp-bibprocess'; without it the answer is always nil."
  (when (and (fboundp 'sp-bibtex--initials-compatible-p)
             (fboundp 'sp-bibtex--surname-key)
             (fboundp 'sp-bibtex--name-parts))
    (let ((f (sp-author-notes-bibtex--last-first form))
          (a (sp-author-notes-bibtex--last-first author)))
      (and f a
           (equal (sp-bibtex--surname-key f) (sp-bibtex--surname-key a))
           (sp-bibtex--initials-compatible-p (cdr (sp-bibtex--name-parts a))
                                             (cdr (sp-bibtex--name-parts f)))))))

(defun sp-author-notes-bibtex--match-forms (forms author)
  "How the name AUTHOR matches the name FORMS: `exact', `possible' or nil."
  (let (best)
    (dolist (form forms best)
      (let ((m (or (sp-author-notes-bibtex--match form author)
                   (and (not (sp-author-notes--organisation-p form))
                        (sp-author-notes-bibtex--given-compatible-p form author)
                        'possible))))
        (cond ((eq m 'exact) (setq best 'exact))
              ((and m (not best)) (setq best m)))))))

(defun sp-author-notes-bibtex--best-match (forms names)
  "The best way a name of NAMES matches the name FORMS: `exact', `possible' or nil."
  (let (best)
    (dolist (name names best)
      (let ((m (sp-author-notes-bibtex--match-forms forms name)))
        (cond ((eq m 'exact) (setq best 'exact))
              ((and m (not best)) (setq best m)))))))

(defun sp-author-notes-bibtex--entry-match (person entry)
  "How the PERSON plist is named in ENTRY: (CONFIDENCE . META-KEY), or nil.
META-KEY is `pub-editor' when the person is only an editor of the entry."
  (let ((as-author (sp-author-notes-bibtex--best-match
                    (plist-get person :forms) (plist-get entry :authors)))
        (as-editor (sp-author-notes-bibtex--best-match
                    (plist-get person :forms) (plist-get entry :editors))))
    (when (or as-author as-editor)
      (cons (if (or (eq as-author 'exact) (eq as-editor 'exact)) 'exact 'possible)
            (if as-author sp-author-notes-key "pub-editor")))))

(defun sp-author-notes-bibtex--links-p (file id)
  "Non-nil when a person meta line in the head of the litnote FILE links to the note ID."
  (with-temp-buffer
    (sp-author-notes--insert-file file 4096)
    (let ((case-fold-search t))
      (goto-char (point-min))
      (re-search-forward
       (format "^-[ \t]+%s[ \t]+::.*id:%s"
               (regexp-opt sp-author-notes-person-keys) (regexp-quote id))
       (sp-author-notes--first-heading) t))))

(defun sp-author-notes-bibtex--author-result (person entry covered)
  "The result for ENTRY of the PERSON plist, or nil when it does not name the person.
It is a plist with :entry :conf :role :status and :file, the litnote of the
key.  COVERED is the table of `sp-author-notes-bibtex--covered'."
  (when-let* ((match (sp-author-notes-bibtex--entry-match person entry)))
    (let* ((file (gethash (plist-get entry :key) covered))
           (status (cond ((null file) 'new)
                         ((sp-author-notes-bibtex--links-p file (plist-get person :id)) 'linked)
                         (t 'unlinked))))
      (list :entry entry :conf (car match) :role (cdr match) :status status :file file))))

(defun sp-author-notes-bibtex--author-job (person callback)
  "Find the entries that name the PERSON plist in slices, and call CALLBACK with them.
The list is of the plists of `sp-author-notes-bibtex--author-result', in the
order of the files.  Return the job."
  (let ((files (sp-author-notes-bibtex--files)) ; a user-error here reaches the command
        (covered (make-hash-table :test #'equal))
        entries result)
    (sp-async-work-run
     "Author works (one)"
     (list (list "reading BibTeX" (lambda () files)
                 (lambda (item job)
                   (sp-author-notes-bibtex--bib-step
                    item job (lambda (found) (dolist (e found) (push e entries))))))
           (list "reading litnotes"
                 (lambda () (sp-author-notes--org-files sp-author-notes-litnotes-directory))
                 (lambda (file _job) (sp-author-notes-bibtex--cover-file covered file)))
           (list "matching"
                 (lambda () (nreverse entries))
                 (lambda (entry _job)
                   (when-let* ((found (sp-author-notes-bibtex--author-result person entry covered)))
                     (push found result)))))
     :done (lambda (_job) (funcall callback (nreverse result))))))

(defun sp-author-notes-bibtex--author-compute (person)
  "The entries that name the PERSON plist, found all at once."
  (let ((sp-async-work-synchronous t) results)
    (sp-author-notes-bibtex--author-job person (lambda (found) (setq results found)))
    results))

(defun sp-author-notes-bibtex--author-item (result)
  "The report item of RESULT, a plist of `sp-author-notes-bibtex--author-result'."
  (let* ((entry (plist-get result :entry))
         (key (plist-get entry :key)))
    (sp-batch-report-item
     (format "(%s) %s%s%s"
             (if (string-empty-p (plist-get entry :year)) "n.d." (plist-get entry :year))
             (truncate-string-to-width (plist-get entry :title) 80 nil nil "…")
             (if (equal (plist-get result :role) "pub-editor") "  [edited]" "")
             (if (eq (plist-get result :status) 'unlinked)
                 (format "  [litnote: %s]"
                         (sp-batch-report-file-link (plist-get result :file)))
               ""))
     :file (plist-get entry :file) :line (format "/{%s,/" (regexp-quote key))
     :label key :key key)))

(defun sp-author-notes-bibtex--author-sections (results)
  "The report sections for RESULTS: what is not in the Works tables comes first."
  (cl-flet ((pick (status conf)
              (mapcar #'sp-author-notes-bibtex--author-item
                      (sort (seq-filter (lambda (r) (and (eq (plist-get r :status) status)
                                                         (or (null conf) (eq (plist-get r :conf) conf))))
                                        results)
                            (lambda (a b) (string< (plist-get (plist-get a :entry) :year)
                                                   (plist-get (plist-get b :entry) :year)))))))
    (list (sp-batch-report-section "No litnote yet (exact name)" (pick 'new 'exact)
                                   "every work found has a litnote")
          (sp-batch-report-section "No litnote yet (possible: surname and initials)" (pick 'new 'possible))
          (sp-batch-report-section "Litnote exists, not linked to this note" (pick 'unlinked nil))
          (sp-batch-report-section "Already in this note" (pick 'linked nil)))))

(defun sp-author-notes-bibtex--author-text (person results excluded)
  "The Org text of the report of RESULTS for the PERSON plist, without the keys EXCLUDED."
  (sp-batch-report-text
   (format "Works of %s in BibTeX" (plist-get person :title))
   (sp-author-notes-bibtex--author-sections results)
   :intro (format "Names compared: %s.  A adds the works above \"Already in this note\" (possible matches only when `sp-author-notes-bibtex-apply-possible'); d drops one, u brings it back, g reads again."
                  (string-join (plist-get person :forms) ", "))
   :excluded excluded))

(defun sp-author-notes-bibtex--author-apply (person results excluded)
  "Add the RESULTS for the PERSON plist that are not EXCLUDED; return how many.
New entries get a litnote, entries whose litnote is not linked get the line,
and the author note gets its Works tables.  Ask once first."
  (let ((todo (seq-filter
               (lambda (r)
                 (and (memq (plist-get r :status) '(new unlinked))
                      (not (member (plist-get (plist-get r :entry) :key) excluded))
                      (or (eq (plist-get r :conf) 'exact) sp-author-notes-bibtex-apply-possible)))
               results))
        (done 0))
    (cond
     ((null todo) (message "Nothing to add: no exact work is left outside the note") 0)
     ((y-or-n-p (format "Add %d work%s to %s? " (length todo) (if (cdr todo) "s" "")
                        (plist-get person :title)))
      (dolist (r todo)
        (let ((entry (plist-get r :entry)))
          (if (eq (plist-get r :status) 'new)
              (when (sp-author-notes-bibtex--create person entry) (cl-incf done))
            (when (sp-author-notes-bibtex--add-author (plist-get r :file) person (plist-get r :role))
              (cl-incf done)))))
      (when-let* ((buffer (plist-get person :buffer))
                  (_ (buffer-live-p buffer)))
        (with-current-buffer buffer
          (condition-case err
              (message "%d added.  %s" done (sp-author-notes--works-run t))
            (error (message "%d added; the Works tables were not updated: %s"
                            done (error-message-string err))))))
      done)
     (t 0))))

(defun sp-author-notes-bibtex--author-show (person results excluded)
  "Show the report of RESULTS for the PERSON plist, without the keys EXCLUDED."
  (sp-batch-report-open
   sp-author-notes-bibtex--author-buffer-name
   (sp-author-notes-bibtex--author-text person results excluded)
   :excluded excluded
   :redraw (lambda (excl) (sp-author-notes-bibtex--author-show person results excl))
   :refresh (lambda (excl) (sp-author-notes-bibtex--author-run person excl))
   :apply (lambda (excl)
            (when (> (sp-author-notes-bibtex--author-apply person results excl) 0)
              (sp-author-notes-bibtex--author-run person excl)))))

(defun sp-author-notes-bibtex--author-run (person &optional excluded)
  "Read the BibTeX files in slices and show the report for the PERSON plist."
  (message "Reading BibTeX files for %s in the background..." (plist-get person :title))
  (sp-author-notes-bibtex--author-job
   person
   (lambda (results) (sp-author-notes-bibtex--author-show person results excluded))))

;;;###autoload
(defun sp-author-notes-bibtex-author ()
  "Show what the BibTeX files hold of the author of the note in this buffer.
Works that no litnote links to this note come first, then the ones already
in it.  In the report, `A' adds the works (a litnote for each, or the
author line in the one that exists) and updates the Works tables of the
note.  The all-authors report is `sp-author-notes-bibtex'."
  (interactive)
  (sp-author-notes-bibtex--author-run (sp-author-notes-bibtex--current-person)))

(defvar sp-author-notes-bibtex-report-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'sp-author-notes-bibtex-visit-entry)
    (define-key map (kbd "o") #'sp-author-notes-bibtex-visit-person)
    (define-key map (kbd "c") #'sp-author-notes-bibtex-create-at-point)
    (define-key map (kbd "C") #'sp-author-notes-bibtex-create-section)
    (define-key map (kbd "g") #'sp-author-notes-bibtex)
    map)
  "Keymap of `sp-author-notes-bibtex-report-mode'.")

(define-derived-mode sp-author-notes-bibtex-report-mode special-mode "Author works"
  "Report of `sp-author-notes-bibtex'.
\\{sp-author-notes-bibtex-report-mode-map}")

(defun sp-author-notes-bibtex--render (groups)
  "Insert the report of GROUPS, as `sp-author-notes-bibtex--compute' returns them."
  (insert (format "Works in BibTeX files without a literature note: %d author note%s\n"
                  (length groups) (if (= 1 (length groups)) "" "s")))
  (sp-echo-help-set '(("RET" "Visit entry") ("o" "Visit author note") ("c" "Create litnote" t)
                      ("C" "Create for all exact") ("g" "Refresh")))
  (if (null groups)
      (insert "\n  none\n")
    (dolist (group groups)
      (let ((person (car group)) (start (point)))
        (insert (format "\n* %s  (%d)\n" (plist-get person :title) (length (cdr group))))
        (put-text-property start (point) 'sp-person person)
        (dolist (m (cdr group))
          (let ((entry (car m)) (line-start (point)))
            (insert (format "  %-9s %-28s %-4s %s  [%s]\n"
                            (if (eq (cdr m) 'exact) "exact" "possible")
                            (plist-get entry :key) (plist-get entry :year)
                            (truncate-string-to-width (plist-get entry :title) 60 nil nil "…")
                            (file-name-nondirectory (plist-get entry :file))))
            (add-text-properties line-start (point)
                                 (list 'sp-person person 'sp-entry entry 'sp-conf (cdr m)))))))))

;;;###autoload
(defun sp-author-notes-bibtex ()
  "Show the BibTeX works of the author notes that have no literature note yet.
The BibTeX files and the notes are read in slices, so Emacs stays usable;
the report opens, or is refreshed, when they are read."
  (interactive)
  (let (found)
    (message "Reading BibTeX files and notes in the background...")
    (sp-author-notes-bibtex--compute-job
     (lambda (groups)
       (setq found groups)
       (with-current-buffer (get-buffer-create sp-author-notes-bibtex--buffer-name)
         (let ((line (line-number-at-pos)))
           (sp-author-notes-bibtex-report-mode)
           (let ((inhibit-read-only t))
             (erase-buffer)
             (sp-author-notes-bibtex--render groups)
             (goto-char (point-min))
             (forward-line (1- line))))
         (pop-to-buffer (current-buffer)))))
    found))

(defun sp-author-notes-bibtex--at-point ()
  (or (get-text-property (line-beginning-position) 'sp-entry)
      (user-error "No entry on this line")))

(defun sp-author-notes-bibtex-visit-entry ()
  "Visit the BibTeX entry on this line."
  (interactive)
  (let ((entry (sp-author-notes-bibtex--at-point)))
    (find-file-other-window (plist-get entry :file))
    (goto-char (plist-get entry :pos))))

(defun sp-author-notes-bibtex-visit-person ()
  "Visit the author note of this line or section."
  (interactive)
  (let ((person (or (get-text-property (line-beginning-position) 'sp-person)
                    (user-error "No author note on this line"))))
    (find-file-other-window (plist-get person :file))))

(defun sp-author-notes-bibtex-create-at-point ()
  "Offer to create the litnote for the entry on this line."
  (interactive)
  (let ((entry (sp-author-notes-bibtex--at-point))
        (person (get-text-property (line-beginning-position) 'sp-person)))
    (when (y-or-n-p (format "Create a litnote for %s under %s? "
                            (plist-get entry :key) (plist-get person :title)))
      (sp-author-notes-bibtex--create person entry)
      (sp-author-notes-bibtex))))

(defun sp-author-notes-bibtex-create-section ()
  "Offer to create litnotes for all exact entries of the section at point."
  (interactive)
  (let* ((person (or (get-text-property (line-beginning-position) 'sp-person)
                     (user-error "No author note on this line")))
         (entries nil))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let ((e (get-text-property (point) 'sp-entry)))
          (when (and e (eq (get-text-property (point) 'sp-conf) 'exact)
                     (eq (get-text-property (point) 'sp-person) person))
            (push e entries)))
        (forward-line 1)))
    (setq entries (nreverse entries))
    (cond
     ((null entries) (user-error "No exact entries in this section"))
     ((y-or-n-p (format "Create %d litnote%s under %s? "
                        (length entries) (if (cdr entries) "s" "") (plist-get person :title)))
      (dolist (e entries) (sp-author-notes-bibtex--create person e))
      (sp-author-notes-bibtex)))))

(provide 'sp-author-notes-bibtex)
;;; sp-author-notes-bibtex.el ends here
