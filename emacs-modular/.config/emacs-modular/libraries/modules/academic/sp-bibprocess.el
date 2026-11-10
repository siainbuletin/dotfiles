;;; sp-bibprocess.el --- BibTeX files, citation keys and attachment checks -*- lexical-binding: t; -*-

;;; Commentary:

;; This module manages the BibTeX bibliography that the academic modules build
;; on: where the .bib files are, how citation keys are generated, and the
;; commands that audit attachments.

;;; Code:

;;;; Defining variables

(defconst sp-bibtex-file-regexp "\\`[[:alnum:]].*\\.bib\\'"
  "Regexp for the names of the BibTeX files in `sp-bibliography-dir'.")

(defvar sp-bibtex-files
  (when (file-exists-p sp-bibliography-dir)
    (directory-files sp-bibliography-dir t sp-bibtex-file-regexp))
  "List of BibTeX files. Use `sp-bibtex-register' to configure.")

;;;###autoload
(defun sp-bibtex-register ()
  "Register the contents of the `sp-bibliography-dir' with `sp-bibtex-files`.
Use when adding or removing a BibTeX file from or to `sp-bibliography-dir'."
  (interactive)
  (when (file-exists-p sp-bibliography-dir)
    (let ((bib-files (directory-files sp-bibliography-dir t sp-bibtex-file-regexp)))
      (setq sp-bibtex-files bib-files
            org-cite-global-bibliography bib-files
            citar-bibliography bib-files
            org-ref-default-bibliography bib-files
            bibtex-completion-bibliography bib-files
            bibtex-files bib-files)))
  (message "Registered:\n%s" (mapconcat #'identity sp-bibtex-files "\n")))

;;;; Citation keys

(require 'ucs-normalize)

(defun sp-bibtex-ascii-key (key)
  "Return KEY as plain ASCII, or KEY itself when nothing is left."
  (let ((ascii (replace-regexp-in-string
                "[^[:ascii:]]" "" (ucs-normalize-NFKD-string key))))
    (if (string-empty-p ascii) key ascii)))

(use-package bibtex
  :ensure nil
  :demand t
  :custom
  (bibtex-dialect 'biblatex)

  ;; Keys: smith-2017-atten-all
  (bibtex-autokey-names 2)
  (bibtex-autokey-names-stretch 0)
  (bibtex-autokey-name-separator "")
  (bibtex-autokey-name-year-separator "-")
  (bibtex-autokey-year-length 4)
  (bibtex-autokey-year-title-separator "-")
  (bibtex-autokey-titlewords 2)
  (bibtex-autokey-titlewords-stretch 1)
  (bibtex-autokey-titleword-length 5)
  (bibtex-autokey-titleword-separator "-")
  (bibtex-autokey-name-case-convert-function #'downcase)
  (bibtex-autokey-titleword-case-convert-function #'downcase)
  (bibtex-autokey-before-presentation-function #'sp-bibtex-ascii-key)
  (bibtex-autokey-edit-before-use t)
  (bibtex-autokey-titleword-ignore
   '("A" "An" "The" "Is" "the" "a" "On" "on" "Eine?" "Der" "Die" "Das"
     "[^[:upper:]].*" ".*[^[:upper:][:lower:]0-9].*"))

  ;; Cleaning and duplicates
  (bibtex-entry-format
   '(opts-or-alts page-dashes whitespace realign last-comma
                  delimiters unify-case braces))
  (bibtex-search-entry-globally t)

  (bibtex-user-optional-fields
   '(("keywords" "Keywords to describe the entry" "")
     ("file"     "Relative or absolute path to attachments" "" )))
  (bibtex-align-at-equal-sign t)
  (bibtex-aux-opt-alist
   '(("keywords" "Keywords to describe the entry" "")
     ("file" "Relative or absolute path to attachments" "")))
  :config
  (sp-bibtex-register)
  :hook (bibtex-mode . sp-bibtex-setup-completion)
  :bind
  (("C-c w b r" . sp-bibtex-register)
   ("C-c w b l" . sp-bibtex-lint-dryrun)
   ("C-c w b L" . sp-bibtex-lint-convert)
   :map bibtex-mode-map
   ("H-b" . org-ref-bibtex-hydra/body))
)

;; Search for missing BibTeX attachments and filenames
(defun sp--bibtex-extract-attachments ()
  "Extract attachment file names from BibTeX files in `sp-bibliography-dir'."
  (sp-bibtex-register)
  (let ((attachments '()))
    (dolist (bibtex-file sp-bibtex-files)
      (with-temp-buffer
        (insert-file-contents bibtex-file)
        (goto-char (point-min))
        (while (re-search-forward "file.*=.*{\\([^}]+\\)}" nil t)
          (let ((file-paths (split-string (match-string 1)
                                          "[[:space:]]*;[[:space:]]*")))
            (dolist (file-path file-paths)
              (push (expand-file-name (string-trim file-path)
                                      sp-bibliography-dir)
                    attachments))))))
    attachments))

(defun sp--bibtex-extract-files ()
  "List files recursively in `sp-bibliography-dir', excluding `.bib' and `.csl'."
  (seq-remove (lambda (file)
                (or (string-suffix-p ".bib" file)
                    (string-suffix-p ".csl" file)))
              (mapcar 'expand-file-name
                      (directory-files-recursively sp-bibliography-dir ""))))

;;;###autoload
(defun sp-bibtex-missing-files ()
  "List BibTeX attachments not listed in a BibTeX file entry."
  (interactive)
  (let* ((files (sp--bibtex-extract-files))
         (attachments (sp--bibtex-extract-attachments))
         (missing (cl-remove-if
                   (lambda (f) (member f attachments)) files)))
    (message "%s files not registered in bibliography" (length missing))
    (dolist (file missing)
      (message file))))

;;;###autoload
(defun sp-bibtex-missing-attachments ()
  "List BibTeX file entries with missing attachment(s)."
  (interactive)
  (let* ((files (sp--bibtex-extract-files))
         (attachments (sp--bibtex-extract-attachments))
         (missing (cl-remove-if
                   (lambda (f) (member f files)) attachments)))
    (message "%s BibTeX files without matching attachment." (length missing))
    (dolist (file missing)
      (message file))))

;;;; Linting the .bib files

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'bibtex)
(require 'sp-async-work)
(require 'sp-batch-report)

(defvar sp-var-dir)
(defvar sp-bibliography-dir)
(declare-function sp-author-notes-bibtex--people "sp-author-notes-bibtex")

(defgroup sp-bibtex nil
  "BibTeX files, names and lint."
  :group 'convenience
  :prefix "sp-bibtex-")

(defcustom sp-bibtex-field-order
  '("author" "editor" "title" "subtitle" "booktitle" "journaltitle" "journal"
    "series" "edition" "volume" "number" "pages" "publisher" "address"
    "location" "institution" "school" "year" "date" "month" "doi" "isbn"
    "issn" "url" "urldate" "file" "keywords" "abstract" "note")
  "The order of the fields in an entry; fields not listed follow, in their order."
  :type '(repeat string)
  :group 'sp-bibtex)

(defcustom sp-bibtex-name-particles
  '("van" "von" "de" "der" "den" "del" "della" "di" "da" "du" "la" "le"
    "ten" "ter" "bin" "al" "el")
  "Lower case words that belong to the last name when it is written after the first name."
  :type '(repeat string)
  :group 'sp-bibtex)

(defcustom sp-bibtex-lint-backup-directory
  (expand-file-name "bibtex-lint-backups/"
                    (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory))
  "Folder where a .bib file is copied before `sp-bibtex-lint-convert' writes it."
  :type 'directory
  :group 'sp-bibtex)

(defcustom sp-bibtex-lint-batch-size 50
  "Number of entries `sp-bibtex-lint-convert' shows at once, for you to apply or skip."
  :type 'integer
  :group 'sp-bibtex)

(defcustom sp-bibtex-files-flatten nil
  "Non-nil: the attachment fix moves the files to the top of `sp-literature-dir'.
The field then holds the bare file name.  Nil leaves the files where they are
and writes their path relative to `sp-literature-dir'."
  :type 'boolean
  :group 'sp-bibtex)

(defvar sp-bibtex-lint--library nil
  "The index of `sp-literature-dir' while a lint job checks attachment paths.")

(defcustom sp-bibtex-people-cache-seconds 600
  "Seconds the list of author notes is kept for name completion and the lint."
  :type 'integer
  :group 'sp-bibtex)

(defun sp-bibtex--unwrap (value)
  "VALUE without its outer braces or quotes, and the delimiter pair; nil if it has none.
Return (TEXT . OPEN), or nil for a value that is a macro or a concatenation."
  (let ((value (string-trim value)))
    (when (> (length value) 1)
      (let ((open (aref value 0)) (close (aref value (1- (length value)))))
        (cond
         ((and (eq open ?{) (eq close ?}) (sp-bibtex--balanced-p (substring value 1 -1)))
          (cons (substring value 1 -1) ?{))
         ((and (eq open ?\") (eq close ?\") (not (string-search "\"" (substring value 1 -1))))
          (cons (substring value 1 -1) ?\")))))))

(defun sp-bibtex--balanced-p (text)
  "Non-nil when the braces of TEXT never close more than they open and end even."
  (let ((depth 0) (ok t))
    (dolist (c (string-to-list text))
      (cond ((eq c ?{) (cl-incf depth))
            ((eq c ?}) (cl-decf depth) (when (< depth 0) (setq ok nil)))))
    (and ok (= depth 0))))

(defun sp-bibtex--split-depth0 (text separator-re)
  "Split TEXT at the matches of SEPARATOR-RE that are outside braces."
  (let ((depth 0) (start 0) (i 0) (n (length text)) parts)
    (while (< i n)
      (let ((c (aref text i)))
        (cond ((eq c ?{) (cl-incf depth) (cl-incf i))
              ((eq c ?}) (cl-decf depth) (cl-incf i))
              ((and (= depth 0) (eq (string-match separator-re text i) i))
               (push (substring text start i) parts)
               (setq i (match-end 0) start i))
              (t (cl-incf i)))))
    (push (substring text start) parts)
    (nreverse parts)))

(defun sp-bibtex-split-names (text)
  "The names in the author or editor TEXT, split at \" and \" outside braces."
  (seq-remove #'string-empty-p
              (mapcar #'string-trim
                      (sp-bibtex--split-depth0 (replace-regexp-in-string "[ \t\n]+" " " text)
                                               "[ \t]+and[ \t]+"))))

(defun sp-bibtex-canonical-name (name)
  "NAME as \"Last, First\".  A corporate {Name}, \"others\" and one-word names stay."
  (let ((name (string-trim (replace-regexp-in-string "[ \t\n]+" " " name))))
    (cond
     ((or (string-empty-p name) (equal name "others")
          (and (eq (aref name 0) ?{) (sp-bibtex--balanced-p name)
               (= 1 (length (sp-bibtex--split-depth0 name "[ \t]+")))))
      name)
     ((string-search "," name)
      (string-join (mapcar #'string-trim (sp-bibtex--split-depth0 name ",")) ", "))
     (t
      (let ((words (sp-bibtex--split-depth0 name "[ \t]+")))
        (if (null (cdr words))
            name
          (let ((last (list (car (last words))))
                (rest (butlast words)))
            (while (and rest (member (car (last rest)) sp-bibtex-name-particles))
              (push (car (last rest)) last)
              (setq rest (butlast rest)))
            (if (null rest)
                name
              (format "%s, %s" (string-join last " ") (string-join rest " "))))))))))

(defun sp-bibtex-canonical-names (text)
  "The author or editor TEXT with every name in the canonical form."
  (string-join (mapcar #'sp-bibtex-canonical-name (sp-bibtex-split-names text)) " and "))

(defun sp-bibtex--name-key (canonical)
  "A lookup key for the CANONICAL name: lower case, no braces, dots or extra spaces."
  (string-trim (replace-regexp-in-string
                "[ \t]+" " "
                (replace-regexp-in-string "[{}.]" "" (downcase canonical)))))

(defvar sp-bibtex--people-cache nil
  "(TIME . INDEX) of the author notes, see `sp-bibtex-people'.")

(defun sp-bibtex--note-aliases (file)
  "The aliases in the head of the note FILE (its ROAM_ALIASES), as a list of strings."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file nil 0 4096)
      (let ((case-fold-search t) aliases)
        (while (re-search-forward "^\\(?:#\\+\\|[ \t]*:\\)ROAM_ALIASES:?[ \t]*\\(.*\\)$" nil t)
          (setq aliases (append aliases (ignore-errors
                                         (split-string-and-unquote (match-string-no-properties 1))))))
        aliases))))

(defun sp-bibtex--make-people (people)
  "The index of PEOPLE: a plist of :names, :keys, :files, :surnames and :buckets.
Each of PEOPLE is a title, or a plist with :title and :file from
`sp-author-notes--file-head'.  The aliases of the note files count as known
names, so a name that is an alias is not suggested to be a typo."
  (let ((keys (make-hash-table :test #'equal))
        (buckets (make-hash-table :test #'equal))
        (files (make-hash-table :test #'equal))
        (surnames (make-hash-table :test #'equal))
        names)
    (dolist (person people)
      (let* ((title (if (stringp person) person (plist-get person :title)))
             (canonical (sp-bibtex-canonical-name title))
             (key (sp-bibtex--name-key canonical)))
        (unless (gethash key keys)
          (puthash key canonical keys)
          (push canonical (gethash (sp-bibtex--surname-key canonical) surnames))
          (when-let* ((file (and (consp person) (plist-get person :file))))
            (puthash key file files))
          (push canonical names)
          (push canonical (gethash (sp-bibtex--bucket key) buckets)))))
    (dolist (person people)
      (when-let* ((file (and (consp person) (plist-get person :file))))
        (dolist (alias (sp-bibtex--note-aliases file))
          (let ((key (sp-bibtex--name-key (sp-bibtex-canonical-name alias))))
            (unless (gethash key keys)
              (puthash key (sp-bibtex-canonical-name (plist-get person :title)) keys))))))
    (list :names (sort names #'string<) :keys keys :files files :surnames surnames
          :buckets buckets
          :memo (make-hash-table :test #'equal))))

(defun sp-bibtex--bucket (key)
  "The bucket of the name KEY: the first letter of the last name and the first of the first name."
  (let ((parts (split-string key ", " t)))
    (format "%s|%s"
            (if parts (substring (car parts) 0 (min 1 (length (car parts)))) "")
            (if (cdr parts) (substring (cadr parts) 0 (min 1 (length (cadr parts)))) ""))))

(defun sp-bibtex-people (&optional refresh)
  "The index of the author notes, read again when REFRESH or older than the cache time."
  (interactive "P")
  (when (or refresh (null sp-bibtex--people-cache)
            (> (- (float-time) (car sp-bibtex--people-cache))
               sp-bibtex-people-cache-seconds))
    (require 'sp-author-notes-bibtex)
    (setq sp-bibtex--people-cache
          (cons (float-time)
                (sp-bibtex--make-people (sp-author-notes-bibtex--people)))))
  (cdr sp-bibtex--people-cache))

;; The names that are not typos of an author note but share its surname.

(defun sp-bibtex--fold (string)
  "STRING without accents, when `sp-author-notes-fold-diacritics' is loaded."
  (if (fboundp 'sp-author-notes-fold-diacritics)
      (sp-author-notes-fold-diacritics string)
    string))

(defun sp-bibtex--name-parts (canonical)
  "The last name and the given names of the CANONICAL name, as (LAST . GIVEN).
GIVEN is nil for a name without a comma."
  (let ((parts (mapcar #'string-trim (sp-bibtex--split-depth0 canonical ","))))
    (cons (car parts) (cadr parts))))

(defun sp-bibtex--surname-key (canonical)
  "A lookup key for the last name of the CANONICAL name: no accents, braces or case."
  (sp-bibtex--name-key (sp-bibtex--fold (car (sp-bibtex--name-parts canonical)))))

(defun sp-bibtex--given-units (given)
  "The given names GIVEN as a list of units (INITIAL . WORD).
INITIAL is an upper case letter.  WORD is the lower case name for a name
written out and nil for an initial: `TW' and `T. W.' give (\"T\") (\"W\"), and
`Theodor W.' gives (\"T\" . \"theodor\") (\"W\").  A hyphen starts a new unit."
  (let (units)
    (dolist (token (split-string (replace-regexp-in-string "[{}.]" " " (sp-bibtex--fold (or given "")))
                                 "[ \t]+" t))
      (dolist (part (split-string token "-" t))
        (cond
         ((string-match-p "\\`[[:upper:]]\\{1,3\\}\\'" part)
          (dolist (c (string-to-list part)) (push (list (char-to-string c)) units)))
         ((= (length part) 1) (push (list (upcase part)) units))
         (t (push (cons (upcase (substring part 0 1)) (downcase part)) units)))))
    (nreverse units)))

(defun sp-bibtex--initials-compatible-p (given note-given)
  "Non-nil when the given names GIVEN fit the NOTE-GIVEN names of an author note.
Each name, in order, has the initial of the other's name in that place, and two
names written out are the same.  One side may stop early or go on: `T', `TW',
`Theodor' and `Theodor W. X.' fit `Theodor W.'; `W', `Michael', `Theodor L.'
and `Theodore' do not."
  (let ((mine (sp-bibtex--given-units given))
        (theirs (sp-bibtex--given-units note-given)))
    (and mine theirs
         (cl-every (lambda (m n)
                     (and (equal (car m) (car n))
                          (or (null (cdr m)) (null (cdr n)) (equal (cdr m) (cdr n)))))
                   mine theirs))))

(defun sp-bibtex--surname-match (canonical people)
  "The author notes with the last name of CANONICAL and compatible given names.
Return nil when CANONICAL is a name of a note already, has no given names, or
no note matches; else the list of the matching note names (canonical).  When
several notes match, those that have as many given names as CANONICAL are
preferred: `TW Adorno' is `Theodor W. Adorno', not `Tamara Adorno'."
  (let ((parts (sp-bibtex--name-parts canonical)))
    (when (and (cdr parts)
               (not (gethash (sp-bibtex--name-key canonical) (plist-get people :keys))))
      (let* ((hits (seq-filter
                    (lambda (note)
                      (when-let* ((given (cdr (sp-bibtex--name-parts note))))
                        (sp-bibtex--initials-compatible-p (cdr parts) given)))
                    (gethash (sp-bibtex--surname-key canonical) (plist-get people :surnames))))
             (wanted (length (sp-bibtex--given-units (cdr parts))))
             (full (seq-filter (lambda (note)
                                 (>= (length (sp-bibtex--given-units (cdr (sp-bibtex--name-parts note))))
                                     wanted))
                               hits)))
        (if (and (cdr hits) full) full hits)))))

(defun sp-bibtex--suggestion (canonical people)
  "The author note a name CANONICAL is probably a typo of, or nil.
It is the note in the same bucket with a name at most two edits away.  A name
that has a note, or none close to it, gets nil."
  (let ((key (sp-bibtex--name-key canonical)))
    (unless (gethash key (plist-get people :keys))
      (let* ((memo (plist-get people :memo))
             (known (gethash key memo 'none)))
        (if (not (eq known 'none))
            known
          (puthash key
                   (seq-find (lambda (candidate)
                               (<= (string-distance key (sp-bibtex--name-key candidate)) 2))
                             (gethash (sp-bibtex--bucket key) (plist-get people :buckets)))
                   memo))))))

(defun sp-bibtex--field-rank (name)
  "The rank of the field NAME in `sp-bibtex-field-order'; unlisted fields come last."
  (or (seq-position sp-bibtex-field-order (downcase name)) (length sp-bibtex-field-order)))

(defun sp-bibtex--case-problem (case)
  "The sentence for CASE, a list (FIELD NAME NOTE-NAME NOTE-FILE [KIND]).
KIND is `surname' for a name with the surname of a note, else a typo of one."
  (if (eq (nth 4 case) 'surname)
      (format "%s: %s → %s (same surname)" (nth 0 case) (nth 1 case) (nth 2 case))
    (format "%s: %s is not an author note; did you mean %s?"
            (nth 0 case) (nth 1 case) (nth 2 case))))

(defun sp-bibtex--lint-names (fields people)
  "Check the author and editor names in FIELDS, an alist of name and raw value.
Return (NEW-FIELDS PROBLEMS CASES AMBIGUOUS): FIELDS with canonical names, the
strings that say what changed, for each name one typo away from an author note
a list (FIELD NAME NOTE-NAME NOTE-FILE), and for each name with the surname of
one note and compatible initials the same list with `surname' added.  AMBIGUOUS
lists (FIELD NAME NOTE-NAMES) for names whose surname and initials fit several
notes."
  (let (problems cases ambiguous new)
    (dolist (field fields)
      (let ((name (car field)) (value (cdr field)))
        (when (member (downcase name) '("author" "editor"))
          (when-let* ((unwrapped (sp-bibtex--unwrap value))
                      (text (car unwrapped)))
            (let ((fixed (sp-bibtex-canonical-names text)))
              (unless (equal fixed (string-trim (replace-regexp-in-string "[ \t\n]+" " " text)))
                (push (format "%s: %s → %s" name
                              (replace-regexp-in-string "[ \t\n]+" " " text) fixed)
                      problems)
                (setq value (if (eq (cdr unwrapped) ?\")
                                (format "\"%s\"" fixed)
                              (format "{%s}" fixed))))
              (when people
                (dolist (n (sp-bibtex-split-names fixed))
                  (if-let* ((near (sp-bibtex--suggestion n people)))
                      (push (list name n near
                                  (gethash (sp-bibtex--name-key near) (plist-get people :files)))
                            cases)
                    (let ((same (sp-bibtex--surname-match n people)))
                      (cond
                       ((null same))
                       ((null (cdr same))
                        (push (list name n (car same)
                                    (gethash (sp-bibtex--name-key (car same)) (plist-get people :files))
                                    'surname)
                              cases))
                       (t (push (list name n same) ambiguous))))))))))
        (push (cons name value) new)))
    (list (nreverse new) (nreverse problems) (nreverse cases) (nreverse ambiguous))))

(defun sp-bibtex--sort-fields (fields)
  "FIELDS in the order of `sp-bibtex-field-order'."
  (sort (copy-sequence fields)
        (lambda (a b) (< (sp-bibtex--field-rank (car a)) (sp-bibtex--field-rank (car b))))))

(defun sp-bibtex--order-problem (fields sorted)
  "The sentence that says FIELDS are not in the order of SORTED, or nil."
  (unless (equal (mapcar #'car sorted) (mapcar #'car fields))
    (format "fields: %s → %s" (string-join (mapcar #'car fields) " ")
            (string-join (mapcar #'car sorted) " "))))

(defun sp-bibtex--lint-fields (fields people)
  "Lint the FIELDS, an alist of name and raw value.
Return (NEW-FIELDS . PROBLEMS): the fields with canonical names, in the
configured order, and a list of strings that say what differs."
  (let* ((names (sp-bibtex--lint-names fields people))
         (sorted (sp-bibtex--sort-fields (car names))))
    (cons sorted
          (append (nth 1 names)
                  (mapcar #'sp-bibtex--case-problem (seq-remove (lambda (c) (eq (nth 4 c) 'surname))
                                                                (nth 2 names)))
                  (when-let* ((problem (sp-bibtex--order-problem (car names) sorted)))
                    (list problem))))))

(defun sp-bibtex--entry-text (type key fields)
  "The text of the entry TYPE, KEY and FIELDS (an alist of name and raw value)."
  (let ((width (apply #'max 1 (mapcar (lambda (f) (length (car f))) fields))))
    (concat "@" type "{" key ",\n"
            (mapconcat (lambda (f)
                         (format "  %s%s = %s," (car f)
                                 (make-string (- width (length (car f))) ?\s) (cdr f)))
                       fields "\n")
            "\n}")))

(defvar sp-bibtex--fill-buffer nil
  "Scratch `bibtex-mode' buffer in which `sp-bibtex--fill-text' lays entries out.")

(defun sp-bibtex--fill-text (text)
  "The entry TEXT laid out the way `bibtex-fill-entry' does it.
That is the standard of `bibtex-mode': field names at `bibtex-field-indentation',
text at `bibtex-text-indentation'.  TEXT itself when it cannot be filled."
  (unless (buffer-live-p sp-bibtex--fill-buffer)
    (setq sp-bibtex--fill-buffer (generate-new-buffer " *sp-bibtex-fill*"))
    (with-current-buffer sp-bibtex--fill-buffer (delay-mode-hooks (bibtex-mode))))
  (with-current-buffer sp-bibtex--fill-buffer
    (erase-buffer)
    (insert text)
    (goto-char (point-min))
    (condition-case nil
        (progn (bibtex-fill-entry)
               (buffer-substring-no-properties (point-min) (point-max)))
      (error text))))

(defun sp-bibtex--entry-rewrites (kinds type key fields people old start end)
  "The rewrites of the entry TYPE, KEY and FIELDS that are of one of KINDS.
OLD is the text of the entry, between START and END.  KINDS are `order',
`indent', `authors' (names to `Last, First'), `notes' (names one typo away from
an author note), `surnames' (names with the surname of one author note and
compatible initials), `ambiguous' (the same for several notes; reported only)
and `files' (attachment paths, see `sp-bibtex-files--rewrite').  Return (REWRITES . PROBLEMS).  REWRITES is an alist from a kind to a
plist of :start, :end, :old, :desc and :new (the new text) or :cases (for
`notes'); PROBLEMS are the lines for the report."
  (let* ((names (sp-bibtex--lint-names fields people))
         (sorted (sp-bibtex--sort-fields fields))
         (order (sp-bibtex--order-problem fields sorted))
         (cases (seq-remove (lambda (c) (eq (nth 4 c) 'surname)) (nth 2 names)))
         (same (seq-filter (lambda (c) (eq (nth 4 c) 'surname)) (nth 2 names)))
         (near (mapcar #'sp-bibtex--case-problem cases))
         (form (nth 1 names))
         (filled (and (memq 'indent kinds) (sp-bibtex--fill-text old)))
         (filed (and (memq 'files kinds) sp-bibtex-lint--library
                     (sp-bibtex-files--rewrite old key sp-bibtex-lint--library)))
         (base (list :start start :end end :old old))
         rewrites)
    (when (and filled (not (equal filled old)))
      (push (cons 'indent (append base (list :new filled :desc '("indentation differs from bibtex-mode"))))
            rewrites))
    (when (and order (memq 'order kinds))
      (push (cons 'order (append base (list :desc (list order)
                                            :new (sp-bibtex--fill-text
                                                  (sp-bibtex--entry-text type key sorted)))))
            rewrites))
    (when (and form (memq 'authors kinds))
      (push (cons 'authors (append base (list :desc form
                                              :new (sp-bibtex--fill-text
                                                    (sp-bibtex--entry-text type key (car names))))))
            rewrites))
    (when (and cases (memq 'notes kinds))
      (push (cons 'notes (append base (list :desc near :cases cases))) rewrites))
    (when (and same (memq 'surnames kinds))
      (push (cons 'surnames (append base (list :desc (mapcar #'sp-bibtex--case-problem same)
                                               :cases same)))
            rewrites))
    (when-let* ((changes (mapcar #'cdr (seq-filter (lambda (n) (eq (car n) 'change)) (nth 1 filed))))
                ((not (equal (car filed) old))))
      (push (cons 'files (append base (list :new (car filed) :desc changes :moves (nth 2 filed))))
            rewrites))
    (when (and (nth 3 names) (memq 'ambiguous kinds))
      (push (cons 'ambiguous
                  (append base (list :desc (mapcar (lambda (a)
                                                     (format "%s: %s could be %s" (nth 0 a) (nth 1 a)
                                                             (string-join (nth 2 a) " or ")))
                                                   (nth 3 names)))))
            rewrites))
    (cons (nreverse rewrites)
          (append form near (and order (list order))
                  (mapcar #'cdr (seq-filter (lambda (n) (eq (car n) 'problem)) (nth 1 filed)))
                  (and filled (not (equal filled old))
                       (list "indentation differs from bibtex-mode"))))))

(defun sp-bibtex--lint-chunk (file limit people seen kinds)
  "Lint the entries from point in the current buffer, at most LIMIT of them.
Return (RESULTS . MORE).  RESULTS lists (FILE KEY POSITION PROBLEMS REWRITES);
MORE is non-nil when LIMIT was reached.  SEEN is a hash table of the keys met
so far.  REWRITES is what `sp-bibtex--entry-rewrites' returns for KINDS: an
alist, empty for an entry that is only reported.  The buffer is not changed."
  (let ((count 0) results)
    (while (and (< count limit)
                (re-search-forward "^[ \t]*@[[:alpha:]]+[ \t]*[{(]" nil t))
      (cl-incf count)
      (let ((beg (match-beginning 0))
            (header (match-string 0)))
        (goto-char beg)
        (let* ((entry (ignore-errors (bibtex-parse-entry)))
               (type (cdr (assoc "=type=" entry)))
               (key (cdr (assoc "=key=" entry)))
               (end (and entry (ignore-errors (bibtex-end-of-entry)))))
          (if (not (and entry key end (not (member (downcase type) '("string" "preamble" "comment")))))
              (progn
                (unless (string-match-p "@[ \t]*\\(string\\|preamble\\|comment\\)" (downcase header))
                  (push (list file (or key "?") beg
                              '("could not be read (a comment inside?), left as it is"))
                        results))
                (goto-char (min (point-max) (1+ beg))))
            (let* ((fields (seq-remove (lambda (f) (string-prefix-p "=" (car f))) entry))
                   (start (save-excursion (goto-char beg) (skip-chars-forward " \t") (point)))
                   (commented (save-excursion
                                (goto-char beg)
                                (re-search-forward "^[ \t]*%" end t)))
                   (analysis (sp-bibtex--entry-rewrites
                              (unless commented kinds) type key fields people
                              (buffer-substring-no-properties start end) start end))
                   (problems (cdr analysis)))
              (when-let* ((first (gethash key seen)))
                (push (format "duplicate key (also in %s)" (file-name-nondirectory first)) problems))
              (puthash key (or (gethash key seen) file) seen)
              (when commented
                (setq problems (append problems '("has a comment inside, left as it is"))))
              (when (or problems (car analysis))
                (push (list file key beg problems (car analysis)) results))
              (goto-char end))))))
    (cons (nreverse results) (>= count limit))))

;;;; Attachment paths

(require 'ucs-normalize)
(defvar sp-literature-dir)

(defconst sp-bibtex-files--absolute-re
  "\\`\\(?:~\\|/Users/[^/]+\\)/Doc[[:alpha:]]*/\\.?literature/\\(.+\\)\\'"
  "An absolute path into the literature folder; accepts typos of `Documents'.")

(defconst sp-bibtex-files--bdsk-field-re
  "^\\([ \t]*\\)bdsk-file-\\([0-9]+\\)\\([ \t]*\\)=[ \t\n\r]*{\\([^}]*\\)}\\([ \t]*,?\\)"
  "A bdsk-file-N field: indent, N, space before =, base64 value, trailing comma.")

(defconst sp-bibtex-files--file-field-re
  "^\\([ \t]*\\)file\\([ \t]*\\)=\\([ \t]*\\){\\([^{}]*\\)}\\([ \t]*,?\\)"
  "A plain file field: indent, space, space, value, trailing comma.")

(defvar sp-bibtex-files--pending nil
  "The moves (FROM . TO) the entry being rewritten needs.")

(cl-defstruct (sp-bibtex-files--ctx (:constructor sp-bibtex-files--ctx-create))
  "The library to resolve in: its DIR, file NAMES, STEMS and the planned MOVES."
  dir names stems flatten
  (moves (make-hash-table :test #'equal))
  (dests (make-hash-table :test #'equal)))

(defun sp-bibtex-files--norm (string)
  "STRING in lower case with only letters and digits of a to z left."
  (replace-regexp-in-string "[^a-z0-9]" "" (downcase (ucs-normalize-NFC-string string))))

(defun sp-bibtex-files--stem-key (name)
  "Key of the file NAME: without extension and BibDesk's trailing digits."
  (sp-bibtex-files--norm
   (replace-regexp-in-string "[0-9]+\\'" "" (file-name-sans-extension name))))

(defun sp-bibtex-files-index (dir flatten)
  "Index the files below DIR (not the hidden ones) for `sp-bibtex-files-report'."
  (let ((ctx (sp-bibtex-files--ctx-create
              :dir dir :flatten flatten
              :names (make-hash-table :test #'equal)
              :stems (make-hash-table :test #'equal))))
    (dolist (file (directory-files-recursively
                   dir "" nil
                   (lambda (d) (not (string-prefix-p "." (file-name-nondirectory d))))))
      (let ((base (file-name-nondirectory file)))
        (unless (string-prefix-p "." base)
          (let ((rel (file-relative-name file dir)))
            (push rel (gethash (downcase (ucs-normalize-NFC-string base))
                               (sp-bibtex-files--ctx-names ctx)))
            (when (string-suffix-p ".pdf" (downcase base))
              (push rel (gethash (sp-bibtex-files--stem-key base)
                                 (sp-bibtex-files--ctx-stems ctx))))))))
    ctx))

(defun sp-bibtex-files--bdsk-path (value)
  "The relative path stored in VALUE, the base64 text of a bdsk-file field.
Nil when VALUE is not a BibDesk bookmark."
  (ignore-errors
    (let* ((text (replace-regexp-in-string "[^A-Za-z0-9+/=]" "" value))
           (raw (base64-decode-string
                 (concat text (make-string (mod (- (length text)) 4) ?=)) nil t))
           (pos (string-match "Xbookmark" raw)))
      (when (and pos (string-prefix-p "bplist00" raw))
        (let* ((p (+ pos 9))
               (marker (aref raw p))
               (kind (ash marker -4))
               (low (logand marker 15))
               (len low) (start (1+ p)))
          (when (= low 15)
            (pcase (aref raw (1+ p))
              (#x10 (setq len (aref raw (+ p 2)) start (+ p 3)))
              (#x11 (setq len (+ (ash (aref raw (+ p 2)) 8) (aref raw (+ p 3)))
                          start (+ p 4)))))
          (pcase kind
            (5 (decode-coding-string (substring raw start (+ start len)) 'utf-8))
            (6 (decode-coding-string (substring raw start (+ start (* 2 len))) 'utf-16be))))))))

(defun sp-bibtex-files--lookup (name ctx)
  "The library paths of the files called like the last part of NAME."
  (gethash (downcase (ucs-normalize-NFC-string (file-name-nondirectory name)))
           (sp-bibtex-files--ctx-names ctx)))

(defun sp-bibtex-files--target-1 (rel ctx)
  "The path for REL as `sp-bibtex-files--target' says, without recording the move."
  (let ((base (file-name-nondirectory rel))
        (dir (sp-bibtex-files--ctx-dir ctx))
        (moves (sp-bibtex-files--ctx-moves ctx))
        (dests (sp-bibtex-files--ctx-dests ctx)))
    (cond ((or (not (sp-bibtex-files--ctx-flatten ctx)) (not (string-match-p "/" rel))) rel)
          ((gethash rel moves))
          ((or (file-exists-p (expand-file-name base dir)) (gethash base dests)) rel)
          (t (puthash base t dests) (puthash rel base moves)))))

(defun sp-bibtex-files--target (rel ctx)
  "The path to write for the library path REL; with `flatten' it plans the move."
  (let ((target (sp-bibtex-files--target-1 rel ctx))
        (dir (sp-bibtex-files--ctx-dir ctx)))
    (unless (equal target rel)
      (push (cons (expand-file-name rel dir) (expand-file-name target dir))
            sp-bibtex-files--pending))
    target))

(defun sp-bibtex-files--resolve (value key ctx)
  "Resolve the bdsk-file VALUE of entry KEY; return (PATH . nil) or (nil . PROBLEM)."
  (if-let* ((old (sp-bibtex-files--bdsk-path value)))
      (let ((found (or (sp-bibtex-files--lookup old ctx)
                       (gethash (sp-bibtex-files--norm key) (sp-bibtex-files--ctx-stems ctx)))))
        (cond ((null found) (cons nil (format "not found: %s" old)))
              ((cdr found) (cons nil (format "ambiguous: %s" (string-join found ", "))))
              (t (cons (car found) nil))))
    (cons nil "not a BibDesk bookmark")))

(defun sp-bibtex-files--relativise (value ctx)
  "Make the absolute literature paths in the file field VALUE relative.
Return (NEW-VALUE NOTES)."
  (let (notes)
    (cons (mapconcat
           (lambda (part)
             (let ((trimmed (string-trim part)))
               (if (and (string-match sp-bibtex-files--absolute-re trimmed)
                        (not (string-search ":" (match-string 1 trimmed))))
                   (let* ((rel (match-string 1 trimmed))
                          (new (if (file-exists-p (expand-file-name rel (sp-bibtex-files--ctx-dir ctx)))
                                   rel
                                 (let ((found (sp-bibtex-files--lookup rel ctx)))
                                   (if (and found (null (cdr found)))
                                       (sp-bibtex-files--target (car found) ctx)
                                     (push (cons 'problem (format "file not found: %s" rel)) notes)
                                     rel)))))
                     (push (cons 'change (format "file: %s → %s" trimmed new)) notes)
                     new)
                 part)))
           (split-string value ";") ";")
          (list (nreverse notes)))))

(defun sp-bibtex-files--rewrite (text key ctx)
  "Rewrite the attachment fields of the entry TEXT (entry KEY).
Return (NEW-TEXT NOTES MOVES), NOTES a list of (KIND . MESSAGE) with KIND
`change' or `problem' and MOVES the files to move, (FROM . TO).  Entries with
unresolved bdsk-file fields keep them."
  (let ((new text) (notes nil) (fields nil) (start 0) (sp-bibtex-files--pending nil))
    (save-match-data
      (while (string-match sp-bibtex-files--bdsk-field-re text start)
        (push (list (match-beginning 0) (match-end 0) (match-string 1 text)
                    (match-string 2 text) (match-string 3 text) (match-string 4 text)
                    (match-string 5 text))
              fields)
        (setq start (match-end 0)))
      (setq fields (nreverse fields))
      (when fields
        (let* ((sorted (sort (copy-sequence fields)
                             (lambda (a b) (< (string-to-number (nth 3 a))
                                              (string-to-number (nth 3 b))))))
               (existing (string-match sp-bibtex-files--file-field-re text))
               paths problems)
          (dolist (f sorted)
            (let ((r (sp-bibtex-files--resolve (nth 5 f) key ctx)))
              (if (car r)
                  (push (car r) paths)
                (push (format "bdsk-file-%s: %s" (nth 3 f) (cdr r)) problems))))
          (setq paths (nreverse paths))
          (when (and (null problems) (cl-some (lambda (p) (string-match-p "[;{}]\\|\\`[ \t]\\|[ \t]\\'" (file-name-nondirectory p))) paths))
            (push "a file name has ; { } or edge spaces" problems))
          (when (and (null problems) (not existing)
                     (string-match-p "^[ \t]*file[ \t]*=" text))
            (push "existing file field is not a plain {...}" problems))
          (if problems
              (dolist (p (nreverse problems)) (push (cons 'problem p) notes))
            (let* ((targets (mapcar (lambda (p) (sp-bibtex-files--target p ctx)) paths))
                   (value (string-join targets ";"))
                   (last-field (car (last fields))))
              (dolist (f (reverse fields))
                (let ((st (nth 0 f)) (en (nth 1 f)))
                  (if (and (eq f last-field) (not existing))
                      (setq new (concat (substring new 0 st)
                                        (nth 2 f) "file"
                                        (make-string (max 1 (+ 6 (length (nth 3 f)) (length (nth 4 f)))) ?\s)
                                        "= {" value "}" (nth 6 f)
                                        (substring new en)))
                    (cond ((string-prefix-p "\r\n" (substring new en)) (setq en (+ en 2)))
                          ((string-prefix-p "\n" (substring new en)) (setq en (1+ en))))
                    (setq new (concat (substring new 0 st) (substring new en))))))
              (when existing
                (when (string-match sp-bibtex-files--file-field-re new)
                  (setq new (concat (substring new 0 (match-end 4)) ";" value
                                    (substring new (match-end 4))))))
              (push (cons 'change (format "%s → file = {%s}"
                                          (mapconcat (lambda (f) (concat "bdsk-file-" (nth 3 f))) sorted ", ")
                                          value))
                    notes)))))
      (when (string-match sp-bibtex-files--file-field-re new)
        (let* ((b (match-beginning 4)) (e (match-end 4))
               (r (sp-bibtex-files--relativise (match-string 4 new) ctx)))
          (setq new (concat (substring new 0 b) (car r) (substring new e)))
          (setq notes (append (reverse (cadr r)) notes)))))
    (list new (nreverse notes) (reverse sp-bibtex-files--pending))))

(defun sp-bibtex-files--library ()
  "Index `sp-literature-dir' for the attachment fix; nil when it is not a folder."
  (when (and (boundp 'sp-literature-dir) (stringp sp-literature-dir)
             (file-directory-p sp-literature-dir))
    (sp-bibtex-files-index sp-literature-dir sp-bibtex-files-flatten)))

(defun sp-bibtex-files--move (moves)
  "Move the files of MOVES, a list of (FROM . TO) absolute paths; never over a file.
Each move is added to a .tsv, one a day, in `sp-bibtex-lint-backup-directory'."
  (dolist (m moves)
    (when (and (file-exists-p (car m)) (not (file-exists-p (cdr m))))
      (rename-file (car m) (cdr m))
      (make-directory sp-bibtex-lint-backup-directory t)
      (write-region (format "%s\t%s\n" (car m) (cdr m)) nil
                    (expand-file-name (format-time-string "files-moves-%Y%m%d.tsv")
                                      sp-bibtex-lint-backup-directory)
                    'append 'silent))))

;;;###autoload
(defun sp-bibtex-lint-fix-files (file)
  "Turn the BibDesk bdsk-file fields of the .bib FILE into file fields.
FILE is the .bib file of the current buffer; with a prefix argument, or when
the buffer is not a .bib file, it is read with completion.  Absolute paths
into `sp-literature-dir' become relative to it.  All entries are fixed at
once, after one question and a backup.  With `sp-bibtex-files-flatten' the
files are moved to the top of the library."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (unless (and (boundp 'sp-literature-dir) (stringp sp-literature-dir)
               (file-directory-p sp-literature-dir))
    (user-error "`sp-literature-dir' is not a folder"))
  (when (or (not sp-bibtex-files-flatten)
            (yes-or-no-p "`sp-bibtex-files-flatten' is on: the files are moved to the top of the library.  Go on? "))
    (sp-bibtex-lint--fix file 'files)))

(defconst sp-bibtex-lint--buffer "*BibTeX lint*")
(defconst sp-bibtex-lint--batch-buffer "*BibTeX lint batch*")

(defconst sp-bibtex-lint--kinds
  '((order . "field order") (indent . "indentation") (authors . "author names")
    (notes . "names near an author note") (surnames . "names with the surname of an author note")
    (ambiguous . "names that fit several author notes")
    (files . "attachment paths"))
  "The kinds of fix, with what the batch pages call them.")

(defun sp-bibtex-lint--files ()
  "The .bib files to lint; a `user-error' says what is wrong when there are none."
  (let ((files (seq-filter #'file-readable-p
                           (if (boundp 'sp-bibtex-files) sp-bibtex-files nil))))
    (or files
        (user-error "No readable BibTeX files in `sp-bibtex-files'; run `sp-bibtex-register'"))))

(defun sp-bibtex-lint--read-file (&optional ask)
  "The one .bib file to lint.
It is the file of the current buffer when that is a .bib file, unless ASK is
non-nil; otherwise it is read with completion over `sp-bibtex-files', with the
current .bib file as the default."
  (let* ((current (and buffer-file-name
                       (string-match-p "\\.bib\\'" buffer-file-name)
                       buffer-file-name))
         (file (if (and current (not ask))
                   current
                 (completing-read "BibTeX file: " (sp-bibtex-lint--files)
                                  nil nil nil nil current))))
    (setq file (expand-file-name file))
    (unless (file-readable-p file)
      (user-error "Cannot read %s" file))
    file))

(defun sp-bibtex-lint--job (name files kinds done)
  "Run the lint job NAME over FILES for the fixes KINDS, without changing them.
DONE gets the list of (FILE KEY POSITION PROBLEMS REWRITES)."
  (let ((people (condition-case nil (sp-bibtex-people) (error nil)))
        (seen (make-hash-table :test #'equal))
        all)
    (setq sp-bibtex-lint--library
          (and (memq 'files kinds) (sp-bibtex-files--library)))
    (sp-async-work-run
     name
     (list (list "reading BibTeX" (lambda () files)
                 (lambda (item job)
                   (let* ((file (if (consp item) (car item) item))
                          (buffer (if (consp item)
                                      (cdr item)
                                    (let ((b (generate-new-buffer " *sp-bibtex-lint*")))
                                      (sp-async-work-on-cleanup job (lambda () (when (buffer-live-p b) (kill-buffer b))))
                                      (with-current-buffer b
                                        (insert-file-contents file)
                                        (delay-mode-hooks (bibtex-mode))
                                        (goto-char (point-min)))
                                      b))))
                     (with-current-buffer buffer
                       (let ((result (sp-bibtex--lint-chunk file 100 people seen kinds)))
                         (setq all (append all (car result)))
                         (if (cdr result)
                             (sp-async-work-push job (cons file buffer))
                           (kill-buffer buffer))))))))
     :done (lambda (_job)
             (setq sp-bibtex-lint--library nil)
             (funcall done all)))))

(defun sp-bibtex-lint--backup (file stamp)
  "Copy FILE to the STAMP sub-folder of `sp-bibtex-lint-backup-directory'."
  (let ((dir (expand-file-name (concat stamp "/") sp-bibtex-lint-backup-directory)))
    (make-directory dir t)
    (copy-file file (expand-file-name (file-name-nondirectory file) dir) t)))

(defun sp-bibtex-lint--entry-text (result link &optional lines)
  "The Org text for the lint RESULT: a heading and its problems, or LINES.
LINK is the Org link to the entry, or nil."
  (concat "* " (or link (nth 1 result)) "\n"
          (mapconcat (lambda (p) (concat "- " p "\n")) (or lines (nth 3 result)) "")))

(defun sp-bibtex-lint--lines (file positions)
  "The line numbers of the buffer POSITIONS of FILE, in the order of POSITIONS.
Each position is the start of a line."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((last 1) (line 1) (table (make-hash-table :test #'eql)))
      (dolist (pos (sort (delete-dups (copy-sequence positions)) #'<))
        (setq pos (min pos (point-max)))
        (setq line (+ line (count-lines last pos)) last pos)
        (puthash pos line table))
      (mapcar (lambda (pos) (or (gethash (min pos (point-max)) table) 1)) positions))))

;;;; The report, with one button for each fix

(defun sp-bibtex-lint--button (kind file label count)
  "The Org link that runs the fix KIND on FILE, labelled LABEL with COUNT entries."
  (org-link-make-string (format "sp-bibtex-lint:%s:%s" kind file)
                        (format "%s (%d)" label count)))

(defun sp-bibtex-lint--follow (path &optional _arg)
  "Follow the link PATH, \"KIND:FILE\", of a button in the report."
  (unless (string-match "\\`\\([a-z]+\\):\\(.*\\)\\'" path)
    (user-error "Not a lint button: %s" path))
  (let ((file (match-string 2 path)))
    (pcase (match-string 1 path)
      ("order" (sp-bibtex-lint-fix-order file))
      ("indent" (sp-bibtex-lint-fix-indent file))
      ("authors" (sp-bibtex-lint-fix-authors file))
      ("files" (sp-bibtex-lint-fix-files file))
      (other (user-error "Unknown lint button: %s" other)))))

(org-link-set-parameters "sp-bibtex-lint" :follow #'sp-bibtex-lint--follow)

(defun sp-bibtex-lint--count (results kind)
  "The number of RESULTS that have a rewrite of KIND."
  (length (seq-filter (lambda (r) (alist-get kind (nth 4 r))) results)))

(defvar sp-bibtex-lint--excluded nil
  "Entries dropped from the author fixes with `d', as keys \"FILE::ENTRY-KEY\".
The list lasts for the Emacs session, like the dropped entries of the other lint
reports.  `u' in the report, or in the batch question, brings an entry back.")

(defun sp-bibtex-lint--entry-key (file key)
  "The key that drops the BibTeX entry KEY of FILE."
  (concat (expand-file-name file) "::" key))

(defun sp-bibtex-lint--key-entry (key)
  "The entry key in the dropped KEY."
  (substring key (+ 2 (string-search "::" key))))

(defun sp-bibtex-lint--dropped-keys (file)
  "The dropped keys of the entries of FILE."
  (let ((prefix (concat (expand-file-name file) "::")))
    (seq-filter (lambda (k) (string-prefix-p prefix k)) sp-bibtex-lint--excluded)))

(defun sp-bibtex-lint--dropped-p (file result)
  "Non-nil when the entry of the lint RESULT of FILE was dropped."
  (member (sp-bibtex-lint--entry-key file (nth 1 result)) sp-bibtex-lint--excluded))

(defun sp-bibtex-lint--undropped (file batch)
  "The items of BATCH, (RESULT BEG END), whose entries were not dropped in FILE."
  (seq-remove (lambda (item) (sp-bibtex-lint--dropped-p file (car item))) batch))

(defun sp-bibtex-lint--key-label (key)
  "The text of the dropped KEY in the report."
  (let ((file (substring key 0 (string-search "::" key))))
    (format "%s in %s" (sp-bibtex-lint--key-entry key) (sp-batch-report-file-link file))))

(defun sp-bibtex-lint--choose (prompt candidates)
  "Read several of CANDIDATES, separated by commas, with PROMPT."
  (completing-read-multiple prompt candidates nil t))

(defun sp-bibtex-lint--drop-dialog (file batch)
  "Ask which entries of BATCH to drop from the author fixes of FILE; return how many."
  (let ((picked (sp-bibtex-lint--choose
                 "Drop from the author fixes, for later (comma separated): "
                 (mapcar (lambda (item) (nth 1 (car item))) (sp-bibtex-lint--undropped file batch)))))
    (dolist (name picked)
      (cl-pushnew (sp-bibtex-lint--entry-key file name) sp-bibtex-lint--excluded :test #'equal))
    (length picked)))

(defun sp-bibtex-lint--restore-dialog (file)
  "Ask which dropped entries of FILE to bring back; return how many."
  (let ((picked (sp-bibtex-lint--choose
                 "Bring back (comma separated): "
                 (mapcar #'sp-bibtex-lint--key-entry (sp-bibtex-lint--dropped-keys file)))))
    (dolist (name picked)
      (setq sp-bibtex-lint--excluded
            (delete (sp-bibtex-lint--entry-key file name) sp-bibtex-lint--excluded)))
    (length picked)))

;;;###autoload
(defun sp-bibtex-lint-restore-dropped (file)
  "Bring back entries of FILE that were dropped from the author fixes."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (if (null (sp-bibtex-lint--dropped-keys file))
      (message "Nothing is dropped in %s" (file-name-nondirectory file))
    (message "%d brought back" (sp-bibtex-lint--restore-dialog file))))

(defun sp-bibtex-lint--section (title kind results pairs file)
  "The Org section TITLE with the RESULTS that have a rewrite of KIND.
PAIRS says the line of each result in FILE.  Nothing when there are none."
  (when-let* ((mine (seq-filter (lambda (r) (alist-get kind (nth 4 r))) results)))
    (concat
     (format "\n* %s (%d)\n" title
             (apply #'+ (mapcar (lambda (r) (length (plist-get (alist-get kind (nth 4 r)) :desc)))
                                mine)))
     (mapconcat
      (lambda (r)
        (propertize
         (concat "** " (sp-batch-report-file-link file (nth 1 r) (alist-get r pairs nil nil #'eq)) "\n"
                 (mapconcat (lambda (d) (concat "- " d "\n"))
                            (plist-get (alist-get kind (nth 4 r)) :desc) ""))
         'sp-batch-report-key (sp-bibtex-lint--entry-key file (nth 1 r))
         'sp-batch-report-file file))
      mine ""))))

(defun sp-bibtex-lint--render (file results)
  "Show RESULTS, a list of (FILE KEY POSITION PROBLEMS REWRITES) of FILE, as a report.
Names with the surname of an author note have sections of their own, so they do
not bury the typos.  `d' drops an entry from the author fixes and `u' brings it
back; the dropped ones are listed at the end."
  (let* ((pairs (cl-mapcar #'cons results
                           (sp-bibtex-lint--lines file (mapcar (lambda (r) (nth 2 r)) results))))
         (shown (seq-remove (lambda (r) (sp-bibtex-lint--dropped-p file r)) results))
         (dropped (sp-bibtex-lint--dropped-keys file))
         (main (seq-filter (lambda (r) (nth 3 r)) shown)))
    (sp-batch-report-open
     sp-bibtex-lint--buffer
     (concat
      (format "#+title: BibTeX lint of %s\n\n" (file-name-nondirectory file))
      (format "- %d entr%s with problems in %s.\n"
              (length main) (if (= 1 (length main)) "y" "ies")
              (sp-batch-report-file-link file))
      (format "- %d entr%s with a name that has the surname of an author note (own section below); %d with a name that fits several.\n"
              (sp-bibtex-lint--count shown 'surnames)
              (if (= 1 (sp-bibtex-lint--count shown 'surnames)) "y" "ies")
              (sp-bibtex-lint--count shown 'ambiguous))
      "- =d= drops an entry from the author fixes for later, =u= brings it back, =A= runs the author fixes.\n"
      (format "- Fix, in batches of %d (a button runs the fix; the file is copied first):\n"
              sp-bibtex-lint-batch-size)
      (format "  - %s\n" (sp-bibtex-lint--button "order" file "field order"
                                                 (sp-bibtex-lint--count results 'order)))
      (format "  - %s\n" (sp-bibtex-lint--button "indent" file "indentation, as in bibtex-mode"
                                                 (sp-bibtex-lint--count results 'indent)))
      (format "  - %s\n" (sp-bibtex-lint--button "files" file "attachment paths"
                                                 (sp-bibtex-lint--count results 'files)))
      (format "  - %s\n" (sp-bibtex-lint--button
                          "authors" file "author names"
                          (length (seq-filter (lambda (r) (seq-some (lambda (k) (alist-get k (nth 4 r)))
                                                                    '(authors notes surnames)))
                                              shown))))
      (mapconcat (lambda (r)
                   (propertize
                    (concat "\n" (sp-bibtex-lint--entry-text
                                  r (sp-batch-report-file-link file (nth 1 r) (alist-get r pairs nil nil #'eq))))
                    'sp-batch-report-key (sp-bibtex-lint--entry-key file (nth 1 r))
                    'sp-batch-report-file file))
                 main "")
      (sp-bibtex-lint--section "Attachment paths" 'files shown pairs file)
      (sp-bibtex-lint--section "Same surname as an author note" 'surnames shown pairs file)
      (sp-bibtex-lint--section "Same surname, several author notes" 'ambiguous shown pairs file)
      (and dropped
           (concat "\n" (sp-batch-report-dropped-section dropped nil #'sp-bibtex-lint--key-label))))
     :refresh (lambda (excluded)
                (setq sp-bibtex-lint--excluded excluded)
                (sp-bibtex-lint-dryrun file))
     :excluded sp-bibtex-lint--excluded
     :apply (lambda (excluded)
              (setq sp-bibtex-lint--excluded excluded)
              (sp-bibtex-lint-fix-authors file)))))

;;;###autoload
(defun sp-bibtex-lint-dryrun (file)
  "List what the .bib FILE breaks, without changing it.
FILE is the .bib file of the current buffer; with a prefix argument, or when
the buffer is not a .bib file, it is read with completion.  It checks the author
and editor names (canonical form `Last, First', and names one typo away from an
author note, and, in sections of their own, names with the surname of one
author note or of several), the order of the fields (`sp-bibtex-field-order'), the indentation
\(as `bibtex-fill-entry' lays it out), duplicate keys and attachment paths
\(BibDesk bdsk-file fields, absolute literature paths).  The report has a
button for each fix.  Notes for authors are never made."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (sp-bibtex-lint--job "BibTeX lint" (list file) '(order indent authors notes surnames ambiguous files)
                       (lambda (results) (sp-bibtex-lint--render file results))))

;;;; Batches

(defun sp-bibtex-lint--show-batch (file kind batch index total all)
  "Show BATCH, number INDEX of TOTAL batches (ALL entries) of the fix KIND for FILE.
Entries dropped from the author fixes are left out."
  (let* ((batch (if (memq kind '(authors notes surnames)) (sp-bibtex-lint--undropped file batch) batch))
         (lines (sp-bibtex-lint--lines file (mapcar (lambda (item) (nth 2 (car item))) batch))))
    (sp-batch-report-show
     sp-bibtex-lint--batch-buffer
     (concat
      (format "#+title: BibTeX %s of %s, batch %d of %d\n\n"
              (alist-get kind sp-bibtex-lint--kinds) (file-name-nondirectory file) index total)
      (format "- %d entr%s in this batch, %d in all.\n" (length batch)
              (if (= 1 (length batch)) "y" "ies") all)
      (mapconcat (lambda (item)
                   (let ((r (car item)))
                     (concat "\n" (sp-bibtex-lint--entry-text
                                   r (sp-batch-report-file-link file (nth 1 r) (pop lines))
                                   (plist-get (alist-get kind (nth 4 r)) :desc)))))
                 batch "")))))

(defun sp-bibtex-lint--ask-batch (file batch index total all kind)
  "Show BATCH, number INDEX of TOTAL in FILE, and ask what to do with it.
BATCH is a list of (RESULT BEG END); ALL is the number of entries in every
batch.  KIND is the fix.  Return ?a to apply, ?s to skip or ?q to stop.  With ?d
some entries are dropped from the author fixes for later, with ?u dropped ones
are brought back; the batch is shown again each time."
  (let (choice)
    (while (progn
             (sp-bibtex-lint--show-batch file kind batch index total all)
             (setq choice
                   (read-char-choice
                    (format "Batch %d of %d (%d entries): [a]pply, [s]kip, [d]rop some for later, [u] bring back, [q]uit "
                            index total (length (sp-bibtex-lint--undropped file batch)))
                    '(?a ?s ?d ?u ?q)))
             (pcase choice
               (?d (sp-bibtex-lint--drop-dialog file batch) t)
               (?u (sp-bibtex-lint--restore-dialog file) t))))
    choice))

(defun sp-bibtex-lint--replace (beg end new)
  "Replace the text between the markers BEG and END with NEW; END ends after it."
  (goto-char beg)
  (delete-region beg end)
  (insert new)
  (set-marker end (point)))

(defun sp-bibtex-lint--apply-batch (work batch kind)
  "Rewrite the entries of BATCH in the buffer WORK, for the fix KIND.
BATCH is a list of (RESULT BEG END) with markers.  An entry whose text is no
longer the one that was linted is left alone.  Return (CHANGED STALE WROTE)."
  (let ((changed 0) (stale 0))
    (with-current-buffer work
      (dolist (item batch)
        (pcase-let* ((`(,r ,beg ,end) item)
                     (rewrite (alist-get kind (nth 4 r))))
          (if (not (equal (plist-get rewrite :old) (buffer-substring-no-properties beg end)))
              (cl-incf stale)
            (sp-bibtex-lint--replace beg end (plist-get rewrite :new))
            (when (eq kind 'files)
              (sp-bibtex-files--move (plist-get rewrite :moves)))
            (cl-incf changed)))))
    (list changed stale t)))

(defun sp-bibtex-lint--signature (file)
  "The modification time and size of FILE, to notice that it changed."
  (let ((attributes (file-attributes file)))
    (list (file-attribute-modification-time attributes) (file-attribute-size attributes))))

(defun sp-bibtex-lint--save (work file)
  "Write the buffer WORK to FILE and bring the buffer that visits FILE up to date."
  (with-current-buffer work
    (write-region (point-min) (point-max) file nil 'silent))
  (when-let* ((visiting (find-buffer-visiting file)))
    (unless (buffer-modified-p visiting)
      (with-current-buffer visiting (revert-buffer t t t)))))

(defun sp-bibtex-lint--run (file kind results ask apply-fn &optional then whole)
  "Go through the entries of RESULTS with a fix of KIND for FILE, in batches.
Batches have `sp-bibtex-lint-batch-size' entries, or with WHOLE all the entries
are one batch.  ASK is called with (BATCH
INDEX TOTAL ALL) and returns `skip', `quit' or an answer for APPLY-FN, which is
called with (WORK BATCH ANSWER) and returns (CHANGED STALE WROTE).  When WROTE,
FILE is copied to `sp-bibtex-lint-backup-directory' (once) and written; nothing
is written without an answer.  THEN is called when the run was not quit."
  (let* ((authorial (memq kind '(authors notes surnames)))
         (fixable (seq-filter (lambda (r) (and (alist-get kind (nth 4 r))
                                               (not (and authorial (sp-bibtex-lint--dropped-p file r)))))
                              results))
         (what (alist-get kind sp-bibtex-lint--kinds))
         (work (generate-new-buffer " *sp-bibtex-lint-work*"))
         (stop nil))
    (if (null fixable)
        (message "BibTeX lint: no %s to fix in %s" what (file-name-nondirectory file))
      (unwind-protect
          (let* ((items (with-current-buffer work
                          (insert-file-contents file)
                          (delay-mode-hooks (bibtex-mode))
                          (mapcar (lambda (r)
                                    (let ((rewrite (alist-get kind (nth 4 r))))
                                      (list r (copy-marker (plist-get rewrite :start))
                                            (copy-marker (plist-get rewrite :end)))))
                                  fixable)))
                 (batches (seq-partition items (max 1 (if whole (length items) sp-bibtex-lint-batch-size))))
                 (total (length batches))
                 (stamp (format-time-string "%Y%m%dT%H%M%S"))
                 (signature (sp-bibtex-lint--signature file))
                 (index 0) (changed 0) (skipped 0) (stale 0) (backed-up nil))
            (while (and batches (not stop))
              (let* ((batch (pop batches))
                     (answer (funcall ask batch (cl-incf index) total (length items))))
                ;; Entries dropped while the batch was asked are not touched.
                (when authorial (setq batch (sp-bibtex-lint--undropped file batch)))
                (pcase (if (and authorial (null batch)) 'skip answer)
                  ('quit (setq stop t) (cl-incf skipped (length batch)))
                  ('skip (cl-incf skipped (length batch)))
                  (_
                   (when-let* ((visiting (find-buffer-visiting file))
                               ((buffer-modified-p visiting)))
                     (user-error "Save %s first" (file-name-nondirectory file)))
                   (let ((done (funcall apply-fn work batch answer)))
                     (cl-incf changed (nth 0 done))
                     (cl-incf stale (nth 1 done))
                     (when (nth 2 done)
                       (unless (equal signature (sp-bibtex-lint--signature file))
                         (user-error "%s changed on disk since it was linted; run the command again"
                                     (file-name-nondirectory file)))
                       (unless backed-up
                         (sp-bibtex-lint--backup file stamp)
                         (setq backed-up t))
                       (sp-bibtex-lint--save work file)
                       (setq signature (sp-bibtex-lint--signature file))))))))
            (message "BibTeX %s of %s: %d done, %d skipped, %d not reached%s%s"
                     what (file-name-nondirectory file) changed skipped
                     (apply #'+ (mapcar #'length batches))
                     (if (> stale 0) (format ", %d changed since the lint" stale) "")
                     (if backed-up
                         (format "; backup in %s" (abbreviate-file-name sp-bibtex-lint-backup-directory))
                       "")))
        (kill-buffer work)))
    (when (and then (not stop)) (funcall then))))

(defun sp-bibtex-lint--review (file kind results &optional then)
  "Go through the rewrites of KIND in RESULTS for FILE, a batch at a time.
Each batch is applied, skipped or quit; see `sp-bibtex-lint--run'."
  (sp-bibtex-lint--run
   file kind results
   (lambda (batch index total all)
     (pcase (sp-bibtex-lint--ask-batch file batch index total all kind)
       (?a 'apply) (?s 'skip) (_ 'quit)))
   (lambda (work batch _answer) (sp-bibtex-lint--apply-batch work batch kind))
   then))

(defun sp-bibtex-lint--unsaved-check (file)
  "Signal a `user-error' when the buffer that visits FILE has unsaved changes."
  (when-let* ((visiting (find-buffer-visiting file))
              ((buffer-modified-p visiting)))
    (user-error "Save %s first" (file-name-nondirectory file))))

(defun sp-bibtex-lint--confirm (file kind count)
  "Ask once whether to apply the fix KIND to COUNT entries of FILE."
  (yes-or-no-p (format "Fix the %s of %d entr%s in %s (a backup is made first)? "
                       (alist-get kind sp-bibtex-lint--kinds) count (if (= 1 count) "y" "ies")
                       (file-name-nondirectory file))))

(defun sp-bibtex-lint--review-whole (file kind results)
  "Apply the fix KIND in RESULTS to the whole FILE after one confirmation."
  (sp-bibtex-lint--run
   file kind results
   (lambda (batch _index _total _all)
     (if (sp-bibtex-lint--confirm file kind (length batch)) 'apply 'skip))
   (lambda (work batch _answer) (sp-bibtex-lint--apply-batch work batch kind))
   nil t))

(defun sp-bibtex-lint--fix (file kind)
  "Lint FILE and apply the fix KIND to all of it after one question."
  (sp-bibtex-lint--unsaved-check file)
  (sp-bibtex-lint--job "BibTeX lint" (list file) (list kind)
                       (lambda (results) (sp-bibtex-lint--review-whole file kind results))))

;;;###autoload
(defun sp-bibtex-lint-fix-order (file)
  "Put the fields of the entries of the .bib FILE in the order of `sp-bibtex-field-order'.
FILE is the .bib file of the current buffer; with a prefix argument, or when
the buffer is not a .bib file, it is read with completion.  All entries are
fixed at once, after one yes-or-no question; FILE is copied to
`sp-bibtex-lint-backup-directory' before it is written.  An entry with a
comment inside is left alone."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (sp-bibtex-lint--fix file 'order))

;;;###autoload
(defun sp-bibtex-lint-fix-indent (file)
  "Indent every entry of the .bib FILE the way `bibtex-mode' does (`bibtex-fill-entry').
All entries at once, after one question and a backup, as `sp-bibtex-lint-fix-order' does."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (sp-bibtex-lint--fix file 'indent))

;;;; Author names

(defun sp-bibtex--rename-names (fields cases)
  "FIELDS with the names of CASES replaced by the names of the author notes.
CASES are lists (FIELD NAME NOTE-NAME ...); the other names stay as written."
  (mapcar
   (lambda (field)
     (let ((mine (seq-filter (lambda (c) (string-equal-ignore-case (car c) (car field))) cases)))
       (if-let* (((consp mine))
                 (unwrapped (sp-bibtex--unwrap (cdr field))))
           (let ((names (mapcar
                         (lambda (n)
                           (if-let* ((hit (seq-find (lambda (m) (equal (nth 1 m) (sp-bibtex-canonical-name n)))
                                                    mine)))
                               (nth 2 hit)
                             n))
                         (sp-bibtex-split-names (car unwrapped)))))
             (cons (car field)
                   (format (if (eq (cdr unwrapped) ?\") "\"%s\"" "{%s}")
                           (string-join names " and "))))
         field)))
   fields))

(defun sp-bibtex-lint--add-alias (file alias)
  "Add ALIAS to the aliases of the note FILE, with vulpea, and save the note."
  (require 'vulpea nil t)
  (unless (fboundp 'vulpea-buffer-alias-add)
    (user-error "vulpea is not loaded; cannot add the alias %s" alias))
  (unless (member alias (sp-bibtex--note-aliases file))
    (with-current-buffer (find-file-noselect file)
      (when (buffer-modified-p)
        (user-error "Save %s first" (file-name-nondirectory file)))
      (vulpea-buffer-alias-add alias)
      (save-buffer))))

(defun sp-bibtex-lint--ask-notes (file batch index total all &optional kind)
  "Show BATCH of names near an author note and ask what to do with the names.
Return ?n to normalise the names in the BibTeX field, ?l to add each as an alias
of the note, ?e to be asked for each name, ?s to skip or ?q to stop.  With ?d
some entries are dropped for later, with ?u dropped ones are brought back."
  (let (choice)
    (while (progn
             (sp-bibtex-lint--show-batch file (or kind 'notes) batch index total all)
             (setq choice
                   (read-char-choice
                    (format "Batch %d of %d (%d entries): [n]ormalise in the field, [l] alias on the note, [e]ach name, [s]kip, [d]rop some for later, [u] bring back, [q]uit "
                            index total (length (sp-bibtex-lint--undropped file batch)))
                    '(?n ?l ?e ?s ?d ?u ?q)))
             (pcase choice
               (?d (sp-bibtex-lint--drop-dialog file batch) t)
               (?u (sp-bibtex-lint--restore-dialog file) t))))
    choice))

(defun sp-bibtex-lint--ask-case (case)
  "Ask what to do with CASE, a list (FIELD NAME NOTE-NAME NOTE-FILE).
Return ?n to normalise, ?l for an alias, ?s to skip or ?q to stop."
  (read-char-choice
   (format "%s is not an author note.  [n]ormalise to %s%s, [s]kip, [q]uit "
           (nth 1 case) (nth 2 case)
           (if (nth 3 case) ", [l] add as alias of the note" ""))
   (if (nth 3 case) '(?n ?l ?s ?q) '(?n ?s ?q))))

(defun sp-bibtex-lint--decide-notes (batch choice &optional kind)
  "The decisions for BATCH of the fix KIND (default `notes') from CHOICE, or `quit'.
A decision is a list (ITEM CASE DECISION), DECISION `normalise' or `alias'.
With ?e each case is asked."
  (catch 'quit
    (let (decisions)
      (dolist (item batch)
        (dolist (case (plist-get (alist-get (or kind 'notes) (nth 4 (car item))) :cases))
          (let ((decision (pcase choice
                            (?n 'normalise)
                            (?l (and (nth 3 case) 'alias))
                            (_ (pcase (sp-bibtex-lint--ask-case case)
                                 (?n 'normalise)
                                 (?l 'alias)
                                 (?q (throw 'quit 'quit))
                                 (_ nil))))))
            (when decision (push (list item case decision) decisions)))))
      (nreverse decisions))))

(defun sp-bibtex-lint--apply-notes (work batch decisions &optional kind)
  "Carry out DECISIONS for BATCH of the fix KIND: rewrite entries in WORK, add aliases.
Return (CHANGED STALE WROTE)."
  (let ((changed 0) (stale 0) (wrote nil) aliases)
    (dolist (d decisions)
      (when (eq (nth 2 d) 'alias)
        (push (cons (nth 3 (nth 1 d)) (nth 1 (nth 1 d))) aliases)))
    (dolist (item batch)
      (when-let* ((cases (mapcar #'cadr (seq-filter (lambda (d) (and (eq (car d) item)
                                                                      (eq (nth 2 d) 'normalise)))
                                                    decisions))))
        (pcase-let ((`(,r ,beg ,end) item))
          (with-current-buffer work
            (if (not (equal (plist-get (alist-get (or kind 'notes) (nth 4 r)) :old)
                            (buffer-substring-no-properties beg end)))
                (cl-incf stale)
              (goto-char beg)
              (let* ((entry (bibtex-parse-entry))
                     (fields (seq-remove (lambda (f) (string-prefix-p "=" (car f))) entry)))
                (sp-bibtex-lint--replace
                 beg end
                 (sp-bibtex--fill-text
                  (sp-bibtex--entry-text (cdr (assoc "=type=" entry)) (cdr (assoc "=key=" entry))
                                         (sp-bibtex--rename-names fields cases)))))
              (cl-incf changed (length cases))
              (setq wrote t))))))
    (dolist (alias (delete-dups aliases))
      (sp-bibtex-lint--add-alias (car alias) (cdr alias))
      (cl-incf changed))
    (when aliases (setq sp-bibtex--people-cache nil))
    (list changed stale wrote)))

(defun sp-bibtex-lint--review-notes (file kind results &optional then)
  "Go through the names of the fix KIND in RESULTS for FILE, a batch at a time.
KIND is `notes' (typos of an author note) or `surnames'.  Each name is
normalised in the BibTeX field, or added as an alias of the note."
  (sp-bibtex-lint--run
   file kind results
   (lambda (batch index total all)
     (pcase (sp-bibtex-lint--ask-notes file batch index total all kind)
       (?s 'skip)
       (?q 'quit)
       (choice (sp-bibtex-lint--decide-notes (sp-bibtex-lint--undropped file batch) choice kind))))
   (lambda (work batch decisions) (sp-bibtex-lint--apply-notes work batch decisions kind))
   then))

;;;###autoload
(defun sp-bibtex-lint-fix-authors (file)
  "Normalise the author and editor names of the .bib FILE, in three steps.
FILE is the .bib file of the current buffer; with a prefix argument, or when
the buffer is not a .bib file, it is read with completion.  Both steps go in
batches of `sp-bibtex-lint-batch-size', with a backup before the first write.
1. Names that are not `Last, First' are rewritten, after you apply a batch.
2. Names one typo away from an author note: for a batch you normalise the name
   in the BibTeX field to the name of the note, add the name as an alias of the
   note (a vulpea alias, so the name is known from then on), or are asked for
   each name.
3. Names with the surname of one author note and given names that fit the
   note's (`TW Adorno' and `Theodor Adorno' for `Theodor W. Adorno'; not
   `Michael Smith' for `John Smith'): the same choices.  A name that fits
   several notes is reported, never changed.
Notes for authors are never made."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (sp-bibtex-lint--unsaved-check file)
  (sp-bibtex-lint--job
   "BibTeX lint" (list file) '(authors)
   (lambda (results)
     (sp-bibtex-lint--review
      file 'authors results
      (lambda ()
        (sp-bibtex-lint--job
         "BibTeX lint" (list file) '(notes)
         (lambda (results)
           (sp-bibtex-lint--review-notes
            file 'notes results
            (lambda ()
              (sp-bibtex-lint--job
               "BibTeX lint" (list file) '(surnames)
               (lambda (results) (sp-bibtex-lint--review-notes file 'surnames results))))))))))))

;;;###autoload
(defun sp-bibtex-lint-convert (file)
  "Ask which fix to run on the .bib FILE.
The fixes are field order, indentation, author names and attachment paths.
See `sp-bibtex-lint-fix-order', `sp-bibtex-lint-fix-indent',
`sp-bibtex-lint-fix-authors' and `sp-bibtex-lint-fix-files'."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (pcase (completing-read "Fix: " '("field order" "indentation" "author names" "attachment paths")
                          nil t)
    ("field order" (sp-bibtex-lint-fix-order file))
    ("indentation" (sp-bibtex-lint-fix-indent file))
    ("author names" (sp-bibtex-lint-fix-authors file))
    ("attachment paths" (sp-bibtex-lint-fix-files file))))

(defun sp-bibtex-author-capf ()
  "Complete a name in an author or editor field from the author notes.
Add to `completion-at-point-functions' in `bibtex-mode'."
  (when-let* ((_ (save-excursion
                             (re-search-backward "^[ \t]*\\([[:alnum:]_-]+\\)[ \t]*=" nil t)))
              (name (match-string-no-properties 1))
              ((member (downcase name) '("author" "editor")))
              (value-start (match-end 0))
              ((string-match-p "[{\"]" (buffer-substring-no-properties value-start (point))))
              (people (sp-bibtex-people)))
    (let* ((end (point))
           (start (save-excursion
                    (if (re-search-backward "\\(?:[{\"]\\|\\band[ \t\n]+\\)" value-start t)
                        (match-end 0)
                      end))))
      (when (<= start end)
        (list start end
              (lambda (string pred action)
                (let ((completion-ignore-case t))
                  (complete-with-action action (plist-get people :names) string pred)))
              :exclusive 'no)))))

(defun sp-bibtex-setup-completion ()
  "Complete author names in this `bibtex-mode' buffer."
  (add-hook 'completion-at-point-functions #'sp-bibtex-author-capf nil t))

(provide 'sp-bibprocess)
;; sp-bibprocess.el ends here
