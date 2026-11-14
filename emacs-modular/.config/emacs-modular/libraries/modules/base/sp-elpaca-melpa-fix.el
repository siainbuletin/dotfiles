;;; sp-elpaca-melpa-fix.el --- Temporary fix: Elpaca and MELPA's main branch -*- lexical-binding: t; -*-

;;; Commentary:

;; TEMPORARY.  MELPA renamed its default branch from `master' to `main'; Elpaca's
;; MELPA menu still hardcodes `master', so cloning and updating the MELPA recipes
;; fails.  See https://github.com/progfolio/elpaca/issues/585 and
;; https://github.com/progfolio/elpaca/pull/586.
;;
;; This file advises `elpaca-menu-melpa--clone' and `elpaca-menu-melpa--update'
;; to use `main'.  Delete this file (and its `sp-load' line in init.el) once
;; Elpaca is fixed; until then `sp-elpaca-melpa-fix' switches it off, and it
;; switches itself off when Elpaca defines `elpaca-melpa-branch'.

;;; Code:

(require 'cl-lib)

(defcustom sp-elpaca-melpa-fix t
  "When non-nil, make Elpaca's MELPA menu use `sp-elpaca-melpa-branch'.
Temporary workaround for MELPA renaming `master' to `main'.  Set to nil
to use Elpaca's own behaviour, for example after Elpaca is fixed."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-elpaca-melpa-branch "main"
  "Branch of the MELPA recipes repository that the fix clones and updates."
  :type 'string
  :group 'spcustom)

(declare-function elpaca-process-call "elpaca")
(defvar elpaca-cache-directory)

(defun sp-elpaca-melpa-fix--active-p ()
  "Non-nil when the MELPA branch fix should replace Elpaca's code."
  (and sp-elpaca-melpa-fix
       (not (boundp 'elpaca-melpa-branch))))

(defun sp-elpaca-melpa-fix--git (&rest args)
  "Run git with ARGS via `elpaca-process-call'.
Return nil on success, otherwise the failed process result."
  (let ((result (apply #'elpaca-process-call "git" args)))
    (unless (zerop (car result)) result)))

(defun sp-elpaca-melpa-fix--clone (orig path)
  "Clone the MELPA recipes to PATH using `sp-elpaca-melpa-branch'.
Around advice for `elpaca-menu-melpa--clone'; ORIG is the original."
  (if (not (sp-elpaca-melpa-fix--active-p))
      (funcall orig path)
    (let ((default-directory path)
          (branch sp-elpaca-melpa-branch))
      (make-directory path t)
      (make-directory (expand-file-name ".git/info/" path) t)
      (message "Downloading MELPA recipes (branch %s)..." branch)
      (let* ((process-environment (append '("GIT_CONFIG_SYSTEM=/dev/null"
                                            "GIT_CONFIG_GLOBAL=/dev/null")
                                          process-environment))
             (err (or (sp-elpaca-melpa-fix--git "init")
                      (sp-elpaca-melpa-fix--git "config" "core.sparseCheckout" "true")
                      (progn
                        (with-temp-buffer
                          (insert "recipes")
                          (append-to-file (point-min) (point-max)
                                          (expand-file-name ".git/info/sparse-checkout" path)))
                        nil)
                      (sp-elpaca-melpa-fix--git "remote" "add" "origin"
                                                "https://github.com/melpa/melpa.git")
                      (sp-elpaca-melpa-fix--git "pull" "--depth=1" "origin" branch)
                      (sp-elpaca-melpa-fix--git "checkout" branch)
                      (sp-elpaca-melpa-fix--git "branch" "--set-upstream-to"
                                                (format "origin/%s" branch) branch))))
        (when err (error "Unable to clone MELPA: %S" err))
        (message "Downloading MELPA recipes...100%%")))))

(defun sp-elpaca-melpa-fix--update (orig)
  "Update the MELPA recipes from `sp-elpaca-melpa-branch'.
Around advice for `elpaca-menu-melpa--update'; ORIG is the original."
  (if (not (sp-elpaca-melpa-fix--active-p))
      (funcall orig)
    (let ((default-directory (expand-file-name "melpa/" elpaca-cache-directory))
          (branch sp-elpaca-melpa-branch))
      (message "Downloading MELPA...")
      (let ((err (or (sp-elpaca-melpa-fix--git "fetch" "--depth=1" "origin" branch)
                     (sp-elpaca-melpa-fix--git "checkout" "-B" branch "FETCH_HEAD")
                     (sp-elpaca-melpa-fix--git "branch" "--set-upstream-to"
                                               (format "origin/%s" branch) branch))))
        (message "%s" (if err (format "Updating MELPA failed: %S" err)
                        "Downloading MELPA...100%"))))))

(advice-add 'elpaca-menu-melpa--clone  :around #'sp-elpaca-melpa-fix--clone)
(advice-add 'elpaca-menu-melpa--update :around #'sp-elpaca-melpa-fix--update)

(provide 'sp-elpaca-melpa-fix)
;;; sp-elpaca-melpa-fix.el ends here
