;;; sp-syslinux-test.el --- Tests for sp-syslinux  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(load (expand-file-name
       "../libraries/modules/base/sp-syslinux.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(ert-deftest sp-syslinux-test-portal ()
  (should (eq (sp-syslinux--parse-portal "(<<uint32 1>>,)") 'dark))
  (should (eq (sp-syslinux--parse-portal "(<<uint32 2>>,)") 'light))
  (should-not (sp-syslinux--parse-portal "(<<uint32 0>>,)"))
  (should-not (sp-syslinux--parse-portal "")))

(ert-deftest sp-syslinux-test-gsettings ()
  (should (eq (sp-syslinux--parse-gsettings "'prefer-dark'\n") 'dark))
  (should (eq (sp-syslinux--parse-gsettings "'prefer-light'\n") 'light))
  (should (eq (sp-syslinux--parse-gsettings "'default'\n") 'light))
  (should-not (sp-syslinux--parse-gsettings "")))

(ert-deftest sp-syslinux-test-kde ()
  (should (eq (sp-syslinux--parse-kde "BreezeDark\n") 'dark))
  (should (eq (sp-syslinux--parse-kde "BreezeLight\n") 'light))
  (should-not (sp-syslinux--parse-kde "\n")))

(ert-deftest sp-syslinux-test-signal ()
  (should (eq (sp-syslinux--signal-appearance 1) 'dark))
  (should (eq (sp-syslinux--signal-appearance '(2)) 'light))
  (should-not (sp-syslinux--signal-appearance 0)))

(ert-deftest sp-syslinux-test-missing-programs ()
  (should-not (sp-syslinux--run "no-such-program-here")))

(provide 'sp-syslinux-test)
;;; sp-syslinux-test.el ends here
