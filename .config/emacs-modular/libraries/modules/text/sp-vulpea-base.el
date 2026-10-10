;; -*- lexical-binding: t; -*-

(use-package vui
  :ensure t)

(use-package vulpea
  :ensure (:wait t)
  :init
  (keymap-global-set "M-o f" 'vulpea-find)
  (keymap-global-set "M-o n a" 'vulpea-buffer-alias-add)
)

(setq vulpea-db-sync-directories '("~/notes/"))

(setq vulpea-db-parse-method 'single-temp-buffer)

(vulpea-db-autosync-mode +1)

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