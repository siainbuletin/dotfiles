;; -*- lexical-binding: t; -*-
;; sp-org-time.el --- Settings for org-mode when dealing with time-related issues, specifically.

;;; Org Pomodoro
;; Helps with time tracking
(use-package org-pomodoro
  :if (and sp-load-extras (locate-library "org-pomodoro"))
  :commands org-pomodoro
  :init
  (progn
    (setq org-pomodoro-audio-player "/usr/bin/afplay")))

(provide 'org-time)