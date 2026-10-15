;; -*- lexical-binding: t; -*-

(use-package vui
  :ensure t)

(use-package vulpea
  :ensure (:wait t)

  :init
  ;; Vulpea derives its defaults from `org-directory'. Doom's :lang org
  ;; module sets it to ~/org/ - override here if your notes live elsewhere,
  ;; or set `vulpea-db-sync-directories' explicitly.
  
  :custom
  (vulpea-db-sync-directories (list "~/notes/" user-emacs-directory))

  :bind
  (("M-o f" . vulpea-find)
   :map org-mode-map
   ("M-o n a" . vulpea-buffer-alias-add))
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