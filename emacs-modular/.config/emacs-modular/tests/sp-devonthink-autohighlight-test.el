;;; sp-devonthink-autohighlight-test.el --- Tests for sp-devonthink-autohighlight -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-devonthink-autohighlight)

(defmacro sp-devonthink-autohighlight-test--fresh (&rest body)
  "Run BODY with the mode state reset and a settle of 2."
  `(let ((sp-devonthink-auto-highlight-settle 2))
     (sp-devonthink-autohighlight--reset)
     ,@body))

(ert-deftest sp-devonthink-autohighlight-waits-for-a-settled-selection ()
  (sp-devonthink-autohighlight-test--fresh
   (should-not (sp-devonthink-autohighlight--step "abc"))
   (should-not (sp-devonthink-autohighlight--step "abcd"))
   (should (eq (sp-devonthink-autohighlight--step "abcd") 'highlight))))

(ert-deftest sp-devonthink-autohighlight-does-not-repeat ()
  (sp-devonthink-autohighlight-test--fresh
   (sp-devonthink-autohighlight--step "abc")
   (should (sp-devonthink-autohighlight--step "abc"))
   (should-not (sp-devonthink-autohighlight--step "abc"))
   (should-not (sp-devonthink-autohighlight--step "abc"))))

(ert-deftest sp-devonthink-autohighlight-empty-selection-rearms ()
  (sp-devonthink-autohighlight-test--fresh
   (sp-devonthink-autohighlight--step "abc")
   (sp-devonthink-autohighlight--step "abc")
   (should-not (sp-devonthink-autohighlight--step nil))
   (sp-devonthink-autohighlight--step "abc")
   (should (sp-devonthink-autohighlight--step "abc"))))

(ert-deftest sp-devonthink-autohighlight-settle-one-is-immediate ()
  (let ((sp-devonthink-auto-highlight-settle 1))
    (sp-devonthink-autohighlight--reset)
    (should (sp-devonthink-autohighlight--step "abc"))))

(ert-deftest sp-devonthink-autohighlight-quotes-the-menu-name ()
  (should (equal (sp-devonthink-autohighlight--quote "a\"b\\c") "a\\\"b\\\\c"))
  (should (string-match-p "is \"Hi\\\\\"x\""
                          (sp-devonthink-autohighlight--click-script "Hi\"x"))))

(ert-deftest sp-devonthink-autohighlight-selection-trims-and-nils ()
  (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "  hello \n")))
    (should (equal (sp-devonthink-autohighlight--selection) "hello")))
  (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "")))
    (should-not (sp-devonthink-autohighlight--selection))))

(ert-deftest sp-devonthink-autohighlight-command-reports-missing-item ()
  (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "none")))
    (should-error (sp-devonthink-highlight-selection) :type 'user-error))
  (cl-letf (((symbol-function 'sp-reading--osascript) (lambda (_) "ok")))
    (should (sp-devonthink-highlight-selection))))

(ert-deftest sp-devonthink-autohighlight-tick-presses-once ()
  (let ((presses 0)
        (sp-devonthink-auto-highlight-settle 2))
    (sp-devonthink-autohighlight--reset)
    (cl-letf (((symbol-function 'sp-devonthink-autohighlight--emacs-focused-p) #'ignore)
              ((symbol-function 'sp-devonthink-autohighlight--selection) (lambda () "abc"))
              ((symbol-function 'sp-devonthink-autohighlight--press)
               (lambda () (cl-incf presses))))
      (dotimes (_ 5) (sp-devonthink-autohighlight--tick)))
    (should (= presses 1))))

(ert-deftest sp-devonthink-autohighlight-tick-idle-while-emacs-focused ()
  (let ((looked nil))
    (cl-letf (((symbol-function 'sp-devonthink-autohighlight--emacs-focused-p) (lambda () t))
              ((symbol-function 'sp-devonthink-autohighlight--selection)
               (lambda () (setq looked t) nil)))
      (sp-devonthink-autohighlight--tick))
    (should-not looked)))

(ert-deftest sp-devonthink-autohighlight-mode-toggles-timer ()
  (unwind-protect
      (progn
        (sp-devonthink-auto-highlight-mode 1)
        (should (timerp sp-devonthink-autohighlight--timer))
        (sp-devonthink-auto-highlight-mode -1)
        (should-not sp-devonthink-autohighlight--timer))
    (sp-devonthink-auto-highlight-mode -1)))

(ert-deftest sp-devonthink-autohighlight-keys ()
  (should (eq (keymap-lookup sp-devonthink-map "h") #'sp-devonthink-highlight-selection))
  (should (eq (keymap-lookup sp-devonthink-map "H") #'sp-devonthink-auto-highlight-mode)))
