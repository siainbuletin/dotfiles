;;; sp-vulpea-split.el --- Split a vulpea heading out with parents and a link left behind -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1") (denote "3.0"))

;;; Commentary:

;; `sp-split-leave-parents' wraps `vulpea-split-heading'.  On top of the
;; normal split it:
;;
;; 1. Adds a `- parents :: [[id:...][Title]]' meta line to the new note,
;;    pointing at the note the heading came from.  The source is the
;;    nearest ancestor heading with an ID, else the file-level note (its
;;    ID is created when missing).  When the subtree already has a
;;    `parents' line, the new link is put in front of the old value,
;;    separated by a comma.
;;
;; 2. Leaves a plain link to the new note in the source file, as a line
;;    of body text exactly where the heading started (not a heading).
;;    With a prefix argument no link is left.
;;
;; 3. Renames the new file with Denote's file-naming scheme
;;    (`ID--title__keywords.org'), using `denote-rename-file', so split
;;    notes are named like the rest of your Denote files, and adds a
;;    matching `#+identifier:' line.  The note keeps its org ID, so
;;    links are unaffected.  Disable with
;;    `sp-split-denote-names'.
;;
;; 4. Keeps footnotes working across the split (see
;;    `sp-split-check-footnotes').  Org labels are unique per file and
;;    this setup uses no footnote section, so a heading that moves away
;;    from its definitions would lose its sources.  Every heading that
;;    cites a footnote gets its own copy of the definition, at the end
;;    of its own text, in the new note, and in the source note for
;;    definitions that left with the subtree.  Copies after the first
;;    get a suffixed label (`[fn:smith]', `[fn:smith-2]', ...).
;;
;; Steps 1, 2 and 4 hook `vulpea-split--write-file', a private function of
;; vulpea, and only act while `sp-split-leave-parents' is running.  A
;; plain `vulpea-split-heading' is unchanged.

;;; Code:

(require 'org)
(require 'org-id)
(require 'subr-x)
(require 'seq)
(require 'vulpea)
(require 'denote)

;; These must be defined before the functions below use them in `let',
;; so that the bindings are dynamic.
(defvar sp-split--active nil
  "Non-nil while `sp-split-leave-parents' is running.")

(defvar sp-split--want-link t
  "Non-nil when the split should leave a plain link in the source file.")

(defgroup sp-split nil
  "Split vulpea headings out with parents and a link left behind."
  :group 'applications)

(defcustom sp-split-denote-names t
  "When non-nil, name split-out notes with Denote's file-naming scheme."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-split-check-footnotes t
  "When non-nil, keep footnote definitions with the headings that cite them.
Definitions are copied, per heading, into the new note and, for those
that leave with the subtree, into the source note."
  :type 'boolean
  :group 'spcustom)

(defvar sp-split--fn-report nil
  "Plist (:into-new N :into-source M :dangling LABELS) for the running split.")

(defun sp-split--link-to (id fallback-title)
  "Return an id link to ID, titled from the database or FALLBACK-TITLE."
  (org-link-make-string
   (concat "id:" id)
   (if-let* ((note (vulpea-db-get-by-id id)))
       (vulpea-note-title note)
     fallback-title)))

(defun sp-split--parent-link (id)
  "Return (PARENT-ID . LINK) for the note the heading with ID lives in.
Walks up the ancestors of the heading and takes the first one with an
ID.  If none has one, falls back to the file-level note, creating its
ID when it is missing."
  (when-let* ((note (vulpea-db-get-by-id id))
              (path (vulpea-note-path note)))
    (with-current-buffer (find-file-noselect path)
      (org-with-wide-buffer
       (when-let* ((pos (org-find-entry-with-id id)))
         (goto-char pos)
         (let (pid title)
           (while (and (not pid) (org-up-heading-safe))
             (when-let* ((x (org-entry-get (point) "ID")))
               (setq pid x
                     title (org-link-display-format
                            (org-get-heading t t t t)))))
           (unless pid
             (goto-char (point-min))
             (setq pid (or (org-entry-get (point-min) "ID")
                           (org-id-get-create))
                   title (or (and (fboundp 'vulpea-buffer-title-get)
                                  (vulpea-buffer-title-get))
                             (file-name-base path))))
           (cons pid (sp-split--link-to pid title))))))))

(defun sp-split--body-with-parent (body parent-id link)
  "Return BODY with LINK recorded in its `parents' meta line.
PARENT-ID is the id LINK points to."
  (let* ((case-fold-search nil)
         ;; Only the section before the first child heading: children
         ;; may carry `parents' lines of their own, which stay untouched.
         (top-end (or (string-match "^\\*+ " body) (length body)))
         (top (substring body 0 top-end))
         (rest (substring body top-end)))
    (cond
     ;; A parents line already exists: prepend the new link to its value.
     ((string-match
       "^\\([ \t]*[-+][ \t]+parents[ \t]+::[ \t]*\\)\\(.*\\)$" top)
      ;; Read everything out of the match data before calling anything
      ;; that may clobber it.
      (let* ((mb (match-beginning 0))
             (me (match-end 0))
             (prefix (match-string 1 top))
             (existing (string-trim (match-string 2 top))))
        (if (string-search (concat "id:" parent-id) existing)
            body
          (concat (substring top 0 mb)
                  prefix link
                  (if (string-empty-p existing)
                      ""
                    (concat ", " existing))
                  (substring top me)
                  rest))))
     (t
      (let ((line (concat "- parents :: " link)))
        (cond
         ((string-empty-p body) line)
         ;; Body opens with meta already: join that list.
         ((string-match-p "\\`[ \t]*[-+][ \t]+[^ \t\n]+[ \t]+::" body)
          (concat line "\n" body))
         (t (concat line "\n\n" body))))))))

