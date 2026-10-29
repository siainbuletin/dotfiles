;;; sp-author-notes-bibtex.el --- Works of an author that only exist in BibTeX -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-author-notes-bibtex' lists, for every :person: note, the entries of
;; the registered BibTeX files whose author field names that person and
;; that have no literature note yet, and offers to create the note.  See the
;; doc docs/tangles/funct/sp-author-notes-bibtex.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'bibtex)
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
  "The .bib files to read: `sp-bibtex-files', else those of `sp-bibliography-dir'."
  (cond ((and (boundp 'sp-bibtex-files) sp-bibtex-files) sp-bibtex-files)
        ((and (boundp 'sp-bibliography-dir) (file-directory-p sp-bibliography-dir))
         (directory-files sp-bibliography-dir t "\\`[[:alnum:]].*\\.bib\\'"))))

(defun sp-author-notes-bibtex--split-authors (field)
  "The names in the BibTeX author FIELD, flipped to First Last, braces removed."
  (mapcar #'sp-author-notes--clean-name
          (split-string (replace-regexp-in-string "[ \t\n]+" " " field)
                        "[ \t]+and[ \t]+" t "[ \t]+")))

(defun sp-author-notes-bibtex--entries (files)
  "The entries of the .bib FILES as plists (:key :title :year :authors :file :pos)."
  (let (entries)
    (dolist (file files)
      (when (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (delay-mode-hooks (bibtex-mode))
          (goto-char (point-min))
          (while (re-search-forward "^[ \t]*@[[:alpha:]]+[ \t]*[{(]" nil t)
            (let ((beg (match-beginning 0)))
              (goto-char beg)
              (when-let* ((entry (ignore-errors (bibtex-parse-entry t)))
                          (key (cdr (assoc "=key=" entry)))
                          (author (cdr (assoc "author" entry))))
                (push (list :key key
                            :title (replace-regexp-in-string
                                    "[{}]" "" (or (cdr (assoc "title" entry)) ""))
                            :year (or (cdr (assoc "year" entry)) "")
                            :authors (sp-author-notes-bibtex--split-authors author)
                            :file file :pos beg)
                      entries))
              (goto-char (min (point-max) (1+ beg))))))))
    (nreverse entries)))

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

(defun sp-author-notes-bibtex--people ()
  "The :person: notes of the vault, as plists from `sp-author-notes--file-head'."
  (seq-filter
   (lambda (head)
     (and (plist-get head :title) (plist-get head :id)
          (member sp-author-notes-person-tag (plist-get head :tags))))
   (mapcar #'sp-author-notes--file-head
           (sp-author-notes--org-files sp-author-notes-directory))))

(defun sp-author-notes-bibtex--covered ()
  "A hash table: every word in the head or the file name of a litnote to its file.
A BibTeX key is covered when it is such a word, which holds for
REFERENCES, ROAM_REFS, #+reference: and @key alike."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (file (sp-author-notes--org-files sp-author-notes-litnotes-directory))
      (with-temp-buffer
        (sp-author-notes--insert-file file 4096)
        (let ((text (concat (file-name-nondirectory file) "\n"
                            (buffer-substring (point-min) (sp-author-notes--first-heading)))))
          (dolist (word (split-string text "[^[:alnum:]_.-]+" t))
            (unless (gethash word table) (puthash word file table))))))
    table))

(defun sp-author-notes-bibtex--compute ()
  "The additional works: a list of (PERSON . MATCHES).
MATCHES is a list of (ENTRY . CONFIDENCE).  Only people with at least one entry that has no literature note are listed."
  (let ((entries (sp-author-notes-bibtex--entries (sp-author-notes-bibtex--files)))
        (covered (sp-author-notes-bibtex--covered))
        result)
    (dolist (person (sp-author-notes-bibtex--people))
      (let (matches)
        (dolist (entry entries)
          (unless (gethash (plist-get entry :key) covered)
            (when-let* ((conf (cl-loop for a in (plist-get entry :authors)
                                       for m = (sp-author-notes-bibtex--match
                                                (plist-get person :title) a)
                                       when (eq m 'exact) return 'exact
                                       when m collect m into found
                                       finally return (car found))))
              (push (cons entry conf) matches))))
        (when matches
          (push (cons person (sort (nreverse matches)
                                   (lambda (a b)
                                     (string< (or (plist-get (car a) :year) "")
                                              (or (plist-get (car b) :year) "")))))
                result))))
    (nreverse result)))

(defun sp-author-notes-bibtex--add-author (file person)
  "Add a pub-author line for the PERSON plist to the litnote FILE, if it has none.
Return non-nil when the line was added."
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
                       (format "^-[ \t]+%s[ \t]+::" (regexp-quote sp-author-notes-key)) limit t)
                (goto-char (point-min))
                (if (re-search-forward "^-[ \t]+[^ \t\n:]+[ \t]+::.*$" limit t)
                    (progn (while (re-search-forward "^-[ \t]+[^ \t\n:]+[ \t]+::.*$" limit t))
                           (end-of-line)
                           (insert "\n"))
                  (goto-char limit)
                  (unless (bolp) (insert "\n"))
                  (insert "\n"))
                (insert (format "- %s :: [[id:%s][%s]]"
                                sp-author-notes-key (plist-get person :id)
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
          (unless (sp-author-notes-bibtex--add-author file person)
            (message "%s: unsaved changes or a pub-author line already, left alone"
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
  "Show the BibTeX works of the author notes that have no literature note yet."
  (interactive)
  (let ((groups (sp-author-notes-bibtex--compute)))
    (with-current-buffer (get-buffer-create sp-author-notes-bibtex--buffer-name)
      (let ((line (line-number-at-pos)))
        (sp-author-notes-bibtex-report-mode)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (sp-author-notes-bibtex--render groups)
          (goto-char (point-min))
          (forward-line (1- line))))
      (pop-to-buffer (current-buffer)))
    groups))

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
