;;; sp-cite-open.el --- Open the DEVONthink record of a selected citation -*- lexical-binding: t; -*-

;;; Commentary:

;; A citation selected in DEVONthink is matched against the reference list of
;; the same document, then the BibTeX files (`sp-cite-match'), then litdb, and
;; the record of the cited work is opened.  The text arrives through
;; `org-protocol://sp-cite-open'.
;; Literate source: docs/tangles/academic/sp-cite-open.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'org-protocol)
(require 'sp-cite-match)
(require 'sp-reading)
(require 'sp-devonthink)
(require 'sp-litdb)

(defgroup sp-cite-open nil
  "Open the DEVONthink record of a selected citation."
  :group 'convenience)

(defcustom sp-cite-open-heading-regexp
  (concat "\\`[ \t]*\\(?:[0-9]+\\|[IVX]+\\)?[.):]?[ \t]*"
          "\\(?:references\\|reference list\\|bibliography\\|works cited"
          "\\|literature cited\\|literature\\|sources\\|bibliographie\\|literatur"
          "\\|bibliograf[ií]a\\|references and notes\\)"
          "[ \t:.]*\\'")
  "Regexp for a line that starts the reference list."
  :type 'regexp)

(defcustom sp-cite-open-minimum-lines 3
  "Fewest lines that must follow a heading for it to start the reference list."
  :type 'integer)

(defcustom sp-cite-open-stop-words
  '("and" "et" "al" "see" "cf" "also" "eg" "ie" "ibid" "vs" "pp" "chap" "ch")
  "Words of an in-text citation that are not surnames."
  :type '(repeat string))

(defun sp-cite-open-references (text)
  "The reference list at the end of TEXT, a string, or nil.
It starts after the last line matching `sp-cite-open-heading-regexp' that
has at least `sp-cite-open-minimum-lines' non-blank lines after it."
  (let ((lines (split-string (replace-regexp-in-string "\r" "" (or text "")) "\n"))
        (case-fold-search t)
        (best nil)
        (index 0)
        (heads nil))
    (dolist (line lines)
      (when (string-match-p sp-cite-open-heading-regexp line) (push index heads))
      (setq index (1+ index)))
    ;; HEADS is last heading first.
    (while (and heads (not best))
      (let ((rest (nthcdr (1+ (car heads)) lines)))
        (when (>= (length (seq-remove #'string-blank-p rest)) sp-cite-open-minimum-lines)
          (setq best (string-join rest "\n"))))
      (setq heads (cdr heads)))
    best))

(defun sp-cite-open--numeric (text)
  "The first number of TEXT when it only holds numbers, brackets and commas, or nil."
  (when (string-match "\\`[ \t\n]*[[(]?\\([0-9]+\\)[0-9,;– \t-]*[])]?[ \t\n]*\\'" text)
    (match-string 1 text)))

(defun sp-cite-open--numbered-entry (number entries)
  "The entry of ENTRIES that starts with NUMBER as =[12]=, =12.= or =12)=."
  (let ((re (format "\\`\\(?:\\[%s\\]\\|%s[.)]\\)[ \t]" number number)))
    (seq-find (lambda (entry) (string-match-p re entry)) entries)))

(defun sp-cite-open--entries-for (text entries)
  "The ENTRIES, a list of strings, that fit the short author-year citation TEXT."
  (let* ((in (sp-cite-match--analyse text))
         (years (plist-get in :years))
         (names (seq-remove (lambda (w) (or (member w sp-cite-open-stop-words)
                                            (string-match-p "\\`[0-9]" w)
                                            (< (length w) 2)))
                            (plist-get in :tokens))))
    (when (and names years)
      (seq-filter
       (lambda (entry)
         (let* ((norm (sp-cite-match-normalise entry))
                (head (concat " " (substring norm 0 (min 150 (length norm))) " "))
                (span (substring norm 0 (min 300 (length norm)))))
           (and (seq-every-p (lambda (n) (string-match-p (concat " " (regexp-quote n) " ") head))
                             names)
                (seq-some (lambda (y) (string-match-p (format "\\b%d" y) span)) years))))
       entries))))

(defun sp-cite-open--choose-entry (entries)
  "Ask which of ENTRIES, a list of strings, is meant; nil to skip."
  (let ((choice (completing-read "Reference: "
                                 (cons "skip" (mapcar (lambda (e) (truncate-string-to-width e 150 nil nil "…"))
                                                      entries))
                                 nil t)))
    (unless (equal choice "skip")
      (seq-find (lambda (e) (equal (truncate-string-to-width e 150 nil nil "…") choice)) entries))))

(defun sp-cite-open-entry (text reference-text)
  "The entry of REFERENCE-TEXT, a reference list, that TEXT, a citation, points to, or nil.
A long TEXT is an entry already and gives nil."
  (let ((entries (sp-cite-match-split-entries reference-text)))
    (if-let* ((number (sp-cite-open--numeric text)))
        (sp-cite-open--numbered-entry number entries)
      (when (plist-get (sp-cite-match--analyse text) :short)
        (let ((found (sp-cite-open--entries-for text entries)))
          (if (cdr found)
              (sp-cite-open--choose-entry found)
            (car found)))))))

(defun sp-cite-open--litdb (query)
  "Search litdb for QUERY, open the hit you choose, and return non-nil; nil without a hit."
  (condition-case err
      (progn (sp-litdb-search (string-trim (replace-regexp-in-string "[\n\t ]+" " " query))) t)
    (user-error (message "sp-cite-open: %s" (error-message-string err)) nil)))

;;;###autoload
(defun sp-cite-open-text (text &optional reference-text)
  "Open the DEVONthink record of the work that TEXT cites.
REFERENCE-TEXT is the reference list of the document TEXT was selected in, if known.
The reference list is tried first, then the BibTeX files, then litdb.
Returns `bibtex', `litdb' or nil."
  (interactive (list (if (use-region-p)
                         (buffer-substring-no-properties (region-beginning) (region-end))
                       (read-string "Citation: "))))
  (let* ((entry (and reference-text (sp-cite-open-entry text reference-text)))
         (query (or entry text))
         (cand (sp-cite-match--resolve query (sp-cite-match-candidates))))
    (cond
     (cand (sp-reading-open (plist-get cand :key)) 'bibtex)
     ((sp-cite-open--litdb query) 'litdb)
     (t (message "sp-cite-open: no record found for \"%s\""
                 (truncate-string-to-width query 60))
        nil))))

(defun sp-cite-open--front ()
  "The record in front in DEVONthink as a plist (:uuid :key :page :text), or nil."
  (ignore-errors (sp-devonthink--parse-front (sp-reading--osascript sp-devonthink--front-script))))

(defun sp-cite-open--plain-text-script (uuid)
  "The AppleScript that returns the plain text of the record UUID."
  (format "tell application id \"DNtp\"
  return plain text of (get record with uuid %s)
end tell"
          (sp-reading--quote uuid)))

(defun sp-cite-open--plain-text (uuid)
  "The plain text of the DEVONthink record UUID, or nil when it cannot be read."
  (ignore-errors (sp-reading--osascript (sp-cite-open--plain-text-script uuid))))

;;;###autoload
(defun sp-cite-open-selection ()
  "Open the record cited by the text selected in DEVONthink.
The reference list of the record in front is used when it has one."
  (interactive)
  (let* ((front (sp-cite-open--front))
         (text (plist-get front :text)))
    (if (string-blank-p (or text ""))
        (user-error "Nothing is selected in DEVONthink")
      (sp-cite-open-text
       text (when-let* ((uuid (plist-get front :uuid))
                        (plain (sp-cite-open--plain-text uuid)))
              (sp-cite-open-references plain))))))

(defun sp-cite-open-protocol (info)
  "Handle org-protocol://sp-cite-open?file=NAME."
  (let* ((front (sp-cite-open--front))
         (copied (sp-cite-match--protocol-text info))
         (text (if (string-blank-p (or copied "")) (plist-get front :text) copied)))
    (if (string-blank-p (or text ""))
        (message "sp-cite-open: nothing was selected")
      (run-with-timer
       0.1 nil
       (lambda ()
         (raise-frame)
         (condition-case err
             (sp-cite-open-text
              text (when-let* ((uuid (plist-get front :uuid))
                               (plain (sp-cite-open--plain-text uuid)))
                     (sp-cite-open-references plain)))
           (error (message "sp-cite-open: %s" (error-message-string err))))))))
  nil)

(add-to-list 'org-protocol-protocol-alist
             '("sp-cite-open" :protocol "sp-cite-open"
               :function sp-cite-open-protocol :kill-client t))

;;; Provide

(provide 'sp-cite-open)
;;; sp-cite-open.el ends here
