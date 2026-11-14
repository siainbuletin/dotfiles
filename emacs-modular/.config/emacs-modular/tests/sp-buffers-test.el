;;; sp-buffers-test.el --- Tests for the Org title column in ibuffer -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'ibuffer)
(require 'sp-buffers)

(defvar ibuffer-formats)
(defvar ibuffer-saved-filter-groups)

(defmacro sp-buffers-test--with-org (text &rest body)
  "Run BODY in a temporary Org buffer holding TEXT."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (delay-mode-hooks (org-mode))
     ,@body))

(ert-deftest sp-buffers-org-title-found ()
  (sp-buffers-test--with-org "#+title: My Note\n\n* Heading\n"
    (should (equal (sp-buffers-org-title) "My Note"))))

(ert-deftest sp-buffers-org-title-case-and-indent-insensitive ()
  (sp-buffers-test--with-org ":PROPERTIES:\n:ID: x\n:END:\n#+TITLE:   Spaced   \n"
    (should (equal (sp-buffers-org-title) "Spaced"))))

(ert-deftest sp-buffers-org-title-missing-is-nil ()
  (sp-buffers-test--with-org "* Only a heading\n"
    (should-not (sp-buffers-org-title))))

(ert-deftest sp-buffers-org-title-empty-is-nil ()
  (sp-buffers-test--with-org "#+title:\n* H\n"
    (should-not (sp-buffers-org-title))))

(ert-deftest sp-buffers-org-title-only-in-org-buffers ()
  (with-temp-buffer
    (insert "#+title: Not org\n")
    (should-not (sp-buffers-org-title))))

(ert-deftest sp-buffers-org-title-ignores-narrowing ()
  (sp-buffers-test--with-org "#+title: Wide\n* A\n* B\n"
    (goto-char (point-max))
    (narrow-to-region (point) (point))
    (should (equal (sp-buffers-org-title) "Wide"))))

(ert-deftest sp-buffers-org-title-cache-follows-edits ()
  (sp-buffers-test--with-org "#+title: Old\n"
    (should (equal (sp-buffers-org-title) "Old"))
    (goto-char (point-min))
    (search-forward "Old")
    (replace-match "New")
    (should (equal (sp-buffers-org-title) "New"))))

(ert-deftest sp-buffers-org-title-cache-reused-when-unchanged ()
  (sp-buffers-test--with-org "#+title: Same\n"
    (sp-buffers-org-title)
    (let ((cache sp-buffers--title-cache))
      (sp-buffers-org-title)
      (should (eq cache sp-buffers--title-cache)))))

(ert-deftest sp-buffers-display-name-falls-back-to-buffer-name ()
  (sp-buffers-test--with-org "* No title\n"
    (should (equal (sp-buffers-display-name) (buffer-name)))))

(ert-deftest sp-buffers-display-name-option-off ()
  (sp-buffers-test--with-org "#+title: Hidden\n"
    (let ((sp-buffers-org-title-in-ibuffer nil))
      (should (equal (sp-buffers-display-name) (buffer-name))))))

(ert-deftest sp-buffers-ibuffer-column-lists-title ()
  "The `sp-name' column shows the title, and the other buffers keep their name."
  (let ((org (generate-new-buffer "sp-buffers-test-org"))
        (plain (generate-new-buffer "sp-buffers-test-plain")))
    (unwind-protect
        (progn
          (with-current-buffer org
            (insert "#+title: Listed Title\n")
            (delay-mode-hooks (org-mode)))
          (with-current-buffer plain (insert "#+title: ignored\n"))
          (let ((ibuffer-formats '((mark " " (sp-name 40 40 :left :elide))))
                (ibuffer-saved-filter-groups nil))
            (save-window-excursion
              (ibuffer nil "*sp-buffers-test-ibuffer*")
              (let ((text (buffer-string)))
                (should (string-match-p "Listed Title" text))
                (should-not (string-match-p "sp-buffers-test-org" text))
                (should (string-match-p "sp-buffers-test-plain" text))
                (should-not (string-match-p "ignored" text)))
              (kill-buffer))))
      (kill-buffer org)
      (kill-buffer plain))))

(ert-deftest sp-buffers-filter-groups-and-formats-use-sp-name ()
  (should (assoc "Main" ibuffer-saved-filter-groups))
  (should (assoc "Org" (cdr (assoc "Main" ibuffer-saved-filter-groups))))
  (dolist (fmt ibuffer-formats)
    (should (assq 'sp-name (seq-filter #'consp fmt)))))

(provide 'sp-buffers-test)
;;; sp-buffers-test.el ends here
