;;; sp-devonthink.el --- DEVONthink records from Org and litnotes -*- lexical-binding: t; -*-

;;; Commentary:

;; A `devonthink:UUID::PAGE' Org link, the `#+devonthink:' keyword of a litnote
;; and the commands that open a record from them.  macOS only.
;; Literate source: docs/tangles/academic/sp-devonthink.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'sp-reading)

(declare-function citar-select-ref "citar")

(defvar citar-embark-map)

(defgroup sp-devonthink nil
  "DEVONthink records from Org and litnotes."
  :group 'sp-academic)

(defcustom sp-devonthink-keyword "devonthink"
  "Name of the litnote keyword (=#+NAME:=) that holds the record's UUID."
  :type 'string :group 'sp-devonthink)

(defcustom sp-devonthink-store-page-offset 0
  "Number added to the page DEVONthink reports when a link is stored."
  :type 'integer :group 'sp-devonthink)

(defcustom sp-devonthink-page-offset 0
  "Number added to a printed page to get the PDF page, for chapters in a parent's PDF.
PDF page minus printed page; see `sp-devonthink-parent-page-offsets'."
  :type 'integer :group 'sp-devonthink)

(defcustom sp-devonthink-parent-page-offsets nil
  "Alist of (PARENT-CITEKEY . OFFSET) overriding `sp-devonthink-page-offset'."
  :type '(alist :key-type string :value-type integer) :group 'sp-devonthink)

(declare-function citar-get-value "citar")

;;;; Links

(defconst sp-devonthink--uuid-regexp
  "\\`[0-9A-Fa-f]\\{8\\}\\(?:-[0-9A-Fa-f]\\{4\\}\\)\\{3\\}-[0-9A-Fa-f]\\{12\\}\\'"
  "The shape of a DEVONthink UUID.")

(defun sp-devonthink--uuid-p (string)
  "Non-nil when STRING looks like a DEVONthink UUID."
  (and (stringp string) (string-match-p sp-devonthink--uuid-regexp string)))

(defun sp-devonthink-link-path (uuid &optional page)
  "The path of a `devonthink:' link to UUID, at PAGE (counted from 1) if given."
  (if page (format "%s::%d" uuid page) uuid))

(defun sp-devonthink--parse-path (path)
  "Split PATH into (UUID . PAGE); PAGE is an integer from 1, or nil."
  (let* ((parts (split-string path "::"))
         (uuid (car parts))
         (page (cadr parts)))
    (unless (sp-devonthink--uuid-p uuid)
      (user-error "Not a DEVONthink UUID: %s" uuid))
    (when (and page (not (string-empty-p page)))
      (unless (string-match-p "\\`[1-9][0-9]*\\'" page)
        (user-error "Bad page in devonthink link: %s" page))
      (setq page (string-to-number page)))
    (cons uuid (and (integerp page) page))))

(defun sp-devonthink-url (path)
  "The DEVONthink item URL for the link PATH (page counted from 1 in PATH)."
  (let ((parsed (sp-devonthink--parse-path path)))
    (sp-reading--url (car parsed) (and (cdr parsed) (1- (cdr parsed))))))

(defun sp-devonthink-follow (path &optional _arg)
  "Open the link PATH in DEVONthink."
  (sp-reading--open-url (sp-devonthink-url path)))

(defun sp-devonthink-export (path description _backend &optional _info)
  "Export the link PATH as its DESCRIPTION, which reads as a citation."
  (or description (format "DEVONthink %s" path)))

(org-link-set-parameters "devonthink"
                         :follow #'sp-devonthink-follow
                         :export #'sp-devonthink-export)

;;;; The litnote keyword

(defun sp-devonthink--keyword-regexp ()
  "A regexp matching the keyword line; group 1 is its value."
  (format "^#\\+%s:[ \t]*\\(.*?\\)[ \t]*$" (regexp-quote sp-devonthink-keyword)))

(defun sp-devonthink-note-uuid (&optional buffer)
  "The UUID in the `#+devonthink:' keyword of BUFFER (default: current), or nil."
  (with-current-buffer (or buffer (current-buffer))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (let ((case-fold-search t))
          (when (re-search-forward (sp-devonthink--keyword-regexp) nil t)
            (let ((value (match-string-no-properties 1)))
              (and (not (string-empty-p value)) value))))))))

