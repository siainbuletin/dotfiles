;;; harness.el --- load emacs-modular without Elpaca/network  -*- lexical-binding: t; -*-
;; Usage (from driver.sh):  emacs -Q --batch -l harness.el --eval '(sp-harness-report)'
;; or in a daemon:          emacs -Q --daemon=NAME -l harness.el --eval '(sp-harness-load-default-modules)'
;;
;; What it does: sources early-init.el (paths, load-path, switches) but NOT init.el,
;; so Elpaca is never bootstrapped; use-package's :ensure becomes a no-op; then
;; requires the modules named in `lem--default-modules' one at a time and records
;; ok/FAILED per module.  Packages that would come from MELPA are simply absent,
;; so modules that need them fail -- that is expected, see SKILL.md.

(defvar sp-harness-dir (file-name-directory (or load-file-name buffer-file-name)))
(defvar sp-harness-config
  (or (getenv "SP_CONFIG_DIR")
      (expand-file-name "../../../" sp-harness-dir))
  "The emacs-modular directory (the one holding init.el).")
(setq user-emacs-directory (file-name-as-directory (expand-file-name sp-harness-config)))

;; early-init.el only defines paths/variables; it is safe to source by hand.
;; var/ is created inside the config dir, so SP_CONFIG_DIR should be a copy.
(load (expand-file-name "early-init.el" user-emacs-directory) nil t)
(setq sp-headless-host t)

(require 'use-package)
(setq use-package-always-ensure nil
      use-package-ensure-function #'ignore   ; no package.el, no Elpaca
      use-package-verbose nil)
(setq package-enable-at-startup nil)

;; Elpaca-only forms used inside modules.
(unless (fboundp 'elpaca)
  (defmacro elpaca (&rest _) nil)
  (defun elpaca-wait (&rest _) nil))

(defvar sp-harness-results nil "Alist (MODULE . ok|error-string), in load order.")

(defun sp-harness-default-modules ()
  "Features listed (uncommented) in `lem--default-modules' of init.el."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" user-emacs-directory))
    (let ((start (progn (search-forward "(defun lem--default-modules") (point)))
          (end (progn (search-forward "(defun lem--minimal-modules") (point)))
          mods)
      (goto-char start)
      (while (re-search-forward "^[ \t]+'\\([[:alnum:]-]+\\)" end t)
        (push (intern (match-string 1)) mods))
      (nreverse mods))))

(defun sp-harness-require (feature)
  (let ((r (condition-case err (progn (require feature) 'ok)
             (error (format "%S" err)))))
    (push (cons feature r) sp-harness-results)
    r))

(defun sp-harness-load-default-modules ()
  (setq sp-harness-results nil)
  (let ((inhibit-message t))
    (dolist (m (sp-harness-default-modules))
      (unless (memq m (lem-gui-only-modules))
        (sp-harness-require m))))
  (setq sp-harness-results (nreverse sp-harness-results)))

(defun sp-harness-report ()
  "Load the default modules and print one line per module."
  (sp-harness-load-default-modules)
  (let ((ok 0) (bad 0))
    (dolist (r sp-harness-results)
      (if (eq (cdr r) 'ok)
          (progn (cl-incf ok) (princ (format "ok      %s\n" (car r))))
        (cl-incf bad)
        (princ (format "FAILED  %s  %s\n" (car r)
                       (truncate-string-to-width (cdr r) 110 nil nil "…")))))
    (princ (format "== %d ok, %d failed\n" ok bad))))

(provide 'sp-harness)
