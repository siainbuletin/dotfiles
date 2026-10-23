;;; sp-org-agenda.el --- Org agenda settings and views -*- lexical-binding: t; -*-

;;; Commentary:

;; Configures Org's agenda: the `C-c o a' key, the prefix format of agenda
;; lines, visual styling of the time grid and tags, scheduling and sorting
;; rules, the list of agenda files, and the `org-super-agenda' grouping. It
;; also adds a command to jump to the daily view, automatic refresh of the
;; agenda after a capture, and an alphapapa recipe for showing an agenda
;; limited to the current subtree or region.

;;; Code:

(keymap-global-set "C-c o a" 'org-agenda)

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

;;;; Org other agenda (yibie)
(use-package org-other-agenda
  :ensure (:host github :repo "yibie/org-other-agenda"))

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

;; org-ql requires org-super-agenda, so it has to be declared after it:
;; the other way round, Elpaca queues org-super-agenda as a dependency first
;; and warns that the explicit declaration came too late.
(use-package org-ql
 :ensure t)

(setq org-agenda-files
        (list
         (sp-path sp-notes-dir "area/")
         (sp-path sp-notes-dir "inbox/") ; this is for tasks that I never actually got to deal with
))

;;; Display an agenda file for the current subtree
;; source: https://github.com/alphapapa/unpackaged.el#agenda-for-subtree-or-region
(defvar org-agenda-overriding-header)
(defvar org-agenda-sorting-strategy)
(defvar org-agenda-restrict)
(defvar org-agenda-restrict-begin)
(defvar org-agenda-restrict-end)

;;;###autoload
(defun sp-org-agenda-current-subtree-or-region (only-todos)
  "Display an agenda view for the current subtree or region.
 With prefix, display only TODO-keyword items."
  (interactive "P")
  (let ((starting-point (point))
        header)
    (with-current-buffer (or (buffer-base-buffer (current-buffer))
                             (current-buffer))
      (if (use-region-p)
          (progn
            (setq header "Region")
            (put 'org-agenda-files 'org-restrict (list (buffer-file-name (current-buffer))))
            (setq org-agenda-restrict (current-buffer))
            (move-marker org-agenda-restrict-begin (region-beginning))
            (move-marker org-agenda-restrict-end
                         (save-excursion
                           ;; If point is at beginning of line, include
                           ;; heading on that line by moving forward 1.
                           (goto-char (1+ (region-end)))
                           (org-end-of-subtree))))
        ;; No region; restrict to subtree.
        (save-excursion
          (save-restriction
            ;; In case the command was called from an indirect buffer, set point
            ;; in the base buffer to the same position while setting restriction.
            (widen)
            (goto-char starting-point)
            (setq header "Subtree")
            (org-agenda-set-restriction-lock))))
      ;; NOTE: Unlike other agenda commands, binding `org-agenda-sorting-strategy'
      ;; around `org-search-view' seems to have no effect.
      (let ((org-agenda-sorting-strategy '(priority-down timestamp-up))
            (org-agenda-overriding-header header))
        (org-search-view (if only-todos t nil) "*"))
      (org-agenda-remove-restriction-lock t)
      (message nil))))

(provide 'sp-org-agenda)
;; sp-org-agenda.el ends here