(defun sp-split--insert-source-link (id title)
  "Insert a plain link to ID on the line where its heading starts.
TITLE is the fallback description.  The link goes in front of the
heading, so it is still there once vulpea cuts the subtree.  Return a
cons of markers around the inserted text, or nil."
  (when-let* ((note (vulpea-db-get-by-id id))
              (path (vulpea-note-path note)))
    (with-current-buffer (find-file-noselect path)
      (org-with-wide-buffer
       (when-let* ((pos (org-find-entry-with-id id)))
         (goto-char pos)
         (let ((beg (copy-marker pos)))
           (insert (sp-split--link-to id (org-link-display-format title))
                   "\n")
           (cons beg (copy-marker (point)))))))))

;;;; Footnotes
;;
;; Org footnote labels are unique per file.  Without a footnote section,
;; definitions sit at the end of the text of the heading that uses them,
;; so a split can strand references (definition left in the source) or
;; strand the source (definition left with the subtree).  Sections here
;; are a heading's own text: from the heading to the next heading of
;; any level, children excluded.

(defun sp-split--fn-scan ()
  "Scan the accessible part of the current Org buffer for footnotes.
Return (HEADS REFS DEFS).  HEADS is the sorted list of heading start
positions.  REFS lists (LABEL BEGIN) for each standard reference
`[fn:LABEL]'.  DEFS lists (LABEL BEGIN TEXT) for each definition, TEXT
being the whole definition as `[fn:LABEL] ...'; a labelled inline
footnote `[fn:LABEL:...]' counts as a definition too."
  (let ((tree (org-element-parse-buffer))
        heads refs defs)
    (org-element-map tree 'headline
      (lambda (h) (push (org-element-property :begin h) heads)))
    (org-element-map tree '(footnote-reference footnote-definition)
      (lambda (el)
        (let ((label (org-element-property :label el))
              (begin (org-element-property :begin el)))
          (when label
            (if (eq (org-element-type el) 'footnote-definition)
                (push (list label begin
                            (string-trim-right
                             (buffer-substring-no-properties
                              begin (org-element-property :end el))))
                      defs)
              (let ((cb (org-element-property :contents-begin el))
                    (ce (org-element-property :contents-end el)))
                (if (eq (org-element-property :type el) 'inline)
                    (when (and cb ce)
                      (push (list label begin
                                  (format "[fn:%s] %s" label
                                          (string-trim
                                           (buffer-substring-no-properties
                                            cb ce))))
                            defs))
                  (push (list label begin) refs))))))))
    (list (sort heads #'<) (nreverse refs) (nreverse defs))))

(defun sp-split--fn-section (pos heads)
  "Return the start of the section containing POS, given sorted HEADS.
Text before the first heading is section 0."
  (let ((sec 0))
    (dolist (h heads sec)
      (when (<= h pos) (setq sec h)))))

(defun sp-split--fn-section-end (sec heads)
  "Return the end of section SEC: the next heading, or the end of buffer."
  (or (seq-find (lambda (h) (> h sec)) heads) (point-max)))

(defun sp-split--fn-fresh (label used)
  "Return LABEL if it is not in USED, else LABEL-2, LABEL-3, ... likewise."
  (if (not (member label used))
      label
    (let ((n 2))
      (while (member (format "%s-%d" label n) used)
        (setq n (1+ n)))
      (format "%s-%d" label n))))

(defun sp-split--fn-def-with-label (text label)
  "Return the definition TEXT with its label replaced by LABEL."
  (replace-regexp-in-string "\\`\\[fn:[^]\n]*\\]" (format "[fn:%s]" label)
                            text t t))

