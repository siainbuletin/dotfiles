;;; sp-cite-hover-test.el --- Tests for the citation hover in sp-citations -*- lexical-binding: t; -*-

;; The hover code sits in sp-citations.el among `use-package' forms, so the
;; test evaluates only that section.  `citar' is stubbed with the current API:
;; `citar-get-entry' and `citar-format-reference'.  `citar-get-template' (removed
;; from citar) is deliberately NOT defined, to catch a regression.

(require 'ert)
(require 'subr-x)

(defvar sp-cite-hover-test--file
  (expand-file-name "../libraries/modules/academic/sp-citations.el"
                    (file-name-directory (or load-file-name buffer-file-name))))

(with-temp-buffer
  (insert-file-contents sp-cite-hover-test--file)
  (goto-char (point-min))
  (search-forward ";;;; Citation hover")
  (let ((end (save-excursion
               (search-forward "(add-hook 'org-mode-hook #'sp-cite-hover-setup)")
               (match-beginning 0)))
        form)
    (narrow-to-region (point) end)
    (while (setq form (condition-case nil (read (current-buffer)) (end-of-file nil)))
      (eval form t))))

(defvar sp-cite-hover-test--entries '(("smith2020attention" . ((title . "Attention")))))

(defun citar-get-entry (key) (cdr (assoc key sp-cite-hover-test--entries)))
(defun citar-format-reference (keys)
  (concat "Smith (2020) " (cdr (assq 'title (citar-get-entry (car keys)))) "  \n"))
(provide 'citar)

(ert-deftest sp-cite-hover-test-reference ()
  (should-not (fboundp 'citar-get-template))
  (should (equal (sp-cite-hover--reference "smith2020attention")
                 "Smith (2020) Attention")))

(ert-deftest sp-cite-hover-test-missing-key ()
  (should-not (sp-cite-hover--reference "nobody1999none"))
  (should-not (sp-cite-hover--reference nil)))

(ert-deftest sp-cite-hover-test-citar-error-is-nil ()
  (cl-letf (((symbol-function 'citar-format-reference)
             (lambda (_) (error "boom"))))
    (should-not (sp-cite-hover--reference "smith2020attention"))))

(ert-deftest sp-cite-hover-test-help-echo-and-eldoc ()
  (with-temp-buffer
    (insert "text [cite:@smith2020attention] more")
    (let ((sp-cite-hover-display '(tooltip echo)) got)
      (should (equal (sp-cite-hover--help-echo nil (current-buffer) 12)
                     "Smith (2020) Attention"))
      (goto-char 12)
      (sp-cite-hover--eldoc (lambda (text &rest _) (setq got text)))
      (should (equal got "Smith (2020) Attention")))))

(provide 'sp-cite-hover-test)
;;; sp-cite-hover-test.el ends here