(defun sp-devonthink-note-citekey (&optional buffer)
  "The citekey of the litnote in BUFFER (default: current), or nil."
  (with-current-buffer (or buffer (current-buffer))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (let ((case-fold-search t))
          (or (when (re-search-forward "^[ \t]*:ROAM_REFS:[ \t]*\\(.*\\)$" nil t)
                (let ((refs (match-string-no-properties 1)))
                  (cond ((string-match "@\\([^] \t,;]+\\)" refs) (match-string 1 refs))
                        ((string-match "cite:\\([^] \t,;]+\\)" refs) (match-string 1 refs)))))
              (progn (goto-char (point-min))
                     (when (re-search-forward "^#\\+reference:[ \t]*\\(\\S-+\\)" nil t)
                       (match-string-no-properties 1)))))))))

(defun sp-devonthink--keyword-insert-point ()
  "The position where a new keyword line goes, at the start of a line."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t))
      (cond ((re-search-forward "^#\\+title:.*$" nil t) (forward-line 1) (point))
            ((looking-at-p "[ \t]*:PROPERTIES:")
             (if (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                 (progn (forward-line 1) (point))
               (point-min)))
            (t (point-min))))))

(defun sp-devonthink-set-keyword (&optional uuid)
  "Write the `#+devonthink:' keyword of the current litnote.
UUID defaults to the record named after the note's citekey."
  (interactive)
  (let* ((key (or (sp-devonthink-note-citekey)
                  (user-error "This note has no citekey (ROAM_REFS or #+reference:)")))
         (uuid (or uuid
                   (let ((rec (sp-devonthink-record key)))
                     (when (and rec (plist-get rec :via)
                                (not (y-or-n-p (format "%s has no record; use the one of %s? "
                                                       key (plist-get rec :via)))))
                       (user-error "Keyword not written"))
                     (plist-get rec :uuid))
                   (user-error "No DEVONthink record named %s.pdf (nor one for its crossref)" key)))
         (old (sp-devonthink-note-uuid)))
    (unless (sp-devonthink--uuid-p uuid)
      (user-error "Not a DEVONthink UUID: %s" uuid))
    (cond
     ((equal old uuid) (message "Keyword already set for %s" key))
     (old
      (when (y-or-n-p (format "Replace %s with %s? " old uuid))
        (save-excursion
          (goto-char (point-min))
          (let ((case-fold-search t))
            (re-search-forward (sp-devonthink--keyword-regexp))
            (replace-match uuid t t nil 1)))))
     (t
      (save-excursion
        (goto-char (sp-devonthink--keyword-insert-point))
        (insert (format "#+%s: %s\n" sp-devonthink-keyword uuid)))))
    uuid))

;;;; Chapters in a parent's PDF

(defun sp-devonthink-first-page (pages)
  "The first page number in the BibTeX PAGES string, or nil.
Takes the part before a range or list separator (--, -, en dash, comma), and
accepts a plain number or a number with a letter prefix such as e123 or S45.
Roman numerals and other text give nil."
  (when (and (stringp pages) (not (string-empty-p (string-trim pages))))
    (let ((first (car (split-string (string-trim pages) "[-–—,;]+" t "[ \t]+"))))
      (when (and first (string-match "\\`[A-Za-z]?\\([0-9]+\\)\\'" first))
        (let ((n (string-to-number (match-string 1 first))))
          (and (>= n 1) n))))))

