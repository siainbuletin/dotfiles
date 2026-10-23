;;; sp-vulpea-para.el --- Vulpea PARA agenda and capture wiring -*- lexical-binding: t; -*-

;;; Commentary:

;; VULPEA PARA SETUP

;;; Code:

(require 'vulpea-para)
;; (vulpea-para-setup-defaults)
;; How can you do the setup defaults manually, instead?

;; keep a cemetery (or anything) out of the agenda file list
(setq vulpea-para-agenda-files-filter
      (lambda (note)
        (not (vulpea-note-tagged-any-p note "cemetery"))))

;; the Area > Project prefix in the agenda
(setq org-agenda-prefix-format
      '((agenda . " %(vulpea-para-agenda-category 36) %?-12t %12s")
        (todo   . " %(vulpea-para-agenda-category 36) ")))

;; Wiring org-capture into vulpea-para
(dolist (template
         '(("t" "task" entry
            (file+headline "inbox.org" "Tasks")
            (function vulpea-para-capture-task-template))

           ("p" "project" entry
            (function vulpea-para-capture-project-target)
            (function vulpea-para-capture-project-template))))
  (add-to-list 'org-capture-templates template t))

(provide 'sp-vulpea-para)
;; sp-vulpea-para.el ends here.
