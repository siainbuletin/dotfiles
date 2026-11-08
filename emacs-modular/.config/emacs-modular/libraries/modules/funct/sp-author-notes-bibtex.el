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
  "The names in the BibTeX author FIELD, flipped to First Last, braces removed."
  (mapcar #'sp-author-notes--clean-name
          (split-string (replace-regexp-in-string "[ \t\n]+" " " field)
                        "[ \t]+and[ \t]+" t "[ \t]+")))

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
    (if (equal p a)
        'exact
      (let ((pw (split-string p "[ .]+" t))
            (aw (split-string a "[ .]+" t)))
        (when (and (cdr pw) (cdr aw)
                   (equal (car (last pw)) (car (last aw)))
                   (eq (aref (car pw) 0) (aref (car aw) 0)))
          'possible)))))

(defun sp-author-notes-bibtex--person-p (head)
  "Non-nil when HEAD, from `sp-author-notes--file-head', is a :person: note."
  (and (plist-get head :title) (plist-get head :id)
       (member sp-author-notes-person-tag (plist-get head :tags))))

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
        (unless (gethash word table) (puthash word file table))))))

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
    (when (cdr words)
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
  (insert "RET visit entry   o visit author note   c create litnote   C create for all exact   g refresh\n")
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