(defun sp-devonthink--field (field key)
  "The value of the BibTeX FIELD (a symbol) of the entry KEY, or nil when empty.
Asks `citar-get-value'; when that gives nothing, reads the field from the
alist of `citar-get-entry', ignoring case."
  (let ((value (and (fboundp 'citar-get-value) (citar-get-value field key))))
    (when (and (not (stringp value)) (fboundp 'citar-get-entry))
      (setq value (cdr (assoc-string (symbol-name field) (citar-get-entry key) t))))
    (and (stringp value) (not (string-empty-p (string-trim value)))
         (string-trim value))))

(defun sp-devonthink--parent-key (key)
  "The citekey of the entry that KEY cross-references, or nil."
  (or (sp-devonthink--field 'crossref key)
      (sp-devonthink--field 'xref key)))

(defun sp-devonthink-record (key)
  "The DEVONthink record that stands for the work KEY, as a plist, or nil.
This is the one place that decides which record a citekey means.  The plist has
:uuid, :supplier (the citekey whose record it is) and :via (the crossref parent
when the record is the parent's, else nil).  KEY's own record wins; otherwise
the record of the entry named by its =crossref= (or =xref=) field."
  (if-let* ((own (sp-reading-uuid key)))
      (list :uuid own :supplier key)
    (when-let* ((parent (sp-devonthink--parent-key key))
                (uuid (sp-reading-uuid parent)))
      (list :uuid uuid :supplier parent :via parent))))

(defun sp-devonthink-note-record-uuid (&optional action)
  "The DEVONthink record UUID for the current litnote, or nil.
The `#+devonthink:' keyword wins; then the record of the note's citekey; then
the record of its crossref parent.  When the record is the parent's, say so.
ACTION, a verb such as \"tag\", makes it ask first (the action would reach the
whole parent book); declining signals a `user-error'."
  (or (sp-devonthink-note-uuid)
      (when-let* ((key (sp-devonthink-note-citekey))
                  (rec (sp-devonthink-record key)))
        (when-let* ((parent (plist-get rec :via)))
          (if action
              (unless (y-or-n-p (format "%s has no record of its own. %s the record of %s (the whole book)? "
                                        key (concat (upcase (substring action 0 1)) (substring action 1)) parent))
                (user-error "Cancelled"))
            (message "%s has no record of its own: using the record of %s" key parent)))
        (plist-get rec :uuid))))

(defun sp-devonthink-resolve (key)
  "Where to open the work KEY in DEVONthink: `sp-devonthink-record' plus the page.
Adds :page (PDF page counted from 1, or nil) and :note (a message, or nil)
when the record is the parent's: the first page of KEY's =pages= plus the offset."
  (when-let* ((found (sp-devonthink-record key)))
    (if-let* ((parent (plist-get found :via)))
        (let* ((printed (sp-devonthink-first-page (sp-devonthink--field 'pages key)))
               (offset (or (cdr (assoc parent sp-devonthink-parent-page-offsets))
                           sp-devonthink-page-offset))
               (page (and printed (max 1 (+ printed offset)))))
          (append found
                  (list :page page
                        :note (if page
                                  (format "%s is in %s: PDF page %d (printed page %d, offset %+d)"
                                          key parent page printed offset)
                                (format "%s is in %s: no usable pages field, using the start"
                                        key parent)))))
      found)))

;;;; Commands

(defun sp-devonthink--read-page ()
  "Ask for a page (counted from 1) when a prefix argument is given, else nil."
  (when current-prefix-arg (read-number "Page: " 1)))

(defun sp-devonthink--read-page-optional (&optional default)
  "Always ask for a page (counted from 1); an empty answer gives nil (whole record).
DEFAULT, a page number, is offered as the initial answer.
Asks again until the answer is empty or a whole number of at least 1."
  (let (page)
    (while (progn
             (let ((answer (string-trim (read-string "Page (empty = whole record): "
                                                     (and default (number-to-string default))))))
               (cond ((string-empty-p answer) (setq page nil) nil)
                     ((string-match-p "\\`[0-9]+\\'" answer)
                      (setq page (string-to-number answer))
                      (< page 1))
                     (t t)))))
    page))

;;;###autoload
(defun sp-devonthink-open-from-note (&optional page)
  "Open the DEVONthink record of the current litnote, at PAGE (from 1) if given."
  (interactive (list (sp-devonthink--read-page)))
  (let* ((key (sp-devonthink-note-citekey))
         (found (and key (sp-devonthink-resolve key)))
         (uuid (or (sp-devonthink-note-uuid)
                   (plist-get found :uuid)
                   (user-error "No DEVONthink record for this note")))
         (page (or page
                   (and (equal uuid (plist-get found :uuid)) (plist-get found :via)
                        (plist-get found :page)))))
    (when (and found (plist-get found :via) (equal uuid (plist-get found :uuid))
               (plist-get found :note))
      (message "%s" (plist-get found :note)))
    (sp-reading--open-url (sp-devonthink-url (sp-devonthink-link-path uuid page)))))

(defun sp-devonthink--description (key page)
  "Link text for the citekey KEY at PAGE."
  (if page (format "%s p. %d" key page) key))

;;;###autoload
(defun sp-devonthink-insert-link (key &optional page)
  "Insert a `devonthink:' link to the record of the citekey KEY, at PAGE (from 1).
Interactively, always asks for the page; an empty answer links the whole record."
  (interactive
   (let* ((key (if (fboundp 'citar-select-ref) (citar-select-ref) (read-string "Citekey: ")))
          (found (sp-devonthink-resolve key)))
     (when (and found (plist-get found :note)) (message "%s" (plist-get found :note)))
     (list key (sp-devonthink--read-page-optional (plist-get found :page)))))
  (let ((uuid (or (plist-get (sp-devonthink-record key) :uuid)
                  (user-error "No DEVONthink record named %s.pdf, and no record for its crossref" key))))
    (insert (org-link-make-string (concat "devonthink:" (sp-devonthink-link-path uuid page))
                                  (sp-devonthink--description key page)))))

(defconst sp-devonthink--front-script
  "tell application id \"DNtp\"
  set bestLine to \"\"
  set firstLine to \"\"
  repeat with theWindow in (every window)
    try
      set theRecord to content record of theWindow
      set thePage to \"\"
      try
        set thePage to (current page of theWindow) as text
      end try
      set theText to \"\"
      try
        set theText to (selected text of theWindow) as text
      end try
      set theLine to (uuid of theRecord) & tab & (name of theRecord) & tab & thePage & tab & theText
      if firstLine is \"\" then set firstLine to theLine
      if theText is not \"\" then
        set bestLine to theLine
        exit repeat
      end if
    end try
  end repeat
  if bestLine is not \"\" then return bestLine
  return firstLine
end tell"
  "AppleScript that reads the record, page and selected text from DEVONthink's windows.
Windows are visited front to back, whatever their kind (main window, tab,
separate document viewer).  The first window with a selection wins; without
any selection, the frontmost window that has a record wins.")

(defun sp-devonthink--parse-front (output)
  "Parse OUTPUT of `sp-devonthink--front-script' into a plist, or nil.
The plist has :uuid, :key, :page (from 1, or nil) and :text."
  (let ((parts (split-string (string-trim-right output "\n") "\t")))
    (when (and (>= (length parts) 2) (sp-devonthink--uuid-p (car parts)))
      (let ((page (nth 2 parts)))
        (list :uuid (car parts)
              :key (replace-regexp-in-string "\\.pdf\\'" "" (nth 1 parts) t t)
              :page (when (and page (string-match-p "\\`[0-9]+\\'" page))
                      (let ((n (+ (string-to-number page) sp-devonthink-store-page-offset)))
                        (and (>= n 1) n)))
              :text (string-trim (mapconcat #'identity (nthcdr 3 parts) "\t")))))))

;;;###autoload
(defun sp-devonthink-store-link ()
  "Store a link to the record and page showing in DEVONthink, for `org-insert-link'."
  (interactive)
  (let ((front (sp-devonthink--parse-front
                (sp-reading--osascript sp-devonthink--front-script))))
    (unless front (user-error "DEVONthink has no open window with a record (open the PDF in DEVONthink first)"))
    (let ((link (concat "devonthink:"
                        (sp-devonthink-link-path (plist-get front :uuid) (plist-get front :page))))
          (desc (sp-devonthink--description (plist-get front :key) (plist-get front :page))))
      (push (list link desc) org-stored-links)
      (unless (string-empty-p (plist-get front :text))
        (kill-new (plist-get front :text)))
      (message "Stored %s%s" desc
               (if (string-empty-p (plist-get front :text)) "" " (selection in the kill ring)")))))

;;;###autoload
(defun sp-devonthink-citar-open (key)
  "Open the DEVONthink record of the citekey KEY; a prefix argument asks for a page.
An entry without a record of its own opens its crossref parent's PDF at the
entry's first page (see `sp-devonthink-resolve')."
  (interactive (list (if (fboundp 'citar-select-ref) (citar-select-ref) (read-string "Citekey: "))))
  (let* ((asked (sp-devonthink--read-page))
         (found (sp-devonthink-resolve key)))
    (cond
     ((and found (plist-get found :via))
      (when (plist-get found :note) (message "%s" (plist-get found :note)))
      (let ((page (or asked (plist-get found :page))))
        (sp-reading--open-url (sp-reading--url (plist-get found :uuid) (and page (1- page))))))
     (t
      (when (and (not found) (sp-devonthink--parent-key key))
        (message "%s has a crossref (%s), but neither has a DEVONthink record"
                 key (sp-devonthink--parent-key key)))
      (sp-reading-open key (and asked (1- asked)))))))

;;;; Chapter keywords

(defconst sp-devonthink--chapter-end "-- end sp-chapter --"
  "The line that closes a chapter block in a record's comment.")

(defun sp-devonthink--keyword-list (string)
  "The words of STRING (separated by comma, semicolon or newline), without duplicates."
  (let (out)
    (dolist (word (split-string (or string "") "[,;\n]+" t "[ \t]+"))
      (unless (member-ignore-case word out) (push word out)))
    (nreverse out)))

(defun sp-devonthink--chapter-block-regexp (key)
  "A regexp matching the whole block of the chapter KEY, with its final newline."
  (concat "^-- sp-chapter: " (regexp-quote key) " --\n\\(?:.*\n\\)*?"
          (regexp-quote sp-devonthink--chapter-end) "\\(?:\n\\|\\'\\)"))

(defun sp-devonthink-chapter-keywords-in (comment key)
  "The keywords stored for the chapter KEY in the record COMMENT, as a list, or nil."
  (when (and (stringp comment)
             (string-match (sp-devonthink--chapter-block-regexp key) comment))
    (let ((block (match-string 0 comment)))
      (when (string-match "^keywords:[ \t]*\\(.*\\)$" block)
        (sp-devonthink--keyword-list (match-string 1 block))))))

(defun sp-devonthink-chapter-comment-with (comment key keywords)
  "COMMENT with the block of the chapter KEY set to the list KEYWORDS.
Text outside the block is left alone.  An empty KEYWORDS removes the block."
  (let* ((comment (or comment ""))
         (block (when keywords
                  (format "-- sp-chapter: %s --\nkeywords: %s\n%s\n"
                          key (string-join keywords ", ") sp-devonthink--chapter-end)))
         (regexp (sp-devonthink--chapter-block-regexp key)))
    (cond
     ((string-match regexp comment)
      (concat (substring comment 0 (match-beginning 0))
              (or block "")
              (substring comment (match-end 0))))
     ((null block) comment)
     ((string-empty-p (string-trim comment)) block)
     (t (concat (string-trim-right comment "\n+") "\n\n" block)))))

(defun sp-devonthink--record-comment (uuid)
  "The comment of the DEVONthink record UUID."
  (sp-reading--osascript
   (format "tell application id \"DNtp\" to return comment of (get record with uuid %s)"
           (sp-reading--quote uuid))))

(defun sp-devonthink--set-record-comment (uuid text)
  "Set the comment of the DEVONthink record UUID to TEXT."
  (sp-reading--osascript
   (format "tell application id \"DNtp\" to set comment of (get record with uuid %s) to %s"
           (sp-reading--quote uuid) (sp-reading--quote text))))

(defun sp-devonthink--chapter-context ()
  "Plist :key, :parent and :uuid for the current litnote, a chapter of a parent's record.
Signals a `user-error' when the note has no citekey, when no record is found,
or when the entry has a record of its own (it is not a chapter)."
  (let* ((key (or (sp-devonthink-note-citekey) (user-error "This note has no citekey")))
         (rec (or (sp-devonthink-record key)
                  (user-error "No DEVONthink record for %s or its crossref" key)))
         (parent (plist-get rec :via)))
    (unless parent
      (user-error "%s has a record of its own; its keywords belong on that record" key))
    (list :key key :parent parent :uuid (plist-get rec :uuid))))

(defun sp-devonthink--parent-kind (parent)
  "The word for what the entry PARENT is: collection, book or work."
  (let ((type (and (fboundp 'citar-get-value) (citar-get-value '=type= parent))))
    (pcase (and (stringp type) (downcase type))
      ((or "collection" "proceedings" "mvcollection") "collection")
      ((or "book" "mvbook") "book")
      (_ "work"))))

(defun sp-devonthink--chapter-heading (parent)
  "The heading text of the keywords section for the parent PARENT."
  (let ((title (sp-devonthink--field 'title parent)))
    (format "Keywords in the %s %s(%s)" (sp-devonthink--parent-kind parent)
            (if title (format "\"%s\" " title) "") parent)))

;;;###autoload
(defun sp-devonthink-chapter-keywords-store (&optional edit)
  "Store the keywords of this chapter in its parent's DEVONthink record.
The keywords come from the chapter's BibTeX =keywords= field; EDIT (a prefix
argument) lets you change them first.  They go into the chapter's own block in
the record's comment: the record's tags are not touched.  Asks before writing."
  (interactive "P")
  (let* ((ctx (sp-devonthink--chapter-context))
         (key (plist-get ctx :key))
         (parent (plist-get ctx :parent))
         (uuid (plist-get ctx :uuid))
         (found (sp-devonthink--keyword-list (sp-devonthink--field 'keywords key)))
         (keywords (if edit
                       (sp-devonthink--keyword-list
                        (read-string (format "Keywords of %s: " key) (string-join found ", ")))
                     found)))
    (when (and (null keywords) (not edit))
      (user-error "%s has no keywords field (use C-u to type them)" key))
    (unless (y-or-n-p (if keywords
                          (format "Write the keywords of %s (%s) into the record of %s, in this chapter's section of its comment (its tags stay as they are)? "
                                  key (string-join keywords ", ") parent)
                        (format "Remove the keywords of %s from the record of %s? " key parent)))
      (user-error "Cancelled"))
    (sp-devonthink--set-record-comment
     uuid (sp-devonthink-chapter-comment-with (sp-devonthink--record-comment uuid) key keywords))
    (message "%s: %s in the record of %s" key
             (if keywords (format "stored %d keyword(s)" (length keywords)) "keywords removed")
             parent)))

(defun sp-devonthink--chapter-section-put (parent heading keywords)
  "Write the KEYWORDS section for PARENT, under HEADING, at the bottom of the buffer.
A section with the property SP_CHAPTER_OF equal to PARENT has its body rewritten;
otherwise a new level 1 heading is appended.  Does not save."
  (save-excursion
    (save-restriction
      (widen)
      (let ((line (string-join keywords ", "))
            (pos (org-find-property "SP_CHAPTER_OF" parent)))
        (if pos
            (progn
              (goto-char pos)
              (org-back-to-heading t)
              (let ((end (save-excursion (org-end-of-subtree t t) (point))))
                (forward-line 1)
                (when (looking-at-p "[ \t]*:PROPERTIES:")
                  (re-search-forward "^[ \t]*:END:[ \t]*\n?" end t))
                (unless (bolp) (insert "\n"))
                (delete-region (point) end)
                (insert line "\n")))
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (format "* %s\n:PROPERTIES:\n:SP_CHAPTER_OF: %s\n:END:\n%s\n"
                          heading parent line)))))))

;;;###autoload
(defun sp-devonthink-chapter-keywords-show ()
  "Show the keywords stored for this chapter at the bottom of the litnote.
Reads the chapter's block from the comment of its parent's record (nothing is
written to DEVONthink) and puts it under a heading naming the book or
collection it sits in.  The buffer is left unsaved."
  (interactive)
  (let* ((ctx (sp-devonthink--chapter-context))
         (key (plist-get ctx :key))
         (parent (plist-get ctx :parent))
         (keywords (sp-devonthink-chapter-keywords-in
                    (sp-devonthink--record-comment (plist-get ctx :uuid)) key)))
    (unless keywords
      (user-error "No keywords stored for %s in the record of %s (run `sp-devonthink-chapter-keywords-store')"
                  key parent))
    (sp-devonthink--chapter-section-put parent (sp-devonthink--chapter-heading parent) keywords)
    (message "%d keyword(s) of %s, as stored in the record of %s (not saved)"
             (length keywords) key parent)))

;;;; Keys

(defvar-keymap sp-devonthink-map
  :doc "Commands of `sp-devonthink' (prefix C-c k d)."
  "o" #'sp-devonthink-open-from-note
  "l" #'sp-devonthink-insert-link
  "s" #'sp-devonthink-store-link
  "k" #'sp-devonthink-set-keyword
  "c" #'sp-devonthink-chapter-keywords-show
  "C" #'sp-devonthink-chapter-keywords-store
  "r" #'sp-reading-refresh)

(keymap-global-set "C-c k d" sp-devonthink-map)

(with-eval-after-load 'citar-embark
  (when (boundp 'citar-embark-map)
    (keymap-set citar-embark-map "D" #'sp-devonthink-citar-open)))

;;; Provide

(provide 'sp-devonthink)
;;; sp-devonthink.el ends here
