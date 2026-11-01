;;; sp-org-tables-test.el --- Tests for following links in table widgets -*- lexical-binding: t; -*-

;; The section "Following links in table widgets" of sp-org-tables.el is
;; evaluated alone.  A widget row is faked: an overlay with the `org-table-widget'
;; property and a `before-string' whose links carry `htmlize-link', as Org
;; fontifies them and the widget keeps them.  `org-link-open-from-string' is
;; recorded instead of run.  Not tested here: the real widget (needs a graphical
;; frame) and a real mouse click.

(require 'ert)
(require 'org)
(require 'cl-lib)
(require 'subr-x)
(require 'seq)

(defvar org-table-widget-mode nil)

(with-temp-buffer
  (insert-file-contents
   (expand-file-name "../libraries/modules/text/sp-org-tables.el"
                     (file-name-directory (or load-file-name buffer-file-name))))
  (goto-char (point-min))
  (search-forward ";;;; Following links in table widgets")
  (let ((end (save-excursion (search-forward "(provide 'sp-org-tables)")
                             (match-beginning 0)))
        form)
    (narrow-to-region (point) end)
    (while (setq form (condition-case nil (read (current-buffer)) (end-of-file nil)))
      (unless (eq (car-safe form) 'with-eval-after-load) (eval form t)))))

(defun sp-org-tables-test--link (text uri)
  (propertize text 'htmlize-link (list :uri uri) 'face 'org-link))

(defun sp-org-tables-test--row (&rest parts)
  (apply #'concat parts))

(defvar sp-org-tables-test--opened nil)

(defmacro sp-org-tables-test--with-row (row &rest body)
  "Run BODY in a buffer whose first line is covered by a widget overlay drawing ROW."
  `(with-temp-buffer
     (insert "| [[id:a][A]] | [[id:b][B]] |\n")
     (let ((ov (make-overlay 1 (point-max))))
       (overlay-put ov 'org-table-widget t)
       (overlay-put ov 'before-string ,row))
     (goto-char 3)
     (let ((sp-org-tables-test--opened nil))
       (cl-letf (((symbol-function 'org-link-open-from-string)
                  (lambda (s &rest _) (push s sp-org-tables-test--opened))))
         ,@body))))

(ert-deftest sp-org-tables-test-one-link-opens-without-menu ()
  (sp-org-tables-test--with-row
   (sp-org-tables-test--row "│ " (sp-org-tables-test--link "Alpha" "id:a") " │ plain │")
   (cl-letf (((symbol-function 'completing-read)
              (lambda (&rest _) (error "menu shown"))))
     (should (sp-org-tables-open-row-link))
     (should (equal sp-org-tables-test--opened '("[[id:a]]"))))))

(ert-deftest sp-org-tables-test-several-links-ask ()
  (sp-org-tables-test--with-row
   (sp-org-tables-test--row (sp-org-tables-test--link "Alpha" "id:a") " "
                            (sp-org-tables-test--link "Beta" "id:b"))
   (cl-letf (((symbol-function 'completing-read)
              (lambda (_p choices &rest _) (cadr choices))))
     (should (sp-org-tables-open-row-link))
     (should (equal sp-org-tables-test--opened '("[[id:b]]"))))))

(ert-deftest sp-org-tables-test-split-link-is-one ()
  (sp-org-tables-test--with-row
   (sp-org-tables-test--row (sp-org-tables-test--link "Al" "id:a") "\n"
                            (sp-org-tables-test--link "pha" "id:a"))
   (should (sp-org-tables-open-row-link))
   (should (equal sp-org-tables-test--opened '("[[id:a]]")))))

(ert-deftest sp-org-tables-test-no-link-or-no-widget ()
  (sp-org-tables-test--with-row "│ plain │"
    (should-not (sp-org-tables-open-row-link)))
  (with-temp-buffer
    (insert "| [[id:a][A]] |\n")
    (goto-char 3)
    (should-not (sp-org-tables-open-row-link))))

(ert-deftest sp-org-tables-test-click-follows-the-clicked-link ()
  (sp-org-tables-test--with-row
   (sp-org-tables-test--row (sp-org-tables-test--link "Alpha" "id:a") " "
                            (sp-org-tables-test--link "Beta" "id:b"))
   (let* ((str (overlay-get (car (overlays-at 3)) 'before-string))
          (event (list 'mouse-1
                       (list (selected-window) 3 '(0 . 0) 0
                             (cons str 8) 3 '(0 . 0) nil '(0 . 0) '(0 . 0))))
          (org-table-widget-mode t))
     (cl-letf (((symbol-function 'select-window) #'ignore))
       (org-open-at-mouse event))
     (should (equal sp-org-tables-test--opened '("[[id:b]]"))))))

(provide 'sp-org-tables-test)
;;; sp-org-tables-test.el ends here
