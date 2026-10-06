;; -*- lexical-binding: t; -*-

;;;; Text Functions

;; Cleaning up unnecessary whitespace
(defun sp-clean-whitespace (&optional Begin End)
  "Delete trailing whitespace, and replace repeated blank lines to just 1.
Only space and tab is considered whitespace here.
Works on whole buffer or selection, respects `narrow-to-region'."
  (interactive)
  (let (xbeg xend)
    (seq-setq (xbeg xend)
              (if (and Begin End)
                  (list Begin End)
                (if (region-active-p)
                    (list (region-beginning) (region-end))
                  (list (point-min) (point-max)))))
    (save-excursion
      (save-restriction
        (narrow-to-region xbeg xend)
        (progn
          (goto-char (point-min))
          (while (re-search-forward "[ \t]+\n" nil t) (replace-match "\n")))
        (progn
          (goto-char (point-min))
          (while (re-search-forward "\n\n\n+" nil t) (replace-match "\n\n")))
        (progn
          (goto-char (point-max))
          (while (eq (char-before) 32) (delete-char -1))))))
  (message "done sp-clean-whitespace"))

(add-hook 'before-save-hook 'sp-clean-whitespace)


;;;;; Fill Paragraph
(defun sp-fill-paragraph ()
  "if in an org buffer use org-fill-paragraph; else use fill-paragraph"
  (interactive)
  (if (derived-mode-p 'org-mode)
      (call-interactively #'org-fill-paragraph)
    (call-interactively #'fill-paragraph)))

(keymap-global-set [remap fill-paragraph]
                #'sp-fill-paragraph)

;;;;; Unfill Paragraph
;; Stefan Monnier <foo at acm.org>. It is the opposite of fill-paragraph
(defun sp-unfill-paragraph (&optional region)
  "Takes a multi-line paragraph and makes it into a single line of text."
  (interactive (progn (barf-if-buffer-read-only) '(t)))
  (let ((fill-column (point-max))
        ;; This would override `fill-column' if it's an integer.
        (emacs-lisp-docstring-fill-column t))
    (fill-paragraph nil region)))
(keymap-global-set "M-Q" #'sp-unfill-paragraph)

;;;;; Formatted Copy
(defun formatted-copy ()
  "Export region to HTML, and copy it to the clipboard."
  (interactive)
  (save-window-excursion
    (let* ((buf (org-export-to-buffer 'html "*Formatted Copy*" nil nil t t))
           (html (with-current-buffer buf (buffer-string))))
      (with-current-buffer buf
        (shell-command-on-region
         (point-min)
         (point-max)
         "textutil -stdin -format html -convert rtf -stdout | pbcopy"))
      (kill-buffer buf))))

(keymap-global-set "H-w" 'formatted-copy)

(provide 'sp-text-manipulation)