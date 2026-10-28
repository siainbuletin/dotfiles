;;; sp-sandbox.el --- Launch a pull request in a sandboxed Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; Commands for the fish function `emacs-pr' (see "Testing a pull request in a
;; sandbox" in docs/main.org), so a sandbox can be started, reset and removed from
;; the Emacs I am already working in.  The sandbox is a second Emacs process with
;; its own worktree, packages and copy of the notes; this one is not touched.

;;; Code:

(defgroup sp-sandbox nil
  "Run pull requests of the dotfiles in a sandboxed Emacs."
  :group 'tools)

(defcustom sp-sandbox-shell "fish"
  "Shell that has the `emacs-pr' function defined."
  :type 'string
  :group 'spcustom)

(defun sp-sandbox--run (&rest args)
  "Run `emacs-pr' with ARGS in a fish process and show its output."
  (let ((buffer (get-buffer-create "*emacs-pr*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)) (erase-buffer)))
    (make-process
     :name "emacs-pr"
     :buffer buffer
     :command (list sp-sandbox-shell "-c"
                    (mapconcat #'shell-quote-argument (cons "emacs-pr" args) " "))
     :noquery t)
    (display-buffer buffer)))

(defun sp-sandbox--number-at-point ()
  "Pull request number near point (as in #22 or a bare 22), or nil."
  (or (thing-at-point 'number)
      (save-excursion
        (skip-chars-backward "0-9")
        (and (eq (char-before) ?#) (thing-at-point 'number)))))

;;;###autoload
(defun sp-sandbox-pr (number)
  "Fetch pull request NUMBER and start a sandboxed Emacs on it.
Running it again for the same number updates the sandbox to the latest commit."
  (interactive (list (read-number "Pull request number: "
                                  (sp-sandbox--number-at-point))))
  (sp-sandbox--run (number-to-string number)))

;;;###autoload
(defun sp-sandbox-remove (number)
  "Remove the sandbox of pull request NUMBER: worktree, packages and notes copy."
  (interactive (list (read-number "Remove the sandbox of pull request: "
                                  (sp-sandbox--number-at-point))))
  (when (y-or-n-p (format "Remove the sandbox of PR #%d? " number))
    (sp-sandbox--run "rm" (number-to-string number))))

;;;###autoload
(defun sp-sandbox-reset-notes (number)
  "Give the sandbox of pull request NUMBER a fresh copy of ~/notes next time."
  (interactive (list (read-number "Reset the notes of pull request: "
                                  (sp-sandbox--number-at-point))))
  (sp-sandbox--run "reset" (number-to-string number)))

;;;###autoload
(defun sp-sandbox-reseed ()
  "Drop the package seed, so the next sandbox clones the live packages again."
  (interactive)
  (sp-sandbox--run "reseed"))

(provide 'sp-sandbox)
;; sp-sandbox.el ends here.
