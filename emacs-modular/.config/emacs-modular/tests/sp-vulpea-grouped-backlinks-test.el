;;; sp-vulpea-grouped-backlinks-test.el --- Tests for sp-vulpea-grouped-backlinks  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'org)

;; The real Vulpea and the table module are not needed: only the functions
;; the module calls are stubbed, with notes as plists.
(when noninteractive
  (provide 'vulpea)
  (provide 'sp-collection-query-core)
  (defvar sp-vulpea-grouped-backlinks-test--links nil
    "Alist of (TARGET-ID . LINK-PLISTS) the stubbed database answers with.")
  (defvar sp-vulpea-grouped-backlinks-test--notes nil
    "Alist of (ID . NOTE-PLIST) the stubbed database answers with.")
  (defun vulpea-db-query-links-to (id)
    (cdr (assoc id sp-vulpea-grouped-backlinks-test--links)))
  (defun vulpea-db-get-by-id (id)
    (cdr (assoc id sp-vulpea-grouped-backlinks-test--notes)))
  (defun vulpea-note-id (note) (plist-get note :id))
  (defun vulpea-note-title (note) (plist-get note :title))
  (defun vulpea-note-path (note) (plist-get note :path))
  (defun sp-collec-query-select-note (_prompt) nil))

(load (expand-file-name
       "../libraries/modules/vulpea/sp-vulpea-grouped-backlinks.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro sp-vulpea-grouped-backlinks-test--with-vault (&rest body)
  "Run BODY with two source notes linking to note \"target\".
Note \"a\" has a plain mention and note \"b\" lists the target under
`pub-author'.  The files are real, in a temporary directory."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sp-gb-" t))
          (file-a (expand-file-name "a.org" dir))
          (file-b (expand-file-name "b.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file file-a
             (insert "* A\nSome prose with [[id:target][T]] inside.\n"))
           (with-temp-file file-b
             (insert "* B\n- pub-author :: [[id:target][T]]\n"))
           (let ((sp-vulpea-grouped-backlinks-test--notes
                  `(("a" . (:id "a" :title "Note A" :path ,file-a))
                    ("b" . (:id "b" :title "Note B" :path ,file-b))
                    ("target" . (:id "target" :title "Target" :path ,file-a))))
                 (sp-vulpea-grouped-backlinks-test--links
                  `(("target" . ((:source "a" :pos 20)
                                 (:source "a" :pos 20)
                                 (:source "b" :pos 12))))))
             ,@body))
       (mapc #'kill-buffer (delq nil (mapcar #'find-buffer-visiting
                                             (list file-a file-b))))
       (delete-directory dir t))))

(ert-deftest sp-vulpea-grouped-backlinks-test-meta-key-found-on-meta-line ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (should (equal (sp-vulpea-grouped-backlinks--meta-key-at file-b 12)
                   "pub-author"))))

(ert-deftest sp-vulpea-grouped-backlinks-test-no-meta-key-in-prose ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (should-not (sp-vulpea-grouped-backlinks--meta-key-at file-a 20))))

(ert-deftest sp-vulpea-grouped-backlinks-test-classify-groups-and-dedups ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (let ((groups (sp-vulpea-grouped-backlinks-classify "target")))
      (should (equal (sort (mapcar #'car groups) #'string<)
                     '("Mentions" "pub-author")))
      (should (equal (mapcar #'vulpea-note-id (cdr (assoc "Mentions" groups)))
                     '("a")))
      (should (equal (mapcar #'vulpea-note-id (cdr (assoc "pub-author" groups)))
                     '("b"))))))

(ert-deftest sp-vulpea-grouped-backlinks-test-org-detached-fills-an-org-buffer ()
  (sp-vulpea-grouped-backlinks-test--with-vault
    (cl-letf (((symbol-function 'display-buffer) #'ignore))
      (sp-vulpea-grouped-backlinks-org-detached
       (cdr (assoc "target" sp-vulpea-grouped-backlinks-test--notes))))
    (with-current-buffer "*vulpea backlinks: Target*"
      (should (derived-mode-p 'org-mode))
      (let ((text (buffer-string)))
        (should (string-match-p "^\\* Backlinks to Target$" text))
        (should (string-match-p "^\\*\\* Mentions (1)$" text))
        (should (string-match-p "^\\*\\* pub-author (1)$" text))
        (should (string-match-p "\\[\\[id:a\\]\\[Note A\\]\\]" text))
        (should (< (string-match "Mentions" text)
                   (string-match "pub-author" text))))
      (kill-buffer))))

(ert-deftest sp-vulpea-grouped-backlinks-test-old-names-are-gone ()
  (dolist (old '(sia-vulpea-show-grouped-backlinks
                 sia-vulpea-classify-backlinks
                 sia-vulpea--line-meta-key-at))
    (should-not (fboundp old))))

(provide 'sp-vulpea-grouped-backlinks-test)
;;; sp-vulpea-grouped-backlinks-test.el ends here
