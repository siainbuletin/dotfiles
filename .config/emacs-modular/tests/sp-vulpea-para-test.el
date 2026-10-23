;;; sp-vulpea-para-test.el --- Tests for sp-vulpea-para  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)

(when noninteractive
  (provide 'vulpea-para)
  (defvar vulpea-para-agenda-files-filter nil)
  (defvar vulpea-para-done-keywords nil)
  (defvar vulpea-para-open-work-files nil)
  (defun vulpea-para-agenda-mode (&rest _) nil)
  (defun vulpea-note-tagged-any-p (note &rest tags)
    (seq-intersection (plist-get note :tags) tags))
  (load (expand-file-name
         "../libraries/modules/text/sp-org-keywords.el"
         (file-name-directory (or load-file-name buffer-file-name)))
        nil t))

(load (expand-file-name
       "../libraries/modules/vulpea/sp-vulpea-para.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(ert-deftest sp-vulpea-para-test-cemetery-is-kept-out ()
  (should-not (sp-vulpea-para-agenda-note-p '(:tags ("cemetery"))))
  (should-not (sp-vulpea-para-agenda-note-p '(:tags ("agenda" "cemetery")))))

(ert-deftest sp-vulpea-para-test-other-notes-are-kept ()
  (should (sp-vulpea-para-agenda-note-p '(:tags ("agenda"))))
  (should (sp-vulpea-para-agenda-note-p '(:tags ("agenda" "project")))))

(ert-deftest sp-vulpea-para-test-filter-is-installed ()
  (should (eq vulpea-para-agenda-files-filter #'sp-vulpea-para-agenda-note-p)))

(ert-deftest sp-vulpea-para-test-inbox-always-counts-as-open-work ()
  (should (member "inbox.org" vulpea-para-open-work-files)))

(ert-deftest sp-vulpea-para-test-done-keywords-come-from-the-keyword-module ()
  (should (equal vulpea-para-done-keywords (sp-org-keywords-done))))
