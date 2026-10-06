;; -*- lexical-binding: t; -*-

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
  (org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "|" "DONE" "CNCL")))

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