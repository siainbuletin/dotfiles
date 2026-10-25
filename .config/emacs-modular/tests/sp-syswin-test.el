;;; sp-syswin-test.el --- Tests for sp-syswin  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(load (expand-file-name
       "../libraries/modules/base/sp-syswin.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(ert-deftest sp-syswin-test-registry ()
  (should (eq (sp-syswin--parse-registry
               "\nHKEY_CURRENT_USER\\...\\Personalize\n    AppsUseLightTheme    REG_DWORD    0x0\n")
              'dark))
  (should (eq (sp-syswin--parse-registry
               "    AppsUseLightTheme    REG_DWORD    0x1\n")
              'light))
  (should-not (sp-syswin--parse-registry "ERROR: not found")))

(ert-deftest sp-syswin-test-not-windows ()
  (unless (memq system-type '(windows-nt cygwin ms-dos))
    (should-not (sp-syswin-appearance))))

(provide 'sp-syswin-test)
;;; sp-syswin-test.el ends here
