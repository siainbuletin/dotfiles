;;; sp-refile.el --- One command to refile, split or merge notes -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:

;; `sp-refile' moves the heading at point to another heading of the same
;; note, to another note, or into a note of its own (`sp-split-leave-parents',
;; which lives in this file).  Before the first heading it merges the whole
;; note into another one.  See docs/tangles/funct/sp-refile.org.
;;
;; `sp-split-leave-parents' wraps `vulpea-split-heading'.  On top of the
;; normal split it:
;;
;; 1. Adds a `- parents :: [[id:...][Title]]' meta line to the new note,
;;    pointing at the note the heading came from.
;; 2. Leaves a plain link to the new note in the source file (not with a
;;    prefix argument).
;; 3. Asks for tags when the new note has none and files it into the folder
;;    of its tags (`sp-split-file-by-tags').
;; 4. Keeps footnotes working across the split (`sp-split-check-footnotes').
;; 5. Moves id links out of the heading text into a `- seealso ::' meta line
;;    (`sp-split-links-to-seealso').
;;
;; Steps 1, 2, 4 and 5 hook `vulpea-split--write-file', a private function of
;; vulpea, and only act while `sp-split-leave-parents' is running.

;;; Code:

(declare-function sp-select-note "sp-org-tag-groups")
(declare-function vulpea-note-path "vulpea")
(declare-function vulpea-note-p "vulpea")
(declare-function vulpea-note-title "vulpea")
(declare-function vulpea-merge "vulpea")
(declare-function vulpea-db-get-by-id "vulpea-db")
(declare-function vulpea-db-update-file "vulpea-db")
(declare-function vulpea-db--forget-file "vulpea-db")

(require 'org)
(require 'org-id)
(require 'subr-x)
(require 'seq)
(require 'cl-lib)
(require 'vulpea)
(declare-function sp-notes-filing-folder "sp-notes")
(defvar sp-notes-filing-root)

;; These must be defined before the functions below use them in `let',
;; so that the bindings are dynamic.
(defvar sp-split--active nil
  "Non-nil while `sp-split-leave-parents' is running.")

(defvar sp-split--want-link t
  "Non-nil when the split should leave a plain link in the source file.")

(defgroup sp-split nil
  "Split vulpea headings out with parents and a link left behind."
  :group 'applications)

(defcustom sp-split-file-by-tags t
  "When non-nil, ask for tags and file a split-out note into its tag folder."
  :type 'boolean
  :group 'sp-split)

(define-obsolete-variable-alias 'sp-split-denote-names 'sp-split-file-by-tags "2026-11-07")

(defcustom sp-split-inherit-tags nil
  "When non-nil, the new note also gets the tags its heading inherits.
It is the value of `org-use-tag-inheritance' while `sp-split-leave-parents' runs."
  :type 'boolean
  :group 'sp-split)

(defcustom sp-split-check-footnotes t
  "When non-nil, keep footnote definitions with the headings that cite them.
Definitions are copied, per heading, into the new note and, for those
that leave with the subtree, into the source note."
  :type 'boolean
  :group 'sp-split)

(defcustom sp-split-links-to-seealso t
  "When non-nil, move id links out of the split heading's title.
They are removed from the title of the new note and listed in a
`- seealso ::' meta line in its body."
  :type 'boolean
  :group 'sp-split)

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

(defconst sp-split--id-link-regexp
  "\\[\\[id:\\([^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]"
  "Match an id link; group 1 is the ID, group 2 the description, if any.")

(defun sp-split--extract-id-links (title)
  "Return (CLEAN-TITLE . LINKS) for the heading text TITLE.
LINKS are the id links found in TITLE, as strings, in order and without
duplicates; CLEAN-TITLE is TITLE with each link replaced by its description
(nothing, for a link without one), whitespace tidied.  When
nothing would be left of TITLE, it is returned as the text of its links'
descriptions and LINKS is nil, so the new note still has a title."
  (let ((links nil)
        (start 0))
    (while (string-match sp-split--id-link-regexp title start)
      (setq start (match-end 0))
      (cl-pushnew (match-string 0 title) links :test #'equal))
    (if (null links)
        (cons title nil)
      (let ((clean (string-trim
                    (replace-regexp-in-string
                     "[ \t]+" " "
                     (replace-regexp-in-string
                      sp-split--id-link-regexp
                      (lambda (m)
                        (save-match-data
                          (string-match sp-split--id-link-regexp m)
                          (or (match-string 2 m) "")))
                      title t t)
                     t t))))
        (if (string-empty-p clean)
            (cons (org-link-display-format title) nil)
          (cons clean (nreverse links)))))))

(defun sp-split--body-with-seealso (body links)
  "Return BODY with the id LINKS recorded in its `seealso' meta line.
A link whose ID is already on the line is not added again.  Like
`sp-split--body-with-parent', only the text before the first child
heading is looked at."
  (let* ((case-fold-search nil)
         (top-end (or (string-match "^\\*+ " body) (length body)))
         (top (substring body 0 top-end))
         (rest (substring body top-end)))
    (cond
     ((null links) body)
     ((string-match
       "^\\([ \t]*[-+][ \t]+seealso[ \t]+::[ \t]*\\)\\(.*\\)$" top)
      (let* ((mb (match-beginning 0))
             (me (match-end 0))
             (prefix (match-string 1 top))
             (existing (string-trim (match-string 2 top)))
             (new (seq-remove
                   (lambda (l)
                     (string-match sp-split--id-link-regexp l)
                     (string-search (concat "id:" (match-string 1 l)) existing))
                   links)))
        (if (null new)
            body
          (concat (substring top 0 mb)
                  prefix existing
                  (if (string-empty-p existing) "" ", ")
                  (string-join new ", ")
                  (substring top me)
                  rest))))
     (t
      (let ((line (concat "- seealso :: " (string-join links ", "))))
        (cond
         ((string-empty-p body) line)
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
             ;; Id links in the heading go to a `seealso' line, not the title.
             (extracted (if sp-split-links-to-seealso
                            (sp-split--extract-id-links title)
                          (cons title nil)))
             (title (car extracted))
             (body (sp-split--fn-check-body body id))
             (body (sp-split--body-with-seealso body (cdr extracted)))
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

(declare-function sp-org-tag-read-note-tags "sp-org-tag-lint")

(defcustom sp-split-ask-tags t
  "When non-nil, ask for the tags of a split-out note that has none.
The menu is `sp-org-tag-read-note-tags' (grouped by tag group); the tags
go into `#+filetags' and decide the folder of the file."
  :type 'boolean
  :group 'sp-split)

(defun sp-split--set-filetags (path tags)
  "Write TAGS as the `#+filetags' line of the note at PATH."
  (with-current-buffer (find-file-noselect path)
    (org-with-wide-buffer
     (goto-char (point-min))
     (let ((case-fold-search t)
           (line (format "#+filetags: :%s:" (mapconcat #'identity tags ":"))))
       (cond ((re-search-forward "^#\\+filetags:.*$" nil t)
              (replace-match line t t))
             ((re-search-forward "^#\\+title:.*$" nil t)
              (insert "\n" line)))))
    (save-buffer)))

(defun sp-split--file-by-tags (note)
  "Ask for the tags of NOTE if it has none, then file it into its tag folder.
Return the note as vulpea knows it afterwards.  The org ID stays the same,
so id links keep working.  A note without tags, or one already in its
folder, stays where it is, and so does one whose target file exists."
  (require 'sp-notes nil t)
  (let* ((old (vulpea-note-path note))
         (id (vulpea-note-id note))
         (tags (or (vulpea-note-tags note)
                   (when (and sp-split-ask-tags (require 'sp-org-tag-lint nil t))
                     (let ((chosen (sp-org-tag-read-note-tags
                                    (format "Tags for \"%s\": " (vulpea-note-title note)))))
                       (when chosen (sp-split--set-filetags old chosen))
                       chosen))))
         (root (and (boundp 'sp-notes-filing-root) sp-notes-filing-root
                    (file-name-as-directory (expand-file-name sp-notes-filing-root))))
         (dir (and tags root (fboundp 'sp-notes-filing-folder)
                   (file-name-as-directory
                    (expand-file-name (sp-notes-filing-folder tags) root))))
         (new (and dir (expand-file-name (file-name-nondirectory old) dir))))
    (if (or (not new) (file-equal-p old new) (file-exists-p new))
        (progn (when (and new (not (file-equal-p old new)))
                 (message "Not filed: %s exists" new))
               (if tags (or (vulpea-db-get-by-id id) note) note))
      (when-let* ((buffer (find-buffer-visiting old)))
        (with-current-buffer buffer (save-buffer))
        (kill-buffer buffer))
      (make-directory dir t)
      (rename-file old new)
          (vulpea-db--forget-file old)
      (org-id-add-location id new)
      (vulpea-db-update-file new)
      (message "Filed in %s" (abbreviate-file-name dir))
      (or (vulpea-db-get-by-id id) note))))

;;;###autoload
(defun sp-split-leave-parents (&optional no-link)
  "Run `vulpea-split-heading', recording where the heading came from.
The new note gets a `- parents ::' line linking back to the note the
subtree was split out of, and the source note gets a plain link to the
new note on the line where the heading started.  The new file is then
filed into the folder of its tags when `sp-split-file-by-tags' is
non-nil.  With a prefix argument NO-LINK, the link in the source is not
left."
  (interactive "P")
  (let* ((sp-split--active t)
         (sp-split--want-link (not no-link))
         ;; Keep vulpea's own stub option (the prefix argument) out of it.
         (current-prefix-arg nil)
         (sp-split--fn-report nil)
         (org-use-tag-inheritance sp-split-inherit-tags)
         (note (call-interactively #'vulpea-split-heading)))
    (prog1 (if (and note sp-split-file-by-tags)
               (sp-split--file-by-tags note)
             note)
      (sp-split--fn-message))))

(unless (fboundp 'vulpea-split--write-file)
  (display-warning
   'sp-split-leave-parents
   "`vulpea-split--write-file' not found; this vulpea version is not supported"))
(advice-add 'vulpea-split--write-file :around #'sp-split--write-file-advice)

(defconst sp-refile--new-note "[New note: own file]"
  "Prompt entry that splits the heading into a note of its own.")

(defconst sp-refile--other-note "[Another note...]"
  "Prompt entry that asks for another note, then a heading in it.")

(defconst sp-refile--top "[Top of note]"
  "Heading prompt entry for the whole note (its end, as a top-level heading).")

(require 'sp-move-region-to-heading)

(defun sp-refile--local-candidates ()
  "Return (OUTLINE-PATH . MARKER) for the headings of this buffer.
The subtree at point is left out, so it cannot be moved into itself."
  (let ((self (save-excursion (org-back-to-heading t) (point)))
        (self-end (save-excursion (org-back-to-heading t)
                                  (org-end-of-subtree t t) (point))))
    (org-with-wide-buffer
     (delq nil
           (org-map-entries
            (lambda ()
              (unless (and (>= (point) self) (< (point) self-end))
                (cons (mapconcat #'identity
                                 (append (org-get-outline-path)
                                         (list (org-get-heading t t t t)))
                                 " > ")
                      (point-marker)))))))))

(defun sp-refile--insert (text target buffer)
  "Insert the subtree TEXT as the last child of TARGET in BUFFER.
TARGET is a marker, or nil for the end of BUFFER as a top-level heading.
BUFFER is saved when it visits a file."
  (with-current-buffer buffer
    (org-with-wide-buffer
     (let ((level 1))
       (if target
           (progn (goto-char target)
                  (setq level (1+ (org-current-level)))
                  (org-end-of-subtree t t))
         (goto-char (point-max)))
       (unless (bolp) (insert "\n"))
       (let ((start (point)))
         (insert text)
         (unless (bolp) (insert "\n"))
         ;; Re-level the inserted tree to LEVEL.
         (save-excursion
           (goto-char start)
           (let ((delta (- level (org-current-level))))
             (unless (zerop delta)
               (org-map-region
                (lambda ()
                  (if (> delta 0)
                      (dotimes (_ delta) (org-do-demote))
                    (dotimes (_ (- delta)) (org-do-promote))))
                start (point-max))))))))
    (when buffer-file-name (save-buffer))))

(defun sp-refile--move-heading (target buffer)
  "Move the subtree at point under TARGET in BUFFER (see `sp-refile--insert').
The copy is made and saved first, the original is removed after."
  (let* ((src (current-buffer))
         (beg (save-excursion (org-back-to-heading t) (copy-marker (point))))
         (end (save-excursion (org-back-to-heading t)
                              (org-end-of-subtree t t) (copy-marker (point))))
         (text (buffer-substring-no-properties beg end)))
    (when (and (eq buffer src) target
               (>= target beg) (< target end))
      (user-error "Cannot refile a heading into itself"))
    (sp-refile--insert text target buffer)
    (with-current-buffer src
      (org-with-wide-buffer
       (delete-region beg end))
      (when buffer-file-name (save-buffer)))))

(defun sp-refile--read-other-note ()
  "Ask for a note and one of its headings.
Return (MARKER-OR-NIL BUFFER NOTE); a nil marker means the whole note."
  (let* ((note (sp-select-note "Refile to note: " :require-match t))
         (path (and (vulpea-note-p note) (vulpea-note-path note))))
    (unless path (user-error "No target note selected"))
    (let* ((cands (sp--org-heading-candidates path))
           (choice (completing-read "Under heading: "
                                    (cons sp-refile--top (mapcar #'car cands))
                                    nil t))
           (buf (find-file-noselect path)))
      (list (unless (string= choice sp-refile--top)
              (cdr (assoc choice cands)))
            buf note))))

(defun sp-refile--note-as-subtree ()
  "Return the whole current note as a level 1 subtree string.
The title becomes the heading, `#+filetags' its tags, the note's ID
stays in a property drawer, the text before the first heading comes
first and the headings follow, one level deeper."
  (let* ((text (org-with-wide-buffer (buffer-substring-no-properties
                                      (point-min) (point-max))))
         title tags id)
    (with-temp-buffer
      (insert text)
      (delay-mode-hooks (org-mode))
      (goto-char (point-min))
      (let ((kw (org-collect-keywords '("TITLE" "FILETAGS"))))
        (setq title (car (cdr (assoc "TITLE" kw)))
              tags (split-string (or (car (cdr (assoc "FILETAGS" kw))) "")
                                 ":" t "[ \t]+")))
      (setq id (org-entry-get (point-min) "ID"))
      (goto-char (point-min))
      ;; Drop the front matter: the top property drawer and #+keywords.
      (when (looking-at-p "[ \t]*:PROPERTIES:")
        (when (re-search-forward "^[ \t]*:END:[ \t]*\n?" nil t)
          (delete-region (point-min) (point))))
      (goto-char (point-min))
      (while (looking-at "[ \t]*#\\+[A-Za-z_]+:.*\n?")
        (replace-match ""))
      ;; Demote every existing heading by one.
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*+\\) " nil t)
        (replace-match "\\1* "))
      (concat "* " (or title "Untitled")
              (if tags (format " :%s:" (string-join tags ":")) "")
              "\n"
              (if id (format ":PROPERTIES:\n:ID:       %s\n:END:\n" id) "")
              (string-trim-left (buffer-string) "\n+")))))

(defun sp-refile--merge-note (target buffer note)
  "Merge the current note under TARGET in BUFFER, the buffer of NOTE.
With the top of the note as TARGET this is `vulpea-merge' (tags, aliases and
meta are folded in and links to the source re-pointed).  With a heading
as TARGET the note becomes a subtree there; Org functions only.  Asks
before the file of the current note is deleted."
  (if (and (null target) (fboundp 'vulpea-merge))
      (let* ((id (org-with-wide-buffer (org-entry-get (point-min) "ID")))
             (source (and id (vulpea-db-get-by-id id))))
        (unless source (user-error "This note is not in the Vulpea database"))
        (unless (y-or-n-p (format "Merge %s into %s and delete it? "
                                  (vulpea-note-title source)
                                  (vulpea-note-title note)))
          (user-error "Merge cancelled"))
        (vulpea-merge source note))
    (sp-refile--merge-subtree target buffer)))

(defun sp-refile--merge-subtree (target buffer)
  "Merge the current note as a subtree under TARGET in BUFFER.
Asks before the file of the current note is deleted afterwards."
  (let ((file buffer-file-name)
        (src (current-buffer)))
    (unless file (user-error "This buffer is not a note file"))
    (when (eq buffer src) (user-error "Cannot merge a note into itself"))
    (unless (y-or-n-p (format "Merge %s into %s and delete it? "
                              (file-name-nondirectory file)
                              (buffer-name buffer)))
      (user-error "Merge cancelled"))
    (let ((text (sp-refile--note-as-subtree)))
      (sp-refile--insert text target buffer)
      (set-buffer-modified-p nil)
      (kill-buffer src)
      (delete-file file delete-by-moving-to-trash)
      (when (fboundp 'vulpea-db-update-file)
        (ignore-errors (vulpea-db-update-file file))))
    (message "Merged %s" (file-name-nondirectory file))))

;;;###autoload
(defun sp-refile (&optional arg)
  "Move the heading at point, or merge the note when before its first heading.
On a heading, choose from the headings of this note, `[New note: own
file]' (split, see `sp-split-leave-parents'; a plain prefix argument
leaves no link) or `[Another note...]'.  Before the first heading, or
with `C-u C-u', the whole note is merged under a heading of another note."
  (interactive "P")
  (unless (derived-mode-p 'org-mode) (user-error "Not an Org buffer"))
  (let ((merge (or (equal arg '(16))
                   (org-with-wide-buffer
                    (and (not (ignore-errors (org-back-to-heading t) t)))))))
    (if merge
        (pcase-let ((`(,target ,buf ,note) (sp-refile--read-other-note)))
          (sp-refile--merge-note target buf note))
      (let* ((cands (sp-refile--local-candidates))
             (choice (completing-read
                      "Refile to: "
                      (append (list sp-refile--new-note sp-refile--other-note)
                              (mapcar #'car cands))
                      nil t)))
        (cond
         ((string= choice sp-refile--new-note)
          (let ((current-prefix-arg arg))
            (sp-split-leave-parents (and arg t))))
         ((string= choice sp-refile--other-note)
          (pcase-let ((`(,target ,buf ,_note) (sp-refile--read-other-note)))
            (sp-refile--move-heading target buf)))
         (t
          (sp-refile--move-heading (cdr (assoc choice cands))
                                   (current-buffer))))))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-w") #'sp-refile))

(provide 'sp-refile)
(provide 'sp-split-leave-parents)
;;; sp-refile.el ends here
