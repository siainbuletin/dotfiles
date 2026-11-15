;;; sp-org-custom-highlight-test.el --- Tests for C-c h  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-org-custom-highlight-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org)
(require (quote cl-lib))
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

;;;; Links inside @@comment:@@

(defmacro sp-och-test--opening (text search &rest body)
  "In an Org buffer with TEXT and point inside SEARCH, run BODY.
Return the list of what was opened, as (link RAW) or (cite KEY)."
  (declare (indent 2))
  `(let (opened)
     (cl-letf (((symbol-function 'org-link-open)
                (lambda (l &rest _)
                  (push (list 'link (org-element-property :raw-link l)) opened)))
               ((symbol-function 'org-cite-follow)
                (lambda (d &rest _)
                  (push (list 'cite (org-element-property :key d)) opened))))
       (sp-och-test--with-buffer ,text
         (goto-char (point-min))
         (search-forward ,search)
         ,@body))
     (nreverse opened)))

(ert-deftest sp-och-link-in-comment-opens ()
  (should (equal (sp-och-test--opening
                     "[[id:aaa][first]]\nx @@comment:see [[id:bbb][second]] ok@@\n"
                     "seco"
                   (should (sp-org-open-comment-link)))
                 '((link "id:bbb")))))

(ert-deftest sp-och-open-at-point-uses-the-comment-link ()
  (should (equal (sp-och-test--opening
                     "[[id:aaa][first]]\n@@comment:[[id:bbb][second]]@@\n"
                     "seco"
                   (org-open-at-point))
                 '((link "id:bbb")))))

(ert-deftest sp-och-citation-in-comment-opens ()
  (should (equal (sp-och-test--opening "@@comment:read [cite:@smith2020] soon@@\n"
                     "smi"
                   (should (sp-org-open-comment-link)))
                 '((cite "smith2020")))))

(ert-deftest sp-och-comment-text-and-edges-do-not-open ()
  (should-not (sp-och-test--opening "@@comment:see [[id:b][s]] ok@@" "see "
                (should-not (sp-org-open-comment-link))))
  (should-not (sp-och-test--opening "@@comment:see [[id:b][s]] ok@@" "[[id:b][s]]"
                (should-not (sp-org-open-comment-link))))
  (should-not (sp-och-test--opening "@@comment:see [[id:b][s]] ok@@" "@@comment:"
                (should-not (sp-org-open-comment-link)))))

(ert-deftest sp-och-other-snippet-and-plain-link-untouched ()
  (should-not (sp-och-test--opening "@@html:[[id:b][s]]@@" "[[id:b"
                (should-not (sp-org-open-comment-link))))
  (should-not (sp-och-test--opening "[[id:b][s]]" "[[id:b"
                (should-not (sp-org-open-comment-link)))))

(ert-deftest sp-och-ret-follows-link-in-comment ()
  (should (equal (sp-och-test--opening "[[id:a][f]]\n@@comment:[[id:b][second]]@@\n"
                     "seco"
                   (let ((org-return-follows-link t))
                     (org-return)))
                 '((link "id:b"))))
  (should-not (sp-och-test--opening "@@comment:[[id:b][second]]@@"
                  "seco"
                (let ((org-return-follows-link nil))
                  (org-return)))))

(provide 'sp-org-custom-highlight-test)
;;; sp-org-custom-highlight-test.el ends here
