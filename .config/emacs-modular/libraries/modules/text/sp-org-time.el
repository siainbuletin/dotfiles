;; -*- lexical-binding: t; -*-
;; sp-org-time.el --- Settings for org-mode when dealing with time-related issues, specifically.

;;; Commentary:

;; This is also really important for task management, but it lives separately as 
;; an issue of scheduling, more specifically.

;;; Code:

;;; Org Pomodoro
;; Helps with time tracking
;; But how exactly can you trigger this we
(use-package org-pomodoro
  :if (and sp-load-extras (locate-library "org-pomodoro"))
  :commands org-pomodoro
  :init
  (progn
    (setq org-pomodoro-audio-player "/usr/bin/afplay")))

(use-package org-auto-scheduler
  :ensure (:host github :repo "SSD2019/org-auto-scheduler"))

;; Includes focus for checklists - plugs into org-auto-scheduler
(use-package org-focus-hud
  :bind ("C-c f" . org-focus-hud)
  :config
  ;; Optional: Customize refresh interval in seconds
  (setq org-focus-hud-refresh-interval 15)
  ;; Automatically follow newly clocked tasks (default t)
  (setq org-focus-hud-follow-active-clock t))

(provide 'org-time)