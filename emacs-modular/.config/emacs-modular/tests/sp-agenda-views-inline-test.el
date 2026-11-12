;;; sp-agenda-views-inline-test.el --- Tests for the inline keyword view  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'seq)
(require 'subr-x)

(defvar sp-writing-projects "/nonexistent/")
(defvar org-agenda-custom-commands nil)
(defvar sp-agenda-views-inline-keywords)
(defvar sp-agenda-views-inline-extra-dirs)

;; Load only the inline section, so the test needs neither Org nor vulpea.
(let ((file (expand-file-name
             "../libraries/modules/text/sp-agenda-views.el"
             (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((start (search-forward ";;;; Inline keywords" nil t))
          (end (search-forward ";;;; Config files" nil t)))
      (eval-region start (- end (length ";;;; Config files")))))))

(defmacro sp-agenda-views-inline-test--term (text)
  "Return non-nil when TEXT matches the regexp of the inline view."
  `(let ((re (substring (sp-agenda-views-inline-regexp) 1 -1)))
     (string-match-p re ,text)))

(ert-deftest sp-agenda-views-inline-test-matches-keywords ()
  (should (sp-agenda-views-inline-test--term "Cite this. FIXME check"))
  (should (sp-agenda-views-inline-test--term "as shown (TK)"))
  (should (sp-agenda-views-inline-test--term "XXX")))

(ert-deftest sp-agenda-views-inline-test-whole-words-only ()
  (should-not (sp-agenda-views-inline-test--term "Atkins wrote XXXL")))

(ert-deftest sp-agenda-views-inline-test-entry-key ()
  (should (equal (car (sp-agenda-views--inline-entry)) "x")))

(provide 'sp-agenda-views-inline-test)
;;; sp-agenda-views-inline-test.el ends here
