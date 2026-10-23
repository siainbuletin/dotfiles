;;; sp-org-lint.el --- Lint and tidy plain lists in Org buffers -*- lexical-binding: t; -*-

;;; Commentary:

;; This module provides two commands for tidying plain lists in Org buffers,
;; aimed at lists of links such as reading or resource lists.
;; `sp-org-lint-list' turns stray paragraph lines into list items, removes
;; blank lines between items and drops items whose https link already appeared
;; earlier.
;;
;; `sp-org-lint-footnotes' lints the footnotes of the whole vulpea vault: it
;; moves the definitions of a trailing `Footnotes' heading to the heading that
;; contains their reference, and reports orphan definitions and dangling
;; references.  A second, headless Emacs reads the files, so Emacs stays
;; usable; the report comes first and nothing is changed (after a backup)
;; until you apply it.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'org)
(require 'org-list)
(require 'org-element)
(require 'subr-x)
(require 'sp-paths nil t)

(defvar sp-notes-dir)

(defconst sp-org--item-re
  "^\\(?:[ \t]+\\*\\|[ \t]*[-+]\\|[ \t]*[0-9]+[.)]\\)[ \t]"
  "Match the start of a plain list item line.
A bare `*' only counts when indented, so headings are not mistaken for items.")

(defconst sp-org--url-re "https://[^] \t\n\r<>\"[]+"
  "Match an https:// URL.
Change `https://' to `https?://' to also treat http links as links.")

;;;; Region detection

(defun sp-org--item-near-point ()
  "Return the start of the list item at or near point, or nil.
On a list line (item or continuation text) that is the item itself.
On a blank line, the nearest list above, then below, is used.
On any other line nil is returned."
  (save-excursion
    (beginning-of-line)
    (cond
     ((org-in-item-p))
     ((looking-at-p "[ \t]*$")
      (or (progn (skip-chars-backward " \t\n")
                 (and (not (bobp)) (org-in-item-p)))
          (progn (skip-chars-forward " \t\n")
                 (beginning-of-line)
                 (and (not (eobp)) (org-in-item-p))))))))

(defun sp-org--list-bounds ()
  "Return (BEG . END) of the whole plain list at or near point, or nil.
BEG is the start of the first item of the outermost list; END is the
end of the last non-blank line belonging to it."
  (let ((item (sp-org--item-near-point)))
    (when item
      (save-excursion
        (goto-char item)
        (let* ((struct (org-list-struct))
               (beg (org-list-get-top-point struct))
               (end (org-list-get-bottom-point struct)))
          (goto-char end)
          (skip-chars-backward " \t\n")
          (cons beg (point)))))))

(defun sp-org--block-bounds ()
  "Return (BEG . END) of the consecutive non-blank lines around point, or nil."
  (save-excursion
    (beginning-of-line)
    (unless (looking-at-p "[ \t]*$")
      (let ((beg (save-excursion
                   (if (re-search-backward "^[ \t]*$" nil t)
                       (progn (forward-line 1) (point))
                     (point-min))))
            (end (save-excursion
                   (if (re-search-forward "^[ \t]*$" nil t)
                       (progn (forward-line -1) (line-end-position))
                     (point-max)))))
        (cons beg end)))))

(defun sp-org--auto-bounds ()
  "Return (BEG . END) of the list at point, else of the text block at point."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (or (sp-org--list-bounds)
      (sp-org--block-bounds)
      (user-error "No list or text block found at point")))

(defun sp-org--region-args ()
  "Return (BEG END): the active region, else the list or block at point."
  (if (use-region-p)
      (list (region-beginning) (region-end))
    (let ((bounds (sp-org--auto-bounds)))
      (list (car bounds) (cdr bounds)))))

;;;###autoload
(defun sp-org-mark-list ()
  "Mark what the lint commands would act on without an active region."
  (interactive)
  (let ((bounds (sp-org--auto-bounds)))
    (goto-char (car bounds))
    (push-mark (cdr bounds) nil t)))

;;;; Step 1: turn plain lines into items

(defun sp-org--convertible-line-p ()
  "Non-nil if the line at point is plain paragraph text outside any list.
Blank lines, headings, keywords, drawers, tables, blocks and text
belonging to a list item (including indented continuation lines)
are not convertible."
  (and (not (looking-at-p "[ \t]*$"))
       (not (org-in-item-p))
       (eq (org-element-type (org-element-at-point)) 'paragraph)))

(defun sp-org--convert-lines-to-items (beg end-marker)
  "Run `org-toggle-item' on each plain line between BEG and END-MARKER.
Return the number of lines converted."
  (let ((count 0))
    (save-excursion
      (goto-char beg)
      (while (< (point) end-marker)
        (let ((next (copy-marker (line-beginning-position 2))))
          (when (sp-org--convertible-line-p)
            ;; Hide the region so `org-toggle-item' only handles this line.
            (let ((mark-active nil))
              (org-toggle-item nil))
            (setq count (1+ count)))
          (goto-char next)
          (set-marker next nil))))
    count))

;;;; Step 2: remove blank lines between items

(defun sp-org--remove-blank-lines-between-items (beg end-marker)
  "Delete blank lines between list items from BEG to END-MARKER."
  (save-excursion
    (goto-char beg)
    (while (re-search-forward "\n\\(?:[ \t]*\n\\)+" end-marker t)
      (let ((blank-beg (match-beginning 0))
            (blank-end (match-end 0)))
        (when (and
               ;; the next non-blank line starts a list item...
               (save-excursion
                 (goto-char blank-end)
                 (looking-at-p sp-org--item-re))
               ;; ...and the previous line belongs to a list
               ;; (an item itself, or an indented continuation line).
               (save-excursion
                 (goto-char blank-beg)
                 (beginning-of-line)
                 (or (looking-at-p sp-org--item-re)
                     (looking-at-p "[ \t]+[^ \t\n]"))))
          (replace-match "\n"))))))

;;;; Step 3: remove duplicate links

(defun sp-org--normalize-url (url)
  "Return URL in a canonical form for comparison.
Trailing punctuation, an unbalanced closing parenthesis and trailing
slashes are dropped, and the host is lower-cased."
  (setq url (replace-regexp-in-string "[.,;:!?]+\\'" "" url))
  (when (and (string-suffix-p ")" url) (not (string-match-p "(" url)))
    (setq url (substring url 0 -1)))
  (setq url (replace-regexp-in-string "/+\\'" "" url))
  (if (string-match "\\`\\(https://[^/?#]*\\)" url)
      (concat (downcase (match-string 1 url)) (substring url (match-end 1)))
    url))

(defun sp-org--item-url (item-beg item-end)
  "Return the normalized https:// URL of the item from ITEM-BEG to ITEM-END.
ITEM-END is the end of the item's last line.  Only the item's own
text is searched, not its nested items.  Return nil if the item has
no such link."
  (save-excursion
    (goto-char item-beg)
    (end-of-line)
    (let ((own-end (save-excursion
                     ;; A nested item line, if any, ends the item's own text.
                     (if (re-search-forward sp-org--item-re item-end t)
                         (line-beginning-position)
                       item-end))))
      (goto-char item-beg)
      (when (re-search-forward sp-org--url-re own-end t)
        (sp-org--normalize-url (match-string 0))))))

(defun sp-org--remove-duplicate-links (beg end-marker)
  "Remove list items whose https:// link already appeared earlier.
The first occurrence is kept.  Items without a link are never removed,
and neither are duplicates that have nested items.
Return (REMOVED . KEPT-BECAUSE-NESTED)."
  (let ((seen (make-hash-table :test #'equal))
        (removed 0)
        (kept 0))
    (save-excursion
      (goto-char beg)
      (while (and (< (point) end-marker)
                  (re-search-forward sp-org--item-re end-marker t))
        (beginning-of-line)
        (if (not (org-in-item-p))
            (end-of-line)
          (let* ((pos (point))
                 (struct (org-list-struct))
                 ;; End of the item's last line, before any trailing blank lines.
                 (item-end (org-list-get-item-end-before-blank pos struct))
                 (url (sp-org--item-url pos item-end)))
            (cond
             ((or (null url) (not (gethash url seen)))
              (when url (puthash url t seen))
              (end-of-line))
             ((org-list-has-child-p pos struct)
              (setq kept (1+ kept))
              (end-of-line))
             (t
              ;; Delete the whole line(s), including the final newline.
              (delete-region pos (min (1+ item-end) (point-max)))
              (setq removed (1+ removed))))))))
    (cons removed kept)))

;;;; Step 4: sort

(defun sp-org--sort-key ()
  "Sort key for the list item at point.
This is the item text as displayed (links replaced by their
description, or their target when they have none), lower-cased."
  (let* ((line (buffer-substring-no-properties
                (line-beginning-position) (line-end-position)))
         (text (replace-regexp-in-string
                "\\`[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t]+\\(?:\\[[- X]\\][ \t]+\\)?"
                "" line)))
    (downcase (string-trim (org-link-display-format text)))))

(defun sp-org--sort-lists (beg end-marker)
  "Sort each top-level list between BEG and END-MARKER alphabetically."
  (save-excursion
    (goto-char beg)
    (while (and (< (point) end-marker)
                (re-search-forward sp-org--item-re end-marker t))
      (beginning-of-line)
      (if (not (org-in-item-p))
          (end-of-line)
        (let ((bottom (copy-marker
                       (org-list-get-bottom-point (org-list-struct)))))
          (org-sort-list nil ?f #'sp-org--sort-key #'string<)
          (goto-char bottom)
          (set-marker bottom nil))))))

;;;; Pipeline and commands

(defun sp-org--check-region (beg end)
  "Signal an error unless in `org-mode' and BEG/END are usable."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (when (= beg end)
    (user-error "Region is empty")))

(defun sp-org--lint (beg end sort)
  "Lint the lines from BEG to END; also sort the lists when SORT is non-nil."
  (sp-org--check-region beg end)
  (let ((beg-marker (copy-marker (save-excursion
                                   (goto-char beg)
                                   (line-beginning-position))))
        (end-marker (copy-marker end))
        (converted 0)
        (dupes '(0 . 0)))
    (unwind-protect
        (atomic-change-group
          (setq converted (sp-org--convert-lines-to-items beg-marker end-marker))
          (sp-org--remove-blank-lines-between-items beg-marker end-marker)
          (setq dupes (sp-org--remove-duplicate-links beg-marker end-marker))
          (when sort
            (sp-org--sort-lists beg-marker end-marker)))
      (set-marker beg-marker nil)
      (set-marker end-marker nil))
    (message "sp-org-lint: %d line(s) converted to items, %d duplicate link(s) removed%s"
             converted (car dupes)
             (if (> (cdr dupes) 0)
                 (format " (%d duplicate(s) with nested items kept)" (cdr dupes))
               ""))))

;;;###autoload
(defun sp-org-lint-list (beg end)
  "Tidy the list lines between BEG and END.
Operates on the active region, or on the list (else the block of
consecutive non-blank lines) at point.  Plain lines are turned into
items with `org-toggle-item', blank lines between items are removed,
and items with a duplicate https:// link are removed."
  (interactive (sp-org--region-args))
  (sp-org--lint beg end nil))

;;;###autoload
(defun sp-org-lint-resources (beg end)
  "Like `sp-org-lint-list', then sort each top-level list alphabetically.
Items are sorted case-insensitively by their displayed text.  Nested
sublists travel with their parent item but are not re-sorted."
  (interactive (sp-org--region-args))
  (sp-org--lint beg end t))

;;;; Sectional footnotes

(defgroup sp-org-lint nil
  "Lint Org files."
  :group 'org)

(defcustom sp-org-lint-fn-section-title "Footnotes"
  "Title of the heading whose footnote definitions are moved (case is ignored)."
  :type 'string
  :group 'sp-org-lint)

(defcustom sp-org-lint-fn-remove-empty-section t
  "When non-nil, remove a footnotes heading that is empty after its moves.
A heading with children, or with anything but the moved definitions
\(a property drawer, a paragraph), is kept."
  :type 'boolean
  :group 'sp-org-lint)

(defcustom sp-org-lint-fn-directory
  (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes")
  "Folder scanned when the vulpea database is not available."
  :type 'directory
  :group 'sp-org-lint)

(defcustom sp-org-lint-fn-exclude-regexp
  "\\(?:\\`\\|/\\)\\(?:\\.[^/]+\\|ltximg\\|attach\\|data\\)/"
  "Files whose path matches this regexp are not scanned.
The path is taken relative to the scanned folder when the file is in
it.  The default skips hidden folders and the usual attachment ones."
  :type 'regexp
  :group 'sp-org-lint)

(defcustom sp-org-lint-fn-backup-directory
  (expand-file-name "sp-org-lint-backups/" user-emacs-directory)
  "Folder that receives a copy of every file before it is changed."
  :type 'directory
  :group 'sp-org-lint)

(defcustom sp-org-lint-fn-files-function #'sp-org-lint-fn-vault-files
  "Function returning the list of Org files to lint."
  :type 'function
  :group 'sp-org-lint)

(defun sp-org-lint-fn--scan ()
  "Scan the current Org buffer for headings and footnotes.
Return (HEADS REFS DEFS).  HEADS lists plists (:begin :title :end
:own-end) sorted by position: :end is the end of the subtree and
:own-end the start of the next heading of any level.  REFS lists
\(LABEL BEGIN) for the standard references `[fn:LABEL]'.  DEFS lists
plists (:label :begin :end :text :inline); a labelled inline
footnote counts as a definition that is already in place."
  (let ((tree (org-element-parse-buffer))
        heads refs defs)
    (org-element-map tree 'headline
      (lambda (h)
        (push (list :begin (org-element-property :begin h)
                    :title (org-element-property :raw-value h)
                    :end (org-element-property :end h)
                    :own-end nil)
              heads)))
    (setq heads (sort heads (lambda (a b)
                              (< (plist-get a :begin) (plist-get b :begin)))))
    (let ((tail heads))
      (while tail
        (plist-put (car tail) :own-end
                   (if (cdr tail) (plist-get (cadr tail) :begin) (point-max)))
        (setq tail (cdr tail))))
    (org-element-map tree '(footnote-reference footnote-definition)
      (lambda (el)
        (let ((label (org-element-property :label el))
              (begin (org-element-property :begin el))
              (end (org-element-property :end el)))
          (when label
            (cond
             ((eq (org-element-type el) 'footnote-definition)
              (push (list :label label :begin begin :end end
                          :text (string-trim-right
                                 (buffer-substring-no-properties begin end)))
                    defs))
             ((eq (org-element-property :type el) 'inline)
              (let ((cb (org-element-property :contents-begin el))
                    (ce (org-element-property :contents-end el)))
                (when (and cb ce)
                  (push (list :label label :begin begin :end end :inline t
                              :text (format "[fn:%s] %s" label
                                            (string-trim
                                             (buffer-substring-no-properties
                                              cb ce))))
                        defs))))
             (t (push (list label begin) refs)))))))
    (list heads (nreverse refs) (nreverse defs))))

(defun sp-org-lint-fn--section (pos heads)
  "Return the start of the section containing POS, given sorted HEADS.
Text before the first heading is section 0."
  (let ((sec 0))
    (dolist (h heads sec)
      (when (<= (plist-get h :begin) pos)
        (setq sec (plist-get h :begin))))))

(defun sp-org-lint-fn--head (sec heads)
  "Return the heading plist of section SEC, or nil for section 0."
  (seq-find (lambda (h) (= (plist-get h :begin) sec)) heads))

(defun sp-org-lint-fn--section-end (sec heads)
  "Return the end of section SEC: the next heading, or the end of buffer."
  (if (zerop sec)
      (if heads (plist-get (car heads) :begin) (point-max))
    (plist-get (sp-org-lint-fn--head sec heads) :own-end)))

(defun sp-org-lint-fn--section-title (sec heads)
  "Return a title for section SEC."
  (if (zerop sec)
      "(before the first heading)"
    (string-trim (plist-get (sp-org-lint-fn--head sec heads) :title))))

(defun sp-org-lint-fn--footnotes-section-p (sec heads)
  "Non-nil when section SEC is a heading titled `sp-org-lint-fn-section-title'."
  (when-let* ((h (sp-org-lint-fn--head sec heads)))
    (string= (downcase (string-trim (plist-get h :title)))
             (downcase sp-org-lint-fn-section-title))))

(defun sp-org-lint-fn--fresh (label used)
  "Return LABEL if it is not in USED, else LABEL-2, LABEL-3, ... likewise."
  (if (not (member label used))
      label
    (let ((n 2))
      (while (member (format "%s-%d" label n) used)
        (setq n (1+ n)))
      (format "%s-%d" label n))))

(defun sp-org-lint-fn--def-with-label (text label)
  "Return the definition TEXT with its label replaced by LABEL."
  (replace-regexp-in-string "\\`\\[fn:[^]\n]*\\]" (format "[fn:%s]" label)
                            text t t))

(defun sp-org-lint-fn--only-deleted-p (head deletions)
  "Non-nil when HEAD's own text is blank once DELETIONS are taken out."
  (let ((pos (save-excursion
               (goto-char (plist-get head :begin))
               (line-end-position)))
        (rest ""))
    (dolist (e (sort (copy-sequence deletions)
                     (lambda (x y) (< (car x) (car y)))))
      (setq rest (concat rest (buffer-substring-no-properties pos (car e)))
            pos (+ (car e) (cadr e))))
    (string-blank-p
     (concat rest (buffer-substring-no-properties pos (plist-get head :own-end))))))

(defun sp-org-lint-fn--plan ()
  "Plan the footnote moves in the current Org buffer; change nothing.
Return a plist: :moves, :orphans, :dangling, :conflicts, :removed (titles
of footnotes headings to remove), and for `sp-org-lint-fn--apply-edits'
:heads, :adds and :edits, with :n-defs, :n-refs and :n-deleted for the
check afterwards."
  (let* ((scan (sp-org-lint-fn--scan))
         (heads (nth 0 scan))
         (refs (nth 1 scan))
         (defs (nth 2 scan))
         (fn-defs (seq-filter
                   (lambda (d)
                     (and (not (plist-get d :inline))
                          (sp-org-lint-fn--footnotes-section-p
                           (sp-org-lint-fn--section (plist-get d :begin)
                                                    heads)
                           heads)))
                   defs))
         (nested-p (lambda (r)
                     (seq-some (lambda (d)
                                 (and (>= (cadr r) (plist-get d :begin))
                                      (< (cadr r) (plist-get d :end))))
                               fn-defs)))
         (cited (seq-remove nested-p refs))
         (def-labels (mapcar (lambda (d) (plist-get d :label)) defs))
         (ref-labels (mapcar #'car refs))
         (used (seq-uniq (append def-labels ref-labels)))
         moves conflicts edits adds removed)
    (dolist (d fn-defs)
      (let* ((label (plist-get d :label))
             (mine (seq-filter (lambda (r) (equal (car r) label)) cited))
             (secs (seq-uniq (mapcar (lambda (r)
                                       (sp-org-lint-fn--section (cadr r) heads))
                                     mine)))
             (from (sp-org-lint-fn--section-title
                    (sp-org-lint-fn--section (plist-get d :begin) heads) heads))
             (line (line-number-at-pos (plist-get d :begin))))
        (cond
         ((> (seq-count (lambda (l) (equal l label)) def-labels) 1)
          (push (cons label "defined more than once") conflicts))
         ((null mine)
          (when (member label (mapcar #'car (seq-filter nested-p refs)))
            (push (cons label "cited only from another footnote") conflicts)))
         ((seq-some (lambda (s) (sp-org-lint-fn--footnotes-section-p s heads))
                    secs)
          (push (cons label "cited from the footnotes section itself")
                conflicts))
         (t
          (let ((first t))
            (dolist (sec secs)
              (let ((new (if first label (sp-org-lint-fn--fresh label used))))
                (push new used)
                (unless (equal new label)
                  (dolist (r (seq-filter
                              (lambda (r)
                                (eql (sp-org-lint-fn--section (cadr r) heads)
                                     sec))
                              mine))
                    ;; Skip `[fn:' to reach the label itself.
                    (push (list (+ (cadr r) 4) (length label) new) edits)))
                (push (sp-org-lint-fn--def-with-label (plist-get d :text) new)
                      (alist-get sec adds nil nil #'eql))
                (push (list :label label :new new :from from
                            :to (sp-org-lint-fn--section-title sec heads)
                            :line line)
                      moves)
                (setq first nil))))
          (push (list (plist-get d :begin)
                      (- (plist-get d :end) (plist-get d :begin))
                      "")
                edits)))))
    (let ((n-deleted (seq-count (lambda (e) (equal (nth 2 e) "")) edits)))
      (when sp-org-lint-fn-remove-empty-section
        (dolist (h heads)
          (let* ((b (plist-get h :begin))
                 (own-end (plist-get h :own-end))
                 (dels (seq-filter (lambda (e)
                                     (and (equal (nth 2 e) "")
                                          (> (car e) b)
                                          (<= (+ (car e) (cadr e)) own-end)))
                                   edits)))
            (when (and dels
                       (>= own-end (plist-get h :end))
                       (sp-org-lint-fn--only-deleted-p h dels))
              (setq edits (cons (list b (- (plist-get h :end) b) "")
                                (seq-difference edits dels))
                    removed (cons (list (string-trim (plist-get h :title))
                                        (= (plist-get h :end) (point-max)))
                                  removed))))))
      (list :moves (nreverse moves)
            :orphans (seq-uniq
                      (mapcar (lambda (d) (plist-get d :label))
                              (seq-filter
                               (lambda (d)
                                 (and (not (plist-get d :inline))
                                      (not (member (plist-get d :label)
                                                   ref-labels))))
                               defs)))
            :dangling (seq-uniq (seq-remove (lambda (l) (member l def-labels))
                                            ref-labels))
            :conflicts (nreverse conflicts)
            :removed removed
            :heads heads :adds adds :edits edits
            :n-defs (length defs) :n-refs (length refs)
            :n-deleted n-deleted))))

(defun sp-org-lint-fn--apply-edits (heads adds edits)
  "Apply footnote changes to the current buffer.
ADDS maps a section to the definition texts to put at the end of it
\(newest first).  EDITS is a list of (POS LENGTH STRING) replacements.
Everything is positioned against the buffer as it is now."
  (dolist (a adds)
    (let* ((pos (sp-org-lint-fn--section-end (car a) heads))
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
  (dolist (e (sort edits (lambda (x y)
                           (or (> (car x) (car y))
                               (and (= (car x) (car y)) (> (cadr x) (cadr y)))))))
    (goto-char (car e))
    (delete-region (car e) (+ (car e) (cadr e)))
    (insert (nth 2 e))))

(defun sp-org-lint-fn--counts (text)
  "Return (N-DEFS N-REFS DANGLING) for the footnotes in TEXT."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert text)
    (pcase-let* ((`(,_ ,refs ,defs) (sp-org-lint-fn--scan))
                 (def-labels (mapcar (lambda (d) (plist-get d :label)) defs)))
      (list (length defs) (length refs)
            (sort (seq-uniq (seq-remove (lambda (l) (member l def-labels))
                                        (mapcar #'car refs)))
                  #'string<)))))

(defun sp-org-lint-fn-plan-text (text)
  "Plan the footnote moves for the Org TEXT.
Return a plist: :moves, :orphans, :dangling, :conflicts, :removed, and
when something moves :changed t and :text, the new text.  A text whose
result fails the check gets :error instead."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert text)
    (let* ((plan (sp-org-lint-fn--plan))
           (result (list :moves (plist-get plan :moves)
                         :orphans (plist-get plan :orphans)
                         :dangling (plist-get plan :dangling)
                         :conflicts (plist-get plan :conflicts)
                         :removed (mapcar #'car (plist-get plan :removed)))))
      (if (null (plist-get plan :moves))
          result
        (sp-org-lint-fn--apply-edits (plist-get plan :heads)
                                     (plist-get plan :adds)
                                     (plist-get plan :edits))
        ;; A footnotes heading removed from the end of the file would
        ;; leave blank lines behind.
        (when (seq-some #'cadr (plist-get plan :removed))
          (goto-char (point-max))
          (skip-chars-backward " \t\n")
          (delete-region (point) (point-max))
          (insert "\n"))
        (let* ((new (buffer-string))
               (after (sp-org-lint-fn--counts new))
               (want-defs (+ (plist-get plan :n-defs)
                             (length (plist-get plan :moves))
                             (- (plist-get plan :n-deleted)))))
          (if (and (= (nth 0 after) want-defs)
                   (= (nth 1 after) (plist-get plan :n-refs))
                   (equal (nth 2 after) (sort (copy-sequence
                                               (plist-get plan :dangling))
                                              #'string<)))
              (append result (list :changed t :text new))
            (append result
                    (list :error "the result failed the footnote check; file left alone"))))))))

(defun sp-org-lint-fn--read (file)
  "Return the text of FILE, read as UTF-8.
Signal an error for a file that is not clean UTF-8 or has carriage returns,
since writing it back could change it."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (when (search-forward "\r" nil t)
      (error "carriage returns in the file; not touched"))
    (when (memq 'eight-bit (find-charset-region (point-min) (point-max)))
      (error "the file is not valid UTF-8; not touched"))
    (buffer-string)))

(defun sp-org-lint-fn-plan-file (file)
  "Plan FILE: the plist of `sp-org-lint-fn-plan-text' with :file and :sha."
  (condition-case err
      (let ((text (sp-org-lint-fn--read file)))
        (append (list :file file :sha (secure-hash 'sha1 text))
                (sp-org-lint-fn-plan-text text)))
    (error (list :file file :error (error-message-string err)))))

(defun sp-org-lint-fn--backup (file root)
  "Copy FILE below the folder ROOT, keeping its path.  Return the copy."
  (let* ((file (file-truename file))
         (dest (expand-file-name
               (replace-regexp-in-string "\\`\\(?:[A-Za-z]:\\)?[/\\\\]*" ""
                                         file)
               root)))
    (make-directory (file-name-directory dest) t)
    (copy-file file dest t t)
    (unless (= (file-attribute-size (file-attributes file))
               (file-attribute-size (file-attributes dest)))
      (error "backup of the file is incomplete"))
    dest))

(defun sp-org-lint-fn--write (file text)
  "Replace the contents of FILE with TEXT, through a temporary file.
When FILE is a symbolic link the file it points to is replaced, so the link
stays a link."
  (let* ((file (file-truename file))
         (tmp (make-temp-file (concat file ".sp-lint-")))
         (modes (file-modes file)))
    (condition-case err
        (progn
          (let ((coding-system-for-write 'utf-8-unix))
            (write-region text nil tmp nil 'silent))
          (when modes (set-file-modes tmp modes))
          (rename-file tmp file t))
      (error (ignore-errors (delete-file tmp))
             (signal (car err) (cdr err))))))

(defun sp-org-lint-fn-apply-file (file sha backup-root)
  "Apply the plan to FILE if its text still has the SHA-1 SHA.
The file is copied below BACKUP-ROOT first.  Return a plist with :file
and :status, `written' (with :backup and :moves) or `skipped' (with
:reason)."
  (condition-case err
      (let ((text (sp-org-lint-fn--read file)))
        (if (not (equal (secure-hash 'sha1 text) sha))
            (list :file file :status 'skipped
                  :reason "changed since the preview")
          (let ((plan (sp-org-lint-fn-plan-text text)))
            (cond
             ((plist-get plan :error)
              (list :file file :status 'skipped :reason (plist-get plan :error)))
             ((not (plist-get plan :changed))
              (list :file file :status 'skipped :reason "nothing to move"))
             (t
              (let ((backup (sp-org-lint-fn--backup file backup-root)))
                ;; The last look, just before the write: it leaves a gap
                ;; of milliseconds for someone else to save the file.
                (cond
                 ((file-locked-p file)
                  (list :file file :status 'skipped
                        :reason "open with unsaved changes in another Emacs"))
                 ((not (equal (secure-hash 'sha1 (sp-org-lint-fn--read file))
                              sha))
                  (list :file file :status 'skipped
                        :reason "changed while it was being linted"))
                 (t
                  (sp-org-lint-fn--write file (plist-get plan :text))
                  (list :file file :status 'written :backup backup
                        :moves (length (plist-get plan :moves)))))))))))
    (error (list :file file :status 'skipped
                 :reason (error-message-string err)))))

(defvar sp-org-lint--library (or load-file-name (locate-library "sp-org-lint"))
  "File this library was loaded from; the headless Emacs loads the same one.")

(defun sp-org-lint-fn--emit (object)
  "Print OBJECT as one line for the main Emacs to read."
  (let ((print-length nil) (print-level nil)
        (print-escape-newlines t) (print-escape-multibyte t)
        (print-escape-nonascii t))
    (princ (concat "SPLINT " (prin1-to-string object) "\n"))))

(defun sp-org-lint-fn--batch (control-file)
  "Run the job described in CONTROL-FILE and print one result per file."
  (let* ((ctl (with-temp-buffer
                (insert-file-contents control-file)
                (read (current-buffer))))
         (files (plist-get ctl :files)))
    (if (eq (plist-get ctl :mode) 'apply)
        (dolist (f files)
          (sp-org-lint-fn--emit
           (sp-org-lint-fn-apply-file (car f) (cdr f)
                                      (plist-get ctl :backup-root))))
      (dolist (f files)
        (let ((plan (sp-org-lint-fn-plan-file f)))
          (sp-org-lint-fn--emit (if (plist-get plan :changed)
                                    (plist-put plan :text nil)
                                  plan)))))
    (sp-org-lint-fn--emit '(:done t))))

(defun sp-org-lint-fn--org-files (candidates root)
  "Return the existing Org files in CANDIDATES, sorted, minus the excluded ones.
Paths inside ROOT are matched against `sp-org-lint-fn-exclude-regexp'
relative to it."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (sort
     (seq-uniq
      (seq-filter
       (lambda (f)
         (and (string-suffix-p ".org" f)
              (file-regular-p f)
              (not (string-match-p
                    sp-org-lint-fn-exclude-regexp
                    (if (string-prefix-p root f) (substring f (length root)) f)))))
       (mapcar #'expand-file-name candidates)))
     #'string<)))

(defun sp-org-lint-fn-vault-files ()
  "Return the Org files of the vulpea database, else of `sp-org-lint-fn-directory'."
  (let ((paths (when (and (fboundp 'vulpea-db-query) (fboundp 'vulpea-note-path))
                 (ignore-errors (mapcar #'vulpea-note-path (vulpea-db-query))))))
    (sp-org-lint-fn--org-files
     (or (delq nil paths)
         (directory-files-recursively sp-org-lint-fn-directory "\\.org\\'"))
     sp-org-lint-fn-directory)))

(defconst sp-org-lint-fn--buffer-name "*sp-org-lint footnotes*"
  "Name of the report buffer.")

(defvar-local sp-org-lint-fn--run nil
  "Plist with the state of the run shown in this report buffer.")

(defun sp-org-lint-fn--get (key)
  "Return KEY of the run state."
  (plist-get sp-org-lint-fn--run key))

(defun sp-org-lint-fn--set (key value)
  "Set KEY of the run state to VALUE."
  (setq sp-org-lint-fn--run (plist-put sp-org-lint-fn--run key value)))

(defun sp-org-lint-fn--header ()
  "Header line of the report buffer."
  (let ((phase (sp-org-lint-fn--get :phase)))
    (pcase phase
      ((or 'scan 'apply)
       (format " Footnote lint: %s %d/%d"
               (if (eq phase 'scan) "scanning" "applying")
               (or (sp-org-lint-fn--get :done) 0)
               (or (sp-org-lint-fn--get :total) 0)))
      ('ready " Footnote lint: RET visit, a apply, g rescan, q quit")
      ('applied " Footnote lint: applied; RET visit, g rescan, q quit")
      (_ " Footnote lint"))))

(defvar sp-org-lint-fn-report-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'sp-org-lint-fn-visit)
    (define-key map (kbd "a") #'sp-org-lint-footnotes-apply)
    (define-key map (kbd "g") #'sp-org-lint-footnotes)
    map)
  "Keymap of `sp-org-lint-fn-report-mode'.")

(define-derived-mode sp-org-lint-fn-report-mode special-mode "FnLint"
  "Report of the footnote lint of the vault."
  (setq-local header-line-format '(:eval (sp-org-lint-fn--header))))

(defun sp-org-lint-fn-visit ()
  "Visit the file and line of the report line at point."
  (interactive)
  (let ((file (get-text-property (line-beginning-position) 'sp-file))
        (line (get-text-property (line-beginning-position) 'sp-line)))
    (unless file (user-error "No file on this line"))
    (find-file-other-window file)
    (goto-char (point-min))
    (forward-line (1- (or line 1)))))

(defun sp-org-lint-fn--shown-p (plan)
  "Non-nil when PLAN has anything to report."
  (or (plist-get plan :moves) (plist-get plan :orphans)
      (plist-get plan :dangling) (plist-get plan :conflicts)
      (plist-get plan :error)))

(defun sp-org-lint-fn--insert-plan (plan)
  "Insert the report of PLAN at the end of the buffer."
  (let ((file (plist-get plan :file))
        (inhibit-read-only t))
    (save-excursion
      (goto-char (point-max))
      (cl-flet ((line (line text)
                  (insert (propertize (concat "  " text "\n")
                                      'sp-file file 'sp-line line))))
        (insert (propertize (format "* %s\n" (abbreviate-file-name file))
                            'sp-file file 'sp-line 1 'face 'bold))
        (when-let* ((err (plist-get plan :error)))
          (line 1 (format "error: %s" err)))
        (dolist (m (plist-get plan :moves))
          (line (plist-get m :line)
                (format "[fn:%s] %s -> %s%s"
                        (plist-get m :label) (plist-get m :from) (plist-get m :to)
                        (if (equal (plist-get m :new) (plist-get m :label))
                            ""
                          (format " (as [fn:%s])" (plist-get m :new))))))
        (dolist (l (plist-get plan :orphans))
          (line 1 (format "orphan: [fn:%s] is defined and never cited" l)))
        (dolist (l (plist-get plan :dangling))
          (line 1 (format "dangling: [fn:%s] is cited and never defined" l)))
        (dolist (c (plist-get plan :conflicts))
          (line 1 (format "left alone: [fn:%s] is %s" (car c) (cdr c))))
        (dolist (title (plist-get plan :removed))
          (line 1 (format "the empty \"%s\" heading would be removed" title)))
        (insert "\n")))))

(defun sp-org-lint-fn--summary ()
  "Return the summary line of a finished scan."
  (let ((plans (sp-org-lint-fn--get :plans)))
    (format "%d file(s) scanned: %d with footnotes to move (%d move(s)), %d orphan definition(s), %d dangling reference(s), %d error(s).\n"
            (or (sp-org-lint-fn--get :scanned) 0)
            (seq-count (lambda (p) (plist-get p :changed)) plans)
            (apply #'+ (mapcar (lambda (p) (length (plist-get p :moves))) plans))
            (apply #'+ (mapcar (lambda (p) (length (plist-get p :orphans))) plans))
            (apply #'+ (mapcar (lambda (p) (length (plist-get p :dangling))) plans))
            (seq-count (lambda (p) (plist-get p :error)) plans))))

(defun sp-org-lint-fn--render ()
  "Draw the whole report, from the state of the run."
  (let ((inhibit-read-only t)
        (plans (reverse (sp-org-lint-fn--get :plans)))
        (results (reverse (sp-org-lint-fn--get :results))))
    (erase-buffer)
    (insert (propertize "Footnote lint\n" 'face 'bold)
            (sp-org-lint-fn--summary) "\n")
    (when results
      (insert (propertize "Applied\n" 'face 'bold)
              (format "Backups are in %s\n\n"
                      (abbreviate-file-name (sp-org-lint-fn--get :backup-root))))
      (dolist (r results)
        (insert (propertize
                 (if (eq (plist-get r :status) 'written)
                     (format "  written: %s (%d move(s)); backup %s\n"
                             (abbreviate-file-name (plist-get r :file))
                             (plist-get r :moves)
                             (abbreviate-file-name (plist-get r :backup)))
                   (format "  skipped: %s (%s)\n"
                           (abbreviate-file-name (plist-get r :file))
                           (plist-get r :reason)))
                 'sp-file (plist-get r :file) 'sp-line 1)))
      (insert "\n"))
    (dolist (p plans)
      ;; What was applied is no longer pending.
      (when (seq-some (lambda (r) (and (eq (plist-get r :status) 'written)
                                       (equal (plist-get r :file) (plist-get p :file))))
                      results)
        (setq p (plist-put (plist-put (copy-sequence p) :moves nil) :removed nil)))
      (when (sp-org-lint-fn--shown-p p)
        (sp-org-lint-fn--insert-plan p)))
    (goto-char (point-min))))

(defun sp-org-lint-fn--handle (item)
  "Handle one result ITEM from the worker."
  (unless (plist-get item :done)
    (sp-org-lint-fn--set :done (1+ (or (sp-org-lint-fn--get :done) 0)))
    (if (eq (sp-org-lint-fn--get :phase) 'scan)
        (progn
          (sp-org-lint-fn--set :plans (cons item (sp-org-lint-fn--get :plans)))
          (when (sp-org-lint-fn--shown-p item)
            (sp-org-lint-fn--insert-plan item)))
      (sp-org-lint-fn--set :results (cons item (sp-org-lint-fn--get :results))))
    (force-mode-line-update)))

(defun sp-org-lint-fn--filter (buffer proc string)
  "Process filter: handle the complete lines of STRING in BUFFER."
  (if (not (buffer-live-p buffer))
      (delete-process proc)
    (with-current-buffer buffer
      (let ((data (concat (sp-org-lint-fn--get :partial) string))
            (start 0))
        (while (string-match "\n" data start)
          (let ((line (substring data start (match-beginning 0))))
            (setq start (match-end 0))
            (when (string-prefix-p "SPLINT " line)
              (sp-org-lint-fn--handle
               (car (read-from-string (substring line 7)))))))
        (sp-org-lint-fn--set :partial (substring data start))))))

(defun sp-org-lint-fn--sync-vulpea (files)
  "Ask vulpea to re-read FILES, one per idle moment."
  (when (and files (fboundp 'vulpea-db-update-file))
    (ignore-errors (vulpea-db-update-file (car files)))
    (when (cdr files)
      (run-with-idle-timer 0.2 nil #'sp-org-lint-fn--sync-vulpea (cdr files)))))

(defun sp-org-lint-fn--finish-apply ()
  "After an apply: refresh the buffers and the database for the written files."
  (let ((written (mapcar (lambda (r) (plist-get r :file))
                         (seq-filter (lambda (r) (eq (plist-get r :status) 'written))
                                     (sp-org-lint-fn--get :results)))))
    (dolist (f written)
      (when-let* ((b (find-buffer-visiting f)))
        (unless (buffer-modified-p b)
          (with-current-buffer b (revert-buffer t t t)))))
    (sp-org-lint-fn--sync-vulpea written)))

(defun sp-org-lint-fn--sentinel (buffer proc _event)
  "Process sentinel: finish the run in BUFFER when PROC has exited."
  (unless (process-live-p proc)
    (let ((err (process-get proc 'stderr))
          (ctl (process-get proc 'control-file)))
      (when ctl (ignore-errors (delete-file ctl)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (let ((failed (not (zerop (process-exit-status proc)))))
            (when (eq (sp-org-lint-fn--get :phase) 'apply)
              (sp-org-lint-fn--finish-apply))
            (sp-org-lint-fn--set :phase (cond (failed 'failed)
                                              ((eq (sp-org-lint-fn--get :phase) 'apply) 'applied)
                                              (t 'ready)))
            (sp-org-lint-fn--render)
            (when failed
              (let ((inhibit-read-only t))
                (goto-char (point-max))
                (insert "The worker Emacs failed:\n"
                        (if (buffer-live-p err)
                            (with-current-buffer err (buffer-string))
                          "")))))))
      (when (buffer-live-p err) (kill-buffer err)))))

(defun sp-org-lint-fn--start (phase files extra)
  "Start the worker for PHASE (`scan' or `apply') on FILES in this buffer.
EXTRA is a plist merged into the control file."
  (unless (and sp-org-lint--library (file-exists-p sp-org-lint--library))
    (user-error "Cannot find sp-org-lint.el to load in the worker Emacs"))
  (let* ((buffer (current-buffer))
         (ctl (make-temp-file "sp-org-lint-" nil ".eld"))
         (err (generate-new-buffer " *sp-org-lint stderr*"))
         proc)
    (with-temp-file ctl
      (let ((print-length nil) (print-level nil))
        (prin1 (append (list :mode (if (eq phase 'scan) 'plan 'apply)
                             :files files)
                       extra)
               (current-buffer))))
    (setq proc (make-process
                :name "sp-org-lint-footnotes"
                :buffer nil
                :command (list (expand-file-name invocation-name
                                                 invocation-directory)
                               "-Q" "--batch" "-l" sp-org-lint--library
                               "--eval"
                               (format "(sp-org-lint-fn--batch %S)" ctl))
                :connection-type 'pipe
                :coding 'utf-8-unix
                :noquery t
                :stderr err
                :filter (lambda (p s) (sp-org-lint-fn--filter buffer p s))
                :sentinel (lambda (p e) (sp-org-lint-fn--sentinel buffer p e))))
    (process-put proc 'control-file ctl)
    (process-put proc 'stderr err)
    (sp-org-lint-fn--set :process proc)
    (sp-org-lint-fn--set :phase phase)
    (when (eq phase 'scan)
      (sp-org-lint-fn--set :scanned (length files)))
    (sp-org-lint-fn--set :total (length files))
    (sp-org-lint-fn--set :done 0)
    (sp-org-lint-fn--set :partial "")))

(defun sp-org-lint-fn--stop ()
  "Stop the worker of this report buffer, if it runs."
  (let ((proc (sp-org-lint-fn--get :process)))
    (when (process-live-p proc)
      (set-process-sentinel proc nil)
      (delete-process proc)
      (when-let* ((ctl (process-get proc 'control-file)))
        (ignore-errors (delete-file ctl))))))

;;;###autoload
(defun sp-org-lint-footnotes (&optional dir)
  "Scan the vault for footnotes to move into the section that cites them.
Footnote definitions in a trailing `Footnotes' heading are planned to
move to the end of the text of the heading that contains their
reference.  A second Emacs does the work, so this one stays usable; the
report fills in as files are read, and nothing is changed until you
press \\<sp-org-lint-fn-report-mode-map>\\[sp-org-lint-footnotes-apply] in the report.  With a prefix argument, ask for a folder
instead of using the vulpea database."
  (interactive (list (when current-prefix-arg
                       (read-directory-name "Lint footnotes under: "
                                            sp-org-lint-fn-directory))))
  (let ((buffer (get-buffer-create sp-org-lint-fn--buffer-name))
        (files (if dir
                   (sp-org-lint-fn--org-files
                    (directory-files-recursively dir "\\.org\\'") dir)
                 (funcall sp-org-lint-fn-files-function))))
    (unless files (user-error "No Org files to lint"))
    (with-current-buffer buffer
      (sp-org-lint-fn--stop)
      (unless (derived-mode-p 'sp-org-lint-fn-report-mode)
        (sp-org-lint-fn-report-mode))
      (setq sp-org-lint-fn--run nil)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Footnote lint\n" 'face 'bold)
                (format "Reading %d file(s) in a second Emacs; nothing is changed.\n\n"
                        (length files))))
      (sp-org-lint-fn--start 'scan files nil))
    (display-buffer buffer)
    (message "Linting footnotes of %d file(s) in the background" (length files))))

;;;###autoload
(defun sp-org-lint-footnotes-apply ()
  "Apply the moves of the footnote lint shown in this report buffer.
Every file is copied to `sp-org-lint-fn-backup-directory' first.  Files
that are open with unsaved changes, or that changed since the scan,
are skipped.  The work is done by a second Emacs."
  (interactive)
  (unless (derived-mode-p 'sp-org-lint-fn-report-mode)
    (user-error "Run this in the footnote lint report"))
  (unless (eq (sp-org-lint-fn--get :phase) 'ready)
    (user-error "The scan has not finished"))
  (let* ((plans (seq-filter (lambda (p) (plist-get p :changed))
                            (sp-org-lint-fn--get :plans)))
         (busy (seq-filter (lambda (p)
                             (when-let* ((b (find-buffer-visiting
                                             (plist-get p :file))))
                               (buffer-modified-p b)))
                           plans))
         (plans (seq-difference plans busy))
         (root (expand-file-name (format-time-string "%Y%m%d-%H%M%S/")
                                 sp-org-lint-fn-backup-directory)))
    (unless plans (user-error "Nothing to apply"))
    (when (yes-or-no-p
           (format "Move footnotes in %d file(s)%s? Copies go to %s "
                   (length plans)
                   (if busy (format " (%d open with unsaved changes are left out)"
                                    (length busy))
                     "")
                   (abbreviate-file-name root)))
      (sp-org-lint-fn--set :results nil)
      (sp-org-lint-fn--set :backup-root root)
      (sp-org-lint-fn--start 'apply
                             (mapcar (lambda (p)
                                       (cons (plist-get p :file) (plist-get p :sha)))
                                     plans)
                             (list :backup-root root)))))

(provide 'sp-org-lint)
;;; sp-org-lint.el ends here
