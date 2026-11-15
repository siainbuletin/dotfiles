;;; sp-agenda-views-inline-test.el --- Tests for the inline keyword view  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar sp-writing-projects "/nonexistent/")
(defvar org-agenda-custom-commands nil)
(defvar sp-agenda-views-inline-keywords)
(defvar sp-agenda-views-inline-filter nil)
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
      (eval-region start (- end (length ";;;; Config files"))))))

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
  (cl-letf (((symbol-function 'sp-agenda-views-inline-files) (lambda () nil)))
    (should (equal (car (sp-agenda-views--inline-entry)) "x"))))

(ert-deftest sp-agenda-views-inline-test-sourcerefs-keyword ()
  (should (member "SOURCEREFS" sp-agenda-views-inline-keywords))
  (should (sp-agenda-views-inline-test--term "SOURCEREFS p. 12 Smith 1999"))
  (should-not (sp-agenda-views-inline-test--term "MYSOURCEREFS")))

(ert-deftest sp-agenda-views-inline-test-filter-narrows ()
  (let ((sp-agenda-views-inline-filter "SOURCEREFS"))
    (should (sp-agenda-views-inline-test--term "SOURCEREFS Smith"))
    (should-not (sp-agenda-views-inline-test--term "FIXME this"))
    (should-not (sp-agenda-views-inline-test--term "CITE this"))))

(ert-deftest sp-agenda-views-inline-test-filter-nil-means-all ()
  (let ((sp-agenda-views-inline-filter nil))
    (should (sp-agenda-views-inline-test--term "FIXME this"))
    (should (sp-agenda-views-inline-test--term "SOURCEREFS Smith"))))

(ert-deftest sp-agenda-views-inline-test-unknown-filter-is-ignored ()
  (let ((sp-agenda-views-inline-filter "NOPE"))
    (should (sp-agenda-views-inline-test--term "FIXME this"))))

(ert-deftest sp-agenda-views-inline-test-filter-set-rejects-unknown ()
  (should-error (sp-agenda-views-inline-filter-set "NOPE") :type 'user-error)
  (should-not sp-agenda-views-inline-filter))

(ert-deftest sp-agenda-views-inline-test-filter-clear ()
  (cl-letf (((symbol-function 'sp-agenda-views-inline) #'ignore))
    (let ((sp-agenda-views-inline-filter "CITE"))
      (sp-agenda-views-inline-filter-clear)
      (should-not sp-agenda-views-inline-filter))))

(provide 'sp-agenda-views-inline-test)
;;; sp-agenda-views-inline-test.el ends here
