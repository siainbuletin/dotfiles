;;; sp-org-tables-dividers-test.el --- Tests for row dividers in table widgets -*- lexical-binding: t; -*-

;; Only the pure function that inserts the dividers is tested; the real widget
;; needs a graphical frame.

(require 'ert)
(require 'cl-lib)

(defvar sp-org-tables-row-dividers t)

(with-temp-buffer
  (insert-file-contents
   (expand-file-name "../libraries/modules/text/sp-org-tables.el"
                     (file-name-directory (or load-file-name buffer-file-name))))
  (goto-char (point-min))
  (search-forward ";;;; Dividers between table rows")
  (let ((end (save-excursion (search-forward ";;;; Following links") (match-beginning 0)))
        form)
    (narrow-to-region (point) end)
    (while (setq form (condition-case nil (read (current-buffer)) (end-of-file nil)))
      (when (memq (car-safe form) '(defun)) (eval form t)))))

(ert-deftest sp-org-tables-dividers-body-rows ()
  (let ((new (sp-org-tables--with-row-dividers
              '(:rows (("a") hline ("1") ("2") ("3")) :header-rows 1
                :lines (0 1 2 3 4) :alignments (left)))))
    (should (equal (plist-get new :rows)
                   '(("a") hline ("1") hline ("2") hline ("3"))))
    (should (equal (plist-get new :lines) '(0 1 2 2 3 3 4)))))

(ert-deftest sp-org-tables-dividers-no-header ()
  (let ((new (sp-org-tables--with-row-dividers
              '(:rows (("1") ("2")) :header-rows 0 :alignments (left)))))
    (should (equal (plist-get new :rows) '(("1") hline ("2"))))
    (should-not (plist-get new :lines))))

(ert-deftest sp-org-tables-dividers-keeps-existing-rules ()
  (let ((new (sp-org-tables--with-row-dividers
              '(:rows (("a") hline ("1") hline ("2")) :header-rows 1
                :lines (0 1 2 3 4)))))
    (should (equal (plist-get new :rows) '(("a") hline ("1") hline ("2"))))))
