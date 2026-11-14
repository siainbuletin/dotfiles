;;; sp-echo-hints-test.el --- Tests for sp-echo-hints -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-echo-hints)

(ert-deftest sp-echo-hints-format-joins-hints ()
  (should (equal (substring-no-properties
                  (sp-echo-hints-format '(("RET" . "visit") ("q" . "quit")) 80))
                 "RET visit   q quit")))

(ert-deftest sp-echo-hints-format-bolds-keys ()
  (let ((text (sp-echo-hints-format '(("RET" . "visit")) 80)))
    (should (eq (get-text-property 0 'face text) 'sp-echo-hints-key))
    (should-not (get-text-property 4 'face text))))

(ert-deftest sp-echo-hints-format-skips-empty-hints ()
  (should (equal (substring-no-properties
                  (sp-echo-hints-format '(("a" . "apply") nil ("d" . nil) ("q" . "quit")) 80))
                 "a apply   q quit")))

(ert-deftest sp-echo-hints-format-drops-what-does-not-fit ()
  (let ((text (substring-no-properties
               (sp-echo-hints-format '(("RET" . "visit") ("d" . "drop") ("q" . "quit")) 16))))
    (should (equal text "RET visit …"))
    (should (<= (string-width text) 16))))

(ert-deftest sp-echo-hints-current-prefers-function ()
  (with-temp-buffer
    (setq sp-echo-hints-list '(("a" . "list"))
          sp-echo-hints-function (lambda () '(("b" . "function"))))
    (should (equal (sp-echo-hints-current) '(("b" . "function"))))
    (setq sp-echo-hints-function nil)
    (should (equal (sp-echo-hints-current) '(("a" . "list"))))))

(ert-deftest sp-echo-hints-show-does-not-log-or-format ()
  "In batch mode `current-message' is always nil, so `message' is stubbed."
  (let (seen log-max)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (setq log-max message-log-max
                       seen (apply #'format-message fmt args)))))
      (let ((message-log-max 100))
        (sp-echo-hints-show '(("%" . "100%")))))
    (should (equal (substring-no-properties seen) "% 100%"))
    (should-not log-max)))

(ert-deftest sp-echo-hints-mode-starts-and-stops-the-timer ()
  (let ((sp-echo-hints--timer nil))
    (with-temp-buffer
      (sp-echo-hints-mode 1)
      (should (timerp sp-echo-hints--timer))
      (sp-echo-hints-mode -1)
      (should-not sp-echo-hints--timer))))

(ert-deftest sp-echo-hints-idle-leaves-a-message-alone ()
  (let (shown (current "Something else"))
    (cl-letf (((symbol-function 'current-message) (lambda () current))
              ((symbol-function 'message)
               (lambda (fmt &rest args) (setq shown (apply #'format-message fmt args)))))
      (with-temp-buffer
        (setq sp-echo-hints-list '(("a" . "apply")))
        (sp-echo-hints-mode 1)
        (sp-echo-hints--idle)
        (should-not shown)
        (setq current nil)
        (sp-echo-hints--idle)
        (should (equal (substring-no-properties shown) "a apply"))
        (sp-echo-hints-mode -1)))))

(provide 'sp-echo-hints-test)
;;; sp-echo-hints-test.el ends here
