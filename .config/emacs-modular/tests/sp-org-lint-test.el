;;; sp-org-lint-test.el --- Tests for the footnote linter in sp-org-lint -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-org-lint)

(defun sp-org-lint-test--text (&rest lines)
  "LINES joined, with a final newline."
  (concat (string-join lines "\n") "\n"))

(defun sp-org-lint-test--result (&rest lines)
  "The plan for LINES."
  (sp-org-lint-fn-plan-text (apply #'sp-org-lint-test--text lines)))

(ert-deftest sp-org-lint-footnote-moves-to-the-citing-heading ()
  (let ((plan (sp-org-lint-test--result
               "#+title: T" "" "* Alpha" "Claim.[fn:a]" ""
               "* Beta" "Other.[fn:b]" ""
               "* Footnotes" "[fn:a] Source A." "" "[fn:b] Source B.")))
    (should (equal (plist-get plan :text)
                   (sp-org-lint-test--text
                    "#+title: T" "" "* Alpha" "Claim.[fn:a]" ""
                    "[fn:a] Source A." ""
                    "* Beta" "Other.[fn:b]" ""
                    "[fn:b] Source B.")))
    (should (equal (mapcar (lambda (m) (plist-get m :to)) (plist-get plan :moves))
                   '("Alpha" "Beta")))
    (should (equal (plist-get plan :removed) '("Footnotes")))))

(ert-deftest sp-org-lint-footnote-cited-twice-gets-a-copy ()
  (let ((plan (sp-org-lint-test--result
               "* Alpha" "One.[fn:s]" "" "* Beta" "Two.[fn:s]" ""
               "* Footnotes" "[fn:s] Source.")))
    (should (equal (plist-get plan :text)
                   (sp-org-lint-test--text
                    "* Alpha" "One.[fn:s]" "" "[fn:s] Source." ""
                    "* Beta" "Two.[fn:s-2]" "" "[fn:s-2] Source.")))))

(ert-deftest sp-org-lint-footnote-in-a-subsection-goes-to-its-own-text ()
  (let ((plan (sp-org-lint-test--result
               "* Parent" "Intro." "** Child" "Claim.[fn:c]" ""
               "** Later" "More." ""
               "* Footnotes" "[fn:c] Source.")))
    (should (equal (plist-get plan :text)
                   (sp-org-lint-test--text
                    "* Parent" "Intro." "** Child" "Claim.[fn:c]" ""
                    "[fn:c] Source." ""
                    "** Later" "More.")))))

(ert-deftest sp-org-lint-footnote-before-first-heading ()
  (let ((plan (sp-org-lint-test--result
               "#+title: T" "" "Intro.[fn:i]" "" "* Alpha" "Text." ""
               "* Footnotes" "[fn:i] Source.")))
    (should (equal (plist-get plan :text)
                   (sp-org-lint-test--text
                    "#+title: T" "" "Intro.[fn:i]" "" "[fn:i] Source." ""
                    "* Alpha" "Text.")))))

(ert-deftest sp-org-lint-footnote-orphans-and-dangling-are-reported-not-deleted ()
  (let ((plan (sp-org-lint-test--result
               "* Alpha" "Claim.[fn:a] Ghost.[fn:ghost]" ""
               "* Footnotes" "[fn:a] Source A." "" "[fn:old] Never cited.")))
    (should (equal (plist-get plan :orphans) '("old")))
    (should (equal (plist-get plan :dangling) '("ghost")))
    (should (string-match-p "\\[fn:old\\] Never cited\\." (plist-get plan :text)))
    (should (string-match-p "^\\* Footnotes$" (plist-get plan :text)))))

(ert-deftest sp-org-lint-footnote-heading-with-other-content-stays ()
  (let ((plan (sp-org-lint-test--result
               "* Alpha" "Claim.[fn:a]" ""
               "* Footnotes" ":PROPERTIES:" ":ID: x" ":END:" "[fn:a] Source A.")))
    (should (string-match-p "^\\* Footnotes\n:PROPERTIES:" (plist-get plan :text)))
    (should-not (plist-get plan :removed))))

(ert-deftest sp-org-lint-footnote-conflicts-stay-where-they-are ()
  (let ((plan (sp-org-lint-test--result
               "* Alpha" "Claim.[fn:a]" "[fn:a] Here already." ""
               "* Footnotes" "[fn:a] Duplicate.")))
    (should-not (plist-get plan :changed))
    (should (equal (plist-get plan :conflicts)
                   '(("a" . "defined more than once"))))))

(ert-deftest sp-org-lint-footnote-plan-is-idempotent ()
  (let* ((first (sp-org-lint-test--result
                 "* Alpha" "One.[fn:s]" "" "* Beta" "Two.[fn:s]" ""
                 "* Footnotes" "[fn:s] Source."))
         (second (sp-org-lint-fn-plan-text (plist-get first :text))))
    (should-not (plist-get second :changed))
    (should-not (plist-get second :moves))))

(ert-deftest sp-org-lint-footnote-no-footnotes-section-is-untouched ()
  (should-not (plist-get (sp-org-lint-test--result
                          "* Alpha" "Claim.[fn:a]" "" "[fn:a] Source.")
                         :changed)))

(defun sp-org-lint-test--vault (&rest files)
  "Make a fake vault from FILES, a list of (NAME . TEXT); return its folder."
  (let ((dir (make-temp-file "sp-lint-vault-" t)))
    (dolist (f files)
      (with-temp-file (expand-file-name (car f) dir)
        (insert (cdr f))))
    dir))

(defun sp-org-lint-test--wait (buffer phases)
  "Wait until the run in BUFFER is in one of PHASES."
  (let ((limit (+ (float-time) 60)))
    (while (and (< (float-time) limit)
                (not (memq (with-current-buffer buffer
                             (sp-org-lint-fn--get :phase))
                           phases)))
      (accept-process-output nil 0.1))
    (should (memq (with-current-buffer buffer (sp-org-lint-fn--get :phase))
                  phases))))

(ert-deftest sp-org-lint-footnote-async-scan-and-apply ()
  (let* ((moving (sp-org-lint-test--text "* Alpha" "Claim.[fn:a]" ""
                                         "* Footnotes" "[fn:a] Source."))
         (fine (sp-org-lint-test--text "* Alpha" "Text."))
         (dir (sp-org-lint-test--vault (cons "moving.org" moving)
                                       (cons "fine.org" fine)
                                       (cons "notes.txt" "ignored")))
         (backups (make-temp-file "sp-lint-backup-" t))
         (sp-org-lint-fn-backup-directory backups)
         (file (expand-file-name "moving.org" dir))
         (buffer nil))
    (unwind-protect
        (cl-letf (((symbol-function 'display-buffer) #'ignore)
                  ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
          (sp-org-lint-footnotes dir)
          (setq buffer (get-buffer sp-org-lint-fn--buffer-name))
          (sp-org-lint-test--wait buffer '(ready failed))
          (with-current-buffer buffer
            (should (eq (sp-org-lint-fn--get :phase) 'ready))
            (should (string-match-p "2 file(s) scanned: 1 with footnotes" (buffer-string)))
            (should (string-match-p "\\[fn:a\\] Footnotes -> Alpha" (buffer-string))))
          ;; Preview first: nothing changed yet.
          (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                         moving))
          (with-current-buffer buffer (sp-org-lint-footnotes-apply))
          (sp-org-lint-test--wait buffer '(applied failed))
          (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                         (sp-org-lint-test--text "* Alpha" "Claim.[fn:a]" ""
                                                 "[fn:a] Source.")))
          (let ((copies (directory-files-recursively backups "moving\\.org\\'")))
            (should (= (length copies) 1))
            (should (equal (with-temp-buffer (insert-file-contents (car copies))
                                             (buffer-string))
                           moving))))
      (when buffer (kill-buffer buffer))
      (delete-directory dir t)
      (delete-directory backups t))))

(ert-deftest sp-org-lint-footnote-apply-skips-a-file-changed-since-the-preview ()
  (let* ((dir (sp-org-lint-test--vault
               (cons "a.org" (sp-org-lint-test--text "* Alpha" "Claim.[fn:a]" ""
                                                     "* Footnotes" "[fn:a] Source."))))
         (backups (make-temp-file "sp-lint-backup-" t))
         (file (expand-file-name "a.org" dir))
         (plan (sp-org-lint-fn-plan-file file)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Changed\n"))
          (let ((result (sp-org-lint-fn-apply-file file (plist-get plan :sha) backups)))
            (should (eq (plist-get result :status) 'skipped))
            (should (equal (plist-get result :reason) "changed since the preview"))
            (should-not (directory-files-recursively backups "a\\.org\\'"))))
      (delete-directory dir t)
      (delete-directory backups t))))

(provide 'sp-org-lint-test)
;;; sp-org-lint-test.el ends here
