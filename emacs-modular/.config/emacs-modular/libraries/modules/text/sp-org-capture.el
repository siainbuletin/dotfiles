;;; sp-org-capture.el --- Org capture templates and capture frames -*- lexical-binding: t; -*-

;;; Commentary:

;; This contains important code for later on utilisation of stuff like
;; journals for your work. There's the Lambda Emacs function for recording
;; the weather at a given point.
;;
;; org-capture should be well plugged into org-gtd to fit with the workflow.
;;
;; Every capture template is defined here and nowhere else (modules do not
;; add their own), and the only inbox is ~/notes/inbox.org.

;;; Code:

;;;; Capture mechanisms

;;;;; Org Directories
;; The only inbox
(setq org-default-notes-file (concat org-directory "inbox.org"))

;; Example note creation function
(defun lem-insert-header-and-time-property ()
  "Insert an org heading with a created time string property."
  (interactive)
  (insert "* ")
  (org-set-property "CREATED" (format-time-string "[%Y-%m-%d %T]")))

;;;; Bindings
(keymap-global-set "C-c c" #'org-capture)

(setq org-capture-templates
      `(("t" "Task" entry
         (file+headline "inbox.org" "Tasks")
         (function vulpea-para-capture-task-template))

        ("i" "Idea or quick thought" entry
         (file+headline "inbox.org" "Thoughts")
         "* %?\n%U")

        ("p" "PARA project" entry
         (function vulpea-para-capture-project-target)
         (function vulpea-para-capture-project-template))

        ("I" "Issue" entry
         (function sp-org-issues-capture-target)
         (function sp-org-issues-capture-template))

        ("n" "New note (with Denote)" plain
         (file denote-last-path)
         #'denote-org-capture
         :no-save t
         :immediate-finish nil
         :kill-buffer t
         :jump-to-captured t)

        ("l" "Listening log" entry
         (file+datetree ,(sp-path sp-notes-dir "inbox/listening-log.org"))
         "* %U\n %i\n %a")))

;; See also sp-vulpea.el for task capturing

;;;;; Create Capture Frame
;; have these functions available for server
(defun lem-activate-capture-frame ()
  "run org-capture in capture frame"
  (progn
    (require 'org)
    (select-frame-by-name "capture")
    (switch-to-buffer (get-buffer-create "new"))
    (org-capture)))

;;;;; Weather Capture Frame
(defun lem-weather-journal-capture ()
  (interactive)
  (progn
    (require 'org)
    (select-frame-by-name "capture")
    (switch-to-buffer (get-buffer-create "new"))
    (lem-org-journal)
    (lem-insert-weather)))

(provide 'sp-org-capture)

(setq org-capture-templates
              '(
                ("f" "Fleeting note"
                 item
                 (file+headline org-default-notes-file "Notes")
                 "- %?")

                ;; I want to replace this with something that doesn't rely on denote
                ("p" "Permanent note" plain
                 (file denote-last-path)
                 #'denote-org-capture
                 :no-save t
                 :immediate-finish nil
                 :kill-buffer t
                 :jump-to-captured t)

                ("t" "New task" entry
                 (file+headline org-default-notes-file "Tasks")
                 "* TODO %i%?"))
)
