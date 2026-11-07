;;; sp-refile-test.el --- Tests for sp-refile -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(unless (require 'vulpea nil t) (provide 'vulpea))
(dolist (f '(sp-split-leave-parents sp-move-region-to-heading))
  (require f nil t))
(require 'sp-refile)

(defmacro sp-refile-test--with-file (var content &rest body)
  (declare (indent 2))
  `(let* ((,var (make-temp-file "sp-refile" nil ".org" ,content)))
     (unwind-protect (progn ,@body)
       (when-let* ((b (get-file-buffer ,var))) (with-current-buffer b (set-buffer-modified-p nil)) (kill-buffer b))
       (delete-file ,var))))

(ert-deftest sp-refile-test-note-as-subtree ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:ID: n1\n:END:\n#+title: My note\n#+filetags: :a:b:\n\nIntro.\n* Child\nText\n")
    (should (equal (sp-refile--note-as-subtree)
                   "* My note :a:b:\n:PROPERTIES:\n:ID:       n1\n:END:\nIntro.\n** Child\nText\n"))))

(ert-deftest sp-refile-test-move-within-file ()
  (sp-refile-test--with-file f "* A\n** A1\n* B\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (goto-char (point-min)) (search-forward "A1")
      (let ((target (save-excursion (goto-char (point-min)) (search-forward "* B")
                                    (copy-marker (line-beginning-position)))))
        (sp-refile--move-heading target (current-buffer)))
      (should (equal (buffer-string) "* A\n* B\n** A1\n")))))

(ert-deftest sp-refile-test-move-into-itself ()
  (sp-refile-test--with-file f "* A\n** A1\n"
    (with-current-buffer (find-file-noselect f)
      (org-mode)
      (goto-char (point-min))
      (let ((target (save-excursion (search-forward "A1") (copy-marker (line-beginning-position)))))
        (should-error (sp-refile--move-heading target (current-buffer)) :type 'user-error)))))

(ert-deftest sp-refile-test-move-to-other-file-top ()
  (sp-refile-test--with-file a "* A\n** A1\n* B\n"
    (sp-refile-test--with-file b "#+title: T\n* X\n"
      (with-current-buffer (find-file-noselect a)
        (org-mode)
        (goto-char (point-min)) (search-forward "A1")
        (sp-refile--move-heading nil (find-file-noselect b))
        (should (equal (buffer-string) "* A\n* B\n")))
      (with-current-buffer (find-file-noselect b)
        (org-mode)
        (should (equal (buffer-string) "#+title: T\n* X\n* A1\n"))))))

(ert-deftest sp-split-file-by-tags-moves-note-into-tag-folder ()
  "A split-out note with tags is moved to its tag folder; one without stays."
  (require 'use-package)
  (setq use-package-always-ensure nil
        use-package-ensure-function #'ignore)
  (require 'sp-notes)
  (let* ((root (make-temp-file "notes" t))
         (sp-notes-filing-root root)
         (sp-split-ask-tags nil)
         (file (expand-file-name "20260101120000_a_film.org" root))
         (stay (expand-file-name "20260101120001_plain.org" root))
         calls)
    (with-temp-file file (insert ":PROPERTIES:\n:ID: f1\n:END:\n#+title: A film\n#+filetags: :film:\n"))
    (with-temp-file stay (insert ":PROPERTIES:\n:ID: s1\n:END:\n#+title: Plain\n"))
    (unwind-protect
        (cl-letf (((symbol-function 'vulpea-note-path) (lambda (n) (plist-get n :path)))
                  ((symbol-function 'vulpea-note-id) (lambda (n) (plist-get n :id)))
                  ((symbol-function 'vulpea-note-tags) (lambda (n) (plist-get n :tags)))
                  ((symbol-function 'vulpea-note-title) (lambda (n) (plist-get n :title)))
                  ((symbol-function 'vulpea-db--forget-file) (lambda (f) (push (list 'forget f) calls)))
                  ((symbol-function 'vulpea-db-update-file) (lambda (f) (push (list 'update f) calls)))
                  ((symbol-function 'vulpea-db-get-by-id) (lambda (_) nil)))
          (let ((new (expand-file-name "objects/films/20260101120000_a_film.org" root)))
            (sp-split--file-by-tags (list :path file :id "f1" :tags '("film") :title "A film"))
            (should (file-exists-p new))
            (should-not (file-exists-p file))
            (should (member (list 'forget file) calls))
            (should (member (list 'update new) calls)))
          (setq calls nil)
          (sp-split--file-by-tags (list :path stay :id "s1" :tags nil :title "Plain"))
          (should (file-exists-p stay))
          (should-not calls))
      (delete-directory root t))))

(provide 'sp-refile-test)
;;; sp-refile-test.el ends here
