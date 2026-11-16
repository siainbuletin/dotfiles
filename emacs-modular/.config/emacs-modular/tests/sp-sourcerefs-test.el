;;; sp-sourcerefs-test.el --- Tests for sp-sourcerefs -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

;; sp-cite-open needs DEVONthink modules; stub it, load the real matcher.
(defvar sp-bibtex-files nil)
(let ((dir (expand-file-name "../libraries/modules/academic/"
                             (file-name-directory (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path dir)
  (unless (featurep 'sp-cite-open)
    (defun sp-cite-open--front () nil)
    (defun sp-cite-open--plain-text (_uuid) nil)
    (defun sp-cite-open-references (_text) nil)
    (defun sp-cite-open-entry (_text _refs) nil)
    (provide 'sp-cite-open))
  (require 'sp-sourcerefs))

(defmacro sp-sourcerefs-test--with-buffer (text &rest body)
  (declare (indent 1))
  `(with-temp-buffer (insert ,text) ,@body))

(ert-deftest sp-sourcerefs-test-collect-lines ()
  (sp-sourcerefs-test--with-buffer
      "* Notes\nSOURCEREFS Smith 2017\n- SOURCEREFS: (Jones 2019, 12)\n  - SOURCEREFS Marx. Das Kapital.\nplain SOURCEREFS in text\nSOURCEREFSX no\nsourcerefs lower\n"
    (let ((refs (sp-sourcerefs-collect)))
      (should (equal (mapcar (lambda (r) (plist-get r :text)) refs)
                     '("Smith 2017" "(Jones 2019, 12)" "Marx. Das Kapital.")))
      (should (equal (mapcar (lambda (r) (plist-get r :bullet)) refs)
                     '("" "- " "  - "))))))

(ert-deftest sp-sourcerefs-test-collect-region ()
  (sp-sourcerefs-test--with-buffer "SOURCEREFS a b\nSOURCEREFS c d\n"
    (should (equal (mapcar (lambda (r) (plist-get r :text))
                           (sp-sourcerefs-collect 1 15))
                   '("a b")))))

(ert-deftest sp-sourcerefs-test-replace-keeps-bullet ()
  (sp-sourcerefs-test--with-buffer "x\n- SOURCEREFS Smith 2017\ny\n"
    (let ((ref (car (sp-sourcerefs-collect))))
      (sp-sourcerefs--replace ref "smith2017title")
      (should (equal (buffer-string) "x\n- [cite:@smith2017title]\ny\n")))))

(ert-deftest sp-sourcerefs-test-citekey ()
  (sp-sourcerefs-test--with-buffer "#+title: T\n#+reference: @smith2017title\n"
    (should (equal (sp-sourcerefs-citekey) "smith2017title")))
  (sp-sourcerefs-test--with-buffer ":PROPERTIES:\n:ROAM_REFS: @jones2019x\n:END:\n"
    (should (equal (sp-sourcerefs-citekey) "jones2019x")))
  (sp-sourcerefs-test--with-buffer "no key\n"
    (should-not (sp-sourcerefs-citekey))))

(ert-deftest sp-sourcerefs-test-convert-end-to-end ()
  (sp-sourcerefs-test--with-buffer "#+title: T\n- SOURCEREFS Smith 2017 Attention\n- SOURCEREFS Nobody 1900 Unknown\n"
    (org-mode)
    (let ((cand (list :key "smith2017attention" :label "Smith 2017" :id "smith2017attention"))
          written)
      (cl-letf (((symbol-function 'sp-cite-match-candidates) (lambda () nil))
                ((symbol-function 'sp-sourcerefs--report) #'ignore)
                ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'sp-cite-match-text)
                 (lambda (text &optional _c)
                   (if (string-match-p "Smith" text)
                       (cons 'accept (list (cons 0.9 cand)))
                     (cons 'none nil))))
                ((symbol-function 'sp-cite-match-write-section)
                 (lambda (items &optional _c) (setq written items)))
                (sp-sourcerefs-reference-text-function #'ignore))
        (should (= (sp-sourcerefs-convert) 1))
        (should (equal (buffer-string)
                       "#+title: T\n- [cite:@smith2017attention]\n- SOURCEREFS Nobody 1900 Unknown\n"))
        (should (equal written (list cand "Nobody 1900 Unknown")))))))


(defun sp-sourcerefs-test--convert (text &optional region)
  "Convert the lines of TEXT with the matcher stubbed to accept Smith; return the buffer.
REGION is nil (no region), or (BEG . END) as 1-based positions."
  (with-temp-buffer
    (insert text)
    (org-mode)
    (cl-letf (((symbol-function 'sp-cite-match-candidates) (lambda () nil))
              ((symbol-function 'sp-sourcerefs--report) #'ignore)
              ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
              ((symbol-function 'sp-cite-match-text)
               (lambda (text &optional _c)
                 (if (string-match-p "Smith" text)
                     (cons 'accept (list (cons 0.9 (list :key "smith" :id "smith"))))
                   (cons 'none nil))))
              ((symbol-function 'sp-cite-match-write-section) #'ignore)
              (sp-sourcerefs-reference-text-function #'ignore))
      (if region
          (progn (set-mark (car region)) (goto-char (cdr region)) (activate-mark)
                 (sp-sourcerefs-convert (region-beginning) (region-end)))
        (sp-sourcerefs-convert)))
    (buffer-string)))

(ert-deftest sp-sourcerefs-test-convert-without-region ()
  (should (equal (sp-sourcerefs-test--convert "- SOURCEREFS Smith 2017\n- SOURCEREFS Other\n")
                 "- [cite:@smith]\n- SOURCEREFS Other\n")))

(ert-deftest sp-sourcerefs-test-convert-last-line-without-newline ()
  (should (equal (sp-sourcerefs-test--convert "- SOURCEREFS Smith 2017")
                 "- [cite:@smith]")))

(ert-deftest sp-sourcerefs-test-convert-point-at-end-of-buffer ()
  (with-temp-buffer
    (insert "text\n- SOURCEREFS Smith 2017\n")
    (should (= (point) (point-max)))
    (should (= (length (sp-sourcerefs-collect)) 1))
    (should (= (length (sp-sourcerefs-collect (point) (point))) 0))))

(ert-deftest sp-sourcerefs-test-convert-region-boundaries ()
  (let ((text "- SOURCEREFS Smith 1\n- SOURCEREFS Smith 2\n- SOURCEREFS Smith 3\n"))
    ;; Region over the second line only (its start to the start of the third).
    (should (equal (sp-sourcerefs-test--convert text (cons 22 43))
                   "- SOURCEREFS Smith 1\n- [cite:@smith]\n- SOURCEREFS Smith 3\n"))
    ;; Region that ends inside the first line: the cut line holds no reference.
    (should-error (sp-sourcerefs-test--convert text (cons 1 12)) :type 'user-error)
    ;; Whole buffer through the region path.
    (should (equal (sp-sourcerefs-test--convert text (cons 1 (1+ (length text))))
                   "- [cite:@smith]\n- [cite:@smith]\n- [cite:@smith]\n"))))

(ert-deftest sp-sourcerefs-test-convert-no-lines-is-a-user-error ()
  (with-temp-buffer
    (insert "nothing here\n")
    (should-error (sp-sourcerefs-convert) :type 'user-error)))

(provide 'sp-sourcerefs-test)
;;; sp-sourcerefs-test.el ends here