(defun sp-split--fn-apply (heads adds edits)
  "Apply footnote changes to the current buffer.
ADDS maps a section to the definition texts to put at the end of it
\(newest first).  EDITS is a list of (POS LENGTH STRING) replacements.
Everything is positioned against the buffer as it is now, and applied
from the end so earlier positions stay valid."
  (dolist (a adds)
    (let* ((pos (sp-split--fn-section-end (car a) heads))
           (prefix (cond ((= pos (point-min)) "")
                         ((and (>= (- pos (point-min)) 2)
                               (string= (buffer-substring-no-properties
                                         (- pos 2) pos)
                                        "\n\n"))
                          "")
                         ((save-excursion (goto-char pos) (bolp)) "\n")
                         (t "\n\n")))
           (suffix (if (= pos (point-max)) "\n" "\n\n")))
      (push (list pos 0 (concat prefix
                                (mapconcat #'identity (reverse (cdr a)) "\n\n")
                                suffix))
            edits)))
  (dolist (e (sort edits (lambda (x y) (> (car x) (car y)))))
    (goto-char (car e))
    (delete-region (car e) (+ (car e) (cadr e)))
    (insert (nth 2 e))))

(defun sp-split--fn-source-defs (id)
  "Return an alist (LABEL . TEXT) of the footnote definitions in ID's file."
  (when-let* ((note (vulpea-db-get-by-id id))
              (path (vulpea-note-path note)))
    (with-current-buffer (find-file-noselect path)
      (org-with-wide-buffer
       (mapcar (lambda (d) (cons (car d) (nth 2 d)))
               (nth 2 (sp-split--fn-scan)))))))

(defun sp-split--fn-fix-body (body source-defs)
  "Make the footnotes in BODY self-contained.
SOURCE-DEFS is an alist (LABEL . TEXT) of the source file's definitions.
A heading in BODY that cites a footnote gets its own copy of the
definition when the definition is not in BODY at all, or when the
footnote is cited from several headings and the heading has none of its
own.  Return (NEW-BODY COPIED DANGLING), DANGLING being the labels
cited but defined nowhere."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert body)
    (pcase-let* ((`(,heads ,refs ,defs) (sp-split--fn-scan))
                 (used (mapcar #'car defs))
                 (edits nil)
                 (adds nil)
                 (copied 0)
                 (dangling nil))
      (dolist (label (seq-uniq (mapcar #'car refs)))
        (let* ((mine (lambda (e) (equal (car e) label)))
               (rsecs (seq-uniq
                       (mapcar (lambda (r) (sp-split--fn-section (cadr r) heads))
                               (seq-filter mine refs))))
               (dsecs (mapcar (lambda (d) (sp-split--fn-section (cadr d) heads))
                              (seq-filter mine defs)))
               (text (or (nth 2 (assoc label defs))
                         (cdr (assoc label source-defs))))
               (needy (cond ((null text)
                             (push label dangling)
                             nil)
                            ;; Defined only in the source: every citing
                            ;; heading gets a copy.
                            ((null dsecs) rsecs)
                            ;; Defined here, cited from several headings:
                            ;; those without a definition get a copy.
                            ((cdr rsecs)
                             (seq-remove (lambda (s) (memql s dsecs)) rsecs))
                            (t nil))))
          (dolist (sec needy)
            (let ((new (sp-split--fn-fresh label used)))
              (push new used)
              (unless (equal new label)
                (dolist (r (seq-filter
                            (lambda (r)
                              (and (equal (car r) label)
                                   (eql (sp-split--fn-section (cadr r) heads)
                                        sec)))
                            refs))
                  ;; Skip `[fn:' to reach the label itself.
                  (push (list (+ (cadr r) 4) (length label) new) edits)))
              (push (sp-split--fn-def-with-label text new)
                    (alist-get sec adds nil nil #'eql))
              (setq copied (1+ copied))))))
      (sp-split--fn-apply heads adds edits)
      (list (string-trim-right (buffer-string)) copied (nreverse dangling)))))

