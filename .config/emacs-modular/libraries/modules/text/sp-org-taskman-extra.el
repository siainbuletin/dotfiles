;; -*- lexical-binding: t; -*-
;; sp-org-taskman-extra.el --- Task management components needed to make the system work

;;; Code:

;; Settings related specifically to task management done through org-mode.
;; Org-agenda is being treated in a separate file. This is because org-agenda
;; has a lot of appearance issues that should be sorted up separately, and
;; it's a different component of such a task management system.

;;; Commentary:
;;;; What are the TODO keywords that you're actually using?
(setq org-todo-keywords
      '((sequence "TODO(t)" "PROG(p)" "DONE(d)")))

;;;; Set up the org tags
(setq org-tag-alist
      '(;; Circumstances
        ("@home" . ?H)
        ("@uni" . ?U)
      ("@waiting" . ?W)

        ;; Devices
        ("@computer" . ?C)
        ("@phone" . ?P)

        ;; Activities
        ("@planning" . ?p)
        ("@configuration" . ?c)
        ("@writing" . ?w)
        ("@reading" . ?s)
        ("@music" . ?m)
        ("@research" . ?r)
        ("@errands" . ?e)

      ;; Effort estimate
      ("deep" . ?d)
      ("shallow" . ?h) ; I wanted to write this as ?sh but it only accepts one symbol
      ("time-eater" . ?t)))

;;;; Setting up the priorities
(setq org-priority-highest 1
      org-priority-lowest 5
      org-priority-default 4)

(defun my-mark-as-project ()
"This function makes sure that the current heading has
(1) the tag :project:
(2) has property COOKIE_DATA set to \"todo recursive\"
(3) has any TODO keyword and
(4) a leading progress indicator"
    (interactive)
    (org-toggle-tag "project" 'on)
    (org-set-property "COOKIE_DATA" "todo recursive")
    (org-back-to-heading t)
    (let* ((title (nth 4 (org-heading-components)))
           (keyword (nth 2 (org-heading-components))))
       (when (and (bound-and-true-p keyword) (string-prefix-p "[" title))
           (message "TODO keyword and progress indicator found")
           )
       (when (and (not (bound-and-true-p keyword)) (string-prefix-p "[" title))
           (message "no TODO keyword but progress indicator found")
           (forward-whitespace 1)
           (insert "NEXT ")
           )
       (when (and (not (bound-and-true-p keyword)) (not (string-prefix-p "[" title)))
           (message "no TODO keyword and no progress indicator found")
           (forward-whitespace 1)
           (insert "NEXT [/] ")
           )
       (when (and (bound-and-true-p keyword) (not (string-prefix-p "[" title)))
           (message "TODO keyword but no progress indicator found")
           (forward-whitespace 2)
           (insert "[/] ")
           )
       )
)

(require 'org-inlinetask)

(setq org-hierarchical-todo-statistics nil)

;;;; TODO faces

(use-package hl-todo
  :ensure t
  :config
  (setq hl-todo-keyword-faces
    `(("TODO"   . ,(face-foreground 'warning))
      ("FIXME"  . ,(face-foreground 'error))
      ("NOTE"   . ,(face-foreground 'success))))
  (global-hl-todo-mode 1))

(use-package consult-todo
  :ensure t
  :init
  (defconst consult-todo--narrow
    '((?t . "TODO")
      (?f . "FIXME")
      (?n . "NOTE"))
    "Mapping of narrow and keywords.")
  ;; :config
  ;; (evil-define-key '(normal) 'global "g t" '("jump todos" . consult-todo))
  )

;; Deep task management dependencies (and understanding how projects really work)
(use-package org-edna
  :ensure t
  :config
  (org-edna-mode))

;;; Vulpea PARA and its settings should be added here (with the intention of going back to that file)

;;; Org-gtd package
(use-package org-gtd
  :ensure (:wait t)
  :after org
  :demand t
  :init
  ;; Suppress upgrade warnings (must be set before package loads)
  (setq org-gtd-update-ack "4.0.0")
  :custom
  ;; Where org-gtd will keep its files (defaults to ~/gtd/)
  (org-gtd-directory "~/notes/area/org-gtd/")

  ;; Configure TODO keyword states (options like "TODO(t)" or "DONE(d!)" are fine)
  ;; TODO keyword are configured elsewhere

  ;; Map GTD semantic states to your keywords
  (org-gtd-keyword-mapping '((todo . "TODO")
                             (next . "NEXT")
                             (wait . "WAIT")
                             (canceled . "CNCL")))

  ;; Add org-gtd files to your agenda
  ;; (org-agenda-files (list org-gtd-directory)) ;; this errors out so it's commented

  :config
  (org-edna-mode 1)

  :bind 
  (("C-c d c" . org-gtd-capture)
   ("C-c d e" . org-gtd-engage)
   ("C-c d p" . org-gtd-process-inbox)
   ("C-c d n" . org-gtd-show-all-next)
   ("C-c d s" . org-gtd-reflect-stuck-projects)

   :map org-gtd-clarify-mode-map
   ("C-c c" . org-gtd-organize) ;; (only works in clarify buffers)

   ;; Quick actions on tasks in agenda views (optional but recommended)
   :map org-agenda-mode-map
   ("C-c ." . org-gtd-agenda-transient)))

;;;; Org TODO Keywords
(customize-set-variable 'org-todo-keywords
                        '((sequence "TODO(t)" "DOING(g)" "NEXT(n)" "WAITING(w@/!)" "MAYBE(m)" "SOMEDAY(s)" "|" "DONE(d)")
                          (sequence "WAITING(w@/!)" "HOLD(h@/!)" "|" "CANCELED(c@/!)")))

(org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "|" "DONE" "CNCL")))

;;;; Org Inline Tasks
(use-package org-inlinetask :ensure nil
  :commands org-inlinetask-insert-task)

;; Creating different TODO keywords for better readability
(setq org-confirm-babel-evaluate nil
        org-hide-emphasis-markers t
        org-todo-keywords '((sequence "TODO" "WAITING" "DOING" "|" "DONE" "CANCELLED"))
        org-modern-todo-faces '(("TODO" :foreground "white" :background "darkgreen" :weight bold)
                                ("DOING" :foreground "white" :background "orange" :weight bold)
                                ("WAITING" :foreground "white" :background "blue")))

(provide 'sp-org-taskman-extra)