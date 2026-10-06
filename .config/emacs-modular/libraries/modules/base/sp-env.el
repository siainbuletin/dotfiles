;; -*- lexical-binding: t; -*-

;; This prefers using the exec-path-from-shell package in order to deal with all the
;; binaries that macOS has to pull.
;;
;; There needs to be a separate solution for Windows and Linux, respectively, so these
;; packages don't get used on every system in part.

(use-package exec-path-from-shell
  :ensure (:wait t))

(when (memq window-system '(mac ns x pgtk)) (exec-path-from-shell-initialize))

(when (daemonp)
  (exec-path-from-shell-initialize))

;; Configuring the load-path

;; (let* ((base-dir (file-name-parent-directory (file-name-directory (or load-file-name buffer-file-name))))
;;        (packages-dir (expand-file-name "packages" base-dir)))
;;   (when (file-directory-p packages-dir)
;;   (add-to-list 'load-path packages-dir)))

;; Personal attempts from 30 september

;; (add-to-list 'load-path (expand-file-name "site-lisp" user-emacs-directory))

;; (let ((site-lisp (expand-file-name "site-lisp/" user-lisp-directory)))
;;  (when (file-directory-p site-lisp)
;;     (add-to-list 'load-path site-lisp)
;;     (dolist (dir (directory-files-recursively site-lisp ".*" t))
;;       (when (file-directory-p dir)
;;        (add-to-list 'load-path dir)))))

;; Set up the load-path
;; (let (base "~/.config/emacs-include/site-lisp/"))
;; (add-to-list 'load-path base)
;;   (dolist (f (directory-files base))
;;   (let ((name (concat base "/" f)))
;;    (when (and (file-directory-p name)
;;      (not (equal f ".."))
;;      (not (equal f ".")))
;;      (add-to-list 'load-path name))))

;; (let ((dir "~/.config/emacs-include/site-lisp/"))
;;  (dolist (file (directory-files-recursively dir "\\.el\\'"))
;;    (add-to-list 'load-path (file-name-directory file))
;;    (load (file-name-sans-extension file))))

(defcustom siapip/exec-path-from-shell:enable nil
  "Try to get the environment variables form shell."
  :group 'siapip
  :type 'boolean)

(when siapip/exec-path-from-shell:enable
  (use-package exec-path-from-shell
    :demand t
    :ensure t
    :init
    (condition-case err
        (exec-path-from-shell-initialize)
      (error (message "Failed to get exec-path from shell: %S" err)))))

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

(global-set-key (kbd "C-M-|") 'sp-replace-with-shell)

(provide 'sp-env)