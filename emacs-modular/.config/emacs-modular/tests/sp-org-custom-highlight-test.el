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

;;;; Links and citations inside @@comment:@@

(defun sp-och-test--context-at (text search)
  "The `org-element-context' in TEXT with point after SEARCH, as (TYPE BEG END)."
  (sp-och-test--with-buffer text
    (goto-char (point-min))
    (search-forward search)
    (let ((c (org-element-context)))
      (list (org-element-type c)
            (org-element-property :begin c)
            (org-element-property :end c)))))

(defmacro sp-och-test--opening (text search &rest body)
  "In an Org buffer with TEXT and point after SEARCH, run BODY.
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

(ert-deftest sp-och-context-finds-link-in-comment ()
  ;; "[[id:b][s]]" starts at 14 in "x @@comment:see " + 1.
  (should (equal (sp-och-test--context-at "x @@comment:see [[id:b][s]] ok@@" "[[id")
                 '(link 17 29))))

(ert-deftest sp-och-context-finds-citation-parts-in-comment ()
  (let ((text "@@comment:read [cite:@smith2020; @doe1999] soon@@"))
    (should (equal (sp-och-test--context-at text "@smi")
                   (list 'citation-reference 22 33)))
    (should (eq (car (sp-och-test--context-at text "[ci")) 'citation))
    (should (equal (cdr (sp-och-test--context-at text "[ci")) '(16 44)))))

(ert-deftest sp-och-context-in-comment-text-stays-the-snippet ()
  (should (eq (car (sp-och-test--context-at "@@comment:see [[id:b][s]] ok@@" "see"))
              'export-snippet)))

(ert-deftest sp-och-context-outside-comment-and-other-backend-untouched ()
  (should (eq (car (sp-och-test--context-at "[[id:b][s]]" "[[id")) 'link))
  (should (eq (car (sp-och-test--context-at "@@html:[[id:b][s]]@@" "[[id"))
              'export-snippet)))

(ert-deftest sp-och-open-at-point-follows-link-in-comment ()
  (should (equal (sp-och-test--opening
                     "[[id:aaa][first]]\n@@comment:see [[id:bbb][second]] ok@@\n"
                     "seco"
                   (org-open-at-point))
                 '((link "id:bbb")))))

(ert-deftest sp-och-open-at-point-follows-citation-in-comment ()
  (should (equal (sp-och-test--opening "@@comment:read [cite:@smith2020] soon@@\n"
                     "smi"
                   (org-open-at-point))
                 '((cite "smith2020")))))

(ert-deftest sp-och-ret-follows-link-in-comment ()
  (let ((text "[[id:a][f]]\n@@comment:[[id:b][second]]@@\n"))
    (should (equal (sp-och-test--opening text "seco"
                     (let ((org-return-follows-link t))
                       (org-return)))
                   '((link "id:b"))))
    (should-not (sp-och-test--opening "@@comment:[[id:b][s]]@@" "[[id:b][s"
                  (let ((org-return-follows-link nil))
                    (org-return))))))

(ert-deftest sp-och-citation-key-at-point-inside-comment ()
  ;; What citar's Embark target finder asks for.
  (sp-och-test--with-buffer "@@comment:read [cite:@smith2020] soon@@"
    (goto-char (point-min))
    (search-forward "smi")
    (let ((ref (org-element-context)))
      (should (eq (org-element-type ref) 'citation-reference))
      (should (equal (org-element-property :key ref) "smith2020"))
      (should (equal (buffer-substring (org-element-property :begin ref)
                                       (org-element-property :end ref))
                     "@smith2020")))))

(ert-deftest sp-och-citation-can-be-inserted-in-comment-text ()
  (sp-och-test--with-buffer "@@comment:read soon@@"
    (goto-char (point-min))
    (search-forward "read ")
    (should (org-cite--allowed-p (org-element-context))))
  (sp-och-test--with-buffer "@@html:read soon@@"
    (goto-char (point-min))
    (search-forward "read ")
    (should-not (org-cite--allowed-p (org-element-context)))))

(ert-deftest sp-och-comment-with-single-at-is-highlighted ()
  (sp-och-test--with-buffer "a @@comment:read [cite:@key] x@@ b"
    (org-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "read")
    (should (memq 'my-org-inline-comment
                  (let ((f (get-text-property (1- (point)) 'face)))
                    (if (listp f) f (list f)))))))

(provide 'sp-org-custom-highlight-test)
;;; sp-org-custom-highlight-test.el ends here
