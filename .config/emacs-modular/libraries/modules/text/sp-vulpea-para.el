;;; sp-vulpea-para.el --- Vulpea PARA agenda files -*- lexical-binding: t; -*-

;;; Commentary:

;; Vulpea PARA agenda wiring: which files are agenda files.

;;; Code:

(require 'vulpea-para)
(require 'sp-org-keywords)

(defun sp-vulpea-para-agenda-note-p (note)
  "Return non-nil when NOTE may be an agenda file.
Notes tagged \"cemetery\" are kept out."
  (not (vulpea-note-tagged-any-p note "cemetery")))

;; keep a cemetery (or anything) out of the agenda file list
(setq vulpea-para-agenda-files-filter #'sp-vulpea-para-agenda-note-p)

(setq vulpea-para-done-keywords (sp-org-keywords-done))
(setq vulpea-para-open-work-files '("inbox.org"))

(vulpea-para-agenda-mode 1)

(defun sp-vulpea-para-refresh-agenda-files ()
  "Set `org-agenda-files' from the database, ignoring errors."
  (condition-case err
      (vulpea-para-agenda-files-update)
    (error (message "[vulpea-para] agenda files not set yet: %s"
                    (error-message-string err)))))

(add-hook 'emacs-startup-hook
          (lambda ()
            (run-with-idle-timer 3 nil #'sp-vulpea-para-refresh-agenda-files)))

(provide 'sp-vulpea-para)
;; sp-vulpea-para.el ends here.
