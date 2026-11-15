;;; sp-batch-report-view-test.el --- Tests for the special-mode report view -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'sp-batch-report)

(defconst sp-batch-report-view-test--name "*sp-batch-report-view-test*")

(defmacro sp-batch-report-view-test--with-report (sections &rest body)
  "Open a report of SECTIONS in the view and run BODY in its buffer."
  (declare (indent 1))
  `(let ((sp-batch-report-display 'special))
     (unwind-protect
         (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
           (with-current-buffer
               (sp-batch-report-open sp-batch-report-view-test--name
                                     (sp-batch-report-text "T" ,sections :intro "intro")
                                     :refresh #'ignore)
             ,@body))
       (when (get-buffer sp-batch-report-view-test--name)
         (kill-buffer sp-batch-report-view-test--name)))))

(defun sp-batch-report-view-test--items (n &optional prefix)
  (cl-loop for i below n
           collect (sp-batch-report-item (format "problem %d" i)
                                         :file (format "/tmp/f%d.org" i)
                                         :key (format "%sk%d" (or prefix "") i))))

(defun sp-batch-report-view-test--goto (regexp)
  (goto-char (point-min))
  (re-search-forward regexp)
  (goto-char (match-beginning 0)))

(ert-deftest sp-batch-report-view-draws-sections-and-rows ()
  (sp-batch-report-view-test--with-report
      (list (sp-batch-report-section "First" (sp-batch-report-view-test--items 3))
            (sp-batch-report-section "Empty" nil "nothing here"))
    (should (derived-mode-p 'sp-batch-report-mode 'special-mode))
    (should buffer-read-only)
    (should (string-match-p "^T\nintro\n" (buffer-string)))
    (should (string-match-p "^▼ First +3 entries$" (buffer-string)))
    (should (string-match-p "^  nothing here$" (buffer-string)))
    (should (= 3 (length sp-batch-report-view--rows)))
    (should (string-match-p "2 sections · 3 entries · 0 dropped" (sp-batch-report-view--header-line)))))

(ert-deftest sp-batch-report-view-links-are-labels ()
  (sp-batch-report-view-test--with-report
      (list (sp-batch-report-section
             "S" (list (sp-batch-report-item
                        (concat "see " (sp-batch-report-file-link "/tmp/a [x].org" "the note"))
                        :file "/tmp/b.org" :line 7))))
    (should-not (string-match-p "\\[\\[" (buffer-string)))
    (sp-batch-report-view-test--goto "the note")
    (should (equal (get-text-property (point) 'sp-batch-report-link) "file:/tmp/a [x].org"))
    (sp-batch-report-view-test--goto "b.org:7")
    (should (equal (get-text-property (point) 'sp-batch-report-link) "file:/tmp/b.org::7"))))

(ert-deftest sp-batch-report-view-tables-are-aligned ()
  (sp-batch-report-view-test--with-report
      (list (sp-batch-report-table-section
             "Works" '("Key" "Title")
             (list (sp-batch-report-item nil :row '("a" "one") :key "1")
                   (sp-batch-report-item nil :row '("longer key" "two") :key "2"))))
    (let ((columns (mapcar (lambda (re) (progn (goto-char (point-min)) (re-search-forward re)
                                               (- (match-beginning 0) (line-beginning-position))))
                           '("Title" "one" "two"))))
      (should (= 1 (length (delete-dups columns)))))))

(ert-deftest sp-batch-report-view-drop-is-local ()
  (let ((called 0))
    (sp-batch-report-view-test--with-report
        (list (sp-batch-report-section "A" (sp-batch-report-view-test--items 3))
              (sp-batch-report-section "B" (sp-batch-report-view-test--items 2 "b")))
      (setq sp-batch-report-redraw-function (lambda (&rest _) (cl-incf called))
            sp-batch-report-refresh-function (lambda (&rest _) (cl-incf called)))
      (let ((size (buffer-size)))
        (sp-batch-report-view-test--goto "problem 1")
        (sp-batch-report-drop)
        (should (= called 0))
        (should (= size (buffer-size)))
        (should (equal sp-batch-report-excluded '("k1")))
        (should (string-match-p "^▼ A +2 of 3$" (buffer-string)))
        (should (string-match-p "1 dropped" (sp-batch-report-view--header-line)))
        ;; the point moved on to the next entry
        (should (looking-at "  • f2.org"))
        (sp-batch-report-view-test--goto "problem 1")
        (should (get-text-property (point) 'sp-batch-report-dropped))
        (should (memq 'sp-batch-report-dropped (ensure-list (get-text-property (point) 'face))))
        (should-error (sp-batch-report-drop) :type 'user-error)
        (sp-batch-report-restore)
        (should-not sp-batch-report-excluded)
        (should (= size (buffer-size)))
        (should (string-match-p "^▼ A +3 entries$" (buffer-string)))
        (should-not (get-text-property (point) 'sp-batch-report-dropped))
        (should-error (sp-batch-report-restore) :type 'user-error)))))

(ert-deftest sp-batch-report-view-drop-hits-every-row-with-the-key ()
  (sp-batch-report-view-test--with-report
      (list (sp-batch-report-section "A" (sp-batch-report-view-test--items 2))
            (sp-batch-report-section "B" (sp-batch-report-view-test--items 2)))
    (sp-batch-report-view-test--goto "problem 0")
    (sp-batch-report-drop)
    (should (string-match-p "^▼ A +1 of 2$" (buffer-string)))
    (should (string-match-p "^▼ B +1 of 2$" (buffer-string)))
    (should (= 2 sp-batch-report-view--dropped))))

(ert-deftest sp-batch-report-view-excluded-keys-start-dropped ()
  (let ((sp-batch-report-display 'special))
    (unwind-protect
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (with-current-buffer
              (sp-batch-report-open
               sp-batch-report-view-test--name
               (sp-batch-report-text
                "T" (list (sp-batch-report-section "A" (sp-batch-report-view-test--items 2)))
                :excluded '("k0" "gone")
                :key-label (lambda (key) (format "label of %s" key)))
               :excluded '("k0" "gone"))
            (should (string-match-p "^▼ A +1 of 2$" (buffer-string)))
            (should (string-match-p "Dropped earlier, not in this report" (buffer-string)))
            (should (string-match-p "label of gone" (buffer-string)))
            (sp-batch-report-view-test--goto "label of gone")
            (sp-batch-report-restore)
            (should (equal sp-batch-report-excluded '("k0")))))
      (when (get-buffer sp-batch-report-view-test--name)
        (kill-buffer sp-batch-report-view-test--name)))))

(ert-deftest sp-batch-report-view-fold-and-move ()
  (sp-batch-report-view-test--with-report
      (list (sp-batch-report-section "A" (sp-batch-report-view-test--items 2))
            (sp-batch-report-section "B" (sp-batch-report-view-test--items 2 "b")))
    (sp-batch-report-view-test--goto "▼ A")
    (sp-batch-report-toggle-section)
    (should (equal (get-text-property (point) 'display) "▶"))
    (sp-batch-report-view-test--goto "problem 0")
    (should (invisible-p (point)))
    ;; next skips the folded rows and lands in B
    (sp-batch-report-view-test--goto "▼ A")
    (sp-batch-report-next)
    (should (= (point) (car (aref sp-batch-report-view--rows 2))))
    ;; everything before it is folded
    (should-error (sp-batch-report-previous) :type 'user-error)
    (sp-batch-report-view-test--goto "▼ A")
    (sp-batch-report-toggle-section)
    (should-not (get-text-property (point) 'display))
    (sp-batch-report-view-test--goto "problem 0")
    (should-not (invisible-p (point)))
    (sp-batch-report-toggle-all)
    (should (cl-every (lambda (s) (aref s 4)) sp-batch-report-view--sections))
    (sp-batch-report-toggle-all)
    (should-not (cl-some (lambda (s) (aref s 4)) sp-batch-report-view--sections))))

(ert-deftest sp-batch-report-view-refresh-keeps-folds ()
  (let ((sp-batch-report-display 'special) refreshed)
    (unwind-protect
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (cl-labels ((show (&optional _excluded)
                        (setq refreshed t)
                        (sp-batch-report-open
                         sp-batch-report-view-test--name
                         (sp-batch-report-text
                          "T" (list (sp-batch-report-section "A" (sp-batch-report-view-test--items 2))))
                         :refresh #'show)))
            (with-current-buffer (show)
              (sp-batch-report-view-test--goto "▼ A")
              (sp-batch-report-toggle-section)
              (setq refreshed nil)
              (sp-batch-report-refresh)
              (should refreshed)
              (should (aref (aref sp-batch-report-view--sections 0) 4)))))
      (when (get-buffer sp-batch-report-view-test--name)
        (kill-buffer sp-batch-report-view-test--name)))))

(ert-deftest sp-batch-report-view-visit ()
  (let (opened)
    (cl-letf (((symbol-function 'org-link-open-from-string) (lambda (s &rest _) (push s opened))))
      (sp-batch-report-view-test--with-report
          (list (sp-batch-report-section
                 "S" (list (sp-batch-report-item "text" :file "/tmp/b.org" :line 3)
                           (sp-batch-report-item "do it" :action (lambda () (push 'ran opened))))))
        (sp-batch-report-view-test--goto "text")
        (sp-batch-report-visit)
        (should (equal opened '("[[file:/tmp/b.org::3]]")))
        (sp-batch-report-view-test--goto "do it")
        (sp-batch-report-visit)
        (should (eq (car opened) 'ran))
        (goto-char (point-min))
        (should-error (sp-batch-report-visit) :type 'user-error)))))

(ert-deftest sp-batch-report-view-hints-and-keys ()
  (sp-batch-report-view-test--with-report
      (list (sp-batch-report-section "A" (sp-batch-report-view-test--items 1)))
    (setq sp-batch-report-apply-function #'ignore)
    (let ((hints (mapcar #'car (sp-batch-report--hints))))
      (dolist (key '("RET" "TAB" "n/p" "d" "u" "A" "g" "k" "q"))
        (should (member key hints))))
    (dolist (binding '(("d" . sp-batch-report-drop) ("u" . sp-batch-report-restore)
                       ("A" . sp-batch-report-apply) ("g" . sp-batch-report-refresh)
                       ("k" . sp-batch-cancel) ("q" . quit-window)
                       ("RET" . sp-batch-report-visit) ("TAB" . sp-batch-report-toggle-section)))
      (should (eq (key-binding (kbd (car binding))) (cdr binding))))))

(ert-deftest sp-batch-report-org-archive ()
  "The Org view is still there, for `org' and for reports that are plain text."
  (skip-unless (ignore-errors (with-temp-buffer (org-mode) t)))
  (let ((name sp-batch-report-view-test--name))
    (unwind-protect
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (let ((sp-batch-report-display 'org))
            (let ((text (sp-batch-report-text
                         "T" (list (sp-batch-report-section "A" (sp-batch-report-view-test--items 1))))))
              (should (string-match-p "^\\* A (1)" text))
              (with-current-buffer (sp-batch-report-open name text)
                (should (derived-mode-p 'sp-batch-report-org-mode))
                (should (sp-batch-report-buffer-p))
                (should (eq (key-binding (kbd "d")) 'sp-batch-report-drop)))))
          (let ((sp-batch-report-display 'special))
            (with-current-buffer (sp-batch-report-open name "#+title: plain\n\n* A\n- x\n")
              (should (derived-mode-p 'sp-batch-report-org-mode))
              (should (sp-batch-report-buffer-p)))))
      (when (get-buffer name) (kill-buffer name)))))

(ert-deftest sp-batch-report-view-is-fast ()
  "Hundreds of sections and thousands of rows draw at once, and a drop costs a row."
  (let* ((items (sp-batch-report-view-test--items 4000))
         (sections (cl-loop for i below 400
                            collect (sp-batch-report-section
                                     (format "Section %d" i)
                                     (seq-subseq items (* i 10) (* (1+ i) 10)))))
         (sp-batch-report-display 'special)
         (start (float-time)))
    (unwind-protect
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (with-current-buffer
              (sp-batch-report-open sp-batch-report-view-test--name
                                    (sp-batch-report-text "T" sections) :refresh #'ignore)
            (let ((drawn (- (float-time) start)))
              (message "sp-batch-report-view: 4000 rows in 400 sections drawn in %.3f s" drawn)
              (should (< drawn 5.0)))
            (goto-char (point-min))
            (sp-batch-report-next)
            (let ((start (float-time)))
              (dotimes (_ 200) (sp-batch-report-drop))
              (message "sp-batch-report-view: 200 drops in %.4f s" (- (float-time) start))
              (should (< (- (float-time) start) 1.0)))
            (should (= 200 sp-batch-report-view--dropped))))
      (when (get-buffer sp-batch-report-view-test--name)
        (kill-buffer sp-batch-report-view-test--name)))))

(provide 'sp-batch-report-view-test)
;;; sp-batch-report-view-test.el ends here
