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
  (:map org-mode-map
   ("M-o n a" . vulpea-buffer-alias-add)
   ("M-o n n" . org-id-get-create))
)

(setq vulpea-db-sync-directories
      (seq-filter #'file-directory-p
                  (list sp-notes-dir user-emacs-directory sp-writing-projects)))

;; The database is rebuilt from the notes, so it lives in `var/' (Git ignores
;; it) and not in the config folder, where Vulpea puts it by default.
(setq vulpea-db-location (expand-file-name "vulpea.db" sp-var-dir))

(setq vulpea-db-parse-method 'single-temp-buffer)

;; Enable autosync a few idle seconds after start-up, not during init, and let
;; vulpea scan in the background: it lists the files in a subprocess and queues
;; them, and the queue parses only the files whose content changed.  Opening a
;; note, the dashboard included, starts nothing.
(setq vulpea-db-sync-scan-on-enable 'background)

(defcustom sp-vulpea-autosync-delay 10
  "Idle seconds after start-up before `vulpea-db-autosync-mode' is turned on.
The scan runs in the background (see `vulpea-db-sync-scan-on-enable'), so a
short wait is enough: it only lets start-up finish and Emacs become usable."
  :type 'number
  :group 'spcustom)

;; Vulpea builds a candidate cache of every note for `vulpea-find' and
;; `vulpea-insert' as soon as autosync is on, reading all rows of the database
;; in 500-note chunks on the main thread (`vulpea-select-cache-prewarm').  With
;; about 9,800 files that kept Emacs busy for minutes.  Without the prewarm the
;; cache is built at the first `vulpea-find' or `vulpea-insert', which pauses once.
(setq vulpea-select-cache-prewarm nil)

(defvar sp-vulpea--autosync-timer nil
  "Idle timer that will call `sp-vulpea-start-autosync', or nil.")

(defun sp-vulpea-start-autosync ()
  "Turn on `vulpea-db-autosync-mode' once, if it is not on yet.
The vault is scanned in the background.  Safe to call any number of times."
  (when (timerp sp-vulpea--autosync-timer)
    (cancel-timer sp-vulpea--autosync-timer))
  (setq sp-vulpea--autosync-timer nil)
  (unless (bound-and-true-p vulpea-db-autosync-mode)
    (let ((started (float-time)))
      (message "[vulpea] starting autosync; changed files are indexed in the background...")
      (vulpea-db-autosync-mode +1)
      (message "[vulpea] autosync started in %.2fs" (- (float-time) started)))))

(defun sp-vulpea-schedule-autosync ()
  "Start `sp-vulpea-start-autosync' after `sp-vulpea-autosync-delay' idle seconds."
  (unless (or (bound-and-true-p vulpea-db-autosync-mode)
              (timerp sp-vulpea--autosync-timer))
    (setq sp-vulpea--autosync-timer
          (run-with-idle-timer sp-vulpea-autosync-delay nil
                               #'sp-vulpea-start-autosync))))

;; Init is over when `after-init-time' is set; then the hook has already run.
(if after-init-time
    (sp-vulpea-schedule-autosync)
  (add-hook 'emacs-startup-hook #'sp-vulpea-schedule-autosync))

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
