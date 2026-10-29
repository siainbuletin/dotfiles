;;; sp-org-archive.el --- Org archiving and Palimpsest -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets where Org archives completed subtrees, adds a command to
;; archive every DONE and CANCELED task in the current file at once, and
;; configures `palimpsest', a minor mode that moves text out of the way instead
;; of deleting it.

;;; Code:

;; Tell org where to archive completed tasks. Wrapped in
;; with-eval-after-load because `org-directory' is defined by org
;; and is not bound at require time. Before Spec 02 this ran at
;; top-level and crashed module-load with `void-variable
;; org-directory' whenever the file was required before org was
;; loaded (e.g. a cold sandbox boot).
(with-eval-after-load 'org
  (setq org-archive-location (concat org-directory "/org-archive/archived.org::datetree/")))

;; Also tell org how to archive all the done tasks (DONE or CANCELED) in a file.
;; From https://changelog.complete.org/archives/9877-emacs-3-more-on-org-mode
;; Based on a stack overflow answer.
;; See https://stackoverflow.com/a/27043756
(defun lem-org-archive-done-tasks ()
  (interactive)
  (org-map-entries
   (lambda ()
     (org-archive-subtree)
     (setq org-map-continue-from (outline-previous-heading)))
   "/DONE" 'file)
  (org-map-entries
   (lambda ()
     (org-archive-subtree)
     (setq org-map-continue-from (outline-previous-heading)))
   "/CANCELED" 'file))

(provide 'sp-org-archive)

;;;; Palimpsest (make archive)
;; This minor mode for Emacs provides several strategies to remove text
;; without permanently deleting it. Namely, it provides the following capabilities:
;;
;; - Send selected text to the bottom of the buffer
;; - Send selected text to the top of the buffer
;; - Send selected text to a trash file

(use-package palimpsest
  :ensure t
  :diminish palimpsest-mode
  :hook ((markdown-mode org-mode) . palimpsest-mode)
  :custom
  (palimpsest-send-bottom "C-c C-z")
  (palimpsest-send-top "C-c C-a")
  :config
  (setq palimpsest-trash-file-suffix ".archive"))
