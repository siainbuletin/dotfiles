;;; sp-vulpea-backlink-check-test.el --- Tests for sp-vulpea-backlink-check  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(defvar sp-vulpea-backlink-check-test--links nil
  "Alist of (TARGET-ID . LINK-PLISTS) the stubbed database answers with.")
(defvar sp-vulpea-backlink-check-test--notes nil
  "Alist of (ID . NOTE-PLIST) the stubbed database answers with.")

(when noninteractive
  (defun vulpea-db-query-links-to (id)
    (cdr (assoc id sp-vulpea-backlink-check-test--links)))
  (defun vulpea-db-get-by-id (id)
    (cdr (assoc id sp-vulpea-backlink-check-test--notes)))
  (defun vulpea-note-id (note) (plist-get note :id))
  (defun vulpea-note-title (note) (plist-get note :title))
  (defun vulpea-note-path (note) (plist-get note :path)))

(load (expand-file-name
       "../libraries/modules/vulpea/sp-vulpea-backlink-check.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro sp-vulpea-backlink-check-test--with-vault (&rest body)
  "Run BODY with notes a and b linking to the heading \"target\".
Note a links once, from under a heading; b links twice.  The files are
real, in a temporary directory, and the database stub knows them."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sp-bc-" t))
          (file-a (expand-file-name "a.org" dir))
          (file-b (expand-file-name "b.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file file-a
             (insert "* A\n** Part\nSee [[id:target][T]] here.\n"))
           (with-temp-file file-b
             (insert "* B\n- pub-author :: [[id:target][T]]\nand [[id:target][T]] again\n"))
           (let ((sp-vulpea-backlink-check-test--notes
                  `(("a" . (:id "a" :title "Note A" :path ,file-a))
                    ("b" . (:id "b" :title "Note B" :path ,file-b))
                    ("target" . (:id "target" :title "The target" :path ,file-a))))
                 (sp-vulpea-backlink-check-test--links
                  `(("target"
                     (:source "b" :pos ,(+ 1 (length "* B\n- pub-author :: ")))
                     (:source "a" :pos ,(+ 1 (length "* A\n** Part\nSee ")))
                     (:source "b" :pos ,(+ 1 (length "* B\n- pub-author :: [[id:target][T]]\nand ")))
                     (:source "target" :pos 1))))
                 (sp-vulpea-backlink-check--last nil))
             ,@body))
       (delete-directory dir t))))

(ert-deftest sp-vulpea-backlink-check-test-counts-links-and-notes ()
  (sp-vulpea-backlink-check-test--with-vault
    (should (equal (sp-vulpea-backlink-check--format
                    "target" (sp-vulpea-backlink-check--links "target"))
                   "3 backlinks from 2 notes"))))

