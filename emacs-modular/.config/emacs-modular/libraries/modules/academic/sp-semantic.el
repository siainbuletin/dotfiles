;;; sp-semantic.el --- Semantic search over notes -*- lexical-binding: t; -*-

;;; Commentary:

;; Oftentimes the search functions that I have enabled in Emacs aren't enough for me to actually
;; be able to find something.
;;
;; There are several packages that are concerned with getting to the information as fast as
;; possible, focusing specifically on linking information that may be found in a database.

;;; Code:

;;;; org-semantic binary install on macOS
(defun sp-semantic--repair-binary (binary)
  "Clear the quarantine flag on BINARY and sign it ad hoc.  Non-nil on success.
Only does anything on macOS."
  (and (eq system-type 'darwin)
       (file-exists-p binary)
       (progn
         ;; Fails harmlessly when the flag is not there.
         (call-process "xattr" nil nil nil "-d" "com.apple.quarantine" binary)
         ;; `call-process' returns a string, not a number, when a signal
         ;; ends the process, so compare with `eq' and not `zerop'.
         (eq 0 (call-process "codesign" nil nil nil "--force" "--sign" "-" binary)))))

(defun sp-semantic--binary-version-a (orig-fun &rest args)
  "Around advice for `org-semantic-binary-version' (ORIG-FUN, ARGS).
A binary killed by a signal makes the original signal
`wrong-type-argument'.  Repair the binary and ask again once; if it
still fails return nil, which the installer reports as a binary that
will not say its version."
  (condition-case nil
      (apply orig-fun args)
    (wrong-type-argument
     (when (sp-semantic--repair-binary (org-semantic--binary))
       (condition-case nil
           (apply orig-fun args)
         (wrong-type-argument nil))))))

(defun sp-semantic--fresh-install-a (&rest _)
  "Before `org-semantic-binary-install', delete the binary already there.
Copying over a signed binary in place keeps its inode, and macOS then
kills it with SIGKILL (\"Killed: 9\").  A fresh file avoids that."
  (let ((old (expand-file-name "org-semantic" org-semantic-install-directory)))
    (when (or (file-exists-p old) (file-symlink-p old))
      (delete-file old))))

(advice-add 'org-semantic-binary-version :around #'sp-semantic--binary-version-a)
(advice-add 'org-semantic-binary-install :before #'sp-semantic--fresh-install-a)

;;;; org-semantic
(use-package org-semantic-results
  :ensure (org-semantic :host github :repo "alberti42/org-semantic")
  :custom
  (org-semantic-vault-root (directory-file-name sp-notes-dir))
  ;; Under var/, which is git-ignored, so Stow and git never see the binary.
  (org-semantic-install-directory
   (expand-file-name "var/org-semantic/" user-emacs-directory))

  :bind (("C-c k s" . org-semantic-find)
         ("C-c k S" . org-semantic-find-in-directory)
         ("C-c k ." . org-semantic-find-at-point)
         ("C-c k R" . org-semantic-reindex))

  ;; Follow mode, on for every results buffer.
  :hook
  (org-semantic-results-mode . next-error-follow-minor-mode)

  ;; Reindex a vault as its notes are saved.
  :init (org-semantic-auto-reindex-mode 1)
)

(provide 'sp-semantic)
;; sp-semantic.el ends here.
