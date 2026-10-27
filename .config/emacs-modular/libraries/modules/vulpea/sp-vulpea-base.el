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

;; Enable autosync a few idle seconds after start-up, not during init, and let
;; vulpea scan in the background: it lists the files in a subprocess and queues
;; them, and the queue parses only the files whose content changed.  Opening a
;; note, the dashboard included, starts nothing.
(setq vulpea-db-sync-scan-on-enable 'background)

(defun sp-vulpea-start-autosync ()
  "Turn on `vulpea-db-autosync-mode', which scans the vault in the background."
  (let ((started (float-time)))
    (message "[vulpea] starting autosync; changed files are indexed in the background...")
    (vulpea-db-autosync-mode +1)
    (message "[vulpea] autosync started in %.2fs" (- (float-time) started))))

(add-hook 'emacs-startup-hook
          (lambda ()
            (run-with-idle-timer 5 nil #'sp-vulpea-start-autosync)))

(setq vulpea-buffer-alias-property "ROAM_ALIASES") ;; By default, aliases are stored in ALIASES. To use ROAM_ALIASES for org-roam compatibility:

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
