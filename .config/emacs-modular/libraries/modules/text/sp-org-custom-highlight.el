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

(defun my-org-insert-inline-comment ()
  (interactive)
  (if (use-region-p)
      (let ((text (buffer-substring (region-beginning) (region-end))))
        (delete-region (region-beginning) (region-end))
        (insert "@@comment:" text "@@"))
    (insert "@@comment:@@")
    (backward-char 2)))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c h") #'my-org-insert-inline-comment))

(provide 'sp-org-custom-highlight)
