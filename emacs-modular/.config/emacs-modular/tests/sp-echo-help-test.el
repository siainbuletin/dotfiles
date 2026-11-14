;;; sp-echo-help-test.el --- Tests for the echo-area hints of sp-interaction -*- lexical-binding: t; -*-

(require 'ert)
(require 'sp-interaction)

(defconst sp-echo-help-test--hints
  '(("C-c C-c" "File it" t) ("C-c C-k" "Abort" t) ("C-c C-r" "New key") ("C-c C-d" "DOI")))

(ert-deftest sp-echo-help-format-grid ()
  (let ((text (sp-echo-help-format sp-echo-help-test--hints nil 2)))
    (should (equal (split-string text "\n")
                   '(" [C-c C-c] File it   [C-c C-r] New key"
                     " [C-c C-k] Abort     [C-c C-d] DOI")))))

(ert-deftest sp-echo-help-format-faces-and-note ()
  (let ((text (sp-echo-help-format sp-echo-help-test--hints "DOI 10.1/x" 2)))
    (should (string-prefix-p " DOI 10.1/x\n" text))
    (should (eq (get-text-property (string-search "File" text) 'face text)
                'sp-echo-help-strong-face))
    (should (eq (get-text-property (string-search "New key" text) 'face text)
                'sp-echo-help-face))))

(ert-deftest sp-echo-help-format-few-hints ()
  (should (equal (sp-echo-help-format '(("q" "Quit")) nil 2) " [q] Quit"))
  (should (equal (sp-echo-help-format nil "only a note") " only a note")))

(ert-deftest sp-echo-help-set-shows-and-turns-off ()
  (let (shown)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) shown))))
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (sp-echo-help-set '(("q" "Quit")) "note")
        (should sp-echo-help-mode)
        (should (member #'sp-echo-help-show post-command-hook))
        (should (equal (car shown) " note\n [q] Quit"))
        (sp-echo-help-set nil)
        (should-not sp-echo-help-mode)
        (should-not (member #'sp-echo-help-show post-command-hook))))))

(provide 'sp-echo-help-test)
;;; sp-echo-help-test.el ends here
