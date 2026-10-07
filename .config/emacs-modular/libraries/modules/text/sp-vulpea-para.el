;; -*- lexical-binding: t; -*-
;; sp-vulpea-para.el

;;; Commentary:

;; VULPEA PARA SETUP

(require 'vulpea-para)
;; (vulpea-para-setup-defaults)
;; How can you do the setup defaults manually, instead?

;; keep a cemetery (or anything) out of the agenda file list
(setq vulpea-para-agenda-files-filter
      (lambda (note)
        (not (vulpea-note-tagged-any-p note "cemetery"))))

;; Getting the custom agenda view for vulpea-para
;; Should this be moved to the org-agenda file, since it's a special command?
(setq org-agenda-custom-commands
      `((" " "Agenda"
         (,vulpea-para-agenda-cmd-refile
          ,vulpea-para-agenda-cmd-today
          ,vulpea-para-agenda-cmd-focus
          ,vulpea-para-agenda-cmd-stuck-projects
          ,vulpea-para-agenda-cmd-waiting
          ,(vulpea-para-agenda-cmd-current-quarter)))))

;; the Area > Project prefix in the agenda
(setq org-agenda-prefix-format
      '((agenda . " %(vulpea-para-agenda-category 36) %?-12t %12s")
        (todo   . " %(vulpea-para-agenda-category 36) ")))

;;; Provide:
(provide 'sp-vulpea-para)
;; sp-vulpea-para.el ends here.