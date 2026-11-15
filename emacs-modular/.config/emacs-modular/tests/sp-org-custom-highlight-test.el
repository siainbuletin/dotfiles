;;; sp-org-custom-highlight-test.el --- Tests for C-c h  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-org-custom-highlight-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org)
(load (expand-file-name "libraries/modules/text/sp-org-custom-highlight.el")
      nil t)

(defmacro sp-och-test--with-buffer (text &rest body)
  "Run BODY in an Org buffer holding TEXT, with `transient-mark-mode' on."
  (declare (indent 1))
  `(with-temp-buffer
     (delay-mode-hooks (org-mode))
     (transient-mark-mode 1)
     (buffer-enable-undo)
     (insert ,text)
     ,@body))

(defun sp-och-test--select (beg end &optional point-at-beg)
  "Select BEG..END; with POINT-AT-BEG put point at the start."
  (if point-at-beg
      (progn (goto-char beg) (push-mark end t t))
    (goto-char end) (push-mark beg t t))
  (setq mark-active t))

(ert-deftest sp-och-no-region-inserts-empty-comment ()
  (sp-och-test--with-buffer ""
    (sp-org-insert-inline-comment)
    (should (equal (buffer-string) "@@comment:@@"))
    (should (= (point) (- (point-max) 2)))))

(ert-deftest sp-och-region-is-wrapped ()
  (sp-och-test--with-buffer "a big idea here"
    (sp-och-test--select 3 9)
    (sp-org-insert-inline-comment)
    (should (equal (buffer-string) "a @@comment:big id@@ea here"))
    (should (= (point) 21))
    (should-not (use-region-p))))

(ert-deftest sp-och-point-at-start-same-result ()
  (sp-och-test--with-buffer "a big idea here"
    (sp-och-test--select 3 9 t)
    (sp-org-insert-inline-comment)
    (should (equal (buffer-string) "a @@comment:big id@@ea here"))
    (should-not (use-region-p))))

(ert-deftest sp-och-second-press-does-not-nest ()
  (sp-och-test--with-buffer "word"
    (sp-och-test--select 1 5)
    (sp-org-insert-inline-comment)
    (sp-org-insert-inline-comment)
    (should (equal (buffer-substring 1 (point-max)) "@@comment:word@@@@comment:@@"))))

(ert-deftest sp-och-multiline-wraps-each-line ()
  (sp-och-test--with-buffer "  one two  \n\nthree\n"
    (sp-och-test--select 1 (point-max))
    (sp-org-insert-inline-comment)
    (should (equal (buffer-string)
                   "  @@comment:one two@@  \n\n@@comment:three@@\n"))))

(ert-deftest sp-och-region-with-at-signs-is-refused ()
  (sp-och-test--with-buffer "mail me@@home"
    (sp-och-test--select 1 (point-max))
    (should-error (sp-org-insert-inline-comment) :type 'user-error)
    (should (equal (buffer-string) "mail me@@home"))))

(ert-deftest sp-och-blank-region-counts-as-no-region ()
  (sp-och-test--with-buffer "a   b"
    (sp-och-test--select 2 5)
    (sp-org-insert-inline-comment)
    (should (equal (buffer-string) "a   @@comment:@@b"))))

(ert-deftest sp-och-undo-is-one-step ()
  (sp-och-test--with-buffer "one\ntwo"
    (undo-boundary)
    (sp-och-test--select 1 (point-max))
    (sp-org-insert-inline-comment)
    (undo-boundary)
    (primitive-undo 1 (cdr buffer-undo-list))
    (should (equal (buffer-string) "one\ntwo"))))

(ert-deftest sp-och-bound-to-c-c-h ()
  (should (eq (lookup-key org-mode-map (kbd "C-c h"))
              #'sp-org-insert-inline-comment)))

(provide 'sp-org-custom-highlight-test)
;;; sp-org-custom-highlight-test.el ends here
