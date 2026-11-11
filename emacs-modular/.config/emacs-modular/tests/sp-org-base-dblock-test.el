;;; sp-org-base-dblock-test.el --- Tests for dynamic block templates -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'org)

;; Load only the template section of sp-org-base, which needs no packages.
(let ((file (expand-file-name "../libraries/modules/text/sp-org-base.el"
                              (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (search-forward ";;;; Dynamic block templates")
    (beginning-of-line)
    (let ((start (point)))
      (search-forward "(with-eval-after-load 'org")
      (beginning-of-line)
      (eval (read (format "(progn %s)" (buffer-substring start (point)))) t))))

(defvar sp-org-dblock-test--calls nil)

(defun org-dblock-write:sp-test-block (params)
  "Test dynamic block: record PARAMS and write a line."
  (push params sp-org-dblock-test--calls)
  (insert "filled"))

(ert-deftest sp-org-dblock-default-template-uses-parent-of-self ()
  (let ((template (cdr (assoc "Children of this note" sp-org-dblock-templates))))
    (should (equal (plist-get template :name) "collection-query-table"))
    (should (eq (plist-get template :parent-of) 'self))))

(ert-deftest sp-org-dblock-insert-and-update ()
  (let ((sp-org-dblock-templates '(("T" :name "sp-test-block" :parent-of self :n 2)))
        (sp-org-dblock-test--calls nil))
    (with-temp-buffer
      (org-mode)
      (insert "* Heading")
      (sp-org-dblock-insert-template "T")
      (should (string-match-p
               "\\* Heading\n#\\+BEGIN: sp-test-block :parent-of self :n 2\nfilled\n#\\+END:"
               (buffer-string)))
      (should (looking-at "#\\+BEGIN: sp-test-block"))
      (should (eq (plist-get (car sp-org-dblock-test--calls) :parent-of) 'self)))))

(ert-deftest sp-org-dblock-insert-without-update ()
  (let ((sp-org-dblock-templates '(("T" :name "sp-test-block")))
        (sp-org-dblock-update-after-insert nil))
    (with-temp-buffer
      (org-mode)
      (sp-org-dblock-insert-template "T")
      (should-not (string-match-p "filled" (buffer-string))))))

(ert-deftest sp-org-dblock-unknown-template-errors ()
  (let ((sp-org-dblock-templates nil))
    (with-temp-buffer
      (org-mode)
      (should-error (sp-org-dblock-insert-template "nope") :type 'user-error))))

;;;; Groups and sources

(defvar org-dynamic-blocks)

(ert-deftest sp-org-dblock-category-is-not-a-block-parameter ()
  (let ((sp-org-dblock-templates '(("T" :category "Academic" :name "sp-test-block" :n 2)))
        (sp-org-dblock-template-functions nil)
        (sp-org-dblock-test--calls nil))
    (with-temp-buffer
      (org-mode)
      (sp-org-dblock-insert-template "T")
      (should (string-match-p "#\\+BEGIN: sp-test-block :n 2\n" (buffer-string)))
      (should-not (string-match-p "category" (buffer-string))))))

(ert-deftest sp-org-dblock-template-functions-add-templates ()
  (let ((sp-org-dblock-templates nil)
        (sp-org-dblock-template-functions
         (list (lambda () '(("From function" :category "Collections" :name "sp-test-block")))))
        (sp-org-dblock-test--calls nil))
    (with-temp-buffer
      (org-mode)
      (sp-org-dblock-insert-template "From function")
      (should (string-match-p "#\\+BEGIN: sp-test-block" (buffer-string))))))

(ert-deftest sp-org-dblock-completion-groups-and-orders ()
  (let* ((sp-org-dblock-category-order '("Academic" "Collections"))
         (templates '(("zeta" :category "Other") ("album" :category "Collections")
                      ("book" :category "Academic") ("alpha")))
         (table (sp-org-dblock--completion-table templates))
         (meta (cdr (funcall table "" nil 'metadata)))
         (group (cdr (assq 'group-function meta)))
         (sort-fn (cdr (assq 'display-sort-function meta))))
    (should (equal (funcall group "book" nil) "Academic"))
    (should (equal (funcall group "alpha" nil) "Other"))
    (should (equal (funcall group "book" t) "book"))
    (should (equal (funcall sort-fn '("zeta" "alpha" "album" "book"))
                   '("book" "album" "alpha" "zeta")))))

(ert-deftest sp-org-dblock-hide-disabled-blocks ()
  (let ((org-dynamic-blocks '(("clocktable" . x) ("vulpea-collection" . y)))
        (sp-org-dblock-disabled-names '("vulpea-collection")))
    (sp-org-dblock-hide-disabled)
    (should (equal org-dynamic-blocks '(("clocktable" . x))))))

(provide 'sp-org-base-dblock-test)
;;; sp-org-base-dblock-test.el ends here
