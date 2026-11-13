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

(defcustom sp-devonthink-label-command '("python3")
  "Program and arguments, before the script path, that run Python with pikepdf."
  :type '(repeat string) :group 'sp-devonthink)

(defcustom sp-devonthink-label-script
  (expand-file-name "tools/pdf-labels-read.py" user-emacs-directory)
  "The script that turns a printed page into a PDF page using the PDF's page labels."
  :type 'file :group 'sp-devonthink)

(declare-function citar-get-value "citar")
(declare-function sp-reading--pdf "sp-reading")

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
                   (sp-reading-uuid key)
                   (user-error "No DEVONthink record named %s.pdf" key)))
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

;;;; Commands

(defun sp-devonthink--read-page ()
  "Ask for a page (counted from 1) when a prefix argument is given, else nil."
  (when current-prefix-arg (read-number "Page: " 1)))

(defun sp-devonthink--read-page-optional ()
  "Always ask for a page (counted from 1); an empty answer gives nil (whole record).
Asks again until the answer is empty or a whole number of at least 1."
  (let (page)
    (while (progn
             (let ((answer (string-trim (read-string "Page (empty = whole record): "))))
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
  (let* ((uuid (or (sp-devonthink-note-uuid)
                   (when-let* ((key (sp-devonthink-note-citekey)))
                     (sp-reading-uuid key))
                   (user-error "No DEVONthink record for this note"))))
    (sp-reading--open-url (sp-devonthink-url (sp-devonthink-link-path uuid page)))))

(defun sp-devonthink--description (key page)
  "Link text for the citekey KEY at PAGE."
  (if page (format "%s p. %d" key page) key))

;;;###autoload
(defun sp-devonthink-insert-link (key &optional page)
  "Insert a `devonthink:' link to the record of the citekey KEY, at PAGE (from 1).
Interactively, always asks for the page; an empty answer links the whole record."
  (interactive
   (let ((key (if (fboundp 'citar-select-ref) (citar-select-ref) (read-string "Citekey: "))))
     (list key (sp-devonthink--read-page-optional))))
  (let ((uuid (or (sp-reading-uuid key) (user-error "No DEVONthink record named %s.pdf" key))))
    (insert (org-link-make-string (concat "devonthink:" (sp-devonthink-link-path uuid page))
                                  (sp-devonthink--description key page)))))

(defconst sp-devonthink--front-script
  "tell application id \"DNtp\"
  try
    set theWindow to think window 1
    set theRecord to content record of theWindow
    set thePage to \"\"
    try
      set thePage to (current page of theWindow) as text
    end try
    set theText to \"\"
    try
      set theText to (selected text of theWindow) as text
    end try
    return (uuid of theRecord) & tab & (name of theRecord) & tab & thePage & tab & theText
  on error
    return \"\"
  end try
end tell"
  "AppleScript that reads the record, page and selected text of DEVONthink's front window.")

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
    (unless front (user-error "DEVONthink has no record open in its front window"))
    (let ((link (concat "devonthink:"
                        (sp-devonthink-link-path (plist-get front :uuid) (plist-get front :page))))
          (desc (sp-devonthink--description (plist-get front :key) (plist-get front :page))))
      (push (list link desc) org-stored-links)
      (unless (string-empty-p (plist-get front :text))
        (kill-new (plist-get front :text)))
      (message "Stored %s%s" desc
               (if (string-empty-p (plist-get front :text)) "" " (selection in the kill ring)")))))

;;;; Chapters in a parent's PDF

(defun sp-devonthink-first-page-label (pages)
  "The first page of the BibTeX PAGES string as written, or nil.
=45--67= and =45-67= give \"45\", =e123= gives \"e123\", =xii--xv= gives \"xii\".
A leading p. or pp. and a trailing + are dropped.  The result is looked up among
the page labels of the PDF, so it is a string, not a number."
  (when (and (stringp pages) (not (string-empty-p (string-trim pages))))
    (let* ((text (replace-regexp-in-string "\\`pp?\\.?[ \t]*" "" (string-trim pages) t t))
           (first (car (split-string text "[-–—,;]+" t "[ \t]+"))))
      (when first
        (setq first (string-trim-right first "\\++"))
        (and (string-match-p "\\`\\(?:[A-Za-z]\\{1,4\\}[0-9]+\\|[0-9]+\\|[A-Za-z]+\\)\\'" first)
             first)))))

(defun sp-devonthink-pdf-page-for-label (file label)
  "The PDF page (counted from 1) of FILE whose page label is LABEL, as a plist.
Asks `sp-devonthink-label-script'.  The plist is (:page N), or (:why WHY :message TEXT)
with WHY one of `no-labels' (the PDF has none), `not-found' (no page has LABEL) and
`error' (anything else, such as pikepdf missing)."
  (let* ((errfile (make-temp-file "sp-pdf-labels"))
         (out nil)
         (status (condition-case err
                     (with-temp-buffer
                       (prog1 (apply #'call-process (car sp-devonthink-label-command) nil
                                     (list t errfile) nil
                                     (append (cdr sp-devonthink-label-command)
                                             (list sp-devonthink-label-script file "--resolve" label)))
                         (setq out (string-trim (buffer-string)))))
                   (error (error-message-string err))))
         (message (string-trim (with-temp-buffer (insert-file-contents errfile) (buffer-string)))))
    (delete-file errfile)
    (cond
     ((and (eq status 0) (string-match-p "\\`[1-9][0-9]*\\'" out))
      (list :page (string-to-number out)))
     ((eq status 3) (list :why 'no-labels :message message))
     ((eq status 4) (list :why 'not-found :message message))
     (t (list :why 'error :message (if (stringp status) status message))))))

(defun sp-devonthink--field (field key)
  "The value of the BibTeX FIELD (a symbol) of the entry KEY, or nil when empty."
  (when (fboundp 'citar-get-value)
    (let ((value (citar-get-value field key)))
      (and (stringp value) (not (string-empty-p (string-trim value)))
           (string-trim value)))))

(defun sp-devonthink--parent-key (key)
  "The citekey of the entry that KEY cross-references, or nil."
  (or (sp-devonthink--field 'crossref key)
      (sp-devonthink--field 'xref key)))

(defun sp-devonthink-resolve (key)
  "Where to open the work KEY in DEVONthink, as a plist, or nil.
The plist has :uuid, :page (PDF page counted from 1, or nil), :via (the parent
citekey, or nil) and :note (a message for the user, or nil).  KEY's own record
is used when there is one; otherwise the record of its crossref parent, at the
PDF page whose page label is the first page of KEY's =pages= (see
`sp-devonthink-pdf-page-for-label')."
  (let ((own (sp-reading-uuid key)))
    (if own
        (list :uuid own)
      (when-let* ((parent (sp-devonthink--parent-key key))
                  (uuid (sp-reading-uuid parent)))
        (let* ((label (sp-devonthink-first-page-label (sp-devonthink--field 'pages key)))
               (pdf (and label (sp-reading--pdf parent)))
               (hit (and pdf (sp-devonthink-pdf-page-for-label pdf label)))
               (page (plist-get hit :page)))
          (list :uuid uuid :page page :via parent
                :note (cond
                       (page (format "%s is in %s: opening PDF page %d (printed page %s, from the PDF's page labels)"
                                     key parent page label))
                       ((not label) (format "%s is in %s: no usable pages field, opening it at the start"
                                            key parent))
                       ((not pdf) (format "%s is in %s: no PDF file found for %s, opening the record at the start"
                                          key parent parent))
                       ((eq (plist-get hit :why) 'no-labels)
                        (format "%s is in %s: its PDF has no page labels, opening at the start (run tools/pdf-labels-book.py %s --first-page N)"
                                key parent parent))
                       ((eq (plist-get hit :why) 'not-found)
                        (format "%s is in %s: no page of its PDF is labelled %s, opening at the start"
                                key parent label))
                       (t (format "%s is in %s: could not read the page labels (%s), opening at the start"
                                  key parent (plist-get hit :message))))))))))

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

;;;; Keys

(defvar-keymap sp-devonthink-map
  :doc "Commands of `sp-devonthink' (prefix C-c k d)."
  "o" #'sp-devonthink-open-from-note
  "l" #'sp-devonthink-insert-link
  "s" #'sp-devonthink-store-link
  "k" #'sp-devonthink-set-keyword
  "r" #'sp-reading-refresh)

(keymap-global-set "C-c k d" sp-devonthink-map)

(with-eval-after-load 'citar-embark
  (when (boundp 'citar-embark-map)
    (keymap-set citar-embark-map "D" #'sp-devonthink-citar-open)))

;;; Provide

(provide 'sp-devonthink)
;;; sp-devonthink.el ends here
