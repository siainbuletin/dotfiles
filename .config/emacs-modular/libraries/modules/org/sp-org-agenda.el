;; -*- lexical-binding: t; -*-

;;;; Org Agenda
;;;;; Agenda Settings
(use-package org-agenda
  :ensure nil
  :commands (org-agenda)
  :custom
  ;; Agenda logging
  (org-agenda-start-with-log-mode t)

  ;; from stack overflow https://stackoverflow.com/a/22900459/6277148
  ;; note that the formatting is nicer that just using '%b'
  (org-agenda-prefix-format
   '((agenda . " %-18c%?-10t ")
     (timeline . "  % s")
     (todo . " ")
     (tags . " ")
     (search . " %i %-12:c")))
)

;; Custom org-agenda views
;; Agenda Custom Commands
  ;; Configure custom agenda views
  ;; https://orgmode.org/manual/Storing-searches.html#Storing-searches
  ;; https://systemcrafters.cc/emacs-from-scratch/organize-your-life-with-org-mode/

  (org-agenda-custom-commands
   '(

     ))

(setq org-agenda-custom-commands
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
              (todo ".*" ((org-agenda-files '("~/notes/inbox.org"))
                          (org-agenda-overriding-header "Unprocessed Inbox Items")))))

        ("d" "Daily Agenda"
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

        ("w" "Weekly Review"
         ((agenda ""
                  ((org-agenda-overriding-header "Completed Tasks")
                   (org-agenda-skip-function '(org-agenda-skip-entry-if 'nottodo 'done))
                   (org-agenda-span 'week)))

          (agenda ""
                  ((org-agenda-overriding-header "Unfinished Scheduled Tasks")
                   (org-agenda-skip-function '(org-agenda-skip-entry-if 'todo 'done))
                   (org-agenda-span 'week)))))))

(setq org-agenda-custom-commands
      '(("r" "Research and university" tags-todo "+@research @reading @uni")))

(setq org-agenda-custom-commands
      '(("u" "Untagged Tasks" tags-todo "-{.*}")))

(setq org-agenda-custom-commands
    '(("p" "Planning"
       ((tags-todo "+@planning"
                    ((org-agenda-overriding-header "Planning Tasks")))
        (tags-todo "-{.*}"
                    ((org-agenda-overriding-header "Untagged Tasks")))))))

(setq org-agenda-custom-commands
      '(("d" "Daily Agenda"
         ((agenda "" ((org-agenda-span 'day)
                      (org-deadline-warning-days 7)))
          (tags-todo "+PRIORITY=\"A\""
                     ((org-agenda-overriding-header "High Priority Tasks")))))))

;;;;; Agenda Jump to Dashboard
(defun lem-jump-to-org-dashboard ()
  (interactive)
  (require 'org)
  (org-agenda nil "d"))

;;;;; Agenda Refresh
;; automatically refresh the agenda after adding a task
(defun lem-org-agenda-refresh ()
  (interactive)
  (when (get-buffer "*Org Agenda*")
    (with-current-buffer "*Org Agenda*"
      (org-agenda-redo)
      (message "[org agenda] refreshed!"))))
(add-hook 'org-capture-after-finalize-hook 'lem-org-agenda-refresh)

;; A wrapping menu that layered two-letter mnemonics over
;; `org-agenda-mode-map' (`ds' schedule, `dd' deadline, `vw' week, etc.)
;; was deleted in Spec 09. Native agenda bindings cover the most common
;; operations. If any of the deleted mnemonics prove load-bearing,
;; restore them as direct `org-agenda-mode-map' bindings (Spec 09 O7).
;; See git history for the prior implementation.

;;; Appearance of the agenda and rendering
;; Agenda styling
  (setq org-auto-align-tags nil)            ;; Don't align tags
  (setq org-agenda-tags-column 0)           ;; Put tags next to heading
  (setq org-agenda-breadcrumbs-separator "  ")
  (setq org-agenda-block-separator " ")     ;; No default block seperator
  (setq org-agenda-time-grid
   '((daily today require-timed)
     (800 1000 1200 1400 1600 1800 2000)
     " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"))
  (setq org-agenda-current-time-string
   "–––––––––––––– Now")

(use-package elegant-agenda-mode
  :ensure t)

;; Display properties
  (setq org-agenda-tags-column org-tags-column)
  (setq org-agenda-show-inherited-tags nil)
  (setq org-agenda-window-setup 'only-window)
  (setq org-agenda-restore-windows-after-quit t)

;;; CONFIGURING THE FUNCTIONALITY
;; Scheduling with org-agenda

  (setq org-agenda-skip-scheduled-if-done t)
  (setq org-agenda-skip-timestamp-if-done t)
  (setq org-agenda-todo-ignore-scheduled 'future)
  (setq org-agenda-todo-ignore-deadlines 'far)
  (setq org-agenda-sorting-strategy
   '((agenda time-up) (todo time-up) (tags time-up) (search time-up)))
  (setq calendar-week-start-day 1) ;; Start week on Monday

;;; EXTENSIONS FOR ORG-AGENDA
(use-package org-super-agenda
:after org
  :ensure (:wait t)
:init
(setq org-super-agenda-date-format "%A (%e)"
      org-super-agenda-groups
      '((:name "Accomplishments"
         :todo ("DONE" "CANCELED")
         :order 4)
        (:name "End of Day"
         :habit t
         :order 2)
        (:name "Uncompleted Work"
         :todo "DOING"
         :scheduled past
         :order 0)
        (:name "Today's Tasks"
         :date today
         :order 1)
        (:name "Today's Tasks"
         :scheduled today
         :order 1)
        (:name "Future Work"
         :todo "TODO"
         :scheduled future
         :order 3))))

(provide 'sp-org-agenda)