(defun sp-split--fn-keep-in-source (id)
  "Keep footnotes usable in the source once the subtree of ID is cut.
Definitions inside the subtree that headings outside it still cite are
copied to those headings.  Must run while the subtree is still in
place.  Return the number of definitions copied."
  (let ((copied 0))
    (when-let* ((note (vulpea-db-get-by-id id))
                (path (vulpea-note-path note)))
      (with-current-buffer (find-file-noselect path)
        (org-with-wide-buffer
         (when-let* ((pos (org-find-entry-with-id id)))
           (goto-char pos)
           (org-back-to-heading t)
           (let ((beg (point))
                 (end (save-excursion (org-end-of-subtree t t) (point))))
             (pcase-let* ((`(,heads ,refs ,defs) (sp-split--fn-scan))
                          (inside (lambda (p) (and (>= p beg) (< p end))))
                          (used (mapcar #'car
                                        (seq-remove
                                         (lambda (d) (funcall inside (cadr d)))
                                         defs)))
                          (edits nil)
                          (adds nil))
               (dolist (d (seq-filter (lambda (d) (funcall inside (cadr d)))
                                      defs))
                 (let* ((label (car d))
                        (outside (seq-filter
                                  (lambda (r)
                                    (and (equal (car r) label)
                                         (not (funcall inside (cadr r)))))
                                  refs))
                        (secs (seq-uniq
                               (mapcar (lambda (r)
                                         (sp-split--fn-section (cadr r) heads))
                                       outside))))
                   ;; The original goes away with the subtree, so the
                   ;; first citing heading may keep the label.
                   (dolist (sec secs)
                     (let ((new (sp-split--fn-fresh label used)))
                       (push new used)
                       (unless (equal new label)
                         (dolist (r (seq-filter
                                     (lambda (r)
                                       (eql (sp-split--fn-section (cadr r) heads)
                                            sec))
                                     outside))
                           (push (list (+ (cadr r) 4) (length label) new)
                                 edits)))
                       (push (sp-split--fn-def-with-label (nth 2 d) new)
                             (alist-get sec adds nil nil #'eql))
                       (setq copied (1+ copied))))))
               (sp-split--fn-apply heads adds edits)))))))
    copied))

(defun sp-split--fn-check-body (body id)
  "Return BODY, the body of the note split from ID, with footnotes fixed.
Never aborts the split: on an error BODY is returned unchanged."
  (if (not sp-split-check-footnotes)
      body
    (condition-case err
        (pcase-let ((`(,new ,copied ,dangling)
                     (sp-split--fn-fix-body body (sp-split--fn-source-defs id))))
          (setq sp-split--fn-report
                (list :into-new copied :dangling dangling))
          new)
      (error
       (message "sp-split: footnote check skipped: %s"
                (error-message-string err))
       body))))

(defun sp-split--fn-after-write (id)
  "Copy definitions leaving with the subtree of ID back into the source."
  (when sp-split-check-footnotes
    (condition-case err
        (setq sp-split--fn-report
              (plist-put sp-split--fn-report :into-source
                         (sp-split--fn-keep-in-source id)))
      (error
       (message "sp-split: footnote copy in source skipped: %s"
                (error-message-string err))))))

(defun sp-split--fn-message ()
  "Report what the footnote check did, when it did anything."
  (let ((n (or (plist-get sp-split--fn-report :into-new) 0))
        (m (or (plist-get sp-split--fn-report :into-source) 0))
        (d (plist-get sp-split--fn-report :dangling)))
    (when (or (> n 0) (> m 0) d)
      (message "Footnotes: %d definition(s) copied into the new note, %d into the source%s"
               n m
               (if d
                   (format "; no definition found for: %s"
                           (string-join d ", "))
                 "")))))

(defun sp-split--write-file-advice (fn &rest args)
  "Around advice for `vulpea-split--write-file'.
FN is the original function and ARGS its arguments: PATH ID TITLE HEAD
TAGS PROPERTIES BODY.  Does nothing unless `sp-split-leave-parents' is
running."
  (if (not sp-split--active)
      (apply fn args)
    (pcase-let ((`(,path ,id ,title ,head ,tags ,props ,body) args))
      ;; The subtree is still in the source file at this point, and
      ;; vulpea has already run its checks, so a refused split never gets
      ;; this far.
      (let* ((parent (sp-split--parent-link id))
             (body (sp-split--fn-check-body body id))
             (body (if parent
                       (sp-split--body-with-parent
                        body (car parent) (cdr parent))
                     body))
             (stub (when sp-split--want-link
                     (sp-split--insert-source-link id title))))
        (condition-case err
            ;; The subtree is still in the source once the file is
            ;; written, which is when its footnotes can be copied back.
            (prog1 (funcall fn path id title head tags props body)
              (sp-split--fn-after-write id))
          (error
           ;; Writing the new file failed: take the link back out.
           (when (and stub (marker-buffer (car stub)))
             (with-current-buffer (marker-buffer (car stub))
               (delete-region (car stub) (cdr stub))))
           (signal (car err) (cdr err))))))))

