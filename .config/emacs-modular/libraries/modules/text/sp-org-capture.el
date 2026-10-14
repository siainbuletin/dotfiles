;;; -*- lexical-binding: t -*-

;;; Commentary:

;; This contains important code for later on utilisation of stuff like
;; journals for your work. There's the Lambda Emacs function for recording
;; the weather at a given point.
;;
;; org-capture should be well plugged into org-gtd to fit with the workflow.

;;; Code:

;;;; Capture mechanisms

;;;;; Org Directories
;; Set these if you're using org
;; the org-agenda thing should be adapted so that it reflects the
;; conventions set by vulpea-para
(setq org-default-notes-file (concat org-directory "inbox.org")
      org-agenda-files (list org-directory))


;; Org-capture note creation with Denote
(with-eval-after-load 'org-capture
  (add-to-list 'org-capture-templates
               '("n" "New note (with Denote)" plain
                 (file denote-last-path)
                 #'denote-org-capture
                 :no-save t
                 :immediate-finish nil
                 :kill-buffer t
                 :jump-to-captured t)))

;; Example note creation function
(defun lem-insert-header-and-time-property ()
  "Insert an org heading with a created time string property."
  (interactive)
  (insert "* ")
  (org-set-property "CREATED" (format-time-string "[%Y-%m-%d %T]")))

;;;; Bindings
(keymap-global-set "C-c c" #'org-capture)

(setq org-capture-templates
        '(
          ("l" "Listening log" entry
           (file+datetree "~/notes/inbox/listening-log.org")
           "* %U\n %i\n %a")

          ("i" "Idea or quick thought to take care of" entry
           (file "~/notes/inbox/thoughts-capture.org"))
))

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