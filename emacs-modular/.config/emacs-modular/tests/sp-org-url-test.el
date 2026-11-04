;;; sp-org-url-test.el --- Tests for the URL at point in Org buffers -*- lexical-binding: t; -*-

;; The section "URL at point in Org buffers" of sp-org-base.el is evaluated alone.

(require 'ert)
(require 'org)
(require 'thingatpt)
(require 'subr-x)

(with-temp-buffer
  (insert-file-contents
   (expand-file-name "../libraries/modules/text/sp-org-base.el"
                     (file-name-directory (or load-file-name buffer-file-name))))
  (goto-char (point-min))
  (search-forward ";;;; URL at point in Org buffers")
  (let ((end (save-excursion (search-forward ";;;; Dynamic block templates")
                             (match-beginning 0)))
        form)
    (narrow-to-region (point) end)
    (while (setq form (condition-case nil (read (current-buffer)) (end-of-file nil)))
      (unless (eq (car-safe form) 'add-hook) (eval form t)))))

(defun sp-org-url-test--at (text pos)
  "The `thing-at-point' url at POS in an Org buffer holding TEXT."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (sp-org-url-install-provider)
    (insert text)
    (goto-char pos)
    (thing-at-point 'url t)))

(ert-deftest sp-org-url-plain-link ()
  (should (equal (sp-org-url-test--at "see https://example.org/a ok" 12)
                 "https://example.org/a")))

(ert-deftest sp-org-url-bracket-link ()
  (should (equal (sp-org-url-test--at "[[https://example.org/a][text]]" 8)
                 "https://example.org/a")))

(ert-deftest sp-org-url-markdown-inside-plain-link ()
  (should (equal (sp-org-url-test--at
                  "https://[www.youtube.com/watch?v=x](https://www.youtube.com/watch?v=x)" 10)
                 "https://www.youtube.com/watch?v=x")))

(ert-deftest sp-org-url-never-a-list ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (sp-org-url-install-provider)
    (insert "just words")
    (goto-char 3)
    (should-not (consp (thing-at-point 'url t)))))

(provide 'sp-org-url-test)
;;; sp-org-url-test.el ends here