(defun sp-split--add-identifier (path)
  "Add a `#+identifier:' line to the note at PATH, from its Denote file name.
Does nothing when the file already has one or its name carries no
Denote identifier.  The line goes after `#+filetags', else after
`#+title'."
  (when-let* ((ident (denote-retrieve-filename-identifier path)))
    (with-current-buffer (find-file-noselect path)
      (org-with-wide-buffer
       (goto-char (point-min))
       (let ((case-fold-search t))
         (unless (re-search-forward "^#\\+identifier:" nil t)
           (goto-char (point-min))
           (when (or (re-search-forward "^#\\+filetags:.*$" nil t)
                     (re-search-forward "^#\\+title:.*$" nil t))
             (insert "\n#+identifier: " ident)))))
      (save-buffer))))

(defun sp-split--denote-rename (note)
  "Rename the file of NOTE with Denote's naming scheme, then re-sync vulpea.
Return the note as vulpea knows it afterwards.  The org ID stays the
same, so id links keep working.  Denote's own `denote-rename-file' does
the naming (identifier, sluggified title, keywords from the tags); its
return value is not relied on, the new name is found by diffing the
directory."
  (let* ((old (vulpea-note-path note))
         (id (vulpea-note-id note))
         (dir (file-name-directory old))
         (before (directory-files dir nil directory-files-no-dot-files-regexp t)))
    ;; No prompts, and save the front matter Denote rewrites.
    (let ((denote-rename-confirmations nil)
          (denote-save-buffers t))
      ;; TITLE `keep-current' reads the `#+title' written by the split;
      ;; KEYWORDS are the note's tags; no signature, default date.
      (denote-rename-file old 'keep-current (vulpea-note-tags note) nil nil))
    (let ((new (car (seq-difference
                     (directory-files dir nil directory-files-no-dot-files-regexp t)
                     before #'string-equal))))
      (if (not new)
          note
        (let ((new-path (expand-file-name new dir)))
          (sp-split--add-identifier new-path)
          (vulpea-db--forget-file old)
          (org-id-add-location id new-path)
          (vulpea-db-update-file new-path)
          (message "Named with Denote: %s" new)
          (or (vulpea-db-get-by-id id) note))))))

;;;###autoload
(defun sp-split-leave-parents (&optional no-link)
  "Run `vulpea-split-heading', recording where the heading came from.
The new note gets a `- parents ::' line linking back to the note the
subtree was split out of, and the source note gets a plain link to the
new note on the line where the heading started.  The new file is then
renamed with Denote's naming scheme when `sp-split-denote-names' is
non-nil.  With a prefix argument NO-LINK, the link in the source is not
left."
  (interactive "P")
  (let* ((sp-split--active t)
         (sp-split--want-link (not no-link))
         ;; Keep vulpea's own stub option (the prefix argument) out of it.
         (current-prefix-arg nil)
         (sp-split--fn-report nil)
         (note (call-interactively #'vulpea-split-heading)))
    (prog1 (if (and note sp-split-denote-names)
               (sp-split--denote-rename note)
             note)
      (sp-split--fn-message))))

(unless (fboundp 'vulpea-split--write-file)
  (display-warning
   'sp-vulpea-split
   "`vulpea-split--write-file' not found; this vulpea version is not supported"))
(advice-add 'vulpea-split--write-file :around #'sp-split--write-file-advice)

;;; Provide:

(provide 'sp-vulpea-split)
;;; sp-vulpea-split.el ends here