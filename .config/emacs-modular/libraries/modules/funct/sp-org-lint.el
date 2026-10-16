;; -*- lexical-binding: t; -*-
;;; sp-org-lint.el --- Lint plain lists in org-mode buffers  

;;; Commentary:

;;; Code:

(require 'org)
(require 'org-list)

(defconst sp-org--item-re
  "^\\(?:[ \t]+\\*\\|[ \t]*[-+]\\|[ \t]*[0-9]+[.)]\\)[ \t]"
  "Match the start of a plain list item line.
A bare `*' only counts when indented, so headings are not mistaken for items.")

(defun sp-org--region-or-error (beg end)
  "Signal an error unless in `org-mode' and BEG/END are usable."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (when (= beg end)
    (user-error "Region is empty")))

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

;;;###autoload
(defun sp-org-lint-list (beg end)
  "Remove blank lines between list items in the region from BEG to END.
Blank lines separating a list from surrounding paragraphs or headings
are left alone."
  (interactive "r")
  (sp-org--region-or-error beg end)
  (let ((end-marker (copy-marker end)))
    (unwind-protect
        (sp-org--remove-blank-lines-between-items beg end-marker)
      (set-marker end-marker nil))))

;;;###autoload
(defun sp-org-lint-resources (beg end)
  "Lint the lists in the region from BEG to END, then sort them alphabetically.
First runs `sp-org-lint-list' so that no stray blank lines travel
with items while sorting.  Each top-level list in the region is then
sorted case-insensitively by item text.  Nested sublists keep their
parent item but are not re-sorted themselves."
  (interactive "r")
  (sp-org--region-or-error beg end)
  (let ((end-marker (copy-marker end)))
    (unwind-protect
        (save-excursion
          (sp-org--remove-blank-lines-between-items beg end-marker)
          (goto-char beg)
          (while (and (< (point) end-marker)
                      (re-search-forward sp-org--item-re end-marker t))
            (beginning-of-line)
            (org-sort-list nil ?a)            ; ?a = alphabetically, case-insensitive
            ;; Jump past the whole list we just sorted.
            (goto-char (org-list-get-bottom-point (org-list-struct)))))
      (set-marker end-marker nil))))

;;; Provide:

(provide 'sp-org-lint)
;;; sp-org-lint.el ends here
