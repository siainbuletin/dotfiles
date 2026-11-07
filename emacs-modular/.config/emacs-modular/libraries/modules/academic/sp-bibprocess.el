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

(defun sp-bibtex--lint-chunk (file limit people apply seen)
  "Lint the entries from point in the current buffer, at most LIMIT of them.
Return (RESULTS . MORE).  RESULTS lists (FILE KEY POSITION PROBLEMS); MORE is
non-nil when LIMIT was reached.  SEEN is a hash table of the keys met so far.
With APPLY the entries that differ are replaced in the buffer."
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
                (push (list file key beg problems) results))
              (if (and apply (not commented)
                       (not (equal fields (car linted)))
                       (or (cl-some (lambda (p) (string-match-p "^\\(author\\|editor\\|fields\\):" p))
                                    (cdr linted))))
                  (let ((text (sp-bibtex--entry-text type key (car linted))))
                    (goto-char beg)
                    (delete-region beg end)
                    (insert text))
                (goto-char end)))))))
    (cons (nreverse results) (>= count limit))))

(defconst sp-bibtex-lint--buffer "*BibTeX lint*")

(defun sp-bibtex-lint--files ()
  "The .bib files to lint; a `user-error' says what is wrong when there are none."
  (let ((files (seq-filter #'file-readable-p
                           (if (boundp 'sp-bibtex-files) sp-bibtex-files nil))))
    (or files
        (user-error "No readable BibTeX files in `sp-bibtex-files'; run `sp-bibtex-register'"))))

(defun sp-bibtex-lint--job (name files apply done)
  "Run the lint job NAME over FILES; with APPLY write the changes.
DONE gets the list of (FILE KEY POSITION PROBLEMS)."
  (let ((people (condition-case nil (sp-bibtex-people) (error nil)))
        (seen (make-hash-table :test #'equal))
        (stamp (format-time-string "%Y%m%dT%H%M%S"))
        all)
    (sp-async-work-run
     name
     (list (list (if apply "rewriting BibTeX" "reading BibTeX") (lambda () files)
                 (lambda (item job)
                   (let* ((file (if (consp item) (car item) item))
                          (buffer (if (consp item)
                                      (cdr item)
                                    (let ((b (generate-new-buffer " *sp-bibtex-lint*")))
                                      (sp-async-work-on-cleanup job (lambda () (when (buffer-live-p b) (kill-buffer b))))
                                      (when apply (sp-bibtex-lint--backup file stamp))
                                      (with-current-buffer b
                                        (insert-file-contents file)
                                        (delay-mode-hooks (bibtex-mode))
                                        (goto-char (point-min)))
                                      b))))
                     (with-current-buffer buffer
                       (let ((result (sp-bibtex--lint-chunk file 100 people apply seen)))
                         (setq all (append all (car result)))
                         (if (cdr result)
                             (sp-async-work-push job (cons file buffer))
                           (when (and apply (buffer-modified-p))
                             (write-region (point-min) (point-max) file nil 'silent)
                             (when-let* ((visiting (find-buffer-visiting file)))
                               (unless (buffer-modified-p visiting)
                                 (with-current-buffer visiting (revert-buffer t t t)))))
                           (kill-buffer buffer))))))))
     :done (lambda (_job) (funcall done all)))))

(defun sp-bibtex-lint--backup (file stamp)
  "Copy FILE to the STAMP sub-folder of `sp-bibtex-lint-backup-directory'."
  (let ((dir (expand-file-name (concat stamp "/") sp-bibtex-lint-backup-directory)))
    (make-directory dir t)
    (copy-file file (expand-file-name (file-name-nondirectory file) dir) t)))

(defvar sp-bibtex-lint-report-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'sp-bibtex-lint-visit)
    (define-key map (kbd "g") #'sp-bibtex-lint-dryrun)
    map)
  "Keymap of `sp-bibtex-lint-report-mode'.")

(define-derived-mode sp-bibtex-lint-report-mode special-mode "BibTeX lint"
  "Report of `sp-bibtex-lint-dryrun'.
\\{sp-bibtex-lint-report-mode-map}")

(defun sp-bibtex-lint--render (results)
  "Show RESULTS, a list of (FILE KEY POSITION PROBLEMS), in the report buffer."
  (with-current-buffer (get-buffer-create sp-bibtex-lint--buffer)
    (sp-bibtex-lint-report-mode)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "BibTeX lint: %d entr%s to fix.  RET visit   g refresh   M-x sp-bibtex-lint-convert to rewrite\n"
                      (length results) (if (= 1 (length results)) "y" "ies")))
      (dolist (r results)
        (let ((start (point)))
          (insert (format "\n* %s  [%s]\n" (nth 1 r) (file-name-nondirectory (nth 0 r))))
          (dolist (p (nth 3 r)) (insert "  - " p "\n"))
          (put-text-property start (point) 'sp-bibtex-entry r)))
      (goto-char (point-min)))
    (pop-to-buffer (current-buffer))))

(defun sp-bibtex-lint-visit ()
  "Visit the BibTeX entry of the section at point."
  (interactive)
  (let ((r (or (get-text-property (point) 'sp-bibtex-entry)
               (user-error "No entry here"))))
    (find-file-other-window (nth 0 r))
    (goto-char (nth 2 r))))

;;;###autoload
(defun sp-bibtex-lint-dryrun ()
  "List what the .bib files of `sp-bibtex-files' break, without changing them.
It checks the author and editor names (canonical form `Last, First', and
names one typo away from an author note), the order of the fields
(`sp-bibtex-field-order') and duplicate keys.  Notes for authors are never made."
  (interactive)
  (let ((files (sp-bibtex-lint--files)))
    (sp-bibtex-lint--job "BibTeX lint" files nil #'sp-bibtex-lint--render)))

(define-obsolete-function-alias 'sp-bibtex-lint-report 'sp-bibtex-lint-dryrun "2026-11-07")

;;;###autoload
(defun sp-bibtex-lint-convert ()
  "Rewrite names and field order in the .bib files after one question.
Each file is copied to `sp-bibtex-lint-backup-directory' first.  Duplicate
keys and names near an author note are reported, not changed; an entry with a
comment inside is left alone."
  (interactive)
  (let ((files (sp-bibtex-lint--files)))
    (when (seq-find #'buffer-modified-p (delq nil (mapcar #'find-buffer-visiting files)))
      (user-error "Save the open .bib buffers first"))
    (when (yes-or-no-p (format "Rewrite names and field order in %d .bib file%s (backups in %s)? "
                               (length files) (if (cdr files) "s" "")
                               sp-bibtex-lint-backup-directory))
      (sp-bibtex-lint--job "BibTeX rewrite" files t
                           (lambda (results)
                             (message "BibTeX rewrite done; %d entr%s still to look at (run sp-bibtex-lint-dryrun)"
                                      (length results) (if (= 1 (length results)) "y" "ies")))))))

(define-obsolete-function-alias 'sp-bibtex-lint-apply 'sp-bibtex-lint-convert "2026-11-07")

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
