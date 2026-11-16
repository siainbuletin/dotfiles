;;; sp-org-base-open-test.el --- Tests for the entry link list switch -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-org-base-open-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org)
(require 'subr-x)

;; Load only the two forms that need no packages.
(let ((file (expand-file-name "../libraries/modules/text/sp-org-base.el"
                              (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (search-forward "(defcustom sp-org-offer-entry-links")
    (beginning-of-line)
    (dotimes (_ 3) (eval (read (current-buffer)) t))))

(defconst sp-org-open-test--text "* H\n[[id:a][one]]\nplain text here\n")

(defmacro sp-org-open-test--at (search &rest body)
  "Run BODY in an Org buffer with point after SEARCH."
  (declare (indent 1))
  `(with-temp-buffer
     (delay-mode-hooks (org-mode))
     (insert sp-org-open-test--text)
     (goto-char (point-min))
     (search-forward ,search)
     ,@body))

(ert-deftest sp-org-open-plain-text-is-refused-with-variable-name ()
  (sp-org-open-test--at "plain"
    (let ((err (should-error (sp-org-refuse-entry-links) :type 'user-error)))
      (should (string-match-p "sp-org-offer-entry-links" (cadr err)))
      (should (string-match-p "disabled" (cadr err))))))

(ert-deftest sp-org-open-plain-text-offers-when-enabled ()
  (sp-org-open-test--at "plain"
    (let ((sp-org-offer-entry-links t))
      (should-not (sp-org-refuse-entry-links)))))

(ert-deftest sp-org-open-link-and-heading-are-not-refused ()
  (sp-org-open-test--at "one"
    (should-not (sp-org-refuse-entry-links)))
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert sp-org-open-test--text)
    (goto-char 3)
    (should-not (sp-org-refuse-entry-links))))

(ert-deftest sp-org-open-at-point-runs-the-refusal-last ()
  (add-hook 'org-open-at-point-functions #'ignore 100)
  (add-hook 'org-open-at-point-functions #'identity 10)
  (should (< (seq-position org-open-at-point-functions #'identity)
             (seq-position org-open-at-point-functions #'sp-org-refuse-entry-links)))
  (remove-hook 'org-open-at-point-functions #'ignore)
  (remove-hook 'org-open-at-point-functions #'identity)
  (should (memq #'sp-org-refuse-entry-links org-open-at-point-functions)))

(provide 'sp-org-base-open-test)
;;; sp-org-base-open-test.el ends here