(ert-deftest sp-vulpea-backlink-check-test-singular ()
  (should (equal (sp-vulpea-backlink-check--format "x" '((:source "a")))
                 "1 backlink from 1 note")))

(ert-deftest sp-vulpea-backlink-check-test-not-backlinked ()
  (sp-vulpea-backlink-check-test--with-vault
    (should (equal (sp-vulpea-backlink-check--format
                    "other" (sp-vulpea-backlink-check--links "other"))
                   "not backlinked"))))

(ert-deftest sp-vulpea-backlink-check-test-result-carries-the-id ()
  (let ((s (sp-vulpea-backlink-check--format "xyz" nil)))
    (should (equal (get-text-property 0 'sp-vulpea-backlink-check s) "xyz"))))

(ert-deftest sp-vulpea-backlink-check-test-self-links-are-ignored ()
  (sp-vulpea-backlink-check-test--with-vault
    (should-not (seq-find (lambda (l) (equal (plist-get l :source) "target"))
                          (sp-vulpea-backlink-check--links "target")))))

(ert-deftest sp-vulpea-backlink-check-test-command-uses-the-heading-id ()
  (sp-vulpea-backlink-check-test--with-vault
    (with-temp-buffer
      (insert "* Heading\n:PROPERTIES:\n:ID: target\n:END:\nbody\n")
      (org-mode)
      (goto-char (point-max))
      (let ((result (sp-vulpea-backlink-check)))
        (should (equal (substring-no-properties result)
                       "3 backlinks from 2 notes"))
        (should (equal (car sp-vulpea-backlink-check--last) "target"))))))

(ert-deftest sp-vulpea-backlink-check-test-command-needs-an-id ()
  (with-temp-buffer
    (insert "* No id here\n")
    (org-mode)
    (should-error (sp-vulpea-backlink-check) :type 'user-error)))

(ert-deftest sp-vulpea-backlink-check-test-command-needs-org ()
  (with-temp-buffer
    (fundamental-mode)
    (should-error (sp-vulpea-backlink-check) :type 'user-error)))

(ert-deftest sp-vulpea-backlink-check-test-target-on-a-result-line ()
  (with-temp-buffer
    (insert (sp-vulpea-backlink-check--format "xyz" nil) "\n")
    (goto-char (point-min))
    (should (equal (sp-vulpea-backlink-check-target)
                   '(sp-vulpea-backlinks . "xyz")))))

(ert-deftest sp-vulpea-backlink-check-test-target-just-after-a-check ()
  (let ((sp-vulpea-backlink-check--last (cons "abc" (float-time))))
    (with-temp-buffer
      (should (equal (sp-vulpea-backlink-check-target)
                     '(sp-vulpea-backlinks . "abc"))))))

(ert-deftest sp-vulpea-backlink-check-test-target-expires ()
  (let ((sp-vulpea-backlink-check--last
         (cons "abc" (- (float-time) sp-vulpea-backlink-check-timeout 1))))
    (with-temp-buffer
      (should-not (sp-vulpea-backlink-check-target)))))

(ert-deftest sp-vulpea-backlink-check-test-no-target-by-default ()
  (let ((sp-vulpea-backlink-check--last nil))
    (with-temp-buffer
      (should-not (sp-vulpea-backlink-check-target)))))

(ert-deftest sp-vulpea-backlink-check-test-restore-a-copied-result ()
  (sp-vulpea-backlink-check-test--with-vault
    (let ((sp-vulpea-backlink-check--history nil))
      (with-temp-buffer
        (insert "* H\n:PROPERTIES:\n:ID: target\n:END:\n")
        (org-mode)
        (sp-vulpea-backlink-check))
      (setq sp-vulpea-backlink-check--last nil)
      (let ((s (sp-vulpea-backlink-check-restore
                "Copied: 3 backlinks from 2 notes")))
        (should (equal s "3 backlinks from 2 notes"))
        (should (equal (get-text-property 0 'sp-vulpea-backlink-check s)
                       "target"))
        (should (equal (car sp-vulpea-backlink-check--last) "target"))))))

(ert-deftest sp-vulpea-backlink-check-test-restore-ignores-other-text ()
  (let ((sp-vulpea-backlink-check--history '(("3 backlinks from 2 notes" . "t"))))
    (should-not (sp-vulpea-backlink-check-restore "hello"))))

;; sp-helper-funct needs the whole config to load: evaluate only the hook
;; variable and the command from it.
(defconst sp-vulpea-backlink-check-test--helper-file
  (expand-file-name
   "../libraries/modules/funct/sp-helper-funct.el"
   (file-name-directory (or load-file-name buffer-file-name)))
  "The file that holds `sp-copy-last-message'.")

(defun sp-vulpea-backlink-check-test--load-copy-last-message ()
  (with-temp-buffer
    (insert-file-contents sp-vulpea-backlink-check-test--helper-file)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (let ((form (read (current-buffer))))
            (when (and (memq (car-safe form) '(defvar defun))
                       (string-prefix-p "sp-copy-last-message"
                                        (symbol-name (cadr form))))
              (eval form t))))
      (end-of-file nil))))

(ert-deftest sp-vulpea-backlink-check-test-copy-last-message-uses-the-hook ()
  (sp-vulpea-backlink-check-test--load-copy-last-message)
  (let ((sp-copy-last-message-functions
         (list (lambda (text) (propertize text 'sp-vulpea-backlink-check "id"))))
        shown)
    (with-current-buffer (get-buffer-create "*Messages*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "old\n3 backlinks from 2 notes\n")))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (setq shown (apply #'format fmt args)))))
      (sp-copy-last-message))
    (should (equal shown "Copied: 3 backlinks from 2 notes"))
    (should (equal (car kill-ring) "3 backlinks from 2 notes"))))

(ert-deftest sp-vulpea-backlink-check-test-locations-have-heading-and-context ()
  (sp-vulpea-backlink-check-test--with-vault
    (let* ((groups (sp-vulpea-backlink-check--locations "target"))
           (a (assoc-default "Note A" groups
                             (lambda (note title)
                               (equal (plist-get note :title) title))))
           (b (assoc-default "Note B" groups
                             (lambda (note title)
                               (equal (plist-get note :title) title)))))
      (should (= (length groups) 2))
      (should (= (length a) 1))
      (should (equal (plist-get (car a) :heading) "Part"))
      (should (= (plist-get (car a) :line) 3))
      (should (equal (plist-get (car a) :context) "See [[id:target][T]] here."))
      (should (= (length b) 2))
      (should (equal (plist-get (car b) :heading) "B"))
      (should (< (plist-get (car b) :pos) (plist-get (cadr b) :pos))))))

(ert-deftest sp-vulpea-backlink-check-test-buffer-lists-the-locations ()
  (sp-vulpea-backlink-check-test--with-vault
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-vulpea-backlink-check-show "target")
      (with-current-buffer "*vulpea backlinks: The target*"
        (should (derived-mode-p 'sp-vulpea-backlink-check-mode))
        (let ((text (buffer-string)))
          (should (string-match-p "Backlinks to The target" text))
          (should (string-match-p "Note A" text))
          (should (string-match-p "Note B" text))
          (should (string-match-p "Part (line 3)" text))
          (should (string-match-p "See \\[\\[id:target\\]\\[T\\]\\] here\\." text)))
        (should (get-text-property (point) 'sp-vulpea-backlink-check-loc))
        (kill-buffer)))))

(ert-deftest sp-vulpea-backlink-check-test-buffer-next-and-previous ()
  (sp-vulpea-backlink-check-test--with-vault
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-vulpea-backlink-check-show "target")
      (with-current-buffer "*vulpea backlinks: The target*"
        (let ((first (get-text-property (point) 'sp-vulpea-backlink-check-loc)))
          (sp-vulpea-backlink-check-next-entry)
          (should-not (eq first (get-text-property
                                 (point) 'sp-vulpea-backlink-check-loc)))
          (sp-vulpea-backlink-check-previous-entry)
          (should (eq first (get-text-property
                             (point) 'sp-vulpea-backlink-check-loc))))
        (kill-buffer)))))

(ert-deftest sp-vulpea-backlink-check-test-visit-jumps-to-the-link ()
  (sp-vulpea-backlink-check-test--with-vault
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-vulpea-backlink-check-show "target")
      (with-current-buffer "*vulpea backlinks: The target*"
        (let ((loc (get-text-property (point) 'sp-vulpea-backlink-check-loc))
              visited)
          (cl-letf (((symbol-function 'find-file-other-window)
                     (lambda (f) (setq visited f)
                       (set-buffer (find-file-noselect f)))))
            (sp-vulpea-backlink-check-visit)
            (should (equal visited (plist-get loc :path)))
            (should (= (point) (plist-get loc :pos)))
            (kill-buffer)))
        (kill-buffer "*vulpea backlinks: The target*")))))

(ert-deftest sp-vulpea-backlink-check-test-empty-buffer ()
  (sp-vulpea-backlink-check-test--with-vault
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (sp-vulpea-backlink-check-show "other")
      (with-current-buffer "*vulpea backlinks: other*"
        (should (string-match-p "Not backlinked" (buffer-string)))
        (kill-buffer)))))

(ert-deftest sp-vulpea-backlink-check-test-open-buffer-wins-over-the-file ()
  (sp-vulpea-backlink-check-test--with-vault
    (let* ((path (plist-get (cdr (assoc "a" sp-vulpea-backlink-check-test--notes))
                            :path))
           (buf (find-file-noselect path)))
      (unwind-protect
          (progn
            (with-current-buffer buf
              (goto-char (point-min))
              (insert "Unsaved line\n"))
            (let ((loc (sp-vulpea-backlink-check--location
                        (list :source "a" :pos (+ 1 (length "* A\n** Part\nSee ") 13)))))
              (should (equal (plist-get loc :heading) "Part"))
              (should (= (plist-get loc :line) 4))))
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))))
