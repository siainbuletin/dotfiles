;;; sp-vault-perf.el --- Settings for a vault of about 10,000 notes -*- lexical-binding: t; -*-

;;; Commentary:

;; Cheaper defaults for Org and Emacs when the vault has thousands of files.
;; `gc-cons-threshold' and the vulpea autosync delay are set elsewhere on
;; purpose (init.el, sp-vulpea-base.el).  `M-x sp-vault-perf-report' shows what
;; the vault costs.

;;; Code:

(setq read-process-output-max (* 1024 1024))

(setq-default bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)
(setq inhibit-compacting-font-caches t)
(global-so-long-mode 1)

(setq org-agenda-inhibit-startup t)
(setq org-element-use-cache t)
(setq org-element-cache-persistent t)

(defun sp-vault-perf--file-size (file)
  "Return the size of FILE in megabytes, or nil when it does not exist."
  (when (and file (file-exists-p file))
    (/ (file-attribute-size (file-attributes file)) 1048576.0)))

(defun sp-vault-perf-report ()
  "Show what the vault costs: files, database, ID table and GC so far."
  (interactive)
  (let* ((dirs (bound-and-true-p vulpea-db-sync-directories))
         (files (apply #'append
                       (mapcar (lambda (d)
                                 (when (file-directory-p d)
                                   (directory-files-recursively d "\\.org\\'")))
                               dirs)))
         (ids (and (bound-and-true-p org-id-locations)
                   (hash-table-p org-id-locations)
                   (hash-table-count org-id-locations))))
    (message (concat "[vault] %d org files; vulpea.db %s MB; org-id table %s ids; "
                     "%d agenda files; %d GCs, %.1fs in GC; gc-cons-threshold %d")
             (length files)
             (let ((s (sp-vault-perf--file-size
                       (bound-and-true-p vulpea-db-location))))
               (if s (format "%.0f" s) "?"))
             (or ids "?")
             (length (org-agenda-files t))
             gcs-done gc-elapsed gc-cons-threshold)))

(provide 'sp-vault-perf)
