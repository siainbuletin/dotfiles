;;;; sp-agenda-views.el --- Custom agenda views -*- lexical-binding: t; -*-

;;; Commentary:

;; Every custom agenda view in one place: the native views and the main PARA
;; view from `vulpea-para'.

;;; Code:

(require 'org-agenda)
(require 'vulpea-para)

;; Custom org-agenda views
;; Agenda Custom Commands
;; Configure custom agenda views
;; https://orgmode.org/manual/Storing-searches.html#Storing-searches
;; https://systemcrafters.cc/emacs-from-scratch/organize-your-life-with-org-mode/

(dolist (view
         '(("d" "Dashboard"
           ((agenda "" ((org-agenda-span 'day)))
           (tags-todo "DEADLINE=\"<today>\""
                     ((org-agenda-overriding-header "Due Today!")))
           (tags-todo "+DEADLINE<\"<+5d>\"+DEADLINE>\"<today>\""
                     ((org-agenda-overriding-header "Due Soon")))
           (todo "NEXT"
                ((org-agenda-overriding-header "Next Tasks")))
           (tags-todo "email" ((org-agenda-overriding-header "Email")))
             ))
        
           ("p" "Planning"
                ((tags-todo "+@planning"
                            ((org-agenda-overriding-header "Planning Tasks")))
                 (tags-todo "-{.*}"
                            ((org-agenda-overriding-header "Untagged Tasks")))
                 (todo ".*" ((org-agenda-files (list (sp-path sp-notes-dir "inbox.org")))
                             (org-agenda-overriding-header "Unprocessed Inbox Items")))))

           ("D" "Daily Agenda"
            ((agenda "" ((org-agenda-span 'day)
                         (org-deadline-warning-days 7)))
             (tags-todo "+PRIORITY=\"A\""
                        ((org-agenda-overriding-header "High Priority Tasks")))))

           ("n" "Next Tasks"
            ((todo "NEXT"
                ((org-agenda-overriding-header "Next Tasks")))))

           ("W" "Work Tasks" tags-todo "+work")

        ;; Low-effort next actions
        ("e" tags-todo "+TODO=\"NEXT\"+Effort<15&+Effort>0"
         ((org-agenda-overriding-header "Low Effort Tasks")
          (org-agenda-max-todos 20)
          (org-agenda-files org-agenda-files)))

        ("w" "Workflow Status"
         ((todo "WAIT"
                ((org-agenda-overriding-header "Waiting on External")
                 (org-agenda-files org-agenda-files)))
          (todo "REVIEW"
                ((org-agenda-overriding-header "In Review")
                 (org-agenda-files org-agenda-files)))
          (todo "PLAN"
                ((org-agenda-overriding-header "In Planning")
                 (org-agenda-todo-list-sublevels nil)
                 (org-agenda-files org-agenda-files)))
          (todo "BACKLOG"
                ((org-agenda-overriding-header "Project Backlog")
                 (org-agenda-todo-list-sublevels nil)
                 (org-agenda-files org-agenda-files)))
          (todo "READY"
                ((org-agenda-overriding-header "Ready for Work")
                 (org-agenda-files org-agenda-files)))
          (todo "ACTIVE"
                ((org-agenda-overriding-header "Active Projects")
                 (org-agenda-files org-agenda-files)))
          (todo "COMPLETED"
                ((org-agenda-overriding-header "Completed Projects")
                 (org-agenda-files org-agenda-files)))
          (todo "CANCELED"
                ((org-agenda-overriding-header "Cancelled Projects")
                 (org-agenda-files org-agenda-files)))))

           ("R" "Weekly Review"
            ((agenda ""
                     ((org-agenda-overriding-header "Completed Tasks")
                      (org-agenda-skip-function '(org-agenda-skip-entry-if 'nottodo 'done))
                      (org-agenda-span 'week)))

             (agenda ""
                     ((org-agenda-overriding-header "Unfinished Scheduled Tasks")
                      (org-agenda-skip-function '(org-agenda-skip-entry-if 'todo 'done))
                      (org-agenda-span 'week)))))

           ("r" "Research and university" tags-todo "+@research @reading @uni")

           ("u" "Untagged Tasks" tags-todo "-{.*}")))
  (add-to-list 'org-agenda-custom-commands view t))

;; Getting the custom agenda view for vulpea-para
(add-to-list 'org-agenda-custom-commands
             `(" " "Agenda"
               (,vulpea-para-agenda-cmd-refile
                ,vulpea-para-agenda-cmd-today
                ,vulpea-para-agenda-cmd-focus
                ,vulpea-para-agenda-cmd-stuck-projects
                ,vulpea-para-agenda-cmd-waiting
                ,(vulpea-para-agenda-cmd-current-quarter))))

(provide 'sp-agenda-views)
;; sp-agenda-views.el ends here
