;;; sp-vulpea-base.el --- Vulpea note database basics -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets up `vulpea', a library and database layer for Org-based
;; notes (an alternative to org-roam), together with `vui', the UI component
;; library used by other Vulpea modules such as `sp-vulpea-vui-table'. It is
;; required from `sp-org-ext', and the further Vulpea extensions live in
;; `sp-vulpea-ext'.

;;; Code:

(use-package vui
  :ensure t)

(use-package vulpea
  :ensure (:wait t)

  :init
  ;; Vulpea derives its defaults from `org-directory'. Doom's :lang org
  ;; module sets it to ~/org/ - override here if your notes live elsewhere,
  ;; or set `vulpea-db-sync-directories' explicitly.

  :bind
  (("M-o f" . vulpea-find)
   :map org-mode-map
   ("M-o n a" . vulpea-buffer-alias-add))
)

(setq vulpea-db-sync-directories (list sp-notes-dir))

(setq vulpea-db-parse-method 'single-temp-buffer)

;; Skip the scan at startup: the database stays as it was, and the scan runs
;; once, after the first note of the vault is opened (see below).
(setq vulpea-db-sync-scan-on-enable nil)

(vulpea-db-autosync-mode +1)

(defun sp-vulpea-scan-once ()
  "Run the deferred full scan after the first note of the vault opens."
  (when (and buffer-file-name
             (vulpea-db-sync-tracked-file-p buffer-file-name))
    (remove-hook 'find-file-hook #'sp-vulpea-scan-once)
    (run-with-idle-timer 2 nil #'vulpea-db-sync-full-scan)))

(add-hook 'find-file-hook #'sp-vulpea-scan-once)

(setq vulpea-buffer-alias-property "ROAM_ALIASES") ;; By default, aliases are stored in ALIASES. To use ROAM_ALIASES for org-roam compatibility:

(vulpea-db-query-by-tags-every '("project" "active")) ;; Query all active projects

;; Configuring the display of notes in the minibuffer
;; "My Notes → Projects → Task"
(setq vulpea-select-describe-fn #'vulpea-select-describe-outline-full)

;; Default annotation: "(primary title) #tag1 #tag2"
(setq vulpea-select-annotate-fn #'vulpea-select-annotate)

;; Templating for Vulpea

(setq vulpea-create-default-function
      (lambda (title)
        (list :file-name (format "%s_%s.org"
                                 (format-time-string "%Y%m%d%H%M%S")
                                 (vulpea-title-to-slug title))
              :tags (if (string-match-p "TODO" title)
                        '("task")
                      '("note")))))

(provide 'sp-vulpea-base)
