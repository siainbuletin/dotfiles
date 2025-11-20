(org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (org . t)
     (R . t))
)

;; This file has been generated from an org-mode file (=main.org=)
;; DO NOT EDIT DIRECTLY, IT WILL BE OVERWRITTEN

;; Installing elpaca
(defvar elpaca-installer-version 0.11)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-repos-directory (expand-file-name "repos/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca--activate-package)))

(let* ((repo  (expand-file-name "elpaca/" elpaca-repos-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;;; Configure elpaca use-package support
(elpaca elpaca-use-package
        ;; Enable use-package :ensure support for Elpaca.
        (elpaca-use-package-mode)
        ;; Assume :elpaca t unless otherwise specified.
        (setq elpaca-use-package-by-default t))

;;When installing a package used in the init file itself,
;;e.g. a package which adds a use-package key word,
;;use the :wait recipe keyword to block until that package is installed/configured.
;;For example:
;;(use-package general :ensure (:wait t) :demand t)

(elpaca-wait)

(setq initial-major-mode 'org-mode)
      ; initial-scratch-message (concat "#+title: Emacs Writing Studio\n"
; "#+subtitle: Scratch Buffer\n\n"
;					"The text in this buffer is not saved "
;					"when exiting Emacs!\n\n"))

(setq load-path (cons "~/.config/emacs-include/sia-modules" load-path))

(load-file (concat (file-name-as-directory user-emacs-directory)
                   "sia-ews-functions.el"))

(sia-missing-executables
 '(("gs" "mutool")
   "pdftotext"
   "soffice"
   "zip"
   "ddjvu"
   "curl"
   ("mpg321" "ogg123" "mplayer" "mpv" "vlc")
   ("grep" "ripgrep")
   ("convert" "gm")
   "dvipng"
   "latex"
   "hunspell"
   "git"))

(set-default-coding-systems 'utf-8)     ; Default to utf-8 encoding
(prefer-coding-system       'utf-8)     ; Add utf-8 at the front for automatic detection.
(set-terminal-coding-system 'utf-8)     ; Set coding system of terminal output
(set-keyboard-coding-system 'utf-8)     ; Set coding system for keyboard input on TERMINAL
(set-language-environment "English")    ; Set up multilingual environment

(defun reload-init-file ()
  (interactive)
  (load-file user-init-file))

;; set shortcut for the reloading
(keymap-global-set "<f5>" 'reload-init-file)

(defun jcs-execute-all-buffers ()
  (interactive)
  (let ((org-confirm-babel-evaluate nil))
    (org-babel-execute-buffer)))

(setq-default cursor-type 'bar) ;; this will make the cursor similar to other text editors

;; WINDOW FUNCTIONS
(setq-default frame-title-format '("✨ %b 🌊")) ;; Make the window title to be the buffer name

;; Redrawing the display when there's graphical errors
(global-set-key (kbd "<f6>") 'redraw-display)

(use-package vundo
  :ensure t)

(use-package anzu
    :ensure t

    :config
; (anzu-mode) ; would this even work?
)

(electric-pair-mode 1)

(use-package dwim-shell-command
  :ensure t
  :bind (([remap shell-command] . dwim-shell-command)
         :map dired-mode-map
         ([remap dired-do-async-shell-command] . dwim-shell-command)
         ([remap dired-do-shell-command] . dwim-shell-command)
         ([remap dired-smart-shell-command] . dwim-shell-command)))

;; SOUNDS
(setq ring-bell-function 'ignore) ;; Disable the bell sound

;; BUFFER FUNCTIONS
(global-auto-revert-mode t) ;; If the file has changed on the disk, then update the buffer as well

(use-package casual
  :ensure t)

(use-package counsel)

(use-package consult)

(use-package deadgrep)

(use-package counsel-fd
  :ensure t
  :after counsel)

(use-package vertico
  :demand t
  :custom
  (vertico-count 13) ; Number of candidates to display
  (vertico-resize t)
  (vertico-cycle t) ; Once passing the last candidate in the list, it will loop back to the first
  :config
  (vertico-mode))

(use-package marginalia
  :init
  (marginalia-mode)
  (setf (alist-get 'elpaca-info marginalia-command-categories) 'elpaca))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides
   '((file (styles partial-completion)))))

(use-package company)

(use-package corfu)
(use-package corfu-prescient)

(use-package embark
  :ensure t
  :bind
  (("C-." . embark-act)
   ("M-." . embark-dwim)
   ("C-h B" . embark-bindings))

  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :ensure t)



(use-package p-search
  :ensure (:host github :repo "zkry/p-search"))

;; (use-package avy) ;; is this still useful for anything?
(use-package helm)
;; (use-package ivy) (Deprecated, this package doesn't seem to be in usage anymore)

(use-package prescient)
(use-package company-prescient)
(use-package ivy-prescient)
(use-package selectrum-prescient)
(use-package vertico-prescient)

(use-package which-key
    :ensure t

    :config
    (which-key-mode)

    :custom
    (which-key-max-description-length 40)
    (which-key-lighter nil)
    (which-key-sort-order 'which-key-description-order)
    (which-key-mode +1)
    :init
    (which-key-add-key-based-replacements
"C-c w"   "Emacs Writing Studio"
    "C-c w b" "Bibliographic"
    "C-c w d" "Denote"
    "C-c w m" "Multimedia"
    "C-c w s" "Spelling and Grammar"
    "C-c w t" "Themes"
    "C-c w x" "Explore"))

(global-unset-key (kbd "C-z"))

(keymap-global-set "C->" 'indent-rigidly-right-to-tab-stop) ; Indent selection by one tab length
(keymap-global-set "C-<" 'indent-rigidly-left-to-tab-stop)  ; De-indent selection by one tab length

(use-package hydra
  :ensure t)

(use-package use-package-hydra
  :ensure t)

;; Set Dired listing switches for more minimalist output
(setq dired-listing-switches "-aghov --group-directories-first")

;;; Recent files
  (use-package recentf
    :ensure nil
    :config
    (recentf-mode t)
    (run-at-time nil (* 5 60) 'recentf-save-list)
    :custom
    (recentf-max-saved-items 50))

(use-package vc-backup)

(setq-default backup-directory-alist
    `(("." . ,(expand-file-name "backups/" user-emacs-directory)))
      make-backup-files t
      vc-make-backup-files t ; Won't create backup of files that are already under version control
      backup-by-copying t ; Avoid symlinks
      delete-old-versions t
      delete-by-moving-to-trash t ; This makes sure that the files aren't permanently deleted
      kept-new-versions 6
      kept-old-versions 3
      version-control t)

;;; Lockfiles unfortunately cause more pain than benefit
(setq create-lockfiles nil)

;;; Bookmarks
  (use-package bookmark
    :ensure nil
    :custom
    (bookmark-save-flag 1)
    :bind
    ("C-x r D" . bookmark-delete))

(setq org-hide-emphasis-markers t)
(setq org-hide-leading-stars t)
(setq org-startup-with-inline-images t)
;; (setq org-image-actual-width '(450))
(setq org-pretty-entities t) ; What makes them pretty?\
(setq org-auto-align-tags nil)
; (setq org-tags-column 0) ; What exactly does this do? Wouldn't it be more correct to set it as nil instead of 0?
(setq org-src-fontify-natively t)

(setq org-agenda-breadcrumbs-separator " ) ")

(setq org-fontify-quote-and-verse-blocks t)

(use-package org-appear
  :hook
  (org-mode . org-appear-mode))

(use-package org-modern
  :after org
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :config
  (setq
   org-auto-align-tags t
   org-tags-column 0
   org-fold-catch-invisible-edits 'show-and-error
   org-special-ctrl-a/e t
   org-insert-heading-respect-content t

   ;; Don't style the following
   org-modern-tag nil
   org-modern-priority nil
   org-modern-todo nil
   org-modern-table nil

   ;; Agenda styling
   org-agenda-tags-column 0
   org-agenda-block-separator ?─
   org-agenda-time-grid
   '((daily today require-timed)
     (800 1000 1200 1400 1600 1800 2000)
     " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄")
   org-agenda-current-time-string
   "⭠ now ─────────────────────────────────────────────────"))

(defface org-checkbox-done-text
  '((t (:foreground "#71696A" :strike-through t)))
  "Face for the text part of a checked org-mode checkbox.")

(font-lock-add-keywords
 'org-mode
 `(("^[ \t]*\\(?:[-+*]\\|[0-9]+[).]\\)[ \t]+\\(\\(?:\\[@\\(?:start:\\)?[0-9]+\\][ \t]*\\)?\\[\\(?:X\\|\\([0-9]+\\)/\\2\\)\\][^\n]*\n\\)"
    1 'org-checkbox-done-text prepend))
 'append)

(use-package spacious-padding
  :ensure t)

;; These are the default values, but I keep them here for visibility.
(setq spacious-padding-widths
      '( :internal-border-width 15
         :header-line-width 4
         :mode-line-width 6
         :tab-width 4
         :right-divider-width 30
         :scroll-bar-width 8
         :fringe-width 8))

(setq spacious-padding-subtle-frame-lines
      `( :mode-line-active 'default
         :mode-line-inactive vertical-border))

;; (spacious-padding-mode 1)

;; Set a key binding if you need to toggle spacious padding.
(define-key global-map (kbd "<f8>") #'spacious-padding-mode)

(setq org-support-shift-select t)

(use-package text-mode
  :ensure nil
  :hook
  (text-mode . visual-line-mode) ; Would this function enable text mode in all text buffers, and not just org-mode?
  :init
  (delete-selection-mode t)
  :custom
  (sentence-end-double-space nil)
  (scroll-error-top-bottom t)
  (save-interprogram-paste-before-kill t))

(add-hook 'org-mode-hook #'org-num-mode)

(electric-indent-mode 0)

(add-hook 'before-save-hook
          'delete-trailing-whitespace) ;; On file save, delete the trailing whitespace --- THIS BASICALLY WORKS LIKE LINTING

(use-package goggles
  :hook
  ((prog-mode text-mode) . goggles-mode)
  :config
  (setq-default goggles-pulse t)) ;; set to nil to disable pulsing

(show-paren-mode 1) ;; Show the closing parens by default --- I actually don't think that this works
(delete-selection-mode 1) ;; The selected text will be overwritten when you start typing

(setq org-link-search-must-match-exact-headline nil)

(setq counsel-outline-display-style 'title)

(setq org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id)

(defun zz/make-id-for-title (title)
  "Return an ID based on TITLE."
  (let* ((new-id (replace-regexp-in-string "[^[:alnum:]]" "-" (downcase title))))
    new-id))

(defun zz/org-custom-id-create ()
  "Create and store CUSTOM_ID for current heading."
  (let* ((title (or (nth 4 (org-heading-components)) ""))
         (new-id (zz/make-id-for-title title)))
    (org-entry-put nil "CUSTOM_ID" new-id)
    (org-id-add-location new-id (buffer-file-name (buffer-base-buffer)))
    new-id))

(defun zz/org-custom-id-get-create (&optional where force)
  "Get or create CUSTOM_ID for heading at WHERE.

If FORCE is t, always recreate the property."
  (org-with-point-at where
    (let ((old-id (org-entry-get nil "CUSTOM_ID")))
      ;; If CUSTOM_ID exists and FORCE is false, return it
      (if (and (not force) old-id (stringp old-id))
          old-id
        ;; otherwise, create it
        (zz/org-custom-id-create)))))

;; Now override counsel-org-link-action
  (defun counsel-org-link-action (x)
    "Insert a link to X.

X is expected to be a cons of the form (title . point), as passed
by `counsel-org-link'.

If X does not have a CUSTOM_ID, create it based on the headline
title."
    (let* ((id (zz/org-custom-id-get-create (cdr x))))
      (org-insert-link nil (concat "#" id) (car x))))

(setq org-todo-keywords
      '((sequence "TODO(t)" "PROG(p)" "DONE(d)")))

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
      ; ("shallow" . ?h)
      ("time-eater" . ?t)))

(setq org-agenda-files (quote ("~/Documents/tracking")))

(global-set-key (kbd "C-c o a") #'org-agenda)

(setq org-log-done 'time
      org-log-redeadline 'time
      org-log-reschedule 'time)

(setq org-priority-highest 1
      org-priority-lowest 5
      org-priority-default 4)

(use-package org-super-agenda
:after org
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

(setq org-agenda-custom-commands
      '(("p" "Planning"
             ((tags-todo "+@planning"
                         ((org-agenda-overriding-header "Planning Tasks")))
              (tags-todo "-{.*}"
                         ((org-agenda-overriding-header "Untagged Tasks")))
              (todo ".*" ((org-agenda-files '("~/Notes/Inbox.org"))
                          (org-agenda-overriding-header "Unprocessed Inbox Items")))))

        ("d" "Daily Agenda"
         ((agenda "" ((org-agenda-span 'day)
                      (org-deadline-warning-days 7)))
          (tags-todo "+PRIORITY=\"A\""
                     ((org-agenda-overriding-header "High Priority Tasks")))))

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

(require 'org-inlinetask)

(use-package org-edna
  :ensure t)

; (org-edna-mode) ; this shows up as symbol's function is void

(use-package dashboard
  :ensure t
  :config
  (add-hook 'elpaca-after-init-hook #'dashboard-insert-startupify-lists)
  (add-hook 'elpaca-after-init-hook #'dashboard-initialize)
  (dashboard-setup-startup-hook))

(setq dashboard-banner-logo-title "Welcome to Emacs Dashboard")
(setq dashboard-startup-banner '3)
(setq dashboard-center-content t)
(setq dashboard-vertically-center-content t)
(setq dashboard-show-shortcuts t)

(setq dashboard-items '((recents   . 5)
                        (bookmarks . 5)
                        (projects  . 5)
                        (agenda    . 5)
                        (registers . 5)))

(setq dashboard-startupify-list '(dashboard-insert-banner
                                  dashboard-insert-newline
                                  dashboard-insert-banner-title
                                  dashboard-insert-newline
                                  dashboard-insert-navigator
                                  dashboard-insert-newline
                                  dashboard-insert-init-info
                                  dashboard-insert-items
                                  dashboard-insert-newline
                                  dashboard-insert-footer))

(setq dashboard-item-shortcuts '((recents   . "r")
                                 (bookmarks . "m")
                                 (projects  . "p")
                                 (agenda    . "a")
                                 (registers . "e")))

(setq dashboard-icon-type 'all-the-icons)  ; use `all-the-icons' package

(setq dashboard-set-heading-icons t)
(setq dashboard-set-file-icons t)

(add-to-list 'dashboard-items '(agenda) t)

;;; Define many keys in many key maps
(use-package denote
  :ensure t
  :defer t

  :config
  (denote-rename-buffer-mode)
  (setq denote-file-type 'org) ; default is org
  (setq denote-history-completion-in-prompts nil)
  (setq denote-rename-confirmations '(modify-file-name add-front-matter))
  (setq denote-sort-keywords t)
  (setq denote-known-keywords
        '("academic-journal"
          "blog-post"
          "book"
          "booksection"
          "concept"
          "course"
          "current"
          "docs"
          "group"
          "institution"
          "journal-article"
          "language"
          "library"
          "music"
          "package"
          "person"
          "process"
          "studyplace"
          "thesis"
          "workflow"
          "zettel"))
  ; (denote-link-description-function #'ews-denote-link-description-title-case) ; I need to actually rename this to my own function starting with sia-

  :hook
  (dired-mode . denote-dired-mode)

  :bind
  ( ;; this block here is taken from Prot's video on use-package
   :map global-map
    ; ("C-c n n" . denote) ; I prefer using denote-open-or-create instead
    ("C-c n o" . denote-open-or-create)
    ("C-c n r" . denote-rename-file)
    ("C-c n f" . denote-rename-file-using-front-matter)

    :map text-mode-map
    ("C-c n i" . denote-link-or-create) ; "insert" mnemonic
    ("C-c n I" . denote-add-links)

    :map dired-mode-map
    ("C-c C-d C-i" . denote-link-dired-marked-notes)
    ("C-c C-d C-r" . denote-dired-rename-marked-files)

    ;; these are copied directly from the Emacs Writing Studio configuration
    ("C-c w d b" . denote-find-backlink)
    ("C-c w d d" . denote-date)
    ("C-c w d l" . denote-find-link)
    ("C-c w d i" . denote-link-or-create)
    ("C-c w d k" . denote-rename-file-keywords)))

(add-hook 'dired-mode-hook #'denote-dired-mode-in-directories)

(setq denote-save-buffers t)

(use-package denote-org
  :ensure t
  :after denote

  :custom
  ;; `denote-org-link-to-heading' controls the behavior of
  ;; `org-store-link': setting to id makes it insert an ID in the
  ;; PROPERTIES drawer
  ;;
  ;; (denote-org-store-link-to-heading 'context)
  (denote-org-store-link-to-heading 'id))

(use-package denote-markdown
  :ensure t
  :after denote)

(use-package denote-explore
  :bind
  (;; Statistics
   ("C-c w x c" . denote-explore-count-notes)
   ("C-c w x C" . denote-explore-count-keywords)
   ("C-c w x b" . denote-explore-barchart-keywords)
   ("C-c w x e" . denote-explore-barchart-filetypes)
   ;; Random walks
   ("C-c w x r" . denote-explore-random-note)
   ("C-c w x l" . denote-explore-random-link)
   ("C-c w x k" . denote-explore-random-keyword)
   ("C-c w x x" . denote-explore-random-regex)
   ;; Denote Janitor
   ("C-c w x d" . denote-explore-identify-duplicate-notes)
   ("C-c w x z" . denote-explore-zero-keywords)
   ("C-c w x s" . denote-explore-single-keywords)
   ("C-c w x o" . denote-explore-sort-keywords)
   ("C-c w x w" . denote-explore-rename-keyword)
   ;; Visualise denote
   ("C-c w x n" . denote-explore-network)
   ("C-c w x v" . denote-explore-network-regenerate)
   ("C-c w x D" . denote-explore-barchart-degree)))

(use-package denote-journal
  :after denote
  :custom
  (denote-journal-keyword "log")
  (denote-journal-directory (expand-file-name "~/Documents/notes/journal"))
  (denote-journal-title-format 'day-date-month-year)
                          )

(use-package denote-sequence
  :ensure t)

(use-package denote-menu
  :ensure t)

(defun denote-org--merge-get-file-data-without-front-matter (file)
  "Return data of FILE without its front matter.
Data is of the form (TITLE FILETAGS CONTENTS), all of which are strings.

Assume that front matter is a contiguous region of lines starting with
#+ from the beginning of the buffer and ending in an empty line."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (goto-char (point-min))
    (let ((title (org-get-title))
          (tags (org-get-tags))
          (contents (progn
                      (when-let* ((beginning (when (re-search-forward "^#\\+" nil t)
                                               (line-beginning-position)))
                                  (end (re-search-forward "^$" nil t)))
                        (delete-region beginning end))
                      (string-trim (buffer-string)))))
      (list title tags contents))))

;;;###autoload
(defun denote-org-merge-notes (target-file other-file)
  "Append OTHER-FILE to TARGET-FILE and delete OTHER-FILE.
When called interactively TARGET-FILE is the current file.
TARGET-FILE and OTHER-FILE are both derived from `org-mode'.

Abort the operation if OTHER-FILE has backlinks."
  (interactive
   (list
    buffer-file-name
    (denote-file-prompt
     "\\.org"
     (format "FILE to merge into `%s'" (propertize buffer-file-name 'face 'denote-faces-prompt-current-name)))))
  (dolist (file (list target-file other-file))
    (with-current-buffer (find-file-noselect file)
      (unless (derived-mode-p 'org-mode)
        (error "The file `%s' is not using `org-mode'" file))))
  (pcase-let ((`(,title ,tags ,contents) (denote-org--merge-get-file-data-without-front-matter other-file)))
    (if (denote--file-has-backlinks-p other-file)
        (error "The other file `%s' has backlinks; aborting the merge" other-file)
      (with-current-buffer (find-file-noselect target-file)
        (goto-char (point-max))
        (unless (looking-at "^$")
          (insert "\n\n"))
        (insert (format "* MERGED: %s :%s:" title (string-join tags ":")))
        (insert "\n\n")
        (insert contents))
      (when (y-or-n-p (format "Merged `%s'; now DELETE it and its buffer? " (propertize other-file 'face 'denote-faces-prompt-current-name)))
        (kill-buffer (get-file-buffer other-file))
        (delete-file other-file)))))

(defvar my-denote-to-agenda-regexp "_project"
  "Denote file names that are added to the agenda.
See `my-add-denote-to-agenda'.")

(defun my-denote-add-to-agenda ()
  "Add current file to the `org-agenda-files', if needed.
The file's name must match the `my-denote-to-agenda-regexp'.

Add this to the `after-save-hook' or call it interactively."
  (interactive)
  (when-let* ((file (buffer-file-name))
              ((denote-file-is-note-p file))
              ((string-match-p my-denote-to-agenda-regexp (buffer-file-name))))
    (add-to-list 'org-agenda-files file)))

;; This will add the file automatically
(add-hook 'after-save-hook #'my-denote-add-to-agenda)

(defun my-denote-remove-from-agenda ()
  "Remove current file from the `org-agenda-files'.
See `my-denote-add-to-agenda' for how to add files to the Org
agenda."
  (interactive)
  (when-let* ((file (buffer-file-name))
              ((string-match-p my-denote-to-agenda-regexp (buffer-file-name))))
    (setq org-agenda-files (delete file org-agenda-files))))

(use-package markdown-mode
  :ensure t)

(use-package markdown-toc
  :ensure t
  :after markdown-mode)

(use-package consult-notes
  :ensure t
  :after consult
  :custom
  (consult-notes-denote-display-keywords-indicator "_")
  :bind
  (("C-c w d f" . consult-notes)
   ("C-c w d g" . consult-notes-search-in-all-notes))
  :init
  (consult-notes-denote-mode))

(use-package obsidian
  :config
  (global-obsidian-mode t)
  (obsidian-backlinks-mode t)

  :custom
  (obsidian-directory "~/Documents/vault")
  ;; Default location for new notes from `obsidian-capture'
  (obsidian-inbox-directory "Inbox")
  ;; Useful if you're going to be using wiki links
  ;; is this setting taken from markdown-mode?
  (markdown-enable-wiki-links t)

  :bind (:map obsidian-mode-map
              ;; Create note
              ("C-c C-n" . obsidian-capture)
              ;; If you prefer you can use `obsidian-insert-wikilink'
              ("C-c C-l" . obsidian-insert-link)
              ;; Open file pointed to by link at point
              ("C-c C-o" . obsidian-follow-link-at-point)
              ;; Open a note note from vault
              ("C-c C-p" . obsidian-jump)
              ;; Follow a backlink for the current file
              ("C-c C-b" . obsidian-backlink-jump)
              )
  )

(use-package obsidian-pcache
  :ensure (obsidian-pcache :host github :repo "knu/obsidian-pcache.el"))

(use-package org-sidebar
  :ensure t)

(defun org-ref-make-org-link-cite-key-visible (&rest _)
  "Make the org-ref cite link visible in descriptive links."

  (save-match-data
    (let ((s (match-string 1))
      (beg (match-beginning 0))
      (end (match-end 0))
      (cite-re (format "^\\(%s:\\)"
               (regexp-opt (-sort
                    (lambda (a b)
                      (> (length a) (length b)))
                    org-ref-cite-types))))
      cite-type)

      (when (and s (string-match cite-re s))
    (setq cite-type (match-string 1 s))
    (remove-text-properties beg end
                '(invisible))
    (add-text-properties
     beg end
     `(face (:foreground ,org-ref-cite-color)))))))

(advice-add 'org-activate-bracket-links :after #'org-ref-make-org-link-cite-key-visible)

(use-package org-ql
  :ensure t)

(use-package markdown-mode
  :ensure t)

(use-package markdown-toc
  :ensure t
  :after markdown-mode)

(use-package consult-notes
  :ensure t
  :after consult
  :custom
  (consult-notes-denote-display-keywords-indicator "_")
  :bind
  (("C-c w d f" . consult-notes)
   ("C-c w d g" . consult-notes-search-in-all-notes))
  :init
  (consult-notes-denote-mode))

(use-package obsidian
  :config
  (global-obsidian-mode t)
  (obsidian-backlinks-mode t)

  :custom
  (obsidian-directory "~/Documents/vault")
  ;; Default location for new notes from `obsidian-capture'
  (obsidian-inbox-directory "Inbox")
  ;; Useful if you're going to be using wiki links
  ;; is this setting taken from markdown-mode?
  (markdown-enable-wiki-links t)

  :bind (:map obsidian-mode-map
              ;; Create note
              ("C-c C-n" . obsidian-capture)
              ;; If you prefer you can use `obsidian-insert-wikilink'
              ("C-c C-l" . obsidian-insert-link)
              ;; Open file pointed to by link at point
              ("C-c C-o" . obsidian-follow-link-at-point)
              ;; Open a note note from vault
              ("C-c C-p" . obsidian-jump)
              ;; Follow a backlink for the current file
              ("C-c C-b" . obsidian-backlink-jump)
              )
  )

(use-package obsidian-pcache
  :ensure (obsidian-pcache :host github :repo "knu/obsidian-pcache.el"))

(use-package org-sidebar
  :ensure t)

(defun org-ref-make-org-link-cite-key-visible (&rest _)
  "Make the org-ref cite link visible in descriptive links."

  (save-match-data
    (let ((s (match-string 1))
      (beg (match-beginning 0))
      (end (match-end 0))
      (cite-re (format "^\\(%s:\\)"
               (regexp-opt (-sort
                    (lambda (a b)
                      (> (length a) (length b)))
                    org-ref-cite-types))))
      cite-type)

      (when (and s (string-match cite-re s))
    (setq cite-type (match-string 1 s))
    (remove-text-properties beg end
                '(invisible))
    (add-text-properties
     beg end
     `(face (:foreground ,org-ref-cite-color)))))))

(advice-add 'org-activate-bracket-links :after #'org-ref-make-org-link-cite-key-visible)

(use-package org-ql
  :ensure t)

(use-package bibtex
  :ensure nil
  :custom
  (bibtex-user-optional-fields
   '(("keywords" "Keywords to describe the entry" "")
     ("file"     "Relative or absolute path to attachments" "" )))
  (bibtex-align-at-equal-sign t)
  :config
  (sia-bibtex-register)
  :bind
  (("C-c w b r" . sia-bibtex-register))
)

(use-package ebib)

(defvar do.refs/db-dirs nil
  "A list of paths to directories containing all my bibtex databases")

(defvar do.refs/pdf-dir nil
  "The path to the directory containing the PDF files. The file
  for the entry with key <key> is stored as <key>.pdf.")

(defvar do.refs/notes-dir nil
  "The path to the directory containing my notes for the
  references. The note for the item with key <key> is stored in
  this folder as <key>.org")

(defvar do.refs/pdf-download-dir nil
  "The path to the temporary directory to which we download PDF
  files.")

(defvar do.refs/file-assoc `(("pdf" . "open")
                           ("docx" . "open")
                           ("doc" . "open")
                           ("pptx" . "open")
                           ("ppt" . "open"))
  "The executables used to open related files from the reference database.")

(defun do.refs/get-db-file-list ()
  "Get the list of all the bib files containing my bib database."
  (mapcan (lambda (dir) (directory-files dir t "\\.bib\\'"))
          do.refs/db-dirs))

(defun do.refs/update-db-file-list ()
  "Update the list of bib files."
  (interactive)
  (let ((db-list (do.refs/get-db-file-list)))
    (setq reftex-default-bibliography db-list)
    (setq bibtex-completion-bibliography db-list)
    (setq ebib-preload-bib-files db-list)))

(setq ebib-file-search-dirs sia-bibtex-files)
;; (setq ebib-notes-directory "~/Documents/ebib-literature-notes")
(setq ebib-preload-bib-files (do.refs/get-db-file-list))

(setq bibtex-autokey-year-length 4)
  (setq bibtex-autokey-titleword-separator "-")
  (setq bibtex-autokey-name-year-separator "-")
  (setq bibtex-autokey-year-title-separator "-")
  (setq bibtex-autokey-titleword-length 8)
  (setq bibtex-autokey-titlewords 3)
  (setq bibtex-autokey-titleword-ignore ;; I took "On" out of this
        '("A" "An" "The" "Eine?" "Der" "Die" "Das" "[^[:upper:]].*" ".*[^[:upper:][:lower:]0-9].*"))

(defun do.refs/ebib-import-from-clipboard ()
    "Attempt to import the contents in the kill ring/clipboard into `ebib'."
    (interactive)
    (with-temp-buffer
      (yank)
      (ebib-import)
      (call-interactively #'ebib)))

(defun do.refs/ebib-add-newest-from-downloads (&optional file-extension)
    "Add the most recent file from `do.refs/pdf-download-dir' to the ebib entry at point."
    (interactive)
    ;; pull out the most recent file from ~/Downloads with the .pdf extension.
    (let ((newest-file (let ((dir-files (directory-files-and-attributes do.refs/pdf-download-dir)))
                         (caar (sort
                                (if (not file-extension)
                                    ;; the newest file from the download directory
                                    (mapcan (lambda (x)
                                              (let ((file-name (concat (file-name-as-directory do.refs/pdf-download-dir) (car x))))
                                                (when (file-regular-p file-name) (cons x nil))))
                                            dir-files)
                                  ;; all files with a certain extension
                                  (mapcan (lambda (x) (when (string-equal (file-name-extension (nth 0 x)) file-extension) (cons x nil)))
                                          dir-files))
                                ;; sort by date
                                (lambda (x y) (not (time-less-p (nth 6 x) (nth 6 y)))))))))
      (if newest-file
          ;; https://nullprogram.com/blog/2017/10/27/
          ;; need to override `read-file-name' because ebib normally prompts us for the file to import
          (let ((fpath (concat (file-name-as-directory do.refs/pdf-download-dir) newest-file))
                (bibkey (ebib--get-key-at-point)))
            (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) fpath)))
              (let ((current-prefix-arg '(4))) ;; C-u (to keep from removing original file)
                (call-interactively #'ebib-import-file)))
            (message "[Ebib] [Dennis] Imported %s for %s" fpath bibkey))
        (message "[Ebib] [Dennis] No files from %s imported." do.refs/pdf-download-dir))))

(use-package citar
  :ensure t
  :defer t ; what's the point of defering in this case?
  :custom
  (org-cite-global-bibliography sia-bibtex-files)
  (org-cite-insert-processor 'citar)
  (org-cite-follow-processor 'citar)
  (org-cite-activate-processor 'citar)
  (citar-bibliography sia-bibtex-files)

  :bind
  (("C-c w b o" . citar-open))
  (:map org-mode-map :package org ("C-c b" . #'org-cite-insert))
  :hook
  (LaTeX-mode . citar-capf-setup)
  (org-mode . citar-capf-setup)
  (markdown-mode . citar-capf-setup))

(use-package citar-embark
  :ensure t
  :after (citar embark)
  :no-require
  :config (citar-embark-mode)
  )

(setq citar-at-point-function 'embark-act)

(use-package citar-denote
  :custom
  (citar-open-always-create-notes t)
  :init
  (citar-denote-mode)
  :bind
  (("C-c w b c" . citar-create-note)
   ("C-c w b n" . citar-denote-open-note)
   ("C-c w b x" . citar-denote-nocite)
   :map org-mode-map
   ("C-c w b k" . citar-denote-add-citekey)
   ("C-c w b K" . citar-denote-remove-citekey)
   ("C-c w b d" . citar-denote-dwim)
   ("C-c w b e" . citar-denote-open-reference-entry)))

(setq citar-denote-title-format 'author-year-title)

(setq citar-denote-title-format-authors '2)

(setq citar-denote-keyword "litnote")

(setq citar-denote-subdir "litnotes")

(setq denote-templates
      '((report . "* Some heading\n\n* Another heading")
      (biblio . ,(concat "Creator: %^{author-or-editor}"
                         "\n\n"
                         "* Basics"
                         "\n\n" ; this will add a new line
                         "* Related bibliography"
                         "insert an org dynamic block here"))))

(require 'oc-natbib)
(require 'oc-csl)

(setq org-cite-global-bibliography sia-bibtex-files
      org-cite-insert-processor 'citar
      org-cite-follow-processor 'citar
      org-cite-activate-processor 'citar)

(use-package biblio
  :bind
  (("C-c w b b" . sia-bibtex-biblio-lookup)))

(use-package org-ref)
  ;;(advice-add #'completing-read-multiple :override #'consult-completing-read-multiple)
  ;;(require 'org-ref)
  ;;(require 'doi-utils) ; this was taken from a different config

(use-package helm-bibtex)

(setq org-ref-default-bibliography '("~/Documents/bibliography/master.bib")
      org-ref-pdf-directory "~/Documents/literature/")

(setq bibtex-completion-bibliography
      '("~/Documents/bibliography/master.bib"
        "~/Documents/bibliography/thesis.bib"
        "~/Documents/bibliography/marx.bib"
        "~/Documents/bibliography/hci.bib"
        "~/Documents/bibliography/aesthetics.bib"
        "~/Documents/bibliography/hegel-prezentare.bib"
        "~/Documents/bibliography/modernitate.bib")
        bibtex-completion-library-path '("~/Documents/literature/")
        bibtex-completion-notes-path "~/Documents/org/"
        bibtex-completion-notes-template-multiple-files "* ${author-or-editor}, ${title}, ${journal}, (${year}) :${=type=}: \n\nSee [[cite:&${=key=}]]\n")

;; Automatically generating BibTeX keys
(require 'bibtex)

(setq bibtex-autokey-year-length 4
      bibtex-autokey-name-year-separator "-"
      bibtex-autokey-year-title-separator "-"
      bibtex-autokey-titleword-separator "-"
      bibtex-autokey-titlewords 2
      bibtex-autokey-titlewords-stretch 1
      bibtex-autokey-titleword-length 5)

(define-key bibtex-mode-map (kbd "H-b") 'org-ref-bibtex-hydra/body)

(use-package consult-recoll)

(use-package pdf-tools
  :ensure t
  :init
  (pdf-tools-install))

(setopt pdf-view-continuous nil)

(use-package pdftotext
  :ensure (:host github :repo "tecosaur/pdftotext.el"))

(use-package org-noter
  :after (org pdf-view)
  :bind (:map org-noter-notes-mode-map
              ("C-M-i" . org-noter-insert-dynamic-block))
  :custom
  (org-noter-notes-search-path (list org-directory))
  (org-noter-supported-modes '(doc-view-mode pdf-view-mode))
  (org-noter-separate-notes-from-heading t)
  :config
  (require 'pdf-macs)
  ;; (defun org-noter-pdf--show-arrow ())
  )

(use-package djvu) ; apparently needed for org-noter

(setq org-noter-auto-save-last-location t)

(setq org-noter-highlight-selected-text t)

(use-package org-pdftools
  :hook (org-mode . org-pdftools-setup-link))

(use-package org-noter-pdftools
  :after org-noter
  :config
  ;; Add a function to ensure precise note is inserted
  (defun org-noter-pdftools-insert-precise-note (&optional toggle-no-questions)
    (interactive "P")
    (org-noter--with-valid-session
     (let ((org-noter-insert-note-no-questions (if toggle-no-questions
                                                   (not org-noter-insert-note-no-questions)
                                                 org-noter-insert-note-no-questions))
           (org-pdftools-use-isearch-link t)
           (org-pdftools-use-freepointer-annot t))
       (org-noter-insert-note (org-noter--get-precise-info)))))

  ;; fix https://github.com/weirdNox/org-noter/pull/93/commits/f8349ae7575e599f375de1be6be2d0d5de4e6cbf
  (defun org-noter-set-start-location (&optional arg)
    "When opening a session with this document, go to the current clocation.
With a prefix ARG, remove start location."
    (interactive "P")
    (org-noter--with-valid-session
     (let ((inhibit-read-only t)
           (ast (org-noter--parse-root))
           (location (org-noter--doc-approx-location (when (called-interactively-p 'any) 'interactive))))
       (with-current-buffer (org-noter--session-notes-buffer session)
         (org-with-wide-buffer
          (goto-char (org-element-property :begin ast))
          (if arg
              (org-entry-delete nil org-noter-property-note-location)
            (org-entry-put nil org-noter-property-note-location
                           (org-noter--pretty-print-location location))))))))
  (with-eval-after-load 'pdf-annot
    (add-hook 'pdf-annot-activate-handler-functions #'org-noter-pdftools-jump-to-note)))

(use-package calibredb
  :defer t
  :config
  (setq calibredb-root-dir "~/Documents/calibre-library")
  (setq calibredb-db-dir "~/Documents/calibre-library/metadata.db")
  )

(use-package projectile
  :ensure t
  :init
  (setq projectile-project-search-path
        '("~/writing/"
          "~/.config/"
          "~/playground"))
  :config
  ;; These are the configurations to use on Linux for projectile
  (define-key projectile-mode-map (kbd "C-c C-p") 'projectile-command-map)
  (global-set-key (kbd "C-c p") 'projectile-command-map)
  (projectile-mode +1))

(use-package ag
  :ensure t)

(use-package olivetti
  :ensure t
  :demand t
  :bind
  (("C-c w o" . sia-olivetti)))

(use-package binder
  :ensure t)

(use-package org-pandoc-import
  :ensure (:host github
               :repo "tecosaur/org-pandoc-import"
               :files ("*.el" "filters" "preprocessors")))

(use-package ox-typst
  :after org)

(use-package ox-pandoc
  :ensure t)

;; default options for all output formats
(setq org-pandoc-options '((standalone . t)))
;; cancel above settings only for 'docx' format
(setq org-pandoc-options-for-docx '((standalone . nil)))
;; special settings for beamer-pdf and latex-pdf exporters
(setq org-pandoc-options-for-beamer-pdf '((pdf-engine . "xelatex")))
(setq org-pandoc-options-for-latex-pdf '((pdf-engine . "pdflatex")))
;; special extensions for markdown_github output
(setq org-pandoc-format-extensions '(markdown_github+pipe_tables+raw_html))

(use-package helpful
  :bind
  (("C-h f" . helpful-function)
   ("C-h x" . helpful-command)
   ("C-h k" . helpful-key)
   ("C-h v" . helpful-variable)))

(use-package lexic
  :ensure t)

(use-package elpher)

(use-package elfeed-org
  :config
  (elfeed-org)
  :custom
  (rmh-elfeed-org-files
   (list (concat (file-name-as-directory (getenv "HOME"))
                       "elfeed.org"))))

(use-package cond-let)

(use-package transient
  :ensure t
  :bind
  (:map global-map
      ("M-s-d" . denote-transient))

  :config
  (transient-define-prefix denote-transient () "Denote dispatch"
    [["Note creation (d)"
      ("dd" "new note" denote)
      ("dj" "new or existing journal entry" denote-journal-new-or-existing-entry)
      ("dn" "open or new" denote-open-or-create)
      ("dt" "new specifying date and time" denote-date)
      ("ds" "create in subdirectory " denote-subdirectory)]
     ["Reviewing (r)"
      ("rd" "notes this day" aw/notes-this-day)]
     ["Folgezettel (f)"
      ("fc" "create parent/child/sibling" denote-sequence)
      ("ff" "find parent/child/sibling notes" denote-sequence-find)
      ("fr" "reparent (adopt) current note into another sequence" denote-sequence-reparent)
      ("fp" "find previous sibling" denote-sequence-find-previous-sibling :transient t)
      ("fn" "find next sibling" denote-sequence-find-next-sibling :transient t)]]

    [["Bookkeeping (b)"
      ("br" "prompt and rename" denote-rename-file)
      ("bf" "rename with frontmatter" denote-rename-file-using-front-matter)
      ("bk" "modify keywords" denote-rename-file-keywords)]
     ["Linking (l)"
      ("li" "insert link" denote-link)
      ("lh" "insert link to org heading" denote-org-link-to-heading)
      ("lb" "show backlinks" denote-backlinks)
      ("lg" "visit backlink" denote-find-backlink)
      ("lo" "org backlink block" denote-org-dblock-insert-backlinks)]]

    [["Searching (s)"
      ("sd" "deft" deft)
      ("sn" "consult-notes" consult-notes)
      ("ss" "consult-notes search" consult-notes-search-in-all-notes)]]))

(use-package magit
  :ensure t
  :after transient)



(use-package tramp
  :config
  (add-to-list 'tramp-methods
               '("yadm"
                 (tramp-login-program "yadm")
                 (tramp-login-args (("enter")))
                 (tramp-login-env (("SHELL") ("/bin/sh")))
                 (tramp-remote-shell "/bin/sh")
                 (tramp-remote-shell-args ("-c")))))

(defun yadm ()
  (interactive)
  (magit-status "/yadm::"))

(when (display-graphic-p)
  (context-menu-mode 1)
  (tool-bar-mode -1)
  (scroll-bar-mode -1)
  (horizontal-scroll-bar-mode -1)
  (setq visible-bell 1
        frame-inhibit-implied-resize t))

(use-package doom-modeline
   :init
   (setq doom-modeline-buffer-encoding nil ; irrelevant for me but shows UTF-8

       ;; identifying the modes we're in
         doom-modeline-major-mode-color-icon t
       doom-modeline-minor-modes t ; keep identification to the current modes

       ;; this works on the buffer state
         doom-modeline-buffer-state-icon t
         doom-modeline-buffer-modification-icon t
       doom-modeline-file-name-style 'auto

       ;; size and rendering of the modeline
       doom-modeline-height 25
       doom-modeline-bar-width 8
       doom-modeline-window-width-limit 85

       ;; navigating the file
       doom-modeline-percent-position t ; is this for the percentage of the position within the file?
       doom-modeline-support-imenu t
       doom-modeline-percent-position nil

       ;; integrating with project management
       doom-modeline-project-detection 'auto

       ;; other
         doom-modeline-lsp-icon t) ; this doesn't currently work as I'm not working with code projects
   (doom-modeline-mode 1))

(use-package pulsar
  :ensure t
  :custom
  (pulsar-face 'pulsar-generic)
  (pulsar-delay 0.15)

  :bind ("<f8>" . pulsar-pulse-line)

  :config
  (dolist (built-in-function '(recenter-top-bottom move-to-window-line-top-bottom reposition-window
                               bookmark-jump other-window delete-window delete-other-windows
                               forward-page backward-page scroll-up-command scroll-down-command
                               ha-new-window tab-new tab-close tab-next org-next-visible-heading
                               org-previous-visible-heading org-forward-heading-same-level
                               org-backward-heading-same-level outline-backward-same-level
                               outline-forward-same-level outline-next-visible-heading
                               outline-previous-visible-heading outline-up-heading))
    (add-to-list 'pulsar-pulse-functions built-in-function))

  (when (fboundp 'winner-undo)
    (add-to-list 'pulsar-pulse-functions 'winner-undo)
    (add-to-list 'pulsar-pulse-functions 'winner-redo))

  (when (fboundp 'winum-select-window-1)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-1)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-2)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-3)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-4)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-5)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-6)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-7)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-8)
    (add-to-list 'pulsar-pulse-functions 'winum-select-window-9))

  (when (fboundp 'aw-delete-window)
    (add-to-list 'pulsar-pulse-functions 'aw-move-window)
    (add-to-list 'pulsar-pulse-functions 'aw-swap-window)
    (add-to-list 'pulsar-pulse-functions 'aw-copy-window)
    (add-to-list 'pulsar-pulse-functions 'aw-split-window-vert)
    (add-to-list 'pulsar-pulse-functions 'aw-split-window-horz)
    (add-to-list 'pulsar-pulse-functions 'aw-split-window-fair)
    (add-to-list 'pulsar-pulse-functions 'aw-delete-window))

  (when (fboundp 'evil-window-right)
    (add-to-list 'pulsar-pulse-functions 'evil-window-right)
    (add-to-list 'pulsar-pulse-functions 'evil-window-left)
    (add-to-list 'pulsar-pulse-functions 'evil-window-up)
    (add-to-list 'pulsar-pulse-functions 'evil-window-down))

  (pulsar-global-mode 1))

(use-package mixed-pitch
  :config
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-property-value)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-special-keyword)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'font-lock-comment-face)
  :hook (text-mode . mixed-pitch-mode))

(defvar ha-fixed-font
  (when window-system
    (or
     ;; Choose favorite installed font from an ordered list (by preference):
     (seq-first
      (seq-filter (lambda (font) (when (x-list-fonts font) font))
                  '("Cascadia Code NF"         ; Microsoft's offical has Nerds
                    "CaskaydiaCove Nerd Font"  ; Best Nerd-based font
                    "NanumGothicCoding"        ; Winner of codingfont.com
                    "Hack Nerd Font"           ; no litagures!?
                    "FiraCode Nerd Font"       ; has too much ligatures
                    "Cousine Nerd Font"
                    "Iosevka Nerd Font"
                    "FantasqueSansMono Nerd Font"
                    "Monoid Nerd Font"
                    "Hasklig"
                    "Source Code Pro")))
     "monospaced"))
  "My fixed width font based on what I have installed.")

(defvar ha-variable-font
  (when window-system
    (or
     (seq-first
      (seq-filter (lambda (font) (when (x-list-fonts font) font))
                  '("SN Pro"
                    "Atkinson Hyperlegible"
                    "Literata"
                    "XCharter"
                    "Charter"
                    "Serif")))
     (warn "Cannot find a Serif Font.  Install Source Sans Pro."))))

(defvar ha-variable-header-font
  (when window-system
    (or
     (seq-first
      (seq-filter (lambda (font) (when (x-list-fonts font) font))
                  '("SN Pro" "Overpass" "DejaVu Sans"
                    "Verdana" "Overpass"
                    "Source Sans Pro"
                    "Lucida Grande"
                    "Sans Serif")))
     (warn "Cannot find a Sans Serif Font.  Install Source Sans Pro."))))

(defun ha-set-favorite-font-size (size)
  "Set the default font size as well as equalize the fixed and variable fonts."

  (let ((fixed-font (format "%s-%d" ha-fixed-font size))
        (prop-font  (format "%s-%d" ha-variable-font size)))
    (when (fboundp 'mixed-pitch-mode)
      (mixed-pitch-mode -1))

    ;; The font specification is the name and the size ... odd enough I guess:
    (set-face-attribute 'default nil :font fixed-font)
    (set-face-attribute 'fixed-pitch nil :font fixed-font :inherit 'default
                        :height 'unspecified)
    (set-face-attribute 'variable-pitch nil :font prop-font :inherit 'default
                        :height 'unspecified)))

(use-package fontaine
  :ensure t
  :init
  (fontaine-mode))

(setq fontaine-presets
      '((regular)

    (prose
     :inherit regular
     ; :line-spacing 1.5 ; I can't actually use this because it messes up all of the minibuffer and makes the lines way too large to be readable
     )

        (large
     :inherit regular
         :default-height 150
         :fixed-pitch-height 1.0
         :variable-pitch-height 1.05)

        (presentation)

        (t
         ;; This is for fallback properties (the default value)
         :default-family "Aporetic Serif Mono"
         :default-weight regular
         :default-height 200

         :fixed-pitch-family "Fira Code"
         :fixed-pitch-weight nil ; falls back to :default-weight
         :fixed-pitch-height 1.05

         :fixed-pitch-serif-family "Aporetic Serif Mono"
         :fixed-pitch-serif-weight nil
         :fixed-pitch-serif-slant nil
         :fixed-pitch-serif-width nil
         :fixed-pitch-serif-height 1.05

         :variable-pitch-family "iA Writer Quattro"
         :variable-pitch-weight nil
         :variable-pitch-height 1.0

         :mode-line-active-family nil
         :mode-line-active-weight nil
         :mode-line-active-slant nil
         :mode-line-active-width nil
         :mode-line-active-height 1.0

         :header-line-family "Gill Sans"
         :header-line-weight nil
         :header-line-slant nil
         :header-line-width nil
         :header-line-height 1.0

         :line-number-family nil
         :line-number-weight nil
         :line-number-slant nil
         :line-number-width nil
         :line-number-height 1.0

         :tab-bar-family nil
         :tab-bar-weight nil
         :tab-bar-slant nil
         :tab-bar-width nil
         :tab-bar-height 1.0

         :tab-line-family nil
         :tab-line-weight nil
         :tab-line-slant nil
         :tab-line-width nil
         :tab-line-height 1.0

         :bold-family nil ; this will just use whatever the underlying face has
         :bold-weight bold

         :italic-family "Source Code Pro"
         :italic-slant italic
         :line-spacing 1)))

(setq fontaine-set-preset 'regular)

(setq prettify-symbols-unprettify-at-point 'right-edge)

(global-prettify-symbols-mode +1)
(prettify-symbols-mode +1)

(add-hook 'text-mode-hook (lambda () (setq-local line-spacing 0.1)))

(use-package all-the-icons
  :if (display-graphic-p))

(use-package nerd-icons
  :ensure t
  :custom
  ;; The Nerd Font you want to use in GUI defaults to fixed-font:
  (nerd-icons-font-family "Symbols Nerd Font Mono"))

(use-package nerd-icons-ibuffer
  :ensure t
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

(defun font-size-adjust (delta)
  "Adjust the current frame's font size.
DELTA would be something like 1 or -1."
  (interactive "nFont size difference: ")
  (when (null delta) (setq delta 1))

  (let* ((font-family (face-attribute 'default :font))
         (font-size   (font-get font-family :size))
         (new-size    (+ delta font-size)))
    (ha-set-favorite-font-size new-size)))

(defun font-size-increase ()
   "Increase the `default' font size of all frames."
   (interactive)
   (font-size-adjust 1))

(defun font-size-decrease ()
   "Decrease the `default' font size of all frames."
   (interactive)
   (font-size-adjust -1))

(global-set-key (kbd "s-+") 'font-size-increase)
(global-set-key (kbd "s-=") 'font-size-increase)
(global-set-key (kbd "s--") 'font-size-decrease)

(use-package lin
  :ensure t)

(setq lin-face 'lin-blue) ; this can be set to whatever color I might want otherwise

;; You can use this to live update the face:
;;
;; (customize-set-variable 'lin-face 'lin-green)

(setq lin-mode-hooks
      '(bongo-mode-hook
        dired-mode-hook
        elfeed-search-mode-hook
        git-rebase-mode-hook
        grep-mode-hook
        ibuffer-mode-hook
        ilist-mode-hook
        ledger-report-mode-hook
        log-view-mode-hook
        magit-log-mode-hook
        mu4e-headers-mode-hook
        notmuch-search-mode-hook
        notmuch-tree-mode-hook
        occur-mode-hook
        org-agenda-mode-hook
        pdf-outline-buffer-mode-hook
        proced-mode-hook
        tabulated-list-mode-hook))

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

(add-to-list 'custom-theme-load-path "~/.config/emacs-include/themes")

(use-package modus-themes
  :ensure (:wait t))

(use-package ef-themes
  :ensure t
  :init
  ;; This makes the Modus commands listed below consider only the Ef
  ;; themes.  For an alternative that includes Modus and all
  ;; derivative themes (like Ef), enable the
  ;; `modus-themes-include-derivatives-mode' instead.  The manual of
  ;; the Ef themes has a section that explains all the possibilities:
  ;;
  ;; - Evaluate `(info "(ef-themes) Working with other Modus themes or taking over Modus")'
  ;; - Visit <https://protesilaos.com/emacs/ef-themes#h:6585235a-5219-4f78-9dd5-6a64d87d1b6e>
  (ef-themes-take-over-modus-themes-mode 1)
  :bind
  (("M-<f5>" . modus-themes-select)
   ("C-<f5>" . modus-themes-load-random))

  :config
  ;; All customisations here.
  (setq modus-themes-mixed-fonts t)
  (setq modus-themes-italic-constructs t)

  ;; Finally, load your theme of choice (or a random one with
  ;; `modus-themes-load-random', `modus-themes-load-random-dark',
  ;; `modus-themes-load-random-light').
  (modus-themes-load-theme 'ef-light))

;; In all of the following, WEIGHT is a symbol such as `semibold',
;; `light', `bold', or anything mentioned in `modus-themes-weights'.
(setq modus-themes-italic-constructs t
      modus-themes-bold-constructs nil
      modus-themes-mixed-fonts t
      modus-themes-variable-pitch-ui nil
      modus-themes-disable-other-themes t

      ;; Options for `modus-themes-prompts' are either nil (the
      ;; default), or a list of properties that may include any of those
      ;; symbols: `italic', `WEIGHT'
      modus-themes-prompts '(italic bold)

      ;; The `modus-themes-completions' is an alist that reads two
      ;; keys: `matches', `selection'.  Each accepts a nil value (or
      ;; empty list) or a list of properties that can include any of
      ;; the following (for WEIGHT read further below):
      ;;
      ;; `matches'   :: `underline', `italic', `WEIGHT'
      ;; `selection' :: `underline', `italic', `WEIGHT'
      modus-themes-completions
      '((matches . (extrabold))
        (selection . (semibold italic text-also))))

(setq modus-themes-org-blocks 'gray-background) ; {nil,'gray-background,'tinted-background}

;; The `modus-themes-headings' is an alist: read the manual's
;; node about it or its doc string.  Basically, it supports
;; per-level configurations for the optional use of
;; `variable-pitch' typography, a height value as a multiple of
;; the base font size (e.g. 1.5), and a `WEIGHT'.
(setq modus-themes-headings
      '((1 . (variable-pitch 1.5))
        (2 . (1.3))
        (agenda-date . (1.3))
        (agenda-structure . (variable-pitch light 1.8))
        (t . (1.1))))

(defun sia-setup-minibuffer ()
  "make minibuffer use larger font size."
  (text-scale-increase 2)) ; Unfortunately the 3 size is a little bit too extreme. it would be nice if I could do it all in increments

(add-hook 'minibuffer-mode-hook 'sia-setup-minibuffer)

(defun sia-setup-text-buffer ()
  "Make the font in the text buffer generally larger."
  (text-scale-increase 4))

(add-hook 'text-mode-hook 'sia-setup-text-buffer)

(setq split-width-threshold 120
      split-height-threshold nil)

(use-package balanced-windows
  :config
  (balanced-windows-mode))

(modify-all-frames-parameters
 '((right-divider-width . 10)
   (internal-border-width . 10)))

(dolist (face '(window-divider
                window-divider-first-pixel
                window-divider-last-pixel))
  (face-spec-reset-face face)
  (set-face-foreground face (face-attribute 'default :background)))

(set-face-background 'fringe (face-attribute 'default :background))

(setq org-link-frame-setup
   '((denote . find-file)
     (vm . vm-visit-folder-other-frame)
     (vm-imap . vm-visit-imap-folder-other-frame)
     (gnus . org-gnus-no-new-news)
     (file . find-file)
     (wl . wl-other-frame)))

(use-package ibuffer
  :ensure nil
  :config
  (setq ibuffer-expert t)
  (setq ibuffer-display-summary nil)
  (setq ibuffer-use-other-window nil)
  (setq ibuffer-show-empty-filter-groups nil)
  (setq ibuffer-default-sorting-mode 'filename/process)
  (setq ibuffer-title-face 'font-lock-doc-face)
  (setq ibuffer-use-header-line t)
  (setq ibuffer-default-shrink-to-minimum-size nil)
  (setq ibuffer-formats
        '((mark modified read-only locked " "
                (name 30 30 :left :elide)
                " "
                (size 9 -1 :right)
                " "
                (mode 16 16 :left :elide)
                " " filename-and-process)
          (mark " "
                (name 16 -1)
                " " filename))))

(setq ibuffer-saved-filter-groups
      '(("Main"
         ("Directories" (mode . dired-mode))
         ("Scripts" (or
                     (mode . shell-script-mode)
                     (mode . shell-mode)
                     (mode . sh-mode)
                     (mode . lua-mode)
                     (mode . bat-mode)))
         ("Markup" (or
                    (mode . markdown-mode)
                    (mode . adoc-mode)))
         ("Org" (mode . org-mode))
         ("Emacs Internals" (or
                   (mode . emacs-lisp-mode)
                   (name . "^\\*Help\\*$")
                   (name . "^\\*Custom.*")
                   (name . "^\\*Org Agenda\\*$")
                   (name . "^\\*info\\*$")
                   (name . "^\\*scratch\\*$")
                   (name . "^\\*Backtrace\\*$")
                   (name . "^\\*Messages\\*$")))))
         )

(use-package perspective
  :ensure t
  :bind
  ("C-x k" . persp-kill-buffer*) ; this basically replaces the built-in kill buffer command
  :custom
  (persp-mode-prefix-key (kbd "C-c M-p"))  ; pick your own prefix key here
  :init
  (persp-mode))

(use-package ace-window
  :ensure t)

(use-package easysession
  :ensure t

  :custom
  (easysession-save-interval (* 10 60))  ; Save every 10 minutes

  ;; Display the active session name in the mode-line lighter.
  (easysession-save-mode-lighter-show-session-name t)

  ;; Optionally, the session name can be shown in the modeline info area:
  ;; (easysession-mode-line-misc-info t)

  :init
  ;; Automatically load the session at startup and restore frame size and
  ;; position (geometry)
  (add-hook 'emacs-startup-hook #'easysession-load-including-geometry 102)

  ;; Automatically save the current session every `easysession-save-interval'
  ;; seconds (default: 10 minutes)
  (add-hook 'emacs-startup-hook #'easysession-save-mode 103))

;; Main keybindings
(global-set-key (kbd "C-c sl") 'easysession-switch-to)  ; Load
(global-set-key (kbd "C-c ss") 'easysession-save-as)  ; Save

;; Other keybindings
(global-set-key (kbd "C-c sL") 'easysession-switch-to-and-restore-geometry)
(global-set-key (kbd "C-c sd") 'easysession-delete)
(global-set-key (kbd "C-c sr") 'easysession-rename)
(global-set-key (kbd "C-c sR") 'easysession-reset)
