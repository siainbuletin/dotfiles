;;; sp-reading-sidenotes-test.el --- Tests for sp-reading-sidenotes -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'cl-lib)

(defvar sp-reading-mode)
(defvar sp-reading-right-margin)

;; The module declares its package with use-package; the test needs no packages.
(defmacro use-package (&rest _) nil)
(require 'sp-reading-sidenotes)

(defun sp-reading-sidenotes-test--scan (text)
  "The scan of an Org buffer with TEXT."
  (with-temp-buffer
    (insert text)
    (org-mode)
    (sp-reading-sidenotes--scan)))

(ert-deftest sp-reading-sidenotes-test-scan-basic ()
  (let ((notes (sp-reading-sidenotes-test--scan
                "A claim[fn::[[id:k][Kant]] and [[id:h][Hume]]] holds.")))
    (should (= (length notes) 1))
    (should (equal (nth 3 (car notes)) "Kant and Hume"))
    (should-not (nth 2 (car notes)))))

(ert-deftest sp-reading-sidenotes-test-scan-label ()
  (let ((notes (sp-reading-sidenotes-test--scan "x[fn:a:[[id:k][Kant]]] z")))
    (should (equal (nth 2 (car notes)) "a"))
    (should (equal (nth 3 (car notes)) "Kant"))))

(ert-deftest sp-reading-sidenotes-test-scan-ignores-others ()
  (should-not (sp-reading-sidenotes-test--scan
               "Ref[fn:1] and [fn::a plain remark] and [fn::[[https://x.org][web]]].")))

(ert-deftest sp-reading-sidenotes-test-scan-positions ()
  (let* ((text "ab [fn::[[id:k][K]]] de")
         (note (car (sp-reading-sidenotes-test--scan text))))
    (should (equal (substring text (1- (nth 0 note)) (1- (nth 1 note)))
                   "[fn::[[id:k][K]]]"))))

(ert-deftest sp-reading-sidenotes-test-scan-two ()
  (let ((notes (sp-reading-sidenotes-test--scan
                "a[fn::[[id:1][One]]] b [fn::[[id:3][Three]]] c")))
    (should (equal (mapcar (lambda (n) (nth 3 n)) notes) '("One" "Three")))))

(ert-deftest sp-reading-sidenotes-test-plain ()
  (should (equal (sp-reading-sidenotes--plain "a [[id:1][B]]  c [[https://x.org]]")
                 "a B c https://x.org")))

(ert-deftest sp-reading-sidenotes-test-lines-fit-margin ()
  (let ((sp-reading-sidenote-margin 20))
    (let ((lines (sp-reading-sidenotes--lines
                  3 "a long reminder about the ground of obligation")))
      (should (> (length lines) 1))
      (should (string-prefix-p "3 " (car lines)))
      (dolist (l lines) (should (<= (string-width l) 19))))))

(defun sp-reading-sidenotes-test--margin-overlays ()
  "The margin overlays of the current buffer, in buffer order."
  (sort (cl-remove-if-not (lambda (o) (overlay-get o 'before-string))
                          (overlays-in (point-min) (point-max)))
        (lambda (a b) (< (overlay-start a) (overlay-start b)))))

(defmacro sp-reading-sidenotes-test--in-window (text &rest body)
  "Show an Org buffer with TEXT in the selected window and run BODY there."
  `(let ((buffer (generate-new-buffer " *sidenote test*")))
     (unwind-protect
         (progn
           (set-window-buffer (selected-window) buffer)
           (with-current-buffer buffer
             (insert ,text)
             (org-mode)
             (let ((sp-reading-sidenote-min-text 10))
               ,@body)))
       (kill-buffer buffer))))

(ert-deftest sp-reading-sidenotes-test-render-and-clear ()
  (sp-reading-sidenotes-test--in-window
   "One[fn::[[id:k][Kant]]] two.\n\nThree[fn::[[id:h][Hume]]] four.\n"
   (sp-reading-sidenotes--render)
   (should (= (length (sp-reading-sidenotes-test--margin-overlays)) 2))
   (should (= (length (cl-remove-if-not
                       (lambda (o) (overlay-get o 'display))
                       (overlays-in (point-min) (point-max))))
              2))
   (should (equal (buffer-string)
                  "One[fn::[[id:k][Kant]]] two.\n\nThree[fn::[[id:h][Hume]]] four.\n"))
   (sp-reading-sidenotes--clear)
   (should-not (overlays-in (point-min) (point-max)))))

(ert-deftest sp-reading-sidenotes-test-notes-do-not-overlap ()
  "Two footnotes on one line put their margin lines on different lines."
  (sp-reading-sidenotes-test--in-window
   "A[fn::[[id:a][First one]]] b[fn::[[id:b][Second one]]] c\n"
   (sp-reading-sidenotes--render)
   (let ((positions (mapcar #'overlay-start
                            (sp-reading-sidenotes-test--margin-overlays))))
     (should (= (length positions) (length (delete-dups (copy-sequence positions))))))))

(ert-deftest sp-reading-sidenotes-test-too-narrow-draws-nothing ()
  (sp-reading-sidenotes-test--in-window
   "A[fn::[[id:x][X]]] b\n"
   (let ((sp-reading-sidenote-min-text 10000))
     (sp-reading-sidenotes--render))
   (should-not (overlays-in (point-min) (point-max)))))

(ert-deftest sp-reading-sidenotes-test-mode-needs-reading-mode ()
  (with-temp-buffer
    (org-mode)
    (let ((sp-reading-mode nil))
      (should-error (sp-reading-sidenotes-mode 1) :type 'user-error)
      (should-not sp-reading-sidenotes-mode))))

(ert-deftest sp-reading-sidenotes-test-mode-sets-and-restores-margin ()
  (sp-reading-sidenotes-test--in-window
   "A[fn::[[id:x][X]]] b\n"
   (let ((sp-reading-mode t)
         (sp-reading-right-margin 6))
     (setq-local right-margin-width 6)
     (sp-reading-sidenotes-mode 1)
     (should (= right-margin-width sp-reading-sidenote-margin))
     (should (= sp-reading-right-margin sp-reading-sidenote-margin))
     (sp-reading-sidenotes-mode -1)
     (should (= right-margin-width 6))
     (should (= sp-reading-right-margin 6))
     (should-not (overlays-in (point-min) (point-max))))))

(ert-deftest sp-reading-sidenotes-test-follow-reading-mode ()
  (sp-reading-sidenotes-test--in-window
   "A[fn::[[id:x][X]]] b\n"
   (let ((sp-reading-mode t) (sp-reading-right-margin 6))
     (sp-reading-sidenotes--follow)
     (should sp-reading-sidenotes-mode)
     (setq sp-reading-mode nil)
     (sp-reading-sidenotes--follow)
     (should-not sp-reading-sidenotes-mode))))

(provide 'sp-reading-sidenotes-test)
;;; sp-reading-sidenotes-test.el ends here
