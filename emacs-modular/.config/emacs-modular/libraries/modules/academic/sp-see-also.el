;;; sp-see-also.el --- "See also" footnotes of litnotes: scan, cache, priority -*- lexical-binding: t; -*-

;;; Commentary:

;; A see-also footnote is an Org footnote that holds an `id:' link: inline,
;; `[fn::[[id:...][Concept]]]', or a definition, `[fn:1] ... [[id:...][Concept]]'.
;; This module finds them without visiting the file (a temporary buffer, no mode, no hook), keeps them in a cache keyed by
;; the modification time and size of each file, and ranks the concepts and the
;; open research questions they point at.
;; The two dashboards are in `sp-see-also-widget' and `org-dblock-write:concept-usage'.
;; See docs/tangles/academic/sp-see-also.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar sp-cache-dir)
(defvar sp-notes-dir)
(defvar sp-org-keywords-research)

(declare-function vulpea-db-query-by-tags-some "vulpea-db")
(declare-function vulpea-db-query-links-to "vulpea-db")
(declare-function vulpea-db-get-by-id "vulpea-db")
(declare-function vulpea-note-path "vulpea-note")
(declare-function vulpea-note-title "vulpea-note")
(declare-function org-entry-get "org")
(declare-function org-reveal "org")

(defgroup sp-see-also nil
  "See-also footnotes of litnotes."
  :group 'sp-academic)

(defcustom sp-see-also-litnote-tag "litnote"
  "Tag of the notes whose footnotes are read."
  :type 'string)

(defcustom sp-see-also-directory
  (expand-file-name "litnotes/" (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes"))
  "Folder with the litnotes, used when Vulpea cannot list them."
  :type 'directory)

(defcustom sp-see-also-files-function #'sp-see-also-default-files
  "Function without arguments that returns the files to read."
  :type 'function)

(defcustom sp-see-also-use-db t
  "When non-nil, ask the Vulpea database which files link to a concept."
  :type 'boolean)

(defcustom sp-see-also-cache-file
  (expand-file-name "see-also-index.eld"
                    (if (boundp 'sp-cache-dir) sp-cache-dir user-emacs-directory))
  "File that keeps the see-also footnotes of each file between sessions.
Each file is stored with its modification time and size."
  :type 'file)

(defcustom sp-see-also-index-max-age 60
  "Seconds the whole-vault index is reused before it is checked again."
  :type 'number)

(defcustom sp-see-also-open-keywords nil
  "Keywords of an open question; nil means those of `sp-org-keywords-research'."
  :type '(repeat string))

(defcustom sp-see-also-closed-keywords nil
  "Keywords of a closed question; nil means those of `sp-org-keywords-research'."
  :type '(repeat string))

(defcustom sp-see-also-where-weights '((prose . 1.0) (quote . 2.0))
  "Weight of a mention by the place it was written."
  :type '(alist :key-type symbol :value-type number))

(defcustom sp-see-also-question-weights
  '(("QUESTION" . 3.0) ("SCOPING" . 2.5) ("READING" . 2.0)
    ("SYNTHESIZING" . 1.5) ("REVIEW" . 1.0))
  "Weight added to a mention under an open question with that keyword."
  :type '(alist :key-type string :value-type number))

(defcustom sp-see-also-concept-score-function #'sp-see-also-default-concept-score
  "Function that scores a concept, called with (ID MENTIONS CONTEXT).
MENTIONS are the mentions of the concept in the litnote looked at.  CONTEXT is a
plist; :other-litnotes is how many other litnotes mention the concept, or nil
when the index has not been built.  A higher number comes first."
  :type 'function)

(defcustom sp-see-also-question-priority-function
  #'sp-see-also-default-question-priority
  "Function that scores an open question, called with (QUESTION MENTIONS).
QUESTION is a plist with :keyword, :title and :pos.  MENTIONS are the see-also
mentions under it.  A higher number comes first."
  :type 'function)

(defconst sp-see-also--fallback-states
  '(("QUESTION" "SCOPING" "READING" "SYNTHESIZING" "REVIEW")
    "STABLE" "ANSWERED" "DROPPED")
  "Open and closed question keywords when `sp-org-keywords-research' is absent.")

(defun sp-see-also--states ()
  "Return (OPEN . CLOSED), the keywords of an open and of a closed question."
  (let* ((sequence (and (boundp 'sp-org-keywords-research)
                        (car sp-org-keywords-research)))
         (words (mapcar (lambda (word) (replace-regexp-in-string "(.*)\\'" "" word))
                        (cdr sequence)))
         (bar (member "|" words))
         (open (if sequence
                   (seq-take-while (lambda (word) (not (equal word "|"))) words)
                 (car sp-see-also--fallback-states)))
         (closed (if sequence (cdr bar) (cdr sp-see-also--fallback-states))))
    (cons (or sp-see-also-open-keywords open)
          (or sp-see-also-closed-keywords closed))))

(defun sp-see-also--plain (string)
  "Return STRING with Org links reduced to their text and footnotes removed."
  (let* ((s (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" string))
         (s (replace-regexp-in-string "\\[\\[[^]]*\\]\\]" "" s))
         (s (replace-regexp-in-string "\\[fn:[^]]*\\(?:\\]\\|\\'\\)" "" s))
         (s (replace-regexp-in-string "[ \t\n]+" " " s)))
    (string-trim s)))

(defun sp-see-also--in-ranges-p (pos ranges)
  "Return non-nil when POS is inside one of RANGES, a list of (BEG . END)."
  (seq-some (lambda (range) (and (>= pos (car range)) (< pos (cdr range)))) ranges))

(defun sp-see-also--block-ranges ()
  "Return (SKIP . QUOTE), the ranges of the blocks that matter for footnotes.
SKIP are source, example, export and comment blocks, which are not read;
QUOTE are quote and verse blocks."
  (let ((case-fold-search t)
        skip quote)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              "^[ \t]*#\\+begin_\\([[:alpha:]]+\\)\\(?:[ \t].*\\)?$" nil t)
        (let* ((name (downcase (match-string 1)))
               (start (match-beginning 0))
               (after (match-end 0))
               (end-regexp (format "^[ \t]*#\\+end_%s[ \t]*$" (regexp-quote name)))
               (end (save-excursion
                      (goto-char after)
                      (if (re-search-forward end-regexp nil t) (match-end 0) (point-max)))))
          (cond ((member name '("src" "example" "export" "comment"))
                 (push (cons start end) skip)
                 (goto-char end))
                ((member name '("quote" "verse"))
                 (push (cons start end) quote))))))
    (cons (nreverse skip) (nreverse quote))))

(defun sp-see-also--drawer-id ()
  "Return the :ID: of the property drawer on the line at point, or nil."
  (when (looking-at "[ \t]*:PROPERTIES:[ \t]*$")
    (let ((end (save-excursion
                 (and (re-search-forward "^[ \t]*:END:" nil t) (point)))))
      (when (and end (re-search-forward "^[ \t]*:ID:[ \t]+\\([^ \t\n]+\\)" end t))
        (match-string-no-properties 1)))))

(defun sp-see-also--heading-id ()
  "Return the :ID: of the entry whose heading line is at point, or nil."
  (save-excursion
    (forward-line 1)
    (while (looking-at "[ \t]*\\(?:SCHEDULED\\|DEADLINE\\|CLOSED\\):")
      (forward-line 1))
    (sp-see-also--drawer-id)))

(defun sp-see-also--headings (keywords skip)
  "Return the headings of the buffer in order, outside the SKIP ranges.
Each is a plist of :pos, :level, :keyword (when it is one of KEYWORDS), :title
and :id."
  (let ((case-fold-search nil)
        headings)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*+\\)[ \t]+\\(.*\\)$" nil t)
        (let ((pos (match-beginning 0))
              (level (length (match-string 1)))
              (rest (match-string-no-properties 2)))
          (unless (sp-see-also--in-ranges-p pos skip)
            (let* ((keyword (and (string-match "\\`\\([[:upper:]]+\\)\\(?:[ \t]+\\|\\'\\)" rest)
                                 (member (match-string 1 rest) keywords)
                                 (match-string 1 rest)))
                   (title (replace-regexp-in-string
                           "[ \t]+:[[:alnum:]_@#%:]+:[ \t]*\\'" ""
                           (replace-regexp-in-string
                            "\\`\\(?:[[:upper:]]+[ \t]+\\)?\\(?:\\[#[A-Z0-9]\\][ \t]*\\)?" ""
                            rest t t)
                           t t)))
              (push (list :pos pos :level level :keyword keyword
                          :title (sp-see-also--plain title)
                          :id (sp-see-also--heading-id))
                    headings))))))
    (nreverse headings)))

(defun sp-see-also--footnote-end (start limit)
  "Return the position after the footnote that starts at START, or nil.
START is at the opening bracket.  The footnote must close before LIMIT, and
brackets inside it must be balanced."
  (save-excursion
    (goto-char (1+ start))
    (let ((depth 1))
      (while (and (> depth 0)
                  (skip-chars-forward "^][" limit)
                  (< (point) limit))
        (if (eq (char-after) ?\[) (setq depth (1+ depth)) (setq depth (1- depth)))
        (forward-char 1))
      (and (= depth 0) (point)))))

(defun sp-see-also--commented-p (pos)
  "Return non-nil when POS is on an Org comment line."
  (save-excursion
    (goto-char pos)
    (beginning-of-line)
    (looking-at "[ \t]*#\\(?: \\|$\\)")))

(defun sp-see-also--footnotes-raw (skip)
  "Return the inline footnotes of the buffer outside the SKIP ranges.
Each is a plist of :beg, :end, :label and :text, in order."
  (let ((case-fold-search t)
        footnotes)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "\\[fn:\\([-_[:word:]]*\\):" nil t)
        (let* ((beg (match-beginning 0))
               (label (let ((name (match-string-no-properties 1)))
                        (and (not (string-empty-p name)) name)))
               (text-beg (match-end 0))
               (limit (save-excursion
                        (goto-char text-beg)
                        (if (re-search-forward "\n[ \t]*\n" nil t)
                            (match-beginning 0)
                          (point-max))))
               (end (sp-see-also--footnote-end beg limit)))
          (when (and end
                     (not (sp-see-also--in-ranges-p beg skip))
                     (not (sp-see-also--commented-p beg))
                     (not (memq (char-before beg) '(?= ?~))))
            (push (list :beg beg :end end :label label
                        :text (buffer-substring-no-properties text-beg (1- end)))
                  footnotes)
            (goto-char end)))))
    (nreverse footnotes)))

;; Definition footnotes (`[fn:1]' in the text, `[fn:1] ...' below) are the form
;; that Org writes for numbered notes; the litnotes of the real vault use them.

(defun sp-see-also--definition-end (text-beg)
  "Return where the footnote definition whose text starts at TEXT-BEG ends.
Like Org, it ends at the next definition, the next heading, two blank lines or
the end of the buffer."
  (save-excursion
    (goto-char text-beg)
    (let ((end (point-max)))
      (when (re-search-forward
             "\\(?:\n\\[fn:[-_[:word:]]+\\]\\|\n\\*+[ \t]\\|\n[ \t]*\n[ \t]*\n\\)" nil t)
        (setq end (1+ (match-beginning 0))))
      (while (and (> end text-beg) (memq (char-before end) '(?\n ?\s ?\t)))
        (setq end (1- end)))
      end)))

(defun sp-see-also--reference-range (label avoid skip)
  "Return (BEG . END) of the first reference `[fn:LABEL]' outside AVOID and SKIP.
AVOID is a list of (BEG . END) ranges, those of the definitions."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t)
          (regexp (format "\\[fn:%s\\]" (regexp-quote label)))
          found)
      (while (and (not found) (re-search-forward regexp nil t))
        (let ((beg (match-beginning 0)))
          (unless (or (sp-see-also--in-ranges-p beg avoid)
                      (sp-see-also--in-ranges-p beg skip)
                      (sp-see-also--commented-p beg))
            (setq found (cons beg (match-end 0))))))
      found)))

(defun sp-see-also--definitions-raw (skip)
  "Return the footnote definitions of the buffer outside the SKIP ranges.
Each is a plist of :beg and :end (the first reference to it, or the definition
itself when nothing refers to it), :def-beg, :def-end, :label and :text."
  (let ((case-fold-search t)
        defs result)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\[fn:\\([-_[:word:]]+\\)\\]" nil t)
        (let ((beg (match-beginning 0)))
          (unless (or (sp-see-also--in-ranges-p beg skip)
                      (sp-see-also--commented-p beg))
            (let* ((label (match-string-no-properties 1))
                   (text-beg (match-end 0))
                   (end (sp-see-also--definition-end text-beg)))
              (push (list beg end label
                          (string-trim (buffer-substring-no-properties text-beg end)))
                    defs)
              (goto-char (max end text-beg)))))))
    (setq defs (nreverse defs))
    (let ((avoid (mapcar (lambda (d) (cons (nth 0 d) (nth 1 d))) defs)))
      (dolist (d defs)
        (let ((ref (sp-see-also--reference-range (nth 2 d) avoid skip)))
          (push (list :beg (if ref (car ref) (nth 0 d))
                      :end (if ref (cdr ref) (nth 1 d))
                      :def-beg (nth 0 d) :def-end (nth 1 d)
                      :label (nth 2 d) :text (nth 3 d))
                result))))
    (nreverse result)))

(defun sp-see-also--footnotes-all (skip)
  "Return the inline and the definition footnotes outside SKIP, ordered by :beg."
  (sort (append (sp-see-also--footnotes-raw skip)
                (sp-see-also--definitions-raw skip))
        (lambda (a b) (< (plist-get a :beg) (plist-get b :beg)))))

(defun sp-see-also--links (text)
  "Return the `id:' links of TEXT as a list of (ID . DESCRIPTION)."
  (let ((start 0)
        links)
    (while (string-match "\\[\\[id:\\([^]\n]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\]" text start)
      (let ((id (match-string 1 text))
            (desc (match-string 2 text))
            (next (match-end 0)))
        (push (cons (replace-regexp-in-string "::.*\\'" "" id) desc) links)
        (setq start next)))
    (nreverse links)))

(defun sp-see-also--snippet (beg end)
  "Return the text around the footnote from BEG to END, cleaned of markup."
  (let* ((bol (save-excursion (goto-char beg) (line-beginning-position)))
         (eol (save-excursion (goto-char end) (line-end-position)))
         (before (buffer-substring-no-properties (max bol (- beg 100)) beg))
         (after (buffer-substring-no-properties end (min eol (+ end 40)))))
    (sp-see-also--plain (concat before after))))

;;;###autoload
(defun sp-see-also-parse-buffer (&optional buffer)
  "Return the see-also footnotes of BUFFER (default the current one), in order.
A see-also footnote is an inline or definition footnote with an `id:' link.
For a definition, :beg and :end are its first reference, :def-beg and :def-end
the definition.  Each is a plist:
:beg, :end, :label, :text, :links (a list of (ID . DESCRIPTION)), :snippet,
:where (`quote' or `prose'), :question (keyword of the nearest question
heading above, or nil), :open (non-nil when that question is open),
:question-title, :question-pos, :heading, :heading-id.
Nothing is moved, narrowed for good or changed, and no mode is needed."
  (with-current-buffer (or buffer (current-buffer))
    (save-restriction
      (widen)
      (save-excursion
        (let* ((states (sp-see-also--states))
               (keywords (append (car states) (cdr states)))
               (ranges (sp-see-also--block-ranges))
               (raw (delq nil
                          (mapcar (lambda (footnote)
                                    (when-let* ((links (sp-see-also--links
                                                        (plist-get footnote :text))))
                                      (append footnote (list :links links))))
                                  (sp-see-also--footnotes-all (car ranges)))))
               (headings (and raw (sp-see-also--headings keywords (car ranges))))
               stack result)
          (dolist (footnote raw)
            (let ((beg (plist-get footnote :beg)))
              (while (and headings (< (plist-get (car headings) :pos) beg))
                (let ((heading (pop headings)))
                  (while (and stack (>= (plist-get (car stack) :level)
                                        (plist-get heading :level)))
                    (pop stack))
                  (push heading stack)))
              (let ((question (seq-find (lambda (h) (plist-get h :keyword)) stack))
                    (nearest (car stack))
                    (with-id (seq-find (lambda (h) (plist-get h :id)) stack)))
                (push (append
                       footnote
                       (list :snippet (sp-see-also--snippet beg (plist-get footnote :end))
                             :where (if (sp-see-also--in-ranges-p beg (cdr ranges))
                                        'quote 'prose)
                             :question (and question (plist-get question :keyword))
                             :open (and question
                                        (member (plist-get question :keyword) (car states))
                                        t)
                             :question-title (and question (plist-get question :title))
                             :question-pos (and question (plist-get question :pos))
                             :heading (and nearest (plist-get nearest :title))
                             :heading-id (and with-id (plist-get with-id :id))))
                      result))))
          (nreverse result))))))

(defun sp-see-also-mentions-in-buffer (&optional buffer)
  "Return one mention for each concept link of each footnote in BUFFER.
A mention is the footnote plist of `sp-see-also-parse-buffer' without :text and
:links, plus :id (the concept) and :desc (the text of the link)."
  (let (mentions)
    (dolist (footnote (sp-see-also-parse-buffer buffer))
      (let ((base (copy-sequence footnote)))
        (cl-remf base :text)
        (cl-remf base :links)
        (dolist (link (plist-get footnote :links))
          (push (append (list :id (car link) :desc (cdr link)) base) mentions))))
    (nreverse mentions)))

(defconst sp-see-also--cache-version 2
  "Version of the cache format; raise it when the mentions change.")

(defvar sp-see-also--files nil
  "Hash table from a file to (MTIME SIZE DATA), or nil until used.")

(defvar sp-see-also--signature nil
  "What the entries of `sp-see-also--files' were read with.")

(defvar sp-see-also--dirty nil
  "Non-nil when `sp-see-also--files' has changes not yet saved.")

(defvar sp-see-also--save-timer nil
  "Idle timer that saves the cache.")

(defvar sp-see-also--index nil
  "The whole-vault index: (:time TIME :files COUNT :concepts HASH), or nil.")

(defun sp-see-also--signature-now ()
  "Return what decides how a file is read: the format and the keywords."
  (list sp-see-also--cache-version (sp-see-also--states)))

(defun sp-see-also--table ()
  "Return the table of cached files, read from disk the first time."
  (unless sp-see-also--files
    (let ((table (make-hash-table :test #'equal)))
      (condition-case nil
          (when (file-readable-p sp-see-also-cache-file)
            (let ((data (with-temp-buffer
                          (insert-file-contents sp-see-also-cache-file)
                          (read (current-buffer)))))
              (setq sp-see-also--signature (plist-get data :signature))
              (dolist (item (plist-get data :files))
                (puthash (car item) (cdr item) table))))
        (error (clrhash table)))
      (setq sp-see-also--files table)))
  (let ((signature (sp-see-also--signature-now)))
    (unless (equal signature sp-see-also--signature)
      (clrhash sp-see-also--files)
      (setq sp-see-also--signature signature
            sp-see-also--index nil
            sp-see-also--dirty t)))
  sp-see-also--files)

(defun sp-see-also--save-if-dirty ()
  "Write the cache to `sp-see-also-cache-file' when it changed."
  (when (and sp-see-also--dirty sp-see-also--files)
    (let (items)
      (maphash (lambda (file value) (push (cons file value) items)) sp-see-also--files)
      (condition-case err
          (progn
            (make-directory (file-name-directory sp-see-also-cache-file) t)
            (with-temp-file sp-see-also-cache-file
              (let ((print-length nil)
                    (print-level nil))
                (prin1 (list :signature sp-see-also--signature :files items)
                       (current-buffer))))
            (setq sp-see-also--dirty nil))
        (error (message "[see-also] could not write the cache: %s"
                        (error-message-string err)))))))

(defun sp-see-also--schedule-save ()
  "Save the cache when Emacs has been idle for a moment."
  (unless sp-see-also--save-timer
    (setq sp-see-also--save-timer
          (run-with-idle-timer 3 nil
                               (lambda ()
                                 (setq sp-see-also--save-timer nil)
                                 (sp-see-also--save-if-dirty))))))

;;;###autoload
(defun sp-see-also-clear-cache ()
  "Forget every cached file, in memory and on disk."
  (interactive)
  (setq sp-see-also--files (make-hash-table :test #'equal)
        sp-see-also--signature (sp-see-also--signature-now)
        sp-see-also--index nil
        sp-see-also--dirty nil)
  (when (file-exists-p sp-see-also-cache-file)
    (delete-file sp-see-also-cache-file))
  (message "[see-also] cache cleared"))

(defun sp-see-also--file-stamp (file)
  "Return (MTIME SIZE) of FILE, the key its data is cached under, or nil."
  (when-let* ((attributes (and (file-readable-p file) (file-attributes file))))
    (list (float-time (file-attribute-modification-time attributes))
          (file-attribute-size attributes))))

(defun sp-see-also--scan-buffer ()
  "Return the data of the current buffer: :id, :title and :mentions."
  (save-restriction
    (widen)
    (save-excursion
      (goto-char (point-min))
      (let ((case-fold-search t))
        (list :id (sp-see-also--drawer-id)
              :title (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" nil t)
                       (string-trim (match-string-no-properties 1)))
              :mentions (sp-see-also-mentions-in-buffer))))))

(defun sp-see-also--scan-file (file unsaved)
  "Return the data of FILE, or nil when it cannot be read.
FILE is read from disk in a temporary buffer in `fundamental-mode', so no
buffer is left behind and no hook runs.  When UNSAVED, the buffer visiting FILE
is read instead."
  (condition-case nil
      (if unsaved
          (with-current-buffer (get-file-buffer file)
            (sp-see-also--scan-buffer))
        (with-temp-buffer
          (insert-file-contents file)
          (sp-see-also--scan-buffer)))
    (error nil)))

(defun sp-see-also-file-data (file)
  "Return the see-also data of FILE: (:id ID :title TITLE :mentions MENTIONS).
It comes from the cache unless the file changed since it was read; nil when FILE
cannot be read."
  (let* ((file (expand-file-name file))
         (table (sp-see-also--table))
         (stamp (sp-see-also--file-stamp file))
         (cached (gethash file table))
         (unsaved (when-let* ((buffer (get-file-buffer file)))
                    (buffer-modified-p buffer))))
    (cond ((not stamp) nil)
          ((and cached (not unsaved) (equal (seq-take cached 2) stamp))
           (nth 2 cached))
          (t (when-let* ((data (sp-see-also--scan-file file unsaved)))
               (unless unsaved
                 (puthash file (append stamp (list data)) table)
                 (setq sp-see-also--dirty t)
                 (sp-see-also--schedule-save))
               data)))))

(defun sp-see-also-default-files ()
  "Return the litnote files: by tag from Vulpea, else from the litnote folder."
  (let ((paths (and (fboundp 'vulpea-db-query-by-tags-some)
                    (ignore-errors
                      (mapcar #'vulpea-note-path
                              (vulpea-db-query-by-tags-some
                               (list sp-see-also-litnote-tag)))))))
    (or (delete-dups (seq-filter #'file-exists-p (delq nil paths)))
        (and (file-directory-p sp-see-also-directory)
             (directory-files-recursively sp-see-also-directory "\\`[^.].*\\.org\\'")))))

(defun sp-see-also--decorate (file data mention)
  "Return MENTION with the :file, :litnote-id and :litnote-title it was found in."
  (append (list :file file
                :litnote-id (plist-get data :id)
                :litnote-title (plist-get data :title))
          mention))

(defun sp-see-also-index (&optional refresh)
  "Return the index of the whole vault: (:time TIME :files COUNT :concepts HASH).
HASH maps a concept id to its mentions (see `sp-see-also--decorate').  The index
is reused for `sp-see-also-index-max-age' seconds unless REFRESH."
  (if (and sp-see-also--index
           (not refresh)
           (< (- (float-time) (plist-get sp-see-also--index :time))
              sp-see-also-index-max-age))
      sp-see-also--index
    (let ((concepts (make-hash-table :test #'equal))
          (count 0))
      (dolist (file (funcall sp-see-also-files-function))
        (when-let* ((data (sp-see-also-file-data file)))
          (setq count (1+ count))
          (dolist (mention (plist-get data :mentions))
            (let ((id (plist-get mention :id)))
              (puthash id (cons (sp-see-also--decorate file data mention)
                                (gethash id concepts))
                       concepts)))))
      (sp-see-also--save-if-dirty)
      (setq sp-see-also--index (list :time (float-time) :files count :concepts concepts)))))

;;;###autoload
(defun sp-see-also-reindex ()
  "Read every litnote again where it changed and rebuild the index."
  (interactive)
  (let* ((started (float-time))
         (index (sp-see-also-index t)))
    (message "[see-also] %d files, %d concepts, in %.2fs"
             (plist-get index :files)
             (hash-table-count (plist-get index :concepts))
             (- (float-time) started))))

(defun sp-see-also--other-litnotes (id file)
  "Return how many files other than FILE mention concept ID, or nil if unknown.
Only the index already in memory is used; it is never built here."
  (when sp-see-also--index
    (let ((others (seq-remove (lambda (file-name) (equal file-name file))
                              (delete-dups
                               (mapcar (lambda (m) (plist-get m :file))
                                       (gethash id (plist-get sp-see-also--index :concepts)))))))
      (length others))))

(defun sp-see-also-mention-weight (mention)
  "Return the weight of MENTION: its place, plus its open question."
  (+ (or (alist-get (plist-get mention :where) sp-see-also-where-weights) 1.0)
     (if (plist-get mention :open)
         (or (cdr (assoc (plist-get mention :question) sp-see-also-question-weights)) 0)
       0)))

(defun sp-see-also-default-concept-score (_id mentions context)
  "Score a concept from the weights of its MENTIONS and the litnotes sharing it.
See `sp-see-also-concept-score-function' for CONTEXT."
  (* (apply #'+ (mapcar #'sp-see-also-mention-weight mentions))
     (1+ (log (1+ (or (plist-get context :other-litnotes) 0))))))

(defun sp-see-also-default-question-priority (question mentions)
  "Score an open QUESTION: the weight of its keyword times the footnotes under it."
  (* (or (cdr (assoc (plist-get question :keyword) sp-see-also-question-weights)) 0)
     (length mentions)))

(defun sp-see-also--concept-title (id mentions)
  "Return the title of concept ID: its note's, else the text MENTIONS use for it."
  (or (and (fboundp 'vulpea-db-get-by-id)
           (when-let* ((note (ignore-errors (vulpea-db-get-by-id id))))
             (vulpea-note-title note)))
      (let ((counts (make-hash-table :test #'equal))
            best)
        (dolist (mention mentions)
          (when-let* ((desc (plist-get mention :desc)))
            (puthash desc (1+ (gethash desc counts 0)) counts)))
        (maphash (lambda (desc n)
                   (when (or (null best) (> n (cdr best)))
                     (setq best (cons desc n))))
                 counts)
        (car best))
      id))

(defun sp-see-also--by-id (mentions)
  "Return MENTIONS grouped by concept id, as an alist of (ID . MENTIONS) in order."
  (let (groups)
    (dolist (mention mentions)
      (let* ((id (plist-get mention :id))
             (cell (assoc id groups)))
        (if cell
            (setcdr cell (append (cdr cell) (list mention)))
          (push (list id mention) groups))))
    (nreverse groups)))

;;;###autoload
(defun sp-see-also-concepts-for-file (file)
  "Return the see-also concepts of FILE, best score first.
Each is a plist of :id, :title, :score, :count, :quotes (mentions in quotes),
:questions (mentions under an open question), :other-litnotes and :mentions."
  (when-let* ((data (sp-see-also-file-data file)))
    (let (concepts)
      (dolist (group (sp-see-also--by-id (plist-get data :mentions)))
        (let* ((id (car group))
               (mentions (cdr group))
               (others (sp-see-also--other-litnotes id (expand-file-name file)))
               (score (funcall sp-see-also-concept-score-function id mentions
                               (list :file file :other-litnotes others))))
          (push (list :id id
                      :title (sp-see-also--concept-title id mentions)
                      :score score
                      :count (length mentions)
                      :quotes (seq-count (lambda (m) (eq (plist-get m :where) 'quote)) mentions)
                      :questions (seq-count (lambda (m) (plist-get m :open)) mentions)
                      :other-litnotes others
                      :mentions mentions)
                concepts)))
      (sort concepts
            (lambda (a b)
              (let ((sa (plist-get a :score))
                    (sb (plist-get b :score)))
                (if (= sa sb)
                    (string< (plist-get a :title) (plist-get b :title))
                  (> sa sb))))))))

;;;###autoload
(defun sp-see-also-questions-for-file (file)
  "Return the open questions of FILE that hold see-also footnotes, best first.
Each is a plist of :keyword, :title, :pos, :priority, :count, :concepts (ids)
and :mentions."
  (when-let* ((data (sp-see-also-file-data file)))
    (let (groups questions)
      (dolist (mention (plist-get data :mentions))
        (when (and (plist-get mention :open) (plist-get mention :question-pos))
          (let* ((pos (plist-get mention :question-pos))
                 (cell (assq pos groups)))
            (if cell
                (setcdr cell (append (cdr cell) (list mention)))
              (push (list pos mention) groups)))))
      (dolist (group groups)
        (let* ((mentions (cdr group))
               (first (car mentions))
               (question (list :keyword (plist-get first :question)
                               :title (plist-get first :question-title)
                               :pos (car group))))
          (push (append question
                        (list :priority (funcall sp-see-also-question-priority-function
                                                 question mentions)
                              :count (length mentions)
                              :concepts (delete-dups
                                         (mapcar (lambda (m) (plist-get m :id)) mentions))
                              :mentions mentions))
                questions)))
      (sort questions (lambda (a b) (> (plist-get a :priority) (plist-get b :priority)))))))

(defun sp-see-also--db-files (id)
  "Return the files that link to concept ID according to Vulpea, or nil."
  (when (and sp-see-also-use-db
             (fboundp 'vulpea-db-query-links-to)
             (fboundp 'vulpea-db-get-by-id))
    (ignore-errors
      (delete-dups
       (delq nil
             (mapcar (lambda (link)
                       (when-let* ((source (plist-get link :source))
                                   (note (vulpea-db-get-by-id source)))
                         (vulpea-note-path note)))
                     (vulpea-db-query-links-to id)))))))

;;;###autoload
(defun sp-see-also-concept-usage (id)
  "Return the litnotes that mention concept ID in a see-also footnote.
A list of plists, most mentions first: :file, :id, :title and :mentions (in file
order).  The Vulpea database narrows the files to read; when it has no answer
the whole-vault index is used."
  (let* ((files (sp-see-also--db-files id))
         (mentions
          (if files
              (cl-loop for file in files
                       for data = (sp-see-also-file-data file)
                       when data
                       append (mapcar (lambda (m) (sp-see-also--decorate file data m))
                                      (seq-filter (lambda (m) (equal (plist-get m :id) id))
                                                  (plist-get data :mentions))))
            (gethash id (plist-get (sp-see-also-index) :concepts))))
         groups result)
    (dolist (mention mentions)
      (let* ((file (plist-get mention :file))
             (cell (assoc file groups)))
        (if cell
            (setcdr cell (append (cdr cell) (list mention)))
          (push (list file mention) groups))))
    (dolist (group groups)
      (let ((mentions (sort (cdr group)
                            (lambda (a b) (< (plist-get a :beg) (plist-get b :beg)))))
            (file (car group)))
        (push (list :file file
                    :id (plist-get (car mentions) :litnote-id)
                    :title (or (plist-get (car mentions) :litnote-title)
                               (file-name-base file))
                    :mentions mentions)
              result)))
    (sort result
          (lambda (a b)
            (let ((na (length (plist-get a :mentions)))
                  (nb (length (plist-get b :mentions))))
              (if (= na nb)
                  (string< (plist-get a :title) (plist-get b :title))
                (> na nb)))))))

(defun sp-see-also--filter-usage (usage where open)
  "Keep the mentions of USAGE in WHERE and, when OPEN, under an open question."
  (delq nil
        (mapcar (lambda (entry)
                  (let ((kept (seq-filter
                               (lambda (m)
                                 (and (or (null where) (eq (plist-get m :where) where))
                                      (or (not open) (plist-get m :open))))
                               (plist-get entry :mentions))))
                    (and kept (plist-put (copy-sequence entry) :mentions kept))))
                usage)))

(defun sp-see-also--cell (string)
  "Return STRING safe for a table cell."
  (replace-regexp-in-string "|" "\\vert{}" (or string "") t t))

(defun sp-see-also-usage-table (usage)
  "Return an Org table with a row for each mention in USAGE."
  (let ((rows nil))
    (dolist (entry usage)
      (let ((link (if (plist-get entry :id)
                      (format "[[id:%s][%s]]" (plist-get entry :id)
                              (sp-see-also--cell (plist-get entry :title)))
                    (format "[[file:%s][%s]]" (plist-get entry :file)
                            (sp-see-also--cell (plist-get entry :title))))))
        (dolist (m (plist-get entry :mentions))
          (push (format "| %s | %s | %s | %s |"
                        link
                        (plist-get m :where)
                        (sp-see-also--cell
                         (if (plist-get m :open)
                             (format "%s %s" (plist-get m :question)
                                     (plist-get m :question-title))
                           (or (plist-get m :heading) "")))
                        (sp-see-also--cell (plist-get m :snippet)))
                rows))))
    (concat "| Litnote | Where | Under | Context |\n|-\n"
            (mapconcat #'identity (nreverse rows) "\n"))))

(defun sp-see-also--id-at-point ()
  "Return the :ID: of the entry at point, or of the file."
  (require 'org)
  (org-entry-get nil "ID" t))

(defun org-dblock-write:concept-usage (params)
  "Write the litnotes that mention a concept into the current dynamic block.
PARAMS: :id is the concept (default the note the block is in), :where `quote' or
`prose' keeps only those places, :open t keeps only the mentions under an open
question.

  #+BEGIN: concept-usage :id \"ID\" :where quote
  #+END:"
  (let* ((id (or (plist-get params :id) (sp-see-also--id-at-point)
                 (user-error "This block is in no note with an ID; give :id")))
         (usage (sp-see-also--filter-usage (sp-see-also-concept-usage id)
                                           (plist-get params :where)
                                           (plist-get params :open))))
    (insert (if usage
                (sp-see-also-usage-table usage)
              "No litnote mentions this concept in a see-also footnote."))))

(defun sp-see-also-visit (file pos)
  "Show FILE with point at POS, in another window."
  (let ((buffer (find-file-noselect file)))
    (pop-to-buffer buffer)
    (widen)
    (goto-char pos)
    (when (fboundp 'org-reveal) (org-reveal))))

;;;###autoload
(defun sp-see-also-show (&optional file)
  "Show the see-also concepts and open questions of FILE in a buffer.
FILE defaults to the file of the current buffer.  This needs no sidebar."
  (interactive)
  (let* ((file (or file buffer-file-name (user-error "This buffer visits no file")))
         (concepts (sp-see-also-concepts-for-file file))
         (questions (sp-see-also-questions-for-file file)))
    (with-current-buffer (get-buffer-create "*see-also*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "See also: %s\n\n" (file-name-nondirectory file)))
        (if (null concepts)
            (insert "No see-also footnotes found.\n")
          (dolist (c concepts)
            (insert (format "%5.1f  %s  x%d  quotes %d  questions %d\n"
                            (plist-get c :score) (plist-get c :title)
                            (plist-get c :count) (plist-get c :quotes)
                            (plist-get c :questions)))))
        (when questions
          (insert "\nOpen questions\n")
          (dolist (q questions)
            (insert (format "%5.1f  %s %s  (%d)\n" (plist-get q :priority)
                            (plist-get q :keyword) (plist-get q :title)
                            (plist-get q :count)))))
        (goto-char (point-min))
        (special-mode)))
    (pop-to-buffer "*see-also*")))

;;;###autoload
(defun sp-see-also-show-concept (id)
  "Show the litnotes that mention concept ID in a see-also footnote.
Interactively, ID is the :ID: of the entry at point."
  (interactive (list (progn (require 'org) (or (org-entry-get nil "ID" t)
                                               (read-string "Concept ID: ")))))
  (let ((usage (sp-see-also-concept-usage id)))
    (with-current-buffer (get-buffer-create "*see-also-concept*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Concept %s\n\n" (sp-see-also--concept-title id nil)))
        (if (null usage)
            (insert "No litnote mentions this concept in a see-also footnote.\n")
          (dolist (entry usage)
            (insert (format "%s (%d)\n" (plist-get entry :title)
                            (length (plist-get entry :mentions))))
            (dolist (m (plist-get entry :mentions))
              (insert (format "   %s  %s\n" (plist-get m :where)
                              (plist-get m :snippet))))))
        (goto-char (point-min))
        (special-mode)))
    (pop-to-buffer "*see-also-concept*")))

(with-eval-after-load 'vulpea-ui
  (condition-case err
      (require 'sp-see-also-widget)
    (error (message "[see-also] the sidebar widgets could not load: %s"
                    (error-message-string err)))))

(provide 'sp-see-also)
;;; sp-see-also.el ends here
