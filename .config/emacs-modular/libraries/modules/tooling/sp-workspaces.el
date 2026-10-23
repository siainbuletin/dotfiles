;;; sp-workspaces.el --- Tab-based workspaces and Projectile -*- lexical-binding: t; -*-

;;; Commentary:

;; Workspaces leveraging tab-bar and project.el. A "workspace" is just a tab
;; with an isolated set of buffers (see consult function). 𝛌-Emacs sets things
;; up so that these workspaces are nicely displayed out of the way in the echo
;; area rather than as visible tabs in the header tab-line at the top of the
;; frame.

;;; Code:

;;;; Workspace Functions

;;;;; Startup Workspaces
(defun sp--workspace-setup ()
  "Set up workspace at startup."
  ;; Add *Messages* and Dashboard to Tab \`Home\'
  (progn
    (tab-bar-rename-tab "Home")
    (when (get-buffer "*Messages*")
      (set-frame-parameter nil
                           'buffer-list
                           (cons (get-buffer "*Messages*")
                                 (frame-parameter nil 'buffer-list))))
    (when (get-buffer "Dashboard")
      (set-frame-parameter nil
                           'buffer-list
                           (cons (get-buffer "Dashboard")
                                 (frame-parameter nil 'buffer-list))))))

(add-hook 'after-init-hook #'sp--workspace-setup)
(defun sp-go-home ()
  (interactive)
  (tab-bar-switch-to-tab "Home"))

;;;;; Open Project in New Workspace
(defun sp-open-existing-project-and-workspace ()
  "Open a project as its own workspace"
  (interactive)
  (progn
    (tab-bar-new-tab)
    (call-interactively 'project-switch-project-open-file)
    (tab-bar-rename-tab (tabspaces--name-tab-by-project-or-default))
    (project-magit-dir)))

;;;;; Open Agenda as Workspace
(defun sp-open-agenda-in-workspace ()
  "Open agenda in its own workspace"
  (interactive)
  (if (member "Agenda" (tabspaces--list-tabspaces))
      (progn
        (tab-bar-switch-to-tab "Agenda")
        (switch-to-buffer "*Org Agenda*")
        (org-agenda-redo)
        (delete-other-windows))
    (progn
      (tab-bar-new-tab)
      (tab-bar-rename-tab "Agenda")
      (require 'org)
      (org-agenda-list))))

;;;;; Open emacs.d in Workspace
(defun sp-open-emacsd-in-workspace ()
  "Open emacs.d in its own workspace"
  (interactive)
  (require 'tabspaces)
  (if (member "emacs-modular-configuration" (tabspaces--list-tabspaces))
      (tab-bar-switch-to-tab "emacs-modular-configuration")
    (progn
      (tab-bar-new-tab)
      (tab-bar-rename-tab "emacs-modular-configuration")
      (find-file sp-library-dir)
      (split-window-right)
      (other-window 1)
      (project-magit-dir))))

;;;;; Open Notes in Workspace

(defun sp-open-notes-in-workspace ()
  "Open notes dir in its own workspace"
  (interactive)
  (require 'tabspaces)
  (if (member "Notes" (tabspaces--list-tabspaces))
      (tab-bar-switch-to-tab "Notes")
    (progn
      (tab-bar-new-tab)
      (tab-bar-rename-tab "Notes")
      (sp-denote-notebook))))

;;;;; Eshell Workspace
(defun sp-open-new-eshell-and-workspace ()
  "Open an eshell buffer in its own workspace"
  (interactive)
  (if (member "Eshell" (tabspaces--list-tabspaces))
      (tab-bar-switch-to-tab "Eshell")
    (progn
      (tab-bar-new-tab)
      (tab-bar-rename-tab "Eshell")
      (lem-eshell-home)
      (rename-buffer "eshell-workspace")
      (delete-other-windows))))

;;;;; Terminal Workspace
  (defun sp-vterm-workspace ()
    "Open vterm in home dir in its own workspace"
    (interactive)
    (let ((default-directory "~/"))
      (require 'multi-vterm)
      (multi-vterm-next)))

(defun sp-open-new-terminal-and-workspace ()
  "Open an empty buffer in its own workspace"
  (interactive)
  (require 'tabspaces)
  (if (member "Terminal" (tabspaces--list-tabspaces))
      (tab-bar-switch-to-tab "Terminal")
    (progn
      (tab-bar-new-tab)
      (tab-bar-rename-tab "Terminal")
      (sp-vterm-workspace)
      (delete-other-windows))))

;;;;; Open Mu4e Email in Workspace
(defun sp-open-email-in-workspace ()
  "Open mu4e email in its own workspace"
  (interactive)
  (require 'tabspaces)
  (if (member "Email" (tabspaces--list-tabspaces))
      (progn
        (tab-bar-switch-to-tab "Email")
        (cond ((get-buffer "*mu4e-headers*")
               (switch-to-buffer "*mu4e-headers*"))
              ((get-buffer " *mu4e-main*")
               (progn
                 (switch-to-buffer " *mu4e-main*")
                 (delete-other-windows)))
              (t (mu4e))))
    (progn
      (tab-bar-new-tab)
      (tab-bar-rename-tab "Email")
      (require 'org) ; need this for loading?
      (find-file (concat org-directory "mail.org"))
      (mu4e)
      (switch-to-buffer " *mu4e-main*"))))

;;;;; Open New Buffer & Workspace
;; This function is a bit weird; It creates a new buffer in a new workspace with a
;; dummy git project to give the isolation of buffers typical with a git project
;; I'm sure there is a more elegant way to do this but I don't know how :)
(defun sp-open-new-buffer-and-workspace ()
  "Open an empty buffer in its own workspace"
  (interactive)
  (tab-bar-new-tab)
  (tab-bar-rename-tab "New project")
  (let ((sp-project-temp-dir "/tmp/temp-projects/"))
    (progn
      (when (not (file-exists-p sp-project-temp-dir))
        (make-directory sp-project-temp-dir t))
      (when (not (file-exists-p (concat sp-project-temp-dir ".git/")))
        (magit-init sp-project-temp-dir))
      (when (not (file-exists-p (concat sp-project-temp-dir "temp")))
        (with-temp-buffer (write-file (concat sp-project-temp-dir "temp")))))
    (setq default-directory sp-project-temp-dir)
    (find-file (concat sp-project-temp-dir "temp"))))

;;;; Workspace Keybindings

(bind-keys :map lem+leader-map
  ("1" . sp-go-home)
  ("2" . sp-open-emacsd-in-workspace)
  ("3" . sp-open-agenda-in-workspace)
  ("4" . sp-open-notes-in-workspace)
  ("6" . sp-open-new-terminal-and-workspace)
  ("5" . sp-open-email-in-workspace))
(bind-key "N" #'sp-open-new-buffer-and-workspace 'project-prefix-map)

;; Including projectile as well for the sake of posterity (and trying things out - and moving from sp-projects - deprecated 2026.10.06)
;; OPTIONAL: ag is nice alternative to using grep with Projectile

(use-package projectile
  :ensure t
  :init
  (setq projectile-project-search-path
        (list (sp-path sp-documents-dir "writing/")
              "~/.config/"))
  
  :config
  (projectile-mode +1)
  
  :bind (("C-c p" . projectile-command-map)
         :map projectile-mode-map
         ("C-c C-p" . projectile-command-map)
         ("<f5>" . projectile-compile-project)
         ("S-<f5>" . projectile-test-project)
         ("<f6>" . projectile-run-project))

  :custom
  (projectile-project-search-path (list sp-git-dir sp-src-dir))
  (projectile-enable-caching t)
  )

(provide 'sp-workspaces)
;; sp-workspaces.el ends here.
