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

(defun sp-bibtex--make-people (titles)
  "The index of the person TITLES: a plist of :names, :keys and :buckets."
  (let ((keys (make-hash-table :test #'equal))
        (buckets (make-hash-table :test #'equal))
        names)
    (dolist (title titles)
      (let* ((canonical (sp-bibtex-canonical-name title))
             (key (sp-bibtex--name-key canonical)))
        (unless (gethash key keys)
          (puthash key canonical keys)
          (push canonical names)
          (push canonical (gethash (sp-bibtex--bucket key) buckets)))))
    (list :names (sort names #'string<) :keys keys :buckets buckets
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
                (sp-bibtex--make-people
                 (mapcar (lambda (head) (plist-get head :title))
                         (sp-author-notes-bibtex--people))))))
  (cdr sp-bibtex--people-cache))

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

(defun sp-bibtex--lint-fields (fields people)
  "Lint the FIELDS, an alist of name and raw value.
Return (NEW-FIELDS . PROBLEMS): the fields with canonical names, in the
configured order, and a list of strings that say what differs."
  (let (problems new)
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
                  (when-let* ((near (sp-bibtex--suggestion n people)))
                    (push (format "%s: %s is not an author note; did you mean %s?" name n near)
                          problems)))))))
        (push (cons name value) new)))
    (setq new (nreverse new))
    (let ((sorted (sort (copy-sequence new)
                        (lambda (a b) (< (sp-bibtex--field-rank (car a))
                                         (sp-bibtex--field-rank (car b)))))))
      (unless (equal (mapcar #'car sorted) (mapcar #'car new))
        (push (format "fields: %s → %s" (string-join (mapcar #'car new) " ")
                      (string-join (mapcar #'car sorted) " "))
              problems))
      (cons sorted (nreverse problems)))))

(defun sp-bibtex--entry-text (type key fields)
  "The text of the entry TYPE, KEY and FIELDS (an alist of name and raw value)."
  (let ((width (apply #'max 1 (mapcar (lambda (f) (length (car f))) fields))))
    (concat "@" type "{" key ",\n"
            (mapconcat (lambda (f)
                         (format "  %s%s = %s," (car f)
                                 (make-string (- width (length (car f))) ?\s) (cdr f)))
                       fields "\n")
            "\n}")))

(defun sp-bibtex--lint-chunk (file limit people seen)
  "Lint the entries from point in the current buffer, at most LIMIT of them.
Return (RESULTS . MORE).  RESULTS lists (FILE KEY POSITION PROBLEMS REWRITE);
MORE is non-nil when LIMIT was reached.  SEEN is a hash table of the keys met
so far.  REWRITE is nil for an entry that is only reported, else a list
(END OLD NEW): where the entry ends, its text and the text
`sp-bibtex-lint-convert' would put in its place.  The buffer is not changed."
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
                   (linted (sp-bibtex--lint-fields fields people))
                   (problems (cdr linted))
                   (commented (save-excursion
                                (goto-char beg)
                                (re-search-forward "^[ \t]*%" end t))))
              (when-let* ((first (gethash key seen)))
                (push (format "duplicate key (also in %s)" (file-name-nondirectory first)) problems))
              (puthash key (or (gethash key seen) file) seen)
              (when commented
                (setq problems (append problems '("has a comment inside, left as it is"))))
              (when problems
                (push (list file key beg problems
                            (and (not commented)
                                 (not (equal fields (car linted)))
                                 (cl-some (lambda (p) (string-match-p "^\\(author\\|editor\\|fields\\):" p))
                                          (cdr linted))
                                 (list end (buffer-substring-no-properties beg end)
                                       (sp-bibtex--entry-text type key (car linted)))))
                      results))
              (goto-char end))))))
    (cons (nreverse results) (>= count limit))))

(defconst sp-bibtex-lint--buffer "*BibTeX lint*")
(defconst sp-bibtex-lint--batch-buffer "*BibTeX lint batch*")

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

(defun sp-bibtex-lint--job (name files done)
  "Run the lint job NAME over FILES, without changing them.
DONE gets the list of (FILE KEY POSITION PROBLEMS REWRITE)."
  (let ((people (condition-case nil (sp-bibtex-people) (error nil)))
        (seen (make-hash-table :test #'equal))
        all)
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
                       (let ((result (sp-bibtex--lint-chunk file 100 people seen)))
                         (setq all (append all (car result)))
                         (if (cdr result)
                             (sp-async-work-push job (cons file buffer))
                           (kill-buffer buffer))))))))
     :done (lambda (_job) (funcall done all)))))

(defun sp-bibtex-lint--backup (file stamp)
  "Copy FILE to the STAMP sub-folder of `sp-bibtex-lint-backup-directory'."
  (let ((dir (expand-file-name (concat stamp "/") sp-bibtex-lint-backup-directory)))
    (make-directory dir t)
    (copy-file file (expand-file-name (file-name-nondirectory file) dir) t)))

(defun sp-bibtex-lint--entry-text (result link)
  "The Org text for the lint RESULT: a heading and its problems.
LINK is the Org link to the entry, or nil."
  (concat "* " (or link (nth 1 result)) "\n"
          (mapconcat (lambda (p) (concat "- " p "\n")) (nth 3 result) "")))

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

(defun sp-bibtex-lint--render (file results)
  "Show RESULTS, a list of (FILE KEY POSITION PROBLEMS REWRITE) of FILE, as a report."
  (let ((lines (sp-bibtex-lint--lines file (mapcar (lambda (r) (nth 2 r)) results)))
        (fixable (length (seq-filter (lambda (r) (nth 4 r)) results))))
    (sp-batch-report-show
     sp-bibtex-lint--buffer
     (concat
      (format "#+title: BibTeX lint of %s\n\n" (file-name-nondirectory file))
      (format "- %d entr%s to look at in %s; %d can be rewritten.\n"
              (length results) (if (= 1 (length results)) "y" "ies")
              (sp-batch-report-file-link file) fixable)
      (format "- =RET= visits an entry, =g= refreshes, =M-x sp-bibtex-lint-convert= rewrites in batches of %d.\n"
              sp-bibtex-lint-batch-size)
      (mapconcat (lambda (r)
                   (concat "\n" (sp-bibtex-lint--entry-text
                                 r (sp-batch-report-file-link file (nth 1 r)
                                                              (pop lines)))))
                 results ""))
     (lambda () (sp-bibtex-lint-dryrun file)))))

;;;###autoload
(defun sp-bibtex-lint-dryrun (file)
  "List what the .bib FILE breaks, without changing it.
FILE is the .bib file of the current buffer; with a prefix argument, or when
the buffer is not a .bib file, it is read with completion.  It checks the author
and editor names (canonical form `Last, First', and names one typo away from an
author note), the order of the fields (`sp-bibtex-field-order') and duplicate
keys.  Notes for authors are never made."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (sp-bibtex-lint--job "BibTeX lint" (list file)
                       (lambda (results) (sp-bibtex-lint--render file results))))

(defun sp-bibtex-lint--ask-batch (file batch index total all)
  "Show BATCH, number INDEX of TOTAL in FILE, and ask what to do with it.
BATCH is a list of (RESULT BEG END); ALL is the number of entries in every
batch.  Return ?a to apply, ?s to skip or ?q to stop."
  (let ((lines (sp-bibtex-lint--lines file (mapcar (lambda (item) (nth 2 (car item))) batch))))
    (sp-batch-report-show
     sp-bibtex-lint--batch-buffer
     (concat
      (format "#+title: BibTeX rewrite of %s, batch %d of %d\n\n" (file-name-nondirectory file) index total)
      (format "- %d entr%s in this batch, %d in all.\n" (length batch)
              (if (= 1 (length batch)) "y" "ies") all)
      "- Each entry's names and field order are rewritten as listed; nothing else changes.\n"
      (mapconcat (lambda (item)
                   (let ((r (car item)))
                     (concat "\n" (sp-bibtex-lint--entry-text
                                   r (sp-batch-report-file-link file (nth 1 r) (pop lines))))))
                 batch ""))))
  (read-char-choice
   (format "Batch %d of %d (%d entries): [a]pply, [s]kip, [q]uit " index total (length batch))
   '(?a ?s ?q)))

(defun sp-bibtex-lint--apply-batch (work batch)
  "Rewrite the entries of BATCH in the buffer WORK.
BATCH is a list of (RESULT BEG END) with markers.  An entry whose text is no
longer the one that was linted is left alone.  Return (CHANGED . STALE)."
  (let ((changed 0) (stale 0))
    (with-current-buffer work
      (dolist (item batch)
        (pcase-let ((`(,r ,beg ,end) item))
          (pcase-let ((`(,_end ,old ,new) (nth 4 r)))
            (if (not (equal old (buffer-substring-no-properties beg end)))
                (cl-incf stale)
              (goto-char beg)
              (delete-region beg end)
              (insert new)
              (cl-incf changed))))))
    (cons changed stale)))

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

(defun sp-bibtex-lint--review (file results)
  "Go through the rewrites in RESULTS for FILE, `sp-bibtex-lint-batch-size' at a time.
Nothing is written without an answer of \"apply\" for a batch.  FILE is copied
to `sp-bibtex-lint-backup-directory' before the first batch is written, and
written again after each applied batch."
  (let* ((fixable (seq-filter (lambda (r) (nth 4 r)) results))
         (work (generate-new-buffer " *sp-bibtex-lint-work*")))
    (if (null fixable)
        (message "BibTeX lint: nothing to rewrite in %s (%d entr%s to look at by hand)"
                 (file-name-nondirectory file) (length results)
                 (if (= 1 (length results)) "y" "ies"))
      (unwind-protect
          (let* ((items (with-current-buffer work
                          (insert-file-contents file)
                          (mapcar (lambda (r)
                                    (list r (copy-marker (nth 2 r)) (copy-marker (car (nth 4 r)))))
                                  fixable)))
                 (batches (seq-partition items (max 1 sp-bibtex-lint-batch-size)))
                 (total (length batches))
                 (stamp (format-time-string "%Y%m%dT%H%M%S"))
                 (signature (sp-bibtex-lint--signature file))
                 (index 0) (applied 0) (skipped 0) (stale 0) (backed-up nil) (stop nil))
            (while (and batches (not stop))
              (let* ((batch (pop batches))
                     (choice (sp-bibtex-lint--ask-batch file batch (cl-incf index) total
                                                        (length items))))
                (pcase choice
                  (?a
                   (when-let* ((visiting (find-buffer-visiting file))
                               ((buffer-modified-p visiting)))
                     (user-error "Save %s first" (file-name-nondirectory file)))
                   (unless (equal signature (sp-bibtex-lint--signature file))
                     (user-error "%s changed on disk since it was linted; run the command again"
                                 (file-name-nondirectory file)))
                   (unless backed-up
                     (sp-bibtex-lint--backup file stamp)
                     (setq backed-up t))
                   (let ((done (sp-bibtex-lint--apply-batch work batch)))
                     (cl-incf applied (car done))
                     (cl-incf stale (cdr done))
                     (sp-bibtex-lint--save work file)
                     (setq signature (sp-bibtex-lint--signature file))))
                  (?s (cl-incf skipped (length batch)))
                  (_ (setq stop t)
                     (cl-incf skipped (length batch))))))
            (message "BibTeX lint of %s: %d rewritten, %d skipped, %d not reached%s%s"
                     (file-name-nondirectory file) applied skipped
                     (apply #'+ (mapcar #'length batches))
                     (if (> stale 0) (format ", %d changed since the lint" stale) "")
                     (if backed-up
                         (format "; backup in %s" (abbreviate-file-name sp-bibtex-lint-backup-directory))
                       "")))
        (kill-buffer work)))))

;;;###autoload
(defun sp-bibtex-lint-convert (file)
  "Rewrite names and field order in one .bib FILE, in batches, after asking.
FILE is the .bib file of the current buffer; with a prefix argument, or when
the buffer is not a .bib file, it is read with completion.  The entries to
rewrite are shown `sp-bibtex-lint-batch-size' at a time; for each batch you
apply it, skip it or quit.  Nothing is written without an \"apply\", and FILE
is copied to `sp-bibtex-lint-backup-directory' before the first write.
Duplicate keys and names near an author note are reported, not changed; an
entry with a comment inside is left alone."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (when-let* ((visiting (find-buffer-visiting file))
              ((buffer-modified-p visiting)))
    (user-error "Save %s first" (file-name-nondirectory file)))
  (sp-bibtex-lint--job "BibTeX lint" (list file)
                       (lambda (results) (sp-bibtex-lint--review file results))))

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
