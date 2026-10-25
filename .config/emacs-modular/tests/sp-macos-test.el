;;; sp-macos-test.el --- Tests for the ambient light of sp-macos  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(defmacro defcustom (sym val &rest _) `(defvar ,sym ,val))

(let ((file (expand-file-name
             "../libraries/modules/base/sp-macos.el"
             (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (form)
      (while (setq form (ignore-errors (read (current-buffer))))
        (when (and (consp form)
                   (memq (car form) '(defcustom defvar defun))
                   (string-match-p "\\`sp-macos-\\(ambient\\|light\\)\\|\\`sp-macos--"
                                   (symbol-name (cadr form))))
          (eval form t))))))

(ert-deftest sp-macos-test-levels ()
  (let ((sp-macos--ambient-family nil))
    (should (eq (sp-macos--level-for 500) 'faded-light))
    (should (eq (sp-macos--level-for 100) 'hard-light))
    (should (eq (sp-macos--level-for 30) 'faded-dark))
    (should (eq (sp-macos--level-for 3) 'hard-dark))
    (should (eq (sp-macos--level-for 0) 'hard-dark))))

(ert-deftest sp-macos-test-hysteresis ()
  ;; hard-light starts at 60; with a 0.25 margin it is kept down to 45.
  (let ((sp-macos--ambient-family 'hard-light))
    (should (eq (sp-macos--level-for 50) 'hard-light))
    (should (eq (sp-macos--level-for 44) 'faded-dark))
    ;; and up to 150 * 1.25 = 187.5 before faded-light takes over.
    (should (eq (sp-macos--level-for 180) 'hard-light))
    (should (eq (sp-macos--level-for 190) 'faded-light))))

(ert-deftest sp-macos-test-sensor-command ()
  (let ((sp-macos-light-sensor-command nil))
    (should-not (sp-macos-ambient-lux))
    (should-not (sp-macos-ambient-family)))
  (let ((sp-macos-light-sensor-command "echo 42.5"))
    (should (= (sp-macos-ambient-lux) 42.5)))
  (let ((sp-macos-light-sensor-command "echo not-a-number"))
    (should-not (sp-macos-ambient-lux))))

(provide 'sp-macos-test)
;;; sp-macos-test.el ends here
