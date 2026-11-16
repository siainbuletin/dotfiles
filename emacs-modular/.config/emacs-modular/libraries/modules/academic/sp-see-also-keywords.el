;;; sp-see-also-keywords.el --- See-also by shared keywords, from litnotes and BibTeX -*- lexical-binding: t; -*-

;;; Commentary:

;; Adds a "Same keywords" part to `sp-see-also-show': the litnotes and the
;; BibTeX entries (also those without a litnote) that share a keyword with the
;; note, rendered as Chicago author-date references.  The keywords of a litnote
;; are on its KEYWORDS: line, kept by `sp-devonthink-keywords'.
;; Literate source: docs/tangles/academic/sp-see-also-keywords.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'bibtex)
(require 'sp-see-also)

(defvar sp-bibtex-files)
(declare-function sp-author-notes-bibtex--files "sp-author-notes-bibtex" ())
(declare-function sp-see-also-view--section "sp-see-also" (title))
(declare-function sp-see-also-view--group "sp-see-also" (title face help action tag))
(declare-function sp-see-also-view--stop "sp-see-also" ())
(declare-function sp-see-also-view--show "sp-see-also" (name redraw))
(declare-function sp-see-also-visit "sp-see-also" (file pos))

(defgroup sp-see-also-keywords nil
  "See-also by shared keywords."
  :group 'sp-see-also)

(defcustom sp-see-also-keywords-line "KEYWORDS"
  "The word that starts the keywords line of a litnote."
  :type 'string :group 'sp-see-also-keywords)

(defcustom sp-see-also-keywords-head-bytes 16384
  "How many bytes at the start of a litnote are read to find its keywords."
  :type 'integer :group 'sp-see-also-keywords)

(defcustom sp-see-also-keywords-max-per-keyword 25
  "The most entries shown under one keyword; the rest is counted."
  :type 'integer :group 'sp-see-also-keywords)

(defcustom sp-see-also-keywords-bibtex t
  "Non-nil to include the BibTeX entries that have no litnote."
  :type 'boolean :group 'sp-see-also-keywords)

(defface sp-see-also-ref-author '((t :inherit bold))
  "Face of the author in a rendered reference." :group 'sp-see-also-keywords)
(defface sp-see-also-ref-year '((t :inherit font-lock-constant-face))
  "Face of the year in a rendered reference." :group 'sp-see-also-keywords)
(defface sp-see-also-ref-title '((t :inherit font-lock-string-face))
  "Face of a quoted title in a rendered reference." :group 'sp-see-also-keywords)
(defface sp-see-also-ref-container '((t :inherit (italic font-lock-type-face)))
  "Face of the book or journal in a rendered reference." :group 'sp-see-also-keywords)
(defface sp-see-also-ref-meta '((t :inherit shadow))
  "Face of volume, pages and publisher in a rendered reference." :group 'sp-see-also-keywords)
(defface sp-see-also-ref-link '((t :inherit link :underline nil))
  "Face of the DOI in a rendered reference." :group 'sp-see-also-keywords)

;;;; Litnotes

(defvar sp-see-also-keywords--note-cache (make-hash-table :test 'equal)
  "Hash table from a litnote file to (STAMP . DATA).")

(defun sp-see-also-keywords--parse (value)
  "The keywords in VALUE, split on commas and semicolons, without empties or repeats."
  (seq-uniq (seq-remove #'string-empty-p
                        (mapcar #'string-trim (split-string (or value "") "[,;]")))
            #'string-equal-ignore-case))

(defun sp-see-also-keywords--head-data ()
  "The plist (:title :keys :keywords) of the head of the current buffer."
  (let* ((case-fold-search nil)
         (end (save-excursion (goto-char (point-min))
                              (if (re-search-forward "^\\*+ " nil t) (line-beginning-position) (point-max))))
         title keys keywords aliases)
    (save-excursion
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" end t)
          (setq title (string-trim (match-string-no-properties 1))))
        (goto-char (point-min))
        (when (re-search-forward "^:ROAM_ALIASES:[ \t]*\\(.*\\)$" end t)
          (setq aliases (ignore-errors (split-string-and-unquote (match-string-no-properties 1)))))
        (goto-char (point-min))
        (when (re-search-forward "^:ROAM_REFS:[ \t]*\\(.*\\)$" end t)
          (let ((refs (match-string-no-properties 1)))
            (with-temp-buffer
              (insert refs)
              (goto-char (point-min))
              (while (re-search-forward "@\\([^ \t\n,;]+\\)" nil t)
                (push (match-string-no-properties 1) keys))))))
      (goto-char (point-min))
      (cond ((re-search-forward (format "^%s:[ \t]*\\(.*?\\)[ \t]*$"
                                        (regexp-quote sp-see-also-keywords-line))
                                end t)
             (setq keywords (sp-see-also-keywords--parse (match-string-no-properties 1))))
            ((progn (goto-char (point-min))
                    (re-search-forward "^- keywords ::[ \t]*\\(.*?\\)[ \t]*$" end t))
             (setq keywords (sp-see-also-keywords--parse (match-string-no-properties 1))))))
    (list :title title :keys (nreverse keys) :keywords keywords :aliases aliases)))

(defun sp-see-also-keywords--note-data (file)
  "The plist (:file :title :keys :keywords) of the litnote FILE, cached, or nil."
  (let* ((stamp (sp-see-also--file-stamp file))
         (cached (gethash file sp-see-also-keywords--note-cache)))
    (cond ((not stamp) nil)
          ((and cached (equal (car cached) stamp)) (cdr cached))
          (t (let ((data (condition-case nil
                             (with-temp-buffer
                               (insert-file-contents file nil 0 sp-see-also-keywords-head-bytes)
                               (append (list :file file) (sp-see-also-keywords--head-data)))
                           (error nil))))
               (puthash file (cons stamp data) sp-see-also-keywords--note-cache)
               data)))))

(defun sp-see-also-keywords--notes ()
  "The data of every litnote."
  (delq nil (mapcar #'sp-see-also-keywords--note-data
                    (funcall sp-see-also-files-function))))

;;;; BibTeX

(defvar sp-see-also-keywords--bib-cache (make-hash-table :test 'equal)
  "Hash table from a .bib file to (STAMP . ENTRIES).")

(defconst sp-see-also-keywords--entry-start
  "^[ \t]*@[[:alpha:]]+[ \t]*[{(][ \t]*\\([^, \t\n]+\\)[ \t]*,"
  "Regexp for the start of a BibTeX entry; group 1 is the key.")

(defun sp-see-also-keywords--bib-files ()
  "The readable .bib files, or nil."
  (seq-filter #'file-readable-p
              (or (ignore-errors
                    (require 'sp-author-notes-bibtex)
                    (sp-author-notes-bibtex--files))
                  (and (boundp 'sp-bibtex-files) sp-bibtex-files))))

(defun sp-see-also-keywords--entry (parsed)
  "The entry plist of PARSED, the alist of `bibtex-parse-entry'."
  (let ((fields (delq nil (mapcar (lambda (cell)
                                    (and (stringp (cdr cell))
                                         (not (string-prefix-p "=" (car cell)))
                                         (cons (downcase (car cell)) (cdr cell))))
                                  parsed))))
    (list :key (cdr (assoc "=key=" parsed))
          :type (downcase (or (cdr (assoc "=type=" parsed)) "misc"))
          :fields fields
          :keywords (sp-see-also-keywords--parse
                     (sp-see-also-keywords--clean (cdr (assoc "keywords" fields)))))))

(defun sp-see-also-keywords--bib-entries (file)
  "The entries of the .bib FILE, cached."
  (let* ((stamp (sp-see-also--file-stamp file))
         (cached (gethash file sp-see-also-keywords--bib-cache)))
    (if (and cached (equal (car cached) stamp))
        (cdr cached)
      (let (entries)
        (condition-case nil
            (with-temp-buffer
              (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
              (delay-mode-hooks (bibtex-mode))
              (goto-char (point-min))
              (while (re-search-forward sp-see-also-keywords--entry-start nil t)
                (goto-char (match-beginning 0))
                (when-let* ((parsed (ignore-errors (bibtex-parse-entry t)))
                            (entry (sp-see-also-keywords--entry parsed)))
                  (push entry entries))
                (end-of-line)))
          (error nil))
        (setq entries (nreverse entries))
        (puthash file (cons stamp entries) sp-see-also-keywords--bib-cache)
        entries))))

(defun sp-see-also-keywords--bib-table ()
  "A hash table from a citekey to its entry plist, over all .bib files (first wins)."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (file (sp-see-also-keywords--bib-files))
      (dolist (entry (sp-see-also-keywords--bib-entries file))
        (unless (gethash (plist-get entry :key) table)
          (puthash (plist-get entry :key) (plist-put (copy-sequence entry) :file file) table))))
    table))

;;;###autoload
(defun sp-see-also-keywords-reindex ()
  "Forget the cached litnote heads and BibTeX entries, so the next view reads them again."
  (interactive)
  (clrhash sp-see-also-keywords--note-cache)
  (clrhash sp-see-also-keywords--bib-cache)
  (message "[see-also] keyword caches cleared"))

;;;; Chicago author-date

(defun sp-see-also-keywords--clean (value)
  "VALUE as one plain line: no braces, no backslash before & % _ #, one space between words."
  (when (stringp value)
    (let ((s (replace-regexp-in-string "\\\\\\([&%_#$]\\)" "\\1" value)))
      (setq s (replace-regexp-in-string "[{}]" "" s))
      (string-trim (replace-regexp-in-string "[ \t\n]+" " " s)))))

(defun sp-see-also-keywords--name (name first)
  "NAME (`Last, First' or `First Last') for a list position: inverted when FIRST."
  (let ((name (string-trim name)))
    (if (string-search "," name)
        (if first name
          (let ((parts (split-string name "," t "[ \t]+")))
            (string-join (append (cdr parts) (list (car parts))) " ")))
      (if (and first (string-search " " name))
          (let ((words (split-string name " " t)))
            (format "%s, %s" (car (last words)) (string-join (butlast words) " ")))
        name))))

(defun sp-see-also-keywords--names (value &optional plain)
  "The Chicago text of the names in the author or editor VALUE, or nil.
The first name is inverted (`Last, First') unless PLAIN."
  (when-let* ((s (sp-see-also-keywords--clean value))
              ((not (string-empty-p s))))
    (let* ((all (split-string s "[ \t]+and[ \t]+" t))
           (more (> (length all) 10))
           (names (if more (seq-take all 7) all))
           (named (cl-loop for n in names for i from 0
                           collect (sp-see-also-keywords--name n (and (not plain) (= i 0))))))
      (cond (more (concat (string-join named ", ") ", et al."))
            ((null (cdr named)) (car named))
            ((null (cddr named)) (format "%s and %s" (car named) (cadr named)))
            (t (format "%s, and %s" (string-join (butlast named) ", ") (car (last named))))))))

(defun sp-see-also-keywords--seg (text face &optional close)
  "TEXT in FACE followed by CLOSE (default \".\") unless it already ends in . ? or !; nil for no TEXT."
  (when (and text (not (string-empty-p text)))
    (let ((end (or close ".")))
      (concat (propertize text 'face face)
              (if (and (string= end ".") (string-match-p "[.?!]\\'" text)) "" end)))))

(defun sp-see-also-keywords--field (entry name)
  "The cleaned field NAME of ENTRY, or nil when empty."
  (let ((v (sp-see-also-keywords--clean (cdr (assoc name (plist-get entry :fields))))))
    (and v (not (string-empty-p v)) v)))

(defun sp-see-also-keywords--pages (value)
  "VALUE, a page range, with an en dash."
  (and value (replace-regexp-in-string "[ \t]*-+[ \t]*" "–" value)))

(defun sp-see-also-keywords--place (entry)
  "The \"Place: Publisher.\" segment of ENTRY, or nil."
  (let ((place (or (sp-see-also-keywords--field entry "address")
                   (sp-see-also-keywords--field entry "location")))
        (pub (or (sp-see-also-keywords--field entry "publisher")
                 (sp-see-also-keywords--field entry "school"))))
    (sp-see-also-keywords--seg (cond ((and place pub) (format "%s: %s" place pub))
                                     (t (or pub place)))
                               'sp-see-also-ref-meta)))

(defun sp-see-also-keywords-reference (entry)
  "ENTRY, an entry plist, as a Chicago author-date reference string with faces."
  (let* ((type (plist-get entry :type))
         (f (lambda (name) (sp-see-also-keywords--field entry name)))
         (who (or (sp-see-also-keywords--names (funcall f "author"))
                  (and (funcall f "editor")
                       (concat (sp-see-also-keywords--names (funcall f "editor")) ", ed"))))
         (year (or (funcall f "year") (and (funcall f "date") (substring (funcall f "date") 0 (min 4 (length (funcall f "date")))))))
         (title (funcall f "title"))
         (head (list (sp-see-also-keywords--seg who 'sp-see-also-ref-author)
                     (sp-see-also-keywords--seg (or year "n.d.") 'sp-see-also-ref-year)))
         (editors (sp-see-also-keywords--names (and (funcall f "author") (funcall f "editor")) t))
         (doi (funcall f "doi"))
         (link (and doi (sp-see-also-keywords--seg doi 'sp-see-also-ref-link)))
         (tail
          (pcase type
            ("article"
             (list (sp-see-also-keywords--seg (and title (format "“%s”" (string-remove-suffix "." title)))
                                              'sp-see-also-ref-title "")
                   (sp-see-also-keywords--seg
                    (concat (or (funcall f "journaltitle") (funcall f "journal") "")) 'sp-see-also-ref-container "")
                   (sp-see-also-keywords--seg
                    (concat (or (funcall f "volume") "")
                            (and (funcall f "number") (format " (%s)" (funcall f "number")))
                            (and (sp-see-also-keywords--pages (funcall f "pages"))
                                 (format ": %s" (sp-see-also-keywords--pages (funcall f "pages")))))
                    'sp-see-also-ref-meta)
                   link))
            ((or "incollection" "inbook" "inproceedings" "conference")
             (list (sp-see-also-keywords--seg (and title (format "“%s”" (string-remove-suffix "." title)))
                                              'sp-see-also-ref-title "")
                   (and (funcall f "booktitle")
                        (concat (propertize "In " 'face 'sp-see-also-ref-meta)
                                (sp-see-also-keywords--seg (funcall f "booktitle") 'sp-see-also-ref-container ",")))
                   (and editors (sp-see-also-keywords--seg (format "edited by %s" editors) 'sp-see-also-ref-meta ","))
                   (sp-see-also-keywords--seg (sp-see-also-keywords--pages (funcall f "pages")) 'sp-see-also-ref-meta)
                   (sp-see-also-keywords--place entry)
                   link))
            ((or "phdthesis" "mastersthesis" "thesis")
             (list (sp-see-also-keywords--seg (and title (format "“%s”" (string-remove-suffix "." title)))
                                              'sp-see-also-ref-title "")
                   (sp-see-also-keywords--seg
                    (concat (if (equal type "mastersthesis") "Master’s thesis" "PhD diss.")
                            (and (funcall f "school") (format ", %s" (funcall f "school"))))
                    'sp-see-also-ref-meta)
                   link))
            ((or "book" "collection" "proceedings" "mvbook")
             (list (sp-see-also-keywords--seg title 'sp-see-also-ref-container)
                   (and (funcall f "edition") (sp-see-also-keywords--seg (format "%s ed." (funcall f "edition")) 'sp-see-also-ref-meta ""))
                   (sp-see-also-keywords--place entry)
                   link))
            (_
             (list (sp-see-also-keywords--seg title 'sp-see-also-ref-container)
                   (sp-see-also-keywords--seg (or (funcall f "howpublished") (funcall f "note") (funcall f "url"))
                                              'sp-see-also-ref-meta)
                   link)))))
    (string-join (delq nil (append head tail)) " ")))

(defun sp-see-also-keywords--sort-key (entry)
  "A sort key for ENTRY: first author's surname, then year."
  (let ((who (or (sp-see-also-keywords--field entry "author")
                 (sp-see-also-keywords--field entry "editor") "")))
    (downcase (format "%s %s" (car (split-string who "[,]\\| and " t "[ \t]+"))
                      (or (sp-see-also-keywords--field entry "year") "")))))

;;;; Matches

(defun sp-see-also-keywords--items ()
  "Every litnote and every BibTeX-only entry that has keywords, as item plists."
  (let* ((table (sp-see-also-keywords--bib-table))
         (notes (sp-see-also-keywords--notes))
         (covered (make-hash-table :test 'equal))
         items)
    (dolist (note notes)
      (dolist (key (plist-get note :keys)) (puthash key t covered))
      (when (plist-get note :keywords)
        (let ((entry (cl-some (lambda (k) (gethash k table)) (plist-get note :keys))))
          (push (list :kind 'litnote :file (plist-get note :file) :title (plist-get note :title)
                      :key (car (plist-get note :keys)) :entry entry
                      :keywords (plist-get note :keywords))
                items))))
    (when sp-see-also-keywords-bibtex
      (maphash (lambda (key entry)
                 (when (and (plist-get entry :keywords) (not (gethash key covered)))
                   (push (list :kind 'bib :file (plist-get entry :file) :key key
                               :title (cdr (assoc "title" (plist-get entry :fields)))
                               :entry entry :keywords (plist-get entry :keywords))
                         items)))
               table))
    items))

(defun sp-see-also-keywords--item-sort-key (item)
  "A sort key for ITEM: litnotes before BibTeX entries, then author and year."
  (concat (if (eq (plist-get item :kind) 'litnote) "0" "1")
          (if (plist-get item :entry)
              (sp-see-also-keywords--sort-key (plist-get item :entry))
            (downcase (or (plist-get item :title) "")))))

(defun sp-see-also-keywords-find (keywords &optional exclude-file exclude-keys)
  "The groups (KEYWORD . ITEMS) of the litnotes and entries that share KEYWORDS.
EXCLUDE-FILE and EXCLUDE-KEYS (citekeys) name the note being shown."
  (let ((items (seq-remove
                (lambda (item)
                  (or (and exclude-file (equal (plist-get item :file) exclude-file))
                      (member (plist-get item :key) exclude-keys)))
                (sp-see-also-keywords--items))))
    (mapcar (lambda (keyword)
              (cons keyword
                    (sort (seq-filter (lambda (item)
                                        (seq-find (lambda (k) (string-equal-ignore-case k keyword))
                                                  (plist-get item :keywords)))
                                      items)
                          (lambda (a b) (string< (sp-see-also-keywords--item-sort-key a)
                                                 (sp-see-also-keywords--item-sort-key b))))))
            keywords)))

(defun sp-see-also-keywords-all ()
  "Every keyword of every litnote and BibTeX entry, sorted, without repeats."
  (sort (seq-uniq (apply #'append (mapcar (lambda (i) (plist-get i :keywords))
                                          (sp-see-also-keywords--items)))
                  #'string-equal-ignore-case)
        #'string-collate-lessp))

(defun sp-see-also-keywords-of (note)
  "The keywords of NOTE (a plist of `sp-see-also--resolve'): its line, else its BibTeX entry."
  (let* ((file (plist-get note :file))
         (data (and file (plist-get note :own) (sp-see-also-keywords--note-data file))))
    (or (plist-get data :keywords)
        (when-let* ((keys (or (plist-get note :citekey) (plist-get data :keys)))
                    (table (sp-see-also-keywords--bib-table)))
          (cl-some (lambda (k) (plist-get (gethash k table) :keywords)) keys)))))

;;;; Drawing

(defun sp-see-also-keywords--wrap (text indent)
  "TEXT filled to the window width, its continuation lines indented by INDENT spaces."
  (with-temp-buffer
    (insert text)
    (let ((fill-column (max 40 (- (sp-see-also-view--width) indent 1))))
      (fill-region (point-min) (point-max)))
    (goto-char (point-min))
    (while (search-forward "\n" nil t) (insert (make-string indent ?\s)))
    (buffer-string)))

(defun sp-see-also-keywords--visit (item)
  "Visit ITEM: the litnote, or the BibTeX entry in its file."
  (if (eq (plist-get item :kind) 'litnote)
      (sp-see-also-visit (plist-get item :file) (point-min))
    (let ((key (plist-get item :key)))
      (pop-to-buffer (find-file-noselect (plist-get item :file)))
      (widen)
      (goto-char (point-min))
      (if (re-search-forward (format "^[ \t]*@[[:alpha:]]+[ \t]*[{(][ \t]*%s[ \t]*," (regexp-quote key)) nil t)
          (goto-char (match-beginning 0))
        (message "No entry %s in %s" key (file-name-nondirectory (plist-get item :file)))))))

(defun sp-see-also-keywords--insert-item (item also)
  "Insert ITEM as a reference with a mark; ALSO lists the other shared keywords."
  (let* ((litnote (eq (plist-get item :kind) 'litnote))
         (entry (plist-get item :entry))
         (ref (if entry
                  (sp-see-also-keywords-reference entry)
                (propertize (or (plist-get item :title) (plist-get item :key) "?")
                            'face 'sp-see-also-ref-title)))
         (wrapped (sp-see-also-keywords--wrap ref 6))
         (start (point)))
    (sp-see-also-view--stop)
    (insert "  " (propertize (if litnote "●" "○") 'face 'sp-see-also-marks) " ")
    (let ((text (point)))
      (insert wrapped)
      (make-text-button text (point) 'face nil 'follow-link t
                        'help-echo (if litnote "Visit this litnote" "Visit this BibTeX entry (no litnote yet)")
                        'action (lambda (_) (sp-see-also-keywords--visit item)))
      ;; the button reset the faces; put those of the reference back
      (let ((pos 0))
        (while (< pos (length wrapped))
          (let ((next (or (next-single-property-change pos 'face wrapped) (length wrapped)))
                (face (get-text-property pos 'face wrapped)))
            (when face (add-face-text-property (+ text pos) (+ text next) face))
            (setq pos next)))))
    (insert "\n")
    (when also
      (insert "      " (propertize (format "also: %s" (string-join also ", ")) 'face 'sp-see-also-marks) "\n"))
    (add-face-text-property start (point) 'sp-see-also-match t)))

(defun sp-see-also-keywords--insert-groups (groups mine)
  "Insert GROUPS of `sp-see-also-keywords-find'; MINE are the keywords of the note shown."
  (dolist (group groups)
    (let* ((keyword (car group)) (items (cdr group))
           (notes (seq-count (lambda (i) (eq (plist-get i :kind) 'litnote)) items))
           (shown (seq-take items sp-see-also-keywords-max-per-keyword)))
      (sp-see-also-view--group
       keyword 'sp-see-also-file-heading "Show every entry with this keyword"
       (lambda () (sp-see-also-keywords-show keyword))
       (format "%d litnote%s · %d BibTeX only" notes (if (= notes 1) "" "s") (- (length items) notes)))
      (if (null items)
          (insert "  nothing else has this keyword\n")
        (dolist (item shown)
          (sp-see-also-keywords--insert-item
           item (seq-remove (lambda (k) (string-equal-ignore-case k keyword))
                            (seq-filter (lambda (k) (seq-find (lambda (m) (string-equal-ignore-case m k)) mine))
                                        (plist-get item :keywords)))))
        (when (> (length items) (length shown))
          (insert (propertize (format "  … %d more\n" (- (length items) (length shown))) 'face 'sp-see-also-marks)))))))

(defun sp-see-also-keywords--concept-p (note)
  "Non-nil when NOTE is a concept note: no citekey and no KEYWORDS: line of its own."
  (let* ((file (plist-get note :file))
         (data (and file (sp-see-also-keywords--note-data file))))
    (not (or (plist-get note :citekey) (plist-get data :keys) (plist-get data :keywords)))))

(defun sp-see-also-keywords--concept-terms (note)
  "The names a concept NOTE answers to: its title, its ROAM_ALIASES and its file name."
  (let* ((file (plist-get note :file))
         (data (and file (sp-see-also-keywords--note-data file)))
         (base (and file (file-name-base file))))
    (seq-uniq
     (seq-remove #'string-empty-p
                 (mapcar #'string-trim
                         (append (list (or (plist-get note :title) (plist-get data :title)))
                                 (plist-get data :aliases)
                                 (and base
                                      (list (replace-regexp-in-string
                                             "[-_]+" " "
                                             (replace-regexp-in-string "\\`[0-9T-]\\{8,\\}[-_]+" "" base)))))))
     #'string-equal-ignore-case)))

(defun sp-see-also-keywords--section (note)
  "Add the keyword part for NOTE to the see-also view.
A litnote gets \"Same keywords\".  A concept note gets \"Literature with this
concept as a keyword\": the litnotes and BibTeX entries whose keywords equal its
title, an alias or its file name."
  (if (sp-see-also-keywords--concept-p note)
      (let* ((terms (sp-see-also-keywords--concept-terms note))
             (groups (seq-filter #'cdr (sp-see-also-keywords-find terms))))
        (when groups
          (sp-see-also-view--section "Literature with this concept as a keyword")
          (sp-see-also-keywords--insert-groups groups terms)))
    (when-let* ((mine (sp-see-also-keywords-of note)))
      (sp-see-also-view--section "Same keywords")
      (let ((groups (sp-see-also-keywords-find mine (plist-get note :file) (plist-get note :citekey))))
        (if (seq-every-p #'null (mapcar #'cdr groups))
            (insert (format "No other litnote or BibTeX entry has %s.\n" (string-join mine ", ")))
          (sp-see-also-keywords--insert-groups groups mine))))))

(add-hook 'sp-see-also-view-sections-functions #'sp-see-also-keywords--section)

;;;###autoload
(defun sp-see-also-keywords-show (keyword)
  "Show the litnotes and BibTeX entries that have KEYWORD, in `*see-also keywords*'."
  (interactive (list (completing-read "Keyword: " (sp-see-also-keywords-all) nil nil)))
  (sp-see-also-view--show
   "*see-also keywords*"
   (lambda ()
     (sp-see-also-view--stop)
     (insert (propertize (format "Keyword: %s" keyword) 'face 'sp-see-also-file-heading) "\n")
     (sp-see-also-keywords--insert-groups (sp-see-also-keywords-find (list keyword)) (list keyword)))))

(provide 'sp-see-also-keywords)
;;; sp-see-also-keywords.el ends here
