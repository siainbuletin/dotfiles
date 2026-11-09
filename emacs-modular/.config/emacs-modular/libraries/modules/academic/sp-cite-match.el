;;; sp-cite-match.el --- Match a selected citation to a BibTeX record -*- lexical-binding: t; -*-

;;; Commentary:

;; Fuzzy match of a selected citation (in-text citation or Bibliography entry,
;; in any style) against the BibTeX records, and a `Cited works' section in the
;; litnote.  The text arrives through `org-protocol://sp-cite-match'.
;; Literate source: docs/tangles/academic/sp-cite-match.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'ucs-normalize)
(require 'org-protocol)

(defvar sp-bibtex-files)
(declare-function citar-has-notes "citar")
(declare-function citar-get-notes "citar")
(declare-function sp-author-notes-latex-to-unicode "sp-author-notes")

(defgroup sp-cite-match nil
  "Match a selected citation to a BibTeX record."
  :group 'convenience)

(defcustom sp-cite-match-accept 0.85
  "Score from which the best match is accepted without asking."
  :type 'number :group 'sp-cite-match)

(defcustom sp-cite-match-margin 0.15
  "How far the best score must be ahead of the second to be accepted."
  :type 'number :group 'sp-cite-match)

(defcustom sp-cite-match-minimum 0.55
  "Score below which there is no match."
  :type 'number :group 'sp-cite-match)

(defcustom sp-cite-match-short-limit 2
  "A text with at most this many content words is a short citation.
Short citations such as `Smith 2017' are matched on surname and year only and are
never accepted automatically."
  :type 'integer :group 'sp-cite-match)

(defcustom sp-cite-match-section-title "Cited works"
  "Heading of the section the cited works are written to."
  :type 'string :group 'sp-cite-match)

(defcustom sp-cite-match-note-function #'sp-cite-match-citar-note
  "Function from a citekey to its litnote.
It returns a string (an Org ID or a file name), t when the note exists but cannot
be linked, or nil when there is no litnote."
  :type 'function :group 'sp-cite-match)

(defcustom sp-cite-match-inbox (expand-file-name "~/.cache/sp-cite-match/")
  "Directory where the hotkey script leaves the selected text."
  :type 'directory :group 'sp-cite-match)

(defcustom sp-cite-match-stop-words
  '("a" "an" "the" "of" "and" "in" "on" "for" "to" "from" "with" "by" "at" "as"
    "or" "de" "la" "le" "der" "die" "das" "und" "von" "et" "al" "eds" "ed" "vol"
    "pp" "no" "p")
  "Words ignored when comparing titles."
  :type '(repeat string) :group 'sp-cite-match)

(defconst sp-cite-match--letters
  '((?ø . "o") (?Ø . "o") (?đ . "d") (?Đ . "d") (?ł . "l") (?Ł . "l")
    (?ß . "ss") (?æ . "ae") (?Æ . "ae") (?œ . "oe") (?Œ . "oe") (?ı . "i"))
  "Letters that do not decompose, and what they become.")

(defun sp-cite-match--unlatex (string)
  "STRING with BibTeX accents written as plain letters or Unicode."
  (if (not (string-match-p "\\\\" string))
      string
    (if (fboundp 'sp-author-notes-latex-to-unicode)
        (sp-author-notes-latex-to-unicode string)
      (replace-regexp-in-string
       "\\\\[\"'`^~=.][ ]*{?\\([[:alpha:]]\\)}?" "\\1" string))))

(defun sp-cite-match-normalise (string)
  "STRING as plain lower case words separated by single spaces."
  (let ((s (sp-cite-match--unlatex (or string ""))))
    (setq s (replace-regexp-in-string "[\\{}]" "" s))
    (setq s (replace-regexp-in-string "[-‐‑]\\s-*\n\\s-*" "" s))
    (setq s (ucs-normalize-NFKD-string s))
    (setq s (replace-regexp-in-string (format "[%c-%c]" #x300 #x36f) "" s))
    (setq s (mapconcat (lambda (c) (or (cdr (assq c sp-cite-match--letters)) (string c)))
                       s ""))
    (setq s (downcase s))
    (string-trim (replace-regexp-in-string "[^[:alnum:]]+" " " s))))

(defun sp-cite-match--content-tokens (normalised)
  "The words of NORMALISED that are not stop words."
  (seq-remove (lambda (w) (member w sp-cite-match-stop-words))
              (split-string normalised " " t)))

(defun sp-cite-match--read-value ()
  "Read a BibTeX field value at point and leave point after it."
  (skip-chars-forward " \t\n")
  (let ((start (point)))
    (cond
     ((eq (char-after) ?{)
      (let ((depth 0) (done nil))
        (while (and (not done) (re-search-forward "[{}]" nil t))
          (setq depth (+ depth (if (eq (char-before) ?{) 1 -1)))
          (when (zerop depth) (setq done t)))
        (buffer-substring-no-properties (1+ start) (max (1+ start) (1- (point))))))
     ((eq (char-after) ?\")
      (forward-char 1)
      (let ((depth 0) (begin (point)))
        (while (and (not (eobp)) (or (> depth 0) (not (eq (char-after) ?\"))))
          (cond ((eq (char-after) ?{) (cl-incf depth))
                ((eq (char-after) ?}) (cl-decf depth)))
          (forward-char 1))
        (prog1 (buffer-substring-no-properties begin (point))
          (unless (eobp) (forward-char 1)))))
     (t (skip-chars-forward "^,\n")
        (string-trim (buffer-substring-no-properties start (point)))))))

(defun sp-cite-match--fields (start end)
  "The fields between START and END as an alist of lower case name to value."
  (save-excursion
    (goto-char start)
    (let (fields)
      (while (re-search-forward "\\([[:alpha:]-]+\\)[ \t\n]*=[ \t\n]*" end t)
        (let ((name (downcase (match-string 1))))
          (push (cons name (sp-cite-match--read-value)) fields)))
      fields)))

(defun sp-cite-match--plain (string)
  "STRING without BibTeX braces, accents written as Unicode where possible."
  (let ((s (sp-cite-match--unlatex (or string ""))))
    (string-trim (replace-regexp-in-string "[ \t\n]+" " " (replace-regexp-in-string "[{}]" "" s)))))

(defun sp-cite-match--surnames (authors)
  "The raw surnames in the BibTeX AUTHORS string."
  (let (out)
    (dolist (a (split-string (or authors "") "[ \t\n]+and[ \t\n]+" t))
      (let ((a (string-trim a)))
        (unless (or (string= a "") (string= (downcase a) "others"))
          (push (cond ((string-match-p "\\`{.*}\\'" a) (substring a 1 -1))
                      ((string-match "\\`\\([^,]+\\)," a) (match-string 1 a))
                      (t (car (last (split-string a "[ \t]+" t)))))
                out))))
    (nreverse out)))

(defun sp-cite-match--doi (value)
  "VALUE as a bare lower case DOI, or nil."
  (when (and value (string-match "10\\.[0-9]\\{4,9\\}/[^ \t\n\"<>{}]+" value))
    (downcase (string-trim-right (match-string 0 value) "[.,;)]+"))))

(defun sp-cite-match--label (surnames year title)
  "A readable label from SURNAMES (raw), YEAR and TITLE."
  (format "%s (%s) %s"
          (pcase (length surnames)
            (0 "Anon.") (1 (car surnames))
            (2 (format "%s and %s" (car surnames) (cadr surnames)))
            (_ (format "%s et al." (car surnames))))
          (or year "n.d.") title))

(defun sp-cite-match--candidate (key fields)
  "The candidate plist for the entry KEY with the FIELDS alist."
  (let* ((get (lambda (name) (cdr (assoc name fields))))
         (raw-names (sp-cite-match--surnames
                     (or (funcall get "author") (funcall get "editor"))))
         (names (mapcar #'sp-cite-match--plain raw-names))
         (year (let ((y (or (funcall get "year") (funcall get "date"))))
                 (when (and y (string-match "[0-9]\\{4\\}" y))
                   (string-to-number (match-string 0 y)))))
         (title (sp-cite-match--plain (funcall get "title")))
         (container (or (funcall get "journaltitle") (funcall get "journal")
                        (funcall get "booktitle"))))
    (list :key key
          :year year
          :doi (sp-cite-match--doi (funcall get "doi"))
          :surnames (mapcar #'sp-cite-match-normalise names)
          :title (sp-cite-match-normalise title)
          :main-title (sp-cite-match-normalise (car (split-string title ":" t)))
          :container (when container (sp-cite-match-normalise container))
          :label (sp-cite-match--label names year title))))

(defun sp-cite-match--parse-buffer ()
  "The candidates for the BibTeX entries in the current buffer."
  (let (result)
    (goto-char (point-min))
    (while (re-search-forward
            "^@\\([[:alpha:]]+\\)[ \t]*[{(][ \t]*\\([^, \t\n]+\\)[ \t]*," nil t)
      (unless (member (downcase (match-string 1)) '("comment" "string" "preamble"))
        (let* ((key (match-string 2))
               (start (point))
               (end (save-excursion (if (re-search-forward "^@" nil t)
                                        (line-beginning-position)
                                      (point-max)))))
          (push (sp-cite-match--candidate key (sp-cite-match--fields start end)) result)
          (goto-char end))))
    (nreverse result)))

(defvar sp-cite-match--cache nil
  "Cons of the file stamps and the candidates read from them.")

(defun sp-cite-match-candidates (&optional files)
  "The candidates from FILES, default `sp-bibtex-files', cached until a file changes."
  (let* ((files (or files (bound-and-true-p sp-bibtex-files)))
         (stamp (mapcar (lambda (f) (cons f (file-attribute-modification-time
                                             (file-attributes f))))
                        files)))
    (if (and sp-cite-match--cache (equal (car sp-cite-match--cache) stamp))
        (cdr sp-cite-match--cache)
      (let (all)
        (dolist (f files)
          (when (file-readable-p f)
            (with-temp-buffer
              (insert-file-contents f)
              (setq all (nconc all (sp-cite-match--parse-buffer))))))
        (setq sp-cite-match--cache (cons stamp all))
        all))))

(defun sp-cite-match--analyse (text)
  "The plist describing the selected TEXT."
  (let* ((norm (sp-cite-match-normalise text))
         (tokens (split-string norm " " t))
         (year-re "\\`\\(?:1[5-9]\\|20\\)[0-9][0-9][a-z]?\\'")
         (years (mapcar (lambda (tok) (string-to-number (substring tok 0 4)))
                        (seq-filter (lambda (tok) (string-match-p year-re tok)) tokens)))
         (words (seq-remove (lambda (w) (or (string-match-p year-re w)
                                            (< (length w) 2)))
                            (sp-cite-match--content-tokens norm)))
         (doi (when (string-match "10\\.[0-9]\\{4,9\\}/[^ \t\n\"<>]+" (or text ""))
                (downcase (string-trim-right (match-string 0 text) "[.,;)]+")))))
    (list :text norm
          :padded (concat " " norm " ")
          :tokens tokens
          :years years
          :doi doi
          :etal (string-match-p " et al " (concat " " norm " "))
          :short (<= (length words) sp-cite-match-short-limit))))

(defun sp-cite-match--token-hit (word tokens)
  "1.0 if WORD is in TOKENS, 0.8 if a long word is one edit away, else 0.0."
  (cond ((member word tokens) 1.0)
        ((and (>= (length word) 6)
              (cl-some (lambda (tok)
                         (and (>= (length tok) 6)
                              (<= (abs (- (length tok) (length word))) 1)
                              (<= (string-distance word tok) 1)))
                       tokens))
         0.8)
        (t 0.0)))

(defun sp-cite-match--surname-hit (surname in)
  "How well SURNAME (normalised) is found in the analysed text IN."
  (cond ((string-empty-p surname) 0.0)
        ((string-match-p (concat " " (regexp-quote surname) " ") (plist-get in :padded)) 1.0)
        (t (let ((last (car (last (split-string surname " " t)))))
             (* 0.9 (if last (sp-cite-match--token-hit last (plist-get in :tokens)) 0.0))))))

(defun sp-cite-match--surname-score (surnames in)
  "Score of the candidate SURNAMES against the analysed text IN."
  (if (null surnames)
      0.0
    (let ((first (sp-cite-match--surname-hit (car surnames) in))
          (others (seq-take (cdr surnames) 3)))
      (if (or (null others) (plist-get in :etal))
          first
        (+ (* 0.6 first)
           (* 0.4 (/ (apply #'+ (mapcar (lambda (s) (sp-cite-match--surname-hit s in)) others))
                     (float (length others)))))))))

(defun sp-cite-match--year-score (year in)
  "Score of the candidate YEAR against the analysed text IN."
  (let ((years (plist-get in :years)))
    (cond ((null year) 0.0)
          ((memq year years) 1.0)
          ((cl-some (lambda (y) (= (abs (- y year)) 1)) years) 0.6)
          (t 0.0))))

(defun sp-cite-match--words-score (normalised in)
  "Share of the content words of NORMALISED found in the analysed text IN."
  (let ((words (sp-cite-match--content-tokens normalised)))
    (if (null words)
        0.0
      (/ (apply #'+ (mapcar (lambda (w) (sp-cite-match--token-hit w (plist-get in :tokens)))
                            words))
         (float (length words))))))

(defun sp-cite-match--title-score (cand in)
  "Score of the title of CAND against the analysed text IN."
  (let ((title (plist-get cand :title))
        (main (plist-get cand :main-title))
        (padded (plist-get in :padded)))
    (+ (* 0.7 (sp-cite-match--words-score title in))
       (* 0.3 (if (and (not (string-empty-p main))
                       (or (string-match-p (concat " " (regexp-quote title) " ") padded)
                           (string-match-p (concat " " (regexp-quote main) " ") padded)))
                  1.0 0.0)))))

(defun sp-cite-match--score (in cand)
  "Score from 0 to 1 of the candidate CAND against the analysed text IN."
  (let ((doi (plist-get in :doi)))
    (if (and doi (equal doi (plist-get cand :doi)))
        1.0
      (let ((names (sp-cite-match--surname-score (plist-get cand :surnames) in)))
        (if (<= names 0.0)
            0.0
          (let ((parts (list (cons 0.35 names)
                             (cons 0.15 (sp-cite-match--year-score (plist-get cand :year) in)))))
            (unless (plist-get in :short)
              (push (cons 0.40 (sp-cite-match--title-score cand in)) parts)
              (when (plist-get cand :container)
                (push (cons 0.10 (sp-cite-match--words-score (plist-get cand :container) in))
                      parts)))
            (/ (apply #'+ (mapcar (lambda (p) (* (car p) (cdr p))) parts))
               (apply #'+ (mapcar #'car parts)))))))))

(defun sp-cite-match-text (text &optional candidates)
  "Match TEXT against CANDIDATES, default all the BibTeX records.
Returns (STATUS . RANKED); STATUS is `accept', `ambiguous' or `none'."
  (let* ((in (sp-cite-match--analyse text))
         (ranked nil))
    (dolist (c (or candidates (sp-cite-match-candidates)))
      (let ((s (sp-cite-match--score in c)))
        (when (> s 0.0) (push (cons s c) ranked))))
    (setq ranked (seq-take (sort ranked (lambda (a b) (> (car a) (car b)))) 10))
    (let ((top (car ranked)) (second (cadr ranked)))
      (cons (cond ((or (null top) (< (car top) sp-cite-match-minimum)) 'none)
                  ((and (>= (car top) sp-cite-match-accept)
                        (not (plist-get in :short))
                        (or (null second)
                            (>= (- (car top) (car second)) sp-cite-match-margin)))
                   'accept)
                  (t 'ambiguous))
            ranked))))

(defun sp-cite-match--entry-start-p (line previous)
  "Non-nil if LINE starts a new entry after the entry text PREVIOUS."
  (or (string-match-p "\\`\\(?:\\[[0-9]+\\]\\|[0-9]+[.)]\\)[ \t]" line)
      (and (string-match-p "[.)?\"”]\\'" previous)
           (string-match-p "\\`[[:upper:]][[:alpha:]'’-]+,[ \t]+[[:upper:]]" line))))

(defun sp-cite-match--join (previous line)
  "PREVIOUS and LINE as one string."
  (if (and (string-suffix-p "-" previous)
           (string-match-p "\\`[[:lower:]]" line))
      (concat (substring previous 0 -1) line)
    (concat previous " " line)))

(defun sp-cite-match--split-chunk (chunk)
  "The entries in CHUNK, a block of lines with no blank line."
  (let (entries current)
    (dolist (raw (split-string chunk "\n" t))
      (let ((line (string-trim raw)))
        (if (and current (sp-cite-match--entry-start-p line current))
            (progn (push current entries) (setq current line))
          (setq current (if current (sp-cite-match--join current line) line)))))
    (when current (push current entries))
    (nreverse entries)))

(defun sp-cite-match-split-entries (text)
  "The Bibliography entries in TEXT, one string each."
  (cl-mapcan #'sp-cite-match--split-chunk
             (split-string (replace-regexp-in-string "\r" "" text)
                           "\n[ \t]*\n+" t "[ \t\n]+")))

(defcustom sp-cite-match-status-function #'sp-cite-match-note-status
  "Function from a note (as `sp-cite-match-note-function' returns it) to its reading state.
It returns a plist (:status STRING :priority STRING), or nil."
  :type 'function :group 'sp-cite-match)

(declare-function vulpea-db-get-by-id "vulpea-db")
(declare-function vulpea-note-path "vulpea-note")
(declare-function sp-litnotes-meta--file-meta "sp-litnotes-meta")

(defun sp-cite-match-citar-note (key)
  "The litnote of KEY through citar: an ID or file name, t if it has none to link, or nil."
  (when (and (fboundp 'citar-has-notes) (funcall (citar-has-notes) key))
    (or (ignore-errors
          (let* ((notes (citar-get-notes (list key)))
                 (item (and (hash-table-p notes) (car-safe (gethash key notes)))))
            (and (stringp item) (not (string-empty-p item)) item)))
        t)))

(defun sp-cite-match--note-file (note)
  "The file of NOTE, a file name or an Org ID, or nil."
  (cond ((not (stringp note)) nil)
        ((file-exists-p note) note)
        ((fboundp 'vulpea-db-get-by-id)
         (when-let* ((found (ignore-errors (vulpea-db-get-by-id note))))
           (vulpea-note-path found)))
        ((fboundp 'org-id-find-id-file) (org-id-find-id-file note))))

(defun sp-cite-match-note-status (note)
  "The reading state of NOTE: (:status S :priority P), from its meta lines."
  (when-let* ((file (sp-cite-match--note-file note))
              ((fboundp 'sp-litnotes-meta--file-meta))
              (meta (ignore-errors (sp-litnotes-meta--file-meta file))))
    (let ((status (plist-get meta :read-status))
          (priority (plist-get meta :read-priority)))
      (list :status (unless (equal status "") status)
            :priority (unless (equal priority "") priority)))))

(defun sp-cite-match--note-link (note)
  "The Org text saying whether the litnote NOTE exists, with a link when possible."
  (cond ((null note) "no litnote")
        ((and (stringp note) (string-match-p "\\`[0-9a-fA-F]\\{8\\}-[0-9a-fA-F-]+\\'" note))
         (format "[[id:%s][litnote]]" note))
        ((and (stringp note) (file-exists-p note))
         (format "[[file:%s][litnote]]" note))
        (t "litnote")))

(defun sp-cite-match--info (key)
  "The litnote and reading state of KEY as a plist (:note :status :priority)."
  (let* ((note (ignore-errors (funcall sp-cite-match-note-function key)))
         (state (and note (ignore-errors (funcall sp-cite-match-status-function note)))))
    (list :note note
          :status (plist-get state :status)
          :priority (plist-get state :priority))))

(defcustom sp-cite-match-display 'table
  "How the Cited works section lists the works: `table' or `list'."
  :type '(choice (const table) (const list)) :group 'sp-cite-match)

(defcustom sp-cite-match-summary t
  "Whether to write a summary line above the list of cited works."
  :type 'boolean :group 'sp-cite-match)

(defconst sp-cite-match--begin "# sp-cite-match:begin")
(defconst sp-cite-match--end "# sp-cite-match:end")
(defconst sp-cite-match--header "| Cite | Work | Litnote | read-status | read-priority |")

(defun sp-cite-match--cell (text)
  "TEXT made safe for a table cell."
  (string-trim (replace-regexp-in-string "|" "/" (replace-regexp-in-string "[\n]+" " " (or text "")))))

(defun sp-cite-match--entry (cand)
  "The entry plist for the candidate CAND: its row or bullet and its reading state."
  (let* ((key (plist-get cand :key))
         (info (sp-cite-match--info key))
         (link (sp-cite-match--note-link (plist-get info :note)))
         (status (plist-get info :status))
         (priority (plist-get info :priority)))
    (list :id key :key key :priority priority :status status
          :has-note (and (plist-get info :note) t)
          :label (plist-get cand :label)
          :text (if (eq sp-cite-match-display 'table)
                    (format "| [cite:@%s] | %s | %s | %s | %s |"
                            key (sp-cite-match--cell (plist-get cand :label)) link
                            (or status "") (or priority ""))
                  (format "- [cite:@%s] %s — %s" key (plist-get cand :label) link)))))

(defun sp-cite-match--line-key (line)
  "The citekey in the row or bullet LINE, or nil."
  (when (string-match "\\[cite:@\\([^]; |]+\\)" line)
    (match-string 1 line)))

(defun sp-cite-match--line-entry (line)
  "The entry plist for a LINE kept from an earlier run, without a BibTeX record."
  (let* ((key (sp-cite-match--line-key line))
         (cells (when (string-prefix-p "|" line)
                  (mapcar #'string-trim (split-string (string-trim line "|" "|") "|"))))
         (text (cond ((eq sp-cite-match-display 'list) line)
                     ((string-prefix-p "|" line) line)
                     (key (format "| [cite:@%s] | (not in the bibliography) | | | |" key))
                     (t (format "| TODO unmatched | %s | | | |"
                                (sp-cite-match--cell (replace-regexp-in-string "\\`- TODO unmatched: " "" line)))))))
    (list :id (or key line) :key key :text text
          :priority (let ((p (nth 4 cells))) (and p (not (string-empty-p p)) p))
          :status (let ((p (nth 3 cells))) (and p (not (string-empty-p p)) p))
          :has-note (and key (not (string-match-p "no litnote" line))))))

(defun sp-cite-match--unmatched-entry (text)
  "The entry plist for TEXT, a citation that matched nothing."
  (let ((clean (sp-cite-match--cell text)))
    (list :id (concat "unmatched:" text) :key nil
          :text (if (eq sp-cite-match-display 'table)
                    (format "| TODO unmatched | %s | | | |" clean)
                  (format "- TODO unmatched: %s" clean)))))

(defun sp-cite-match--block-lines ()
  "The kept lines between the markers in the current buffer, and the block bounds."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward (concat "^" (regexp-quote sp-cite-match--begin) "$") nil t)
      (let ((start (1+ (point))))
        (when (re-search-forward (concat "^" (regexp-quote sp-cite-match--end) "$") nil t)
          (let ((end (match-beginning 0)))
            (list (seq-filter
                   (lambda (l) (or (string-prefix-p "- " l)
                                   (and (string-prefix-p "| " l)
                                        (not (string-prefix-p "| Cite " l)))))
                   (split-string (buffer-substring-no-properties start end) "\n" t))
                  start end)))))))

(defun sp-cite-match--summary (entries)
  "The summary line for ENTRIES."
  (let* ((cited (seq-filter (lambda (e) (plist-get e :key)) entries))
         (with-note (seq-count (lambda (e) (plist-get e :has-note)) cited))
         (counts nil))
    (dolist (e cited)
      (when (plist-get e :status)
        (let ((cell (assoc (plist-get e :status) counts)))
          (if cell (cl-incf (cdr cell)) (push (cons (plist-get e :status) 1) counts)))))
    (concat (format "%d cited, %d with litnotes, %d unmatched"
                    (length cited) with-note (- (length entries) (length cited)))
            (when counts
              (concat "; read-status: "
                      (mapconcat (lambda (c) (format "%s %d" (car c) (cdr c)))
                                 (sort counts (lambda (a b) (string< (car a) (car b)))) ", "))))))

(defun sp-cite-match--sort (entries)
  "ENTRIES ordered by read-priority (none last), then by their text."
  (sort (copy-sequence entries)
        (lambda (a b)
          (let ((pa (or (plist-get a :priority) "99"))
                (pb (or (plist-get b :priority) "99")))
            (if (string= pa pb)
                (string< (downcase (plist-get a :text)) (downcase (plist-get b :text)))
              (string< pa pb))))))

(defun sp-cite-match--block-text (entries)
  "The generated block for ENTRIES, markers included."
  (concat sp-cite-match--begin "\n"
          (if sp-cite-match-summary (concat (sp-cite-match--summary entries) "\n") "")
          (when (and entries (eq sp-cite-match-display 'table))
            (concat sp-cite-match--header "\n|-\n"))
          (mapconcat (lambda (e) (plist-get e :text)) (sp-cite-match--sort entries) "\n")
          (if entries "\n" "")
          sp-cite-match--end))

(defun sp-cite-match-write-section (items &optional candidates)
  "Add ITEMS to the Cited works section of the current buffer.
Each item is a candidate plist, or a string for a text that did not match.
CANDIDATES (default all BibTeX records) are used to refresh the old rows."
  (let* ((existing (car (sp-cite-match--block-lines)))
         (cands (or candidates (sp-cite-match-candidates)))
         (by-key (make-hash-table :test 'equal))
         (table (make-hash-table :test 'equal))
         (order nil))
    (dolist (c cands) (puthash (plist-get c :key) c by-key))
    (cl-flet ((add (entry)
                (let ((id (plist-get entry :id)))
                  (unless (gethash id table) (push id order))
                  (puthash id entry table))))
      (dolist (line existing)
        (let* ((key (sp-cite-match--line-key line))
               (cand (and key (gethash key by-key))))
          (add (if cand (sp-cite-match--entry cand) (sp-cite-match--line-entry line)))))
      (dolist (item items)
        (add (if (stringp item)
                 (sp-cite-match--unmatched-entry item)
               (sp-cite-match--entry item)))))
    (let* ((entries (mapcar (lambda (id) (gethash id table)) (nreverse order)))
           (body (sp-cite-match--block-text entries))
           (found (sp-cite-match--block-lines)))
      (save-excursion
        (if found
            (progn
              (goto-char (1- (nth 1 found)))
              (delete-region (point) (1+ (nth 2 found)))
              (delete-region (line-beginning-position) (line-end-position))
              (insert body)
              (when (and (not (eobp)) (not (eq (char-after) ?\n))) (insert "\n")))
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (format "\n* %s\n%s\n" sp-cite-match-section-title body)))
        (when (and (eq sp-cite-match-display 'table) (derived-mode-p 'org-mode)
                   (re-search-backward (concat "^" (regexp-quote sp-cite-match--header)) nil t))
          (ignore-errors (org-table-align))))
      (length entries))))

(defun sp-cite-match-refresh-section ()
  "Re-check the litnote and reading state of every work in the Cited works section."
  (interactive)
  (unless (sp-cite-match--block-lines) (user-error "No Cited works section in this buffer"))
  (message "Cited works: %d" (sp-cite-match-write-section nil)))

(defun sp-cite-match--target-buffer ()
  "The Org file buffer the cited works are written to."
  (let ((org-file (lambda (b) (with-current-buffer b
                                (and (derived-mode-p 'org-mode) buffer-file-name b)))))
    (or (funcall org-file (window-buffer (selected-window)))
        (seq-some org-file (buffer-list))
        (user-error "No Org file buffer to write the cited works into"))))

(defun sp-cite-match--choose (ranked)
  "Ask which of RANKED, a list of (SCORE . CANDIDATE), is meant.  Nil to skip."
  (let* ((labels (mapcar (lambda (r) (cons (format "%.2f  %s" (car r) (plist-get (cdr r) :label))
                                           (cdr r)))
                         ranked))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      '(metadata (display-sort-function . identity))
                    (complete-with-action action (cons "skip" (mapcar #'car labels))
                                          string pred))))
         (choice (completing-read "Cited work: " table nil t)))
    (cdr (assoc choice labels))))

(defun sp-cite-match--resolve (text candidates)
  "The candidate for TEXT, asking if needed, or nil."
  (let* ((result (sp-cite-match-text text candidates))
         (ranked (cdr result)))
    (pcase (car result)
      ('accept (cdar ranked))
      ('ambiguous (sp-cite-match--choose ranked))
      (_ nil))))

;;;###autoload
(defun sp-cite-match-selection (text &optional insert)
  "Match the citation TEXT (the region, or typed) to a BibTeX record.
The record is added to the Cited works section of the Org file; with INSERT (a
prefix argument) the citation is inserted at point instead."
  (interactive (list (if (use-region-p)
                         (buffer-substring-no-properties (region-beginning) (region-end))
                       (read-string "Citation: "))
                     current-prefix-arg))
  (let ((cand (sp-cite-match--resolve text (sp-cite-match-candidates))))
    (cond
     ((null cand) (message "sp-cite-match: no match for \"%s\"" (truncate-string-to-width text 50)) nil)
     (insert (insert (format "[cite:@%s]" (plist-get cand :key))) cand)
     (t (let ((buffer (sp-cite-match--target-buffer)))
          (with-current-buffer buffer (sp-cite-match-write-section (list cand)))
          (message "sp-cite-match: %s added to %s" (plist-get cand :label) (buffer-name buffer))
          cand)))))

(defun sp-cite-match--report (results)
  "Show RESULTS, a list of (ENTRY STATUS RANKED), in a report buffer."
  (with-current-buffer (get-buffer-create "*sp-cite-match*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "%d entries\n\n" (length results)))
      (dolist (r results)
        (pcase-let ((`(,entry ,status ,ranked) r))
          (insert (format "%-9s %s\n" status (truncate-string-to-width entry 90 nil nil "…")))
          (when ranked
            (insert (format "          -> %.2f  %s\n" (caar ranked) (plist-get (cdar ranked) :label))))))
      (goto-char (point-min))
      (special-mode))
    (display-buffer (current-buffer))))

;;;###autoload
(defun sp-cite-match-bibliography (text)
  "Match every entry of the Bibliography TEXT and write them to Cited works.
A report is shown first and nothing is written until you confirm."
  (interactive (list (if (use-region-p)
                         (buffer-substring-no-properties (region-beginning) (region-end))
                       (read-string "Bibliography: "))))
  (let* ((candidates (sp-cite-match-candidates))
         (results (mapcar (lambda (e) (let ((m (sp-cite-match-text e candidates)))
                                        (list e (car m) (cdr m))))
                          (sp-cite-match-split-entries text)))
         (buffer (sp-cite-match--target-buffer)))
    (sp-cite-match--report results)
    (when (y-or-n-p (format "Write %d entries to %s? " (length results) (buffer-name buffer)))
      (let (items)
        (dolist (r results)
          (pcase-let ((`(,entry ,status ,ranked) r))
            (push (pcase status
                    ('accept (cdar ranked))
                    ('ambiguous (or (sp-cite-match--choose ranked) entry))
                    (_ entry))
                  items)))
        (with-current-buffer buffer
          (message "sp-cite-match: %d works in %s"
                   (sp-cite-match-write-section (nreverse items) candidates)
                   (buffer-name buffer)))))))

;;;###autoload
(defun sp-cite-match-handle (text)
  "Match TEXT: several Bibliography entries as a list, one as a single citation."
  (if (cdr (sp-cite-match-split-entries text))
      (sp-cite-match-bibliography text)
    (sp-cite-match-selection text)))

(defun sp-cite-match--protocol-text (info)
  "The text in the org-protocol INFO plist, or nil."
  (let ((name (plist-get info :file)))
    (cond
     (name
      (when (or (string-match-p "/" name) (string-prefix-p "." name))
        (user-error "sp-cite-match: refused file name %s" name))
      (let ((file (expand-file-name name sp-cite-match-inbox)))
        (when (file-readable-p file)
          (prog1 (with-temp-buffer (insert-file-contents file) (buffer-string))
            (ignore-errors (delete-file file))))))
     (t (plist-get info :text)))))

(defun sp-cite-match-protocol (info)
  "Handle org-protocol://sp-cite-match?file=NAME (or ?text=...)."
  (let ((text (sp-cite-match--protocol-text info)))
    (if (and text (not (string-blank-p text)))
        (run-with-timer 0.1 nil
                        (lambda ()
                          (raise-frame)
                          (sp-cite-match-handle text)))
      (message "sp-cite-match: nothing was selected")))
  nil)

(add-to-list 'org-protocol-protocol-alist
             '("sp-cite-match" :protocol "sp-cite-match"
               :function sp-cite-match-protocol :kill-client t))

;;; Provide

(provide 'sp-cite-match)
;;; sp-cite-match.el ends here
