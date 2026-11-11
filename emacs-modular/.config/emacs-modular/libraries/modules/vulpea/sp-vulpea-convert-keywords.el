;;; sp-vulpea-convert-keywords.el --- Convert Org file-header keywords to Vulpea meta lines -*- lexical-binding: t; -*-

;;; Commentary:

;; Turns file-header keywords such as `#+bib-project: thesis' into Vulpea meta
;; lines, `- bib-project :: thesis', in the first section of a note. It lists
;; the keywords found (in the current note, or in every note with C-u), lets you
;; pick which to convert, previews the result and then writes it.

;;; Code:

(require 'org)
(require 'org-element)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'sp-vulpea-convert-properties)
(require 'sp-batch-report)

(declare-function vulpea-db-query "vulpea-db")
(declare-function vulpea-note-path "vulpea-note")

(defgroup sp-vulpea-convert-keywords nil
  "Convert Org file-header keywords to Vulpea meta lines."
  :group 'org
  :prefix "sp-vulpea-convert-keywords-")

(defcustom sp-vulpea-convert-keywords-ignore '("title" "date")
  "Header keywords never offered for conversion (case-insensitive).
Org and Vulpea read these from the header, so the usual choice is
to keep `title' and `date'. Add `filetags', `startup' and the like
if you do not want them in the list either."
  :type '(repeat string)
  :group 'sp-vulpea-convert-keywords)

(defcustom sp-vulpea-convert-keywords-remove-original t
  "Non-nil means remove the `#+key:' line once its meta line is written.
Nil keeps both the keyword and the meta line."
  :type 'boolean
  :group 'sp-vulpea-convert-keywords)

(defun sp-vulpea-convert-keywords--ignored-p (key)
  "Non-nil if KEY is in `sp-vulpea-convert-keywords-ignore'."
  (member (downcase key) (mapcar #'downcase sp-vulpea-convert-keywords-ignore)))

(defun sp-vulpea-convert-keywords--scan-buffer ()
  "Return the header keywords of the current buffer, in order.
Each is a plist (:key KEY :value VALUE :beg BEG :end END), KEY in
lower case, BEG..END the whole line with its newline. Only
top-level keywords before the first heading count."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (narrow-to-region
       (point-min)
       (if (re-search-forward org-outline-regexp-bol nil t)
           (match-beginning 0)
         (point-max)))
      (let* ((tree (org-element-parse-buffer))
             (section (car (org-element-contents tree)))
             found)
        (when (and section (eq (org-element-type section) 'section))
          (dolist (el (org-element-contents section))
            (when (eq (org-element-type el) 'keyword)
              (let ((beg (org-element-property :begin el)))
                (push (list :key (downcase (org-element-property :key el))
                            :value (string-trim (or (org-element-property :value el) ""))
                            :beg beg
                            :end (save-excursion
                                   (goto-char beg)
                                   (forward-line 1)
                                   (point)))
                      found)))))
        (nreverse found)))))

(defun sp-vulpea-convert-keywords--convertible (&optional keys)
  "Header keywords of the current buffer that could be converted.
Drops ignored keys and empty values. With KEYS, keeps only those."
  (seq-filter
   (lambda (e)
     (and (not (string-empty-p (plist-get e :value)))
          (not (sp-vulpea-convert-keywords--ignored-p (plist-get e :key)))
          (or (null keys) (member (plist-get e :key) keys))))
   (sp-vulpea-convert-keywords--scan-buffer)))

(defun sp-vulpea-convert-keywords--file-may-have-keys-p ()
  "Non-nil if the current buffer has a `#+key:' line that is not ignored.
A cheap text check, used to skip parsing files that cannot match."
  (save-excursion
    (goto-char (point-min))
    (catch 'found
      (while (re-search-forward "^#\\+\\([A-Za-z0-9_-]+\\):" nil t)
        (unless (sp-vulpea-convert-keywords--ignored-p (match-string 1))
          (throw 'found t)))
      nil)))

(defun sp-vulpea-convert-keywords--call-on-source (source fn)
  "Call FN in SOURCE, a buffer or a file name, and return its value.
A file is read into a temporary Org buffer; SOURCE is not visited."
  (if (bufferp source)
      (with-current-buffer source (funcall fn))
    (with-temp-buffer
      (insert-file-contents source)
      (when (sp-vulpea-convert-keywords--file-may-have-keys-p)
        (delay-mode-hooks (org-mode))
        (funcall fn)))))

(defun sp-vulpea-convert-keywords--collect (sources)
  "Return (KEY . (:count N :example VALUE)) for the keywords in SOURCES.
SOURCES are buffers or file names. N counts the sources having
KEY; the list is sorted by KEY."
  (let ((table (make-hash-table :test #'equal))
        (reporter (and (> (length sources) 20)
                       (make-progress-reporter "Scanning header keywords " 0 (length sources))))
        (i 0))
    (dolist (source sources)
      (let ((seen nil))
        (dolist (e (sp-vulpea-convert-keywords--call-on-source
                    source #'sp-vulpea-convert-keywords--convertible))
          (let ((key (plist-get e :key)))
            (unless (member key seen)
              (push key seen)
              (let ((old (gethash key table)))
                (puthash key (list :count (1+ (if old (plist-get old :count) 0))
                                   :example (if old (plist-get old :example) (plist-get e :value)))
                         table))))))
      (when reporter (progress-reporter-update reporter (cl-incf i))))
    (when reporter (progress-reporter-done reporter))
    (let (alist)
      (maphash (lambda (k v) (push (cons k v) alist)) table)
      (sort alist (lambda (a b) (string< (car a) (car b)))))))

(defun sp-vulpea-convert-keywords--meta-present-p (key value start end)
  "Non-nil if \"- KEY :: VALUE\" is a line between START and END."
  (save-excursion
    (goto-char start)
    (re-search-forward
     (format "^-[ \t]+%s[ \t]+::[ \t]+%s[ \t]*$"
             (regexp-quote key) (regexp-quote value))
     end t)))

(defun sp-vulpea-convert-keywords--insert-meta (pairs)
  "Insert meta lines for PAIRS, a list of (KEY . VALUE), in the first section.
Returns the pairs that were added (those not already present)."
  (save-excursion
    (goto-char (point-max))
    (unless (or (bobp) (bolp)) (insert "\n"))
    (goto-char (point-min))
    (let* ((start (sia-vulpea--after-property-drawer-pos))
           (end (save-excursion
                  (goto-char start)
                  (if (re-search-forward org-outline-regexp-bol nil t)
                      (match-beginning 0)
                    (point-max))))
           (new (seq-remove
                 (lambda (p)
                   (sp-vulpea-convert-keywords--meta-present-p
                    (car p) (cdr p) start end))
                 pairs)))
      (when new
        (let ((text (mapconcat (lambda (p) (format "- %s :: %s\n" (car p) (cdr p)))
                               new ""))
              (meta-below (save-excursion
                            (goto-char start)
                            (skip-chars-forward " \t\n")
                            (beginning-of-line)
                            (and (looking-at "-[ \t]+[^ \t\n]+[ \t]+::")
                                 (point)))))
          (if meta-below
              (progn (goto-char meta-below) (insert text))
            (goto-char start)
            (insert text)
            (unless (or (eobp) (looking-at "[ \t]*$")) (insert "\n"))
            (sia-vulpea--ensure-blank-line-before-meta))))
      new)))

(defun sp-vulpea-convert-keywords--plan (keys)
  "Return (KEY . VALUE) for the header keywords named in KEYS."
  (mapcar (lambda (e) (cons (plist-get e :key) (plist-get e :value)))
          (sp-vulpea-convert-keywords--convertible keys)))

(defun sp-vulpea-convert-keywords--apply (keys)
  "Convert the header keywords named in KEYS in the current buffer.
Honours `sp-vulpea-convert-keywords-remove-original'. Does not
save. Returns the list of (KEY . VALUE) converted."
  (let ((entries (sp-vulpea-convert-keywords--convertible keys)))
    (when entries
      (when sp-vulpea-convert-keywords-remove-original
        (dolist (e (reverse entries))
          (delete-region (plist-get e :beg) (plist-get e :end))))
      (sp-vulpea-convert-keywords--insert-meta
       (mapcar (lambda (e) (cons (plist-get e :key) (plist-get e :value)))
               entries))
      (mapcar (lambda (e) (cons (plist-get e :key) (plist-get e :value)))
              entries))))

(defun sp-vulpea-convert-keywords--read-keys (choices)
  "Ask which of CHOICES, from `--collect', to convert; return the key names."
  (let* ((table (lambda (string pred action)
                  (if (eq action 'metadata)
                      `(metadata
                        (annotation-function
                         . ,(lambda (key)
                              (let ((info (cdr (assoc key choices))))
                                (format "  %d note%s, e.g. %s"
                                        (plist-get info :count)
                                        (if (= 1 (plist-get info :count)) "" "s")
                                        (truncate-string-to-width
                                         (plist-get info :example) 40 nil nil "…"))))))
                    (complete-with-action action (mapcar #'car choices) string pred)))))
    (completing-read-multiple "Convert header keywords to meta (comma-separated): "
                              table nil t)))

(defun sp-vulpea-convert-keywords--show-preview (plan)
  "Show PLAN, an alist of (SOURCE . PAIRS), in a preview buffer."
  (sp-batch-report-show
   "*keywords to meta preview*"
   (with-temp-buffer
     (insert (format "#+title: Header keywords -> meta lines (%s)\n\n"
                     (if sp-vulpea-convert-keywords-remove-original
                         "the #+key: lines are removed"
                       "the #+key: lines are kept")))
     (dolist (item plan)
       (let ((source (car item)))
         (insert (format "* %s\n" (if (bufferp source)
                                      (buffer-name source)
                                    (sp-batch-report-file-link
                                     source (abbreviate-file-name source))))
                 (mapconcat (lambda (p) (format "- %s :: %s\n" (car p) (cdr p)))
                            (cdr item) ""))))
     (buffer-string))))

(defun sp-vulpea-convert-keywords--note-files ()
  "Return the file names of all Vulpea notes."
  (seq-filter (lambda (f) (and (stringp f) (file-exists-p f)
                               (string-suffix-p ".org" f)))
              (seq-uniq (mapcar #'vulpea-note-path (vulpea-db-query)))))

;;;###autoload
(defun sp-vulpea-convert-keywords (&optional all-notes)
  "Convert file-header keywords such as `#+bib-project:' to Vulpea meta lines.
Lists the header keywords found in the current note (in every
Vulpea note with prefix argument ALL-NOTES), minus
`sp-vulpea-convert-keywords-ignore', lets you pick which to
convert, shows a preview and asks before writing. See
`sp-vulpea-convert-keywords-remove-original'.

The current note is changed but not saved. With ALL-NOTES each
note is saved, except one with unsaved changes, which is skipped."
  (interactive "P")
  (unless (or all-notes (derived-mode-p 'org-mode))
    (user-error "Not an Org buffer; use C-u to run over all notes"))
  (let* ((sources (if all-notes
                      (sp-vulpea-convert-keywords--note-files)
                    (list (current-buffer))))
         (choices (sp-vulpea-convert-keywords--collect sources)))
    (unless choices
      (user-error "No header keywords to convert (ignoring %s)"
                  (string-join sp-vulpea-convert-keywords-ignore ", ")))
    (let* ((keys (sp-vulpea-convert-keywords--read-keys choices))
           (plan (and keys
                      (seq-filter
                       #'cdr
                       (mapcar (lambda (s)
                                 (cons s (sp-vulpea-convert-keywords--call-on-source
                                          s (lambda () (sp-vulpea-convert-keywords--plan keys)))))
                               sources)))))
      (unless keys (user-error "Nothing picked"))
      (unless plan (user-error "None of those keywords has a value to convert"))
      (sp-vulpea-convert-keywords--show-preview plan)
      (unwind-protect
          (unless (y-or-n-p (format "Convert %d note%s? "
                                    (length plan) (if (= 1 (length plan)) "" "s")))
            (user-error "Aborted"))
        (when-let* ((win (get-buffer-window "*keywords to meta preview*")))
          (quit-window nil win)))
      (if (not all-notes)
          (let ((done (with-current-buffer (car sources)
                        (sp-vulpea-convert-keywords--apply keys))))
            (message "Converted %d header keyword%s to meta lines (not saved; C-/ undoes)"
                     (length done) (if (= 1 (length done)) "" "s")))
        (let ((converted 0) skipped)
          (let ((run (sp-batch-report-run-batches
                      plan
                      (lambda (item _decision)
                        (let* ((file (car item))
                               (open (get-file-buffer file)))
                          (if (and open (buffer-modified-p open))
                              (push file skipped)
                            (with-current-buffer (find-file-noselect file)
                              (cl-incf converted (length (sp-vulpea-convert-keywords--apply keys)))
                              (save-buffer)
                              (unless open (kill-buffer))))))
                      :label "Keywords to meta"
                      :describe (lambda (item)
                                  (format "Convert %s?" (file-name-nondirectory (car item)))))))
            (message "Converted %d header keyword%s in %d note%s%s%s"
                     converted (if (= 1 converted) "" "s")
                     (- (plist-get run :done) (length skipped))
                     (if (= 1 (- (plist-get run :done) (length skipped))) "" "s")
                     (if skipped
                         (format "; skipped %d with unsaved changes: %s" (length skipped)
                                 (string-join (mapcar #'file-name-nondirectory skipped) ", "))
                       "")
                     (sp-batch-report-batches-note run))))))))

;;;###autoload
(defun sp-vulpea-convert-keywords-all-notes ()
  "Run `sp-vulpea-convert-keywords' over every Vulpea note."
  (interactive)
  (sp-vulpea-convert-keywords t))

(provide 'sp-vulpea-convert-keywords)
;;; sp-vulpea-convert-keywords.el ends here
