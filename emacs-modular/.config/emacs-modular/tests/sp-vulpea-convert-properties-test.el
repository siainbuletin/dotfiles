;;; sp-vulpea-convert-properties-test.el --- Tests for the property preview report -*- lexical-binding: t; -*-

(require 'ert)
(unless (featurep 'vulpea) (provide 'vulpea))
(unless (fboundp 'vulpea-db-query) (defun vulpea-db-query (&rest _) nil))
(unless (fboundp 'vulpea-note-path) (defun vulpea-note-path (n) n))
(require 'sp-vulpea-convert-properties)

(ert-deftest sp-vulpea-convert-properties-preview-drop-and-apply ()
  "A dropped file leaves the preview and the conversion that A runs."
  (let ((a "/tmp/vault/a.org") (b "/tmp/vault/b.org") applied)
    (cl-letf (((symbol-function 'vulpea-db-query) (lambda (&rest _) nil))
              ((symbol-function 'sia-vulpea--files-with-convertible-properties)
               (lambda () (list a b)))
              ((symbol-function 'sia-vulpea--process-files-async)
               (lambda (files fn _label done)
                 (funcall done (mapcar (lambda (f) (format "- %s: x" (sp-batch-report-file-link f))) files))))
              ((symbol-function 'pop-to-buffer) #'ignore))
      (unwind-protect
          (progn
            (sia-vulpea-convert-all-notes-properties-to-meta-dryrun)
            (with-current-buffer "*vulpea property conversion preview*"
              (should (derived-mode-p 'sp-batch-report-mode))
              (goto-char (point-min))
              (re-search-forward "^- \\[\\[file:/tmp/vault/b\\.org")
              (sp-batch-report-drop)
              (should (equal sp-batch-report-excluded (list b)))
              (should-not (string-match-p "b\\.org\\]\\]: x" (buffer-string)))
              (should (string-match-p "Dropped from the list" (buffer-string)))
              (cl-letf (((symbol-function 'sia-vulpea-convert-all-notes-properties-to-meta)
                         (lambda (&rest args) (setq applied args))))
                (sp-batch-report-apply))
              (should (equal (cadr applied) (list b)))))
        (when (get-buffer "*vulpea property conversion preview*")
          (kill-buffer "*vulpea property conversion preview*"))))))

(ert-deftest sp-vulpea-convert-properties-convertible-files-skip-excluded ()
  (cl-letf (((symbol-function 'sia-vulpea--files-with-convertible-properties)
             (lambda () (list "a" "b"))))
    (let ((sia-vulpea-convert--excluded '("a")))
      (should (equal (sia-vulpea--convertible-files) '("b"))))))

(provide 'sp-vulpea-convert-properties-test)
;;; sp-vulpea-convert-properties-test.el ends here
