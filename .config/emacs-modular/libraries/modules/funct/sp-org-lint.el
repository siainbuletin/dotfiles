;;; sp-org-lint.el --- Lint plain lists in org-mode buffers  -*- lexical-binding: t; -*-

(require 'org)
(require 'org-list)
(require 'org-element)
(require 'subr-x)

(defconst sp-org--item-re
  "^\\(?:[ \t]+\\*\\|[ \t]*[-+]\\|[ \t]*[0-9]+[.)]\\)[ \t]"
  "Match the start of a plain list item line.
A bare `*' only counts when indented, so headings are not mistaken for items.")

(defconst sp-org--url-re "https://[^] \t\n\r<>\"[]+"
  "Match an https:// URL.
Change `https://' to `https?://' to also treat http links as links.")

;;; Region detection
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

;;; Step 1: turn plain lines into items

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

;;; Step 2: remove blank lines between items

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

;;; Step 3: remove duplicate links

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
Only the item's own text is searched, not its nested items.  Return
nil if the item has no such link."
  (save-excursion
    (goto-char item-beg)
    (forward-line 1)
    (let ((own-end (save-excursion
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
              (delete-region pos item-end)
              (setq removed (1+ removed))))))))
    (cons removed kept)))

;;; Step 4: sort

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

;;; Pipeline and commands

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

;;; Provide:

(provide 'sp-org-lint)
;;; sp-org-lint.el ends herea
