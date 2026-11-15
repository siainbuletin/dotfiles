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

(ert-deftest sp-echo-help-show-now-forces ()
  (let (shown)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) shown)))
              ((symbol-function 'current-message) (lambda () "other")))
      (with-temp-buffer
        (should-error (sp-echo-help-show-now) :type 'user-error)
        (setq sp-echo-help-idle-delay nil)
        (sp-echo-help-set '(("q" "Quit")))
        (setq shown nil)
        (sp-echo-help-show)
        (should-not shown)
        (sp-echo-help-show-now)
        (should (equal (car shown) " [q] Quit"))
        (should (eq (lookup-key sp-echo-help-mode-map (kbd "C-c ?")) #'sp-echo-help-show-now))))))

(ert-deftest sp-echo-help-idle-timer-starts-and-stops ()
  (let ((sp-echo-help-idle-delay 60) (sp-echo-help--timer nil))
    (unwind-protect
        (progn
          (with-temp-buffer
            (sp-echo-help-set '(("q" "Quit")))
            (should (timerp sp-echo-help--timer)))
          ;; buffer is killed: the next idle run cancels the timer
          (sp-echo-help--idle-show)
          (should-not sp-echo-help--timer))
      (when (timerp sp-echo-help--timer) (cancel-timer sp-echo-help--timer)))))

(ert-deftest sp-echo-help-idle-show-replaces-a-message ()
  (let (shown)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) shown)))
              ((symbol-function 'current-message) (lambda () "other")))
      (let ((sp-echo-help-idle-delay nil) (sp-echo-help--timer nil))
        (switch-to-buffer (get-buffer-create "*sp-echo-help-idle-test*"))
        (unwind-protect
            (progn
              (sp-echo-help-set '(("q" "Quit")))
              (setq shown nil)
              (cl-letf (((symbol-function 'current-idle-time) (lambda () 2.0)))
                (sp-echo-help--idle-show))
              (should-not shown)        ; younger than the hold time
              (cl-letf (((symbol-function 'current-idle-time) (lambda () 6.0)))
                (sp-echo-help--idle-show))
              (should (equal (car shown) " [q] Quit")))
          (kill-buffer "*sp-echo-help-idle-test*"))))))

(provide 'sp-echo-help-test)
;;; sp-echo-help-test.el ends here
