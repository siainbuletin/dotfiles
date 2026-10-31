;;; sp-org-tables-test.el --- Tests for the quiet table look in sp-org-tables -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'cl-lib)
(require 'color)
(require 'sp-org-tables)

(ert-deftest sp-org-tables-blend-mixes-foreground-into-background ()
  (cl-letf (((symbol-function 'face-attribute)
             (lambda (_face attr &rest _)
               (if (eq attr :foreground) "#ffffff" "#000000"))))
    (should (equal (sp-org-tables--blend 0) "#000000"))
    (should (equal (sp-org-tables--blend 1) "#ffffff"))
    (should (member (sp-org-tables--blend 0.5) (list "#7f7f7f" "#808080")))))

(ert-deftest sp-org-tables-blend-is-nil-without-colours ()
  (cl-letf (((symbol-function 'face-attribute)
             (lambda (&rest _) 'unspecified)))
    (should-not (sp-org-tables--blend 0.2))))

(ert-deftest sp-org-tables-org-modern-leaves-tables-to-the-widget ()
  (should-not org-modern-table))

(ert-deftest sp-org-tables-quiet-pipes-dim-separators-and-rules ()
  (with-temp-buffer
    (insert "| ab | cd |\n|----+----|\n| 1  | 2  |\n\nplain | text\n")
    (org-mode)
    (sp-org-tables-quiet-pipes-mode 1)
    (font-lock-ensure)
    (let ((dimmed (lambda (pos)
                    (memq 'sp-org-tables-pipe
                          (ensure-list (get-text-property pos 'face))))))
      (should (funcall dimmed 1))                       ; leading pipe
      (should-not (funcall dimmed 3))                   ; cell text
      (should (funcall dimmed (+ 13 3)))                ; inside the rule line
      (should-not (funcall dimmed (- (point-max) 6))))))  ; pipe outside a table

(provide 'sp-org-tables-test)
;;; sp-org-tables-test.el ends here
