;; -*- lexical-binding: t; -*-

;;; Commentary:

;; This prefers using the exec-path-from-shell package in order to deal with all the
;; binaries that macOS has to pull.
;;
;; There needs to be a separate solution for Windows and Linux, respectively, so these
;; packages don't get used on every system in part.
;;
;; The folders my files live in (notes, bibliography, checkouts) are named in
;; `sp-paths' and can be overridden by SP_* environment variables.  Those are read
;; when `sp-paths' loads, which is before the shell's environment is imported
;; below, so a GUI Emacs only sees them when it is started from a shell (or when
;; they are set for the graphical session).  Nothing here changes those folders.

;;; Code:

(require 'sp-paths)

;; This configuration of exec-path-from-shell is taken from John Wiegley
(use-package exec-path-from-shell
  :ensure t
  :when (memq window-system '(mac ns x pgtk))
  :config
  (exec-path-from-shell-initialize)
  (dolist (var '("ASPELL_CONF"
                 "EDITOR"
                 "GNUPGHOME"
                 "NIX_SSL_CERT_FILE"
                 "NODE_EXTRA_CA_CERTS"
                 "PASSWORD_STORE_DIR"
                 "SSH_AUTH_SOCK"
                 "SSL_CERT_FILE"
                 "STARDICT_DATA_DIR"))
    (exec-path-from-shell-copy-env var)))

(when (daemonp)
  (exec-path-from-shell-initialize))

;; Configuring the load-path (all of this is now done recursively from the
;; variables I have set from the user in ealy-init.el)

;; Why would you want to get the environment variables from shell?
;; this is currently commented out
;; it's taken from the original modular configuration that I followed.

;; (defcustom siapip/exec-path-from-shell:enable nil
;;   "Try to get the environment variables form shell."
;;   :group 'siapip
;;   :type 'boolean)

;; (when siapip/exec-path-from-shell:enable
;;   (use-package exec-path-from-shell
;;     :demand t
;;     :ensure t
;;     :init
;;     (condition-case err
;;         (exec-path-from-shell-initialize)
;;       (error (message "Failed to get exec-path from shell: %S" err)))))

;; However, I should see the way that this code actually acts and if it's useful, in reality.

(defun sp-replace-with-shell (posBegin posEnd command)
  "Pipe region through shell command and replace"
  (interactive (let (command)
		 (unless (mark)
		   (user-error "The mark is not set now, so there is no region"))
                 (setq command (read-shell-command "Shell command on region: "))
                 (list (region-beginning) (region-end) command)))
  (with-temp-message ""
    (let ((string (buffer-substring-no-properties posBegin posEnd))
          (buffer (current-buffer))
          (shell-output-exists (get-buffer "*Shell Command Output*")))
      (with-temp-buffer
        (insert string)
        (shell-command-on-region (point-min) (point-max) command (current-buffer) t)
        (setq string (buffer-substring-no-properties (point-min) (point-max))))
      (delete-region posBegin posEnd)
      (insert string)
      ;; If *Shell Command Output* wasn't opened before, kill it
      (unless shell-output-exists
        (let ((output-buffer (get-buffer "*Shell Command Output*")))
          (when output-buffer
            (kill-buffer output-buffer)))))))

(keymap-global-set "C-M-|" 'sp-replace-with-shell)

;;; Recommended in https://blog.dornea.nu/2026/04/23/claude-code-customizations-in-emacs/ for getting a terminal backend in Emacs. See also sp-terminal.el
(use-package inheritenv
  :straight (:type git :host github :repo "purcell/inheritenv"))

;;; Environment variable so yadm can work as dotfiles in Emacs
(dolist (var '("ASPELL_CONF"
               ...
               "STARDICT_DATA_DIR"
               "GIT_CEILING_DIRECTORIES"))
  (exec-path-from-shell-copy-env var))

;;; Provide:

(provide 'sp-env)
;; sp-env.el ends here.
