;;; sp-notes-test.el --- Tests for sp-notes (filing by tag) -*- lexical-binding: t; -*-

(require 'ert)
(require 'use-package)
(setq use-package-always-ensure nil)
(setq use-package-ensure-function #'ignore)
(require 'sp-notes)
(require 'sp-org-tag-lint)

(ert-deftest sp-notes-filing-folder-rules ()
  (should (equal (sp-notes-filing-folder '("litnote")) "litnotes"))
  (should (equal (sp-notes-filing-folder '("person")) "people"))
  (should (equal (sp-notes-filing-folder '("emacs")) "docs-emacs"))
  (should (equal (sp-notes-filing-folder '("docs")) "docs"))
  (dolist (tag '("process" "workflow" "system"))
    (should (equal (sp-notes-filing-folder (list tag)) "docs")))
  (should (equal (sp-notes-filing-folder '("film")) "objects/films"))
  (should (equal (sp-notes-filing-folder '("hardware")) "objects/hardware"))
  (should (equal (sp-notes-filing-folder '("concept")) "knowledge"))
  (should (equal (sp-notes-filing-folder '("zettel")) "knowledge"))
  (should (equal (sp-notes-filing-folder '("album")) "other"))
  (should (equal (sp-notes-filing-folder nil) "other")))

(ert-deftest sp-notes-filing-folder-precedence ()
  (should (equal (sp-notes-filing-folder '("emacs" "litnote")) "litnotes"))
  (should (equal (sp-notes-filing-folder '("emacs" "docs")) "docs-emacs"))
  (should (equal (sp-notes-filing-folder '("zettel" "docs")) "docs"))
  (should (equal (sp-notes-filing-folder '("zettel" "film")) "objects/films"))
  (should (equal (sp-notes-filing-folder '("PERSON" "zettel")) "people")))

(ert-deftest sp-notes-filing-clean-name-denote ()
  (should (equal (sp-notes-filing-clean-name "20240101T120000--my-title__a_b.org")
                 "20240101120000_my_title.org"))
  (should (equal (sp-notes-filing-clean-name "20240101T120000==1a--my-title__a.org")
                 "20240101120000_my_title.org"))
  (should (equal (sp-notes-filing-clean-name "20240101T120000__a.org") "20240101120000.org"))
  (should (equal (sp-notes-filing-clean-name "20240101120000_my_title.org")
                 "20240101120000_my_title.org"))
  (should (equal (sp-notes-filing-clean-name "plain.org") "plain.org")))

(defun sp-notes-filing-test--note (root rel tags &optional id identifier)
  "Write note REL under ROOT with TAGS."
  (let ((file (expand-file-name rel root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (when id (insert ":PROPERTIES:\n:ID: " id "\n:END:\n"))
      (insert "#+title: T\n")
      (when identifier (insert "#+identifier: " identifier "\n"))
      (when tags (insert "#+filetags: :" (string-join tags ":") ":\n"))
      (insert "\nBody\n"))
    file))

(defmacro sp-notes-filing-test--with-root (&rest body)
  (declare (indent 0))
  `(let* ((root (make-temp-file "notes" t))
          (sp-notes-filing-root root)
          (sp-notes-filing-backup-dir (make-temp-file "bak" t)))
     (unwind-protect (progn ,@body)
       (delete-directory root t)
       (delete-directory sp-notes-filing-backup-dir t))))

(ert-deftest sp-notes-filing-plan-and-apply ()
  (sp-notes-filing-test--with-root
    (sp-notes-filing-test--note root "a.org" '("person") "id-a")
    (sp-notes-filing-test--note root "20240101T120000--b-note__emacs.org" '("emacs") "id-b" "20240101T120000")
    (sp-notes-filing-test--note root "c.org" nil "id-c")
    (sp-notes-filing-test--note root "litnotes/d.org" '("litnote") "id-d")
    (sp-notes-filing-test--note root "inbox/e.org" nil)
    (sp-notes-filing-test--note root "inbox.org" nil)
    (let* ((plan (sp-notes-filing-plan))
           (tos (mapcar (lambda (e) (file-relative-name (plist-get e :to) root)) plan)))
      (should (equal (sort tos #'string<)
                     '("docs-emacs/20240101120000_b_note.org" "other/c.org" "people/a.org")))
      (let ((res (sp-notes-filing-apply plan)))
        (should (= (plist-get res :moved) 3))
        (should (null (plist-get res :failed)))
        (should (file-directory-p (plist-get res :backup))))
      (should (file-exists-p (expand-file-name "people/a.org" root)))
      (should (file-exists-p (expand-file-name "inbox/e.org" root)))
      (should-not (file-exists-p (expand-file-name "a.org" root)))
      ;; #+identifier: dropped, :ID: kept
      (with-temp-buffer
        (insert-file-contents (expand-file-name "docs-emacs/20240101120000_b_note.org" root))
        (should-not (string-match-p "#\\+identifier" (buffer-string)))
        (should (string-match-p ":ID: id-b" (buffer-string))))
      ;; idempotent
      (should (null (sp-notes-filing-plan))))))

(ert-deftest sp-notes-filing-collision-is-skipped ()
  (sp-notes-filing-test--with-root
    (sp-notes-filing-test--note root "a.org" '("person") "id-a")
    (sp-notes-filing-test--note root "people/a.org" '("person") "id-x")
    (let ((plan (sp-notes-filing-plan)))
      (should (= (length plan) 1))
      (should (plist-get (car plan) :skip))
      (should (= 0 (plist-get (sp-notes-filing-apply plan) :moved)))
      (should (file-exists-p (expand-file-name "a.org" root))))))

(ert-deftest sp-notes-filing-restore ()
  (sp-notes-filing-test--with-root
    (sp-notes-filing-test--note root "a.org" '("person") "id-a")
    (let ((res (sp-notes-filing-apply (sp-notes-filing-plan))))
      (sp-notes-filing-restore (plist-get res :backup))
      (should (file-exists-p (expand-file-name "a.org" root)))
      (should-not (file-exists-p (expand-file-name "people/a.org" root))))))

(ert-deftest sp-notes-filing-scheduled-leaves-untagged ()
  (sp-notes-filing-test--with-root
    (sp-notes-filing-test--note root "a.org" '("film") "id-a")
    (sp-notes-filing-test--note root "c.org" nil "id-c")
    (sp-notes-filing-run-scheduled)
    (should (file-exists-p (expand-file-name "objects/films/a.org" root)))
    (should (file-exists-p (expand-file-name "c.org" root)))))

(ert-deftest sp-notes-filing-auto-place-on-save ()
  (sp-notes-filing-test--with-root
    (let ((file (sp-notes-filing-test--note root "n.org" '("concept") "id-n")))
      (with-current-buffer (find-file-noselect file)
        (org-mode)
        (sp-notes-filing-auto-place)
        (should (equal buffer-file-name (expand-file-name "knowledge/n.org" root)))
        (set-buffer-modified-p nil)
        (kill-buffer))
      (should (file-exists-p (expand-file-name "knowledge/n.org" root))))))

(ert-deftest sp-notes-filing-unregistered-rule-tags ()
  (let ((org-tag-persistent-alist '("litnote" "person"))
        (org-tag-alist nil)
        (sp-notes-filing-rules '((("litnote") . "litnotes") (("person" "newtag") . "people"))))
    (should (equal (sp-notes-filing-unregistered-tags) '("newtag")))))

(ert-deftest sp-notes-filing-check-offers-to-register ()
  (let ((org-tag-persistent-alist '("litnote"))
        (org-tag-alist nil)
        (sp-notes-filing-rules '((("litnote") . "litnotes") (("newtag") . "x")))
        added asked)
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (p) (setq asked p) t))
              ((symbol-function 'sp-org-tag-add)
               (lambda (tag &rest _) (push tag added) (push tag org-tag-persistent-alist))))
      (should (null (sp-notes-filing-check-rule-tags)))
      (should (equal added '("newtag")))
      (should (string-match-p "newtag" asked)))))

(ert-deftest sp-notes-filing-check-declined-stays-unregistered ()
  (let ((org-tag-persistent-alist '("litnote"))
        (org-tag-alist nil)
        (sp-notes-filing-rules '((("newtag") . "x"))))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
      (should (equal (sp-notes-filing-check-rule-tags) '("newtag"))))))

;;;; Create and open

(unless (require 'vulpea nil t) (provide 'vulpea)) ; only the require is needed
(defvar vulpea-default-notes-directory)
(require 'sp-org-link-conversion)

(ert-deftest sp-notes-created-stamp-format ()
  (should (string-match-p "\\`\\[[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}\\]\\'"
                          (sp-org-created-stamp)))
  (should (equal (sp-org-created-stamp (encode-time 0 5 9 7 11 2026)) "[2026-11-07 09:05]")))

(ert-deftest sp-notes-create-uses-vulpea-create ()
  "vulpea-create gets the tag folder in its template, the tags and :CREATED:."
  (let* ((root (make-temp-file "notes" t))
         (sp-notes-filing-root root)
         (vulpea-default-notes-directory root)
         (tags '("film")) args)
    (unwind-protect
        (cl-letf (((symbol-function 'sp-org-tag-read-note-tags) (lambda (&rest _) tags))
                  ((symbol-function 'vulpea-create)
                   (lambda (title template &rest keys)
                     (setq args (list title template keys))
                     ;; Like vulpea without :properties support: no :CREATED:.
                     (let ((f (expand-file-name (format "objects/films/%s.org" (md5 (format "%S" (list title template)))) root)))
                       (make-directory (file-name-directory f) t)
                       (with-temp-file f (insert ":PROPERTIES:\n:ID: i\n:END:\n#+title: A New Film\n"))
                       f)))
                  ((symbol-function 'vulpea-note-path) #'identity)
                  ((symbol-function 'find-file) (lambda (f) (set-buffer (find-file-noselect f)))))
          (let ((file (sp-notes-create "A New Film")))
            (should (equal (nth 0 args) "A New Film"))
            (should (equal (nth 1 args) "objects/films/${timestamp}_${slug}.org"))
            (should (equal (plist-get (nth 2 args) :tags) '("film")))
            (should (assoc "CREATED" (plist-get (nth 2 args) :properties)))
            ;; the fallback added :CREATED: to the drawer
            (with-temp-buffer
              (insert-file-contents file)
              (should (re-search-forward "^:CREATED: +\\[[0-9-]+ [0-9:]+\\]$" nil t))))
          (setq tags nil)
          (sp-notes-create "No Tags")
          (should (equal (nth 1 args) "${timestamp}_${slug}.org")))
      (mapc #'kill-buffer (seq-filter (lambda (b) (and (buffer-file-name b) (string-prefix-p root (buffer-file-name b)))) (buffer-list)))
      (delete-directory root t))))

(ert-deftest sp-notes-create-nil-vulpea-default-directory ()
  "A nil `vulpea-default-notes-directory' (vulpea's default) must not reach vulpea."
  (let* ((root (make-temp-file "notes" t))
         (sp-notes-filing-root root)
         (vulpea-default-notes-directory nil)
         seen)
    (unwind-protect
        (progn
          (should (equal (sp-notes-create-base) (file-name-as-directory root)))
          (should (equal (sp-notes-create-file-template '("film"))
                         "objects/films/${timestamp}_${slug}.org"))
          (should (equal (sp-notes-create-file-template nil) "${timestamp}_${slug}.org"))
          (cl-letf (((symbol-function 'sp-org-tag-read-note-tags) (lambda (&rest _) nil))
                    ((symbol-function 'vulpea-create)
                     (lambda (&rest _)
                       ;; vulpea calls `file-name-as-directory' on this.
                       (setq seen (file-name-as-directory vulpea-default-notes-directory))
                       (let ((f (expand-file-name "n.org" root)))
                         (with-temp-file f (insert ":PROPERTIES:\n:ID: i\n:END:\n#+title: N\n"))
                         f)))
                    ((symbol-function 'vulpea-note-path) #'identity)
                    ((symbol-function 'find-file) (lambda (f) (set-buffer (find-file-noselect f)))))
            (sp-notes-create "N"))
          (should (equal seen (file-name-as-directory root))))
      (mapc #'kill-buffer (seq-filter (lambda (b) (and (buffer-file-name b) (string-prefix-p root (buffer-file-name b)))) (buffer-list)))
      (delete-directory root t))))

(ert-deftest sp-notes-vulpea-create-advice-adds-created ()
  "Any note made by vulpea-create (find, inbox tab) gets :CREATED:, also in a visiting buffer."
  (let* ((root (make-temp-file "notes" t))
         (f1 (expand-file-name "a.org" root))
         (f2 (expand-file-name "b.org" root))
         (f3 (expand-file-name "c.org" root))
         (body ":PROPERTIES:\n:ID: i\n:END:\n#+title: T\n")
         (with-created ":PROPERTIES:\n:ID: i\n:CREATED:  [2020-01-01 10:00]\n:END:\n#+title: T\n"))
    (unwind-protect
        (cl-letf (((symbol-function 'vulpea-note-path) #'identity)
                  ((symbol-function 'vulpea-create)
                   (lambda (file &rest _) file)))
          (advice-add 'vulpea-create :filter-return #'sp-notes-created-after-vulpea-create)
          (unwind-protect
              (progn
                (with-temp-file f1 (insert body))
                (with-temp-file f3 (insert with-created))
                (with-temp-file f2 (insert body))
                (vulpea-create f1)
                (vulpea-create f3)
                (with-temp-buffer (insert-file-contents f1)
                                  (should (re-search-forward "^:CREATED: +\\[[0-9-]+ [0-9:]+\\]$" nil t)))
                ;; an existing :CREATED: is kept
                (with-temp-buffer (insert-file-contents f3)
                                  (should (search-forward "[2020-01-01 10:00]" nil t)))
                ;; visited file: the buffer gets it, the file is not touched
                (let ((buf (find-file-noselect f2)))
                  (vulpea-create f2)
                  (with-current-buffer buf
                    (goto-char (point-min))
                    (should (re-search-forward "^:CREATED:" nil t))
                    (set-buffer-modified-p nil))
                  (kill-buffer buf))
                (should (null (vulpea-create nil))))
            (advice-remove 'vulpea-create #'sp-notes-created-after-vulpea-create)))
      (delete-directory root t))))

(ert-deftest sp-notes-open-info-and-candidates ()
  (let* ((root (make-temp-file "notes" t))
         (sp-notes-filing-root root))
    (unwind-protect
        (progn
          (clrhash sp-notes-open--cache)
          (make-directory (expand-file-name "people" root))
          (make-directory (expand-file-name ".git" root))
          (with-temp-file (expand-file-name "people/ann.org" root)
            (insert ":PROPERTIES:\n:ID: a\n:CREATED:  [2026-11-07 Sat 19:02]\n:END:\n#+title: Ann\n#+filetags: :person:x:\n\n* H\n:CREATED: [1999-01-01]\n"))
          (with-temp-file (expand-file-name "20240101120000_old.org" root)
            (insert "#+title: Old\n"))
          (with-temp-file (expand-file-name ".git/skip.org" root) (insert "x"))
          (let ((items (sp-notes-open--candidates)))
            (should (equal (mapcar #'car items) '("people/ann.org" "20240101120000_old.org")))
            (should (equal (plist-get (cdr (car items)) :created) "2026-11-07 19:02"))
            (should (equal (plist-get (cdr (car items)) :tags) '("person" "x")))
            (should (equal (plist-get (cdr (cadr items)) :created) "2024-01-01 12:00"))
            (should (string-match-p "2026-11-07 19:02  :person:x:  Ann"
                                    (sp-notes-open--annotate (cdr (car items)))))))
      (delete-directory root t))))

(ert-deftest sp-notes-open-denote-name-date ()
  (should (equal (sp-notes-open--name-date "20240101T120000--t__a.org") "2024-01-01 12:00"))
  (should (equal (sp-notes-open--name-date "20260507T101500-my-note.org") "2026-05-07 10:15"))
  (should (null (sp-notes-open--name-date "plain.org"))))

(provide 'sp-notes-test)
;;; sp-notes-test.el ends here

(ert-deftest sp-notes-filing-report-links-files ()
  "The dry-run report is a report buffer: every file to move is a link."
  (let* ((root (file-name-as-directory (make-temp-file "sp-filing" t)))
         (sp-notes-filing-root root)
         (from (expand-file-name "a.org" root)))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'sp-notes-filing-check-rule-tags) #'ignore)
                    ((symbol-function 'sp-notes-filing-plan)
                     (lambda (&rest _)
                       (list (list :from from :to (expand-file-name "docs/a.org" root)
                                   :folder "docs")))))
            (save-window-excursion (sp-notes-filing-dryrun)))
          (with-current-buffer "*Notes filing*"
            (should (derived-mode-p 'sp-batch-report-mode))
            (should (eq major-mode 'sp-notes-filing-report-mode))
            (should sp-notes-filing--current-plan)
            (should (eq (lookup-key (current-local-map) (kbd "C-c C-c"))
                        #'sp-notes-filing-convert))
            (should (string-match-p
                     (format "\\[\\[file:%s\\]\\[a\\.org\\]\\] -> docs/a\\.org"
                             (regexp-quote from))
                     (buffer-string)))))
      (when (get-buffer "*Notes filing*") (kill-buffer "*Notes filing*"))
      (delete-directory root t))))
