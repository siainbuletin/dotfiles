;;; sp-vulpea-ui-view-test.el --- Tests for sp-vulpea-ui-view  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(provide 'vulpea-ui)
(provide 'vui)

(defvar vulpea-ui--rendering nil)
(defvar-local vulpea-ui--refresh-generation 0)
(defvar vulpea-ui-auto-refresh-delay 1.5)
(defvar-local test-note nil)
(defvar test-calls nil)
(defvar test-focus-calls 0)

(define-derived-mode vulpea-ui-sidebar-mode special-mode "vui")
(defun vulpea-note-id (note) (plist-get note :id))
(defun vulpea-ui--get-note-from-buffer (buffer)
  (buffer-local-value 'test-note buffer))
(defun vulpea-ui--get-main-window (&optional _frame) (selected-window))
(defun vulpea-ui-visit-note (_note) (select-window test-main-window))
(defun vulpea-ui--jump-to-position (_note _pos) nil)
(defun vulpea-ui--jump-to-file-position (_path _pos) nil)
(defun vulpea-ui--jump-to-file-line (_path _line) nil)
(defvar test-main-window nil)
(defun vui-component (type &rest props) (cons type props))
(defun vui-instance-buffer (instance) (plist-get instance :buffer))
(defun vui-mount (component name)
  (push (list 'mount (plist-get (cdr component) :note) name) test-calls)
  (list :buffer (get-buffer name)))
(defun vui-update (_instance props) (push (list 'hard (plist-get props :note)) test-calls))
(defun vui-update-props (_instance props) (push (list 'soft (plist-get props :note)) test-calls))

(load (expand-file-name
       "../libraries/modules/vulpea/sp-vulpea-ui-view.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro test-with-windows (&rest body)
  "Run BODY with windows wa, wp, wb and wv showing A, P, B and the view."
  (declare (indent 0))
  `(let ((test-calls nil)
         (sp-vulpea-ui-view--note nil)
         (sp-vulpea-ui-view--instance nil)
         (sp-vulpea-ui-view--sync-timer nil)
         (sp-vulpea-ui-view--idle-timer nil)
         (a (generate-new-buffer " test-a"))
         (p (generate-new-buffer " test-p"))
         (b (generate-new-buffer " test-b")))
     (unwind-protect
         (save-window-excursion
           (delete-other-windows)
           (with-current-buffer a (setq test-note '(:id "a")))
           (with-current-buffer b (setq test-note '(:id "b")))
           (let* ((window-min-height 1)
                  (window-safe-min-height 1)
                  (view (get-buffer-create sp-vulpea-ui-view-buffer-name))
                  (wa (selected-window))
                  (wp (split-window))
                  (wb (split-window wp))
                  (wv (split-window wb)))
             (with-current-buffer view (sp-vulpea-ui-view-mode))
             (set-window-buffer wa a)
             (set-window-buffer wp p)
             (set-window-buffer wb b)
             (set-window-buffer wv view)
             ,@body))
       (when-let* ((view (sp-vulpea-ui-view--buffer))) (kill-buffer view))
       (mapc #'kill-buffer (list a p b)))))

(ert-deftest sp-vulpea-ui-view-test-find-note-newest ()
  (test-with-windows
    (select-window wa)
    (select-window wb)
    (select-window wp)
    (should (equal (sp-vulpea-ui-view--find-note) '(:id "b")))
    (select-window wa)
    (should (equal (sp-vulpea-ui-view--find-note) '(:id "a")))))

(ert-deftest sp-vulpea-ui-view-test-find-note-skips-view ()
  (test-with-windows
    (select-window wb)
    (select-window wv)
    (should (equal (sp-vulpea-ui-view--find-note) '(:id "b")))))

(ert-deftest sp-vulpea-ui-view-test-find-note-none ()
  (test-with-windows
    (with-current-buffer (window-buffer wa) (setq test-note nil))
    (with-current-buffer (window-buffer wb) (setq test-note nil))
    (should-not (sp-vulpea-ui-view--find-note))))

(ert-deftest sp-vulpea-ui-view-test-sync-mounts-then-updates ()
  (test-with-windows
    (select-window wa)
    (sp-vulpea-ui-view--sync)
    (should (equal (car test-calls)
                   (list 'mount '(:id "a") sp-vulpea-ui-view-buffer-name)))
    (setq sp-vulpea-ui-view--instance
          (list :buffer (sp-vulpea-ui-view--buffer)))
    (sp-vulpea-ui-view--sync)
    (should (= (length test-calls) 1))
    (select-window wb)
    (sp-vulpea-ui-view--sync)
    (should (equal (car test-calls) '(soft (:id "b"))))
    (should (equal sp-vulpea-ui-view--note '(:id "b")))))

(ert-deftest sp-vulpea-ui-view-test-hard-refresh ()
  (test-with-windows
    (select-window wa)
    (sp-vulpea-ui-view--sync)
    (setq sp-vulpea-ui-view--instance
          (list :buffer (sp-vulpea-ui-view--buffer)))
    (sp-vulpea-ui-view-refresh)
    (should (equal (car test-calls) '(hard (:id "a"))))
    (should (= 1 (buffer-local-value 'vulpea-ui--refresh-generation
                                     (sp-vulpea-ui-view--buffer))))))

(ert-deftest sp-vulpea-ui-view-test-no-window-no-render ()
  (test-with-windows
    (select-window wa)
    (delete-window wv)
    (sp-vulpea-ui-view--sync)
    (should-not test-calls)))

(ert-deftest sp-vulpea-ui-view-test-main-window-from-view ()
  (test-with-windows
    (select-window wb)
    (select-window wv)
    (should (eq (vulpea-ui--get-main-window) wb))
    (select-window wa)
    (should (eq (vulpea-ui--get-main-window) wa))))

(ert-deftest sp-vulpea-ui-view-test-visit-focuses-frame ()
  (test-with-windows
    (let ((test-focus-calls 0)
          (test-main-window wa))
      (cl-letf (((symbol-function 'select-frame-set-input-focus)
                 (lambda (_frame) (cl-incf test-focus-calls))))
        (select-window wv)
        (vulpea-ui-visit-note nil)
        (should (= test-focus-calls 1))
        (select-window wp)
        (vulpea-ui-visit-note nil)
        (should (= test-focus-calls 1))
        (select-window wv)
        (let ((sp-vulpea-ui-view-focus-on-visit nil))
          (vulpea-ui-visit-note nil))
        (should (= test-focus-calls 1))))))

(ert-deftest sp-vulpea-ui-view-test-frame-name ()
  (let ((sp-vulpea-ui-view-frame-name "tile-me")
        (sp-vulpea-ui-view-frame-parameters '((name . "other") (width . 40))))
    (let ((parameters (sp-vulpea-ui-view--frame-parameters)))
      (should (equal (alist-get 'name parameters) "tile-me"))
      (should (= (length (seq-filter (lambda (p) (eq (car p) 'name)) parameters)) 1))
      (should (equal (alist-get 'width parameters) 40)))))

(ert-deftest sp-vulpea-ui-view-test-wrap-on ()
  (let ((sp-vulpea-ui-view-wrap-lines t)
        (sp-vulpea-ui-view-wrap-indent t))
    (with-temp-buffer
      (setq-local truncate-lines t)
      (sp-vulpea-ui-view--apply-wrap)
      (should visual-line-mode)
      (should-not truncate-lines))))

(ert-deftest sp-vulpea-ui-view-test-wrap-off ()
  (let ((sp-vulpea-ui-view-wrap-lines nil))
    (with-temp-buffer
      (visual-line-mode 1)
      (sp-vulpea-ui-view--apply-wrap)
      (should-not visual-line-mode))))

(ert-deftest sp-vulpea-ui-view-test-wrap-is-local-to-the-view ()
  (let ((sp-vulpea-ui-view-wrap-lines t)
        (other (generate-new-buffer " test-other"))
        (view (generate-new-buffer " test-view")))
    (unwind-protect
        (progn
          (with-current-buffer view (sp-vulpea-ui-view-mode))
          (should (buffer-local-value 'visual-line-mode view))
          (should-not (buffer-local-value 'visual-line-mode other)))
      (kill-buffer other)
      (kill-buffer view))))

(ert-deftest sp-vulpea-ui-view-test-toggle-and-teardown ()
  (let ((sp-vulpea-ui-view-use-frame nil)
        (sp-vulpea-ui-view--note nil)
        (sp-vulpea-ui-view--instance nil)
        (sp-vulpea-ui-view--sync-timer nil)
        (sp-vulpea-ui-view--idle-timer nil)
        (test-calls nil)
        (a (generate-new-buffer " test-a")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (with-current-buffer a (setq test-note '(:id "a")))
          (switch-to-buffer a)
          (sp-vulpea-ui-view-toggle)
          (should (sp-vulpea-ui-view--window))
          (should (equal sp-vulpea-ui-view--note '(:id "a")))
          (should (memq #'sp-vulpea-ui-view--on-window-change
                        window-selection-change-functions))
          (should sp-vulpea-ui-view--idle-timer)
          (sp-vulpea-ui-view-toggle)
          (should-not (sp-vulpea-ui-view--buffer))
          (should-not sp-vulpea-ui-view--idle-timer)
          (should-not (memq #'sp-vulpea-ui-view--on-window-change
                            window-selection-change-functions)))
      (kill-buffer a)
      (when-let* ((view (sp-vulpea-ui-view--buffer))) (kill-buffer view)))))

;;; sp-vulpea-ui-view-test.el ends here
