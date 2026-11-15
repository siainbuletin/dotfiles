;;; sp-org-custom-highlight.el --- Org emphasis helpers -*- lexical-binding: t; -*-

;;; Commentary:

;; Small function which creates a bespoke org-mode comment which is supposed
;; to mimic the behavior of comments in Obsidian, making them stand out in the
;; text as tasks I need to take care of.

;;; Code:

(defface my-org-inline-comment
  '((t :inherit lazy-highlight))
  "Face for @@comment:...@@ inline comments.
Inherits `lazy-highlight', which `sp-themes' tints from the theme in use.")

(add-hook 'org-mode-hook
          (lambda ()
            (font-lock-add-keywords
             nil
             '(("\\(@@comment:\\)\\([^@\n]*\\)\\(@@\\)"
                (1 'shadow prepend)
                (2 'my-org-inline-comment prepend)
                (3 'shadow prepend)))
             'append)))

(defun sp-org--comment-lines (text)
  "Return TEXT with each non-blank line wrapped as an inline comment.
Leading and trailing whitespace of a line stays outside the markers."
  (mapconcat
   (lambda (line)
     (if (string-blank-p line)
         line
       (string-match "\\`\\([ \t]*\\)\\(.*?\\)\\([ \t]*\\)\\'" line)
       (concat (match-string 1 line)
               "@@comment:" (match-string 2 line) "@@"
               (match-string 3 line))))
   (split-string text "\n")
   "\n"))

(defun sp-org-insert-inline-comment ()
  "Wrap the active region in `@@comment:...@@', or insert an empty one.
With a region, each non-blank line becomes its own comment, so the
highlighting (one line only) matches the export.  Without a region,
insert `@@comment:@@' and put point inside it."
  (interactive)
  (let ((beg (and (use-region-p) (region-beginning)))
        (end (and (use-region-p) (region-end))))
    (if (not (and beg (string-match-p "[^ \t\n]" (buffer-substring-no-properties beg end))))
        (progn
          (deactivate-mark)
          (insert "@@comment:@@")
          (backward-char 2))
      (let ((text (buffer-substring beg end)))
        (when (string-search "@@" text)
          (user-error "The region contains @@, which would end the comment early"))
        (atomic-change-group
          (goto-char beg)
          (delete-region beg end)
          (insert (sp-org--comment-lines text)))
        (deactivate-mark)))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c h") #'sp-org-insert-inline-comment))

(provide 'sp-org-custom-highlight)
