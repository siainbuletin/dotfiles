;;; ...  -*- lexical-binding: t -*-
;; -*-no-byte-compile: t; -*-

(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
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

(org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (org . t)
     (R . t))
)

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

(defun sia-execute-all-buffers ()
  (interactive)
  (let ((org-confirm-babel-evaluate nil))
    (org-babel-execute-buffer))
)

(global-set-key (kbd "C-c o o") 'org-org-export-to-org)
(global-set-key (kbd "C-c e c") 'sia-execute-all-buffers)

(setq-default cursor-type 'bar) ;; this will make the cursor similar to other text editors

;; WINDOW FUNCTIONS
(setq-default frame-title-format '("␥ %b ␥")) ;; Make the window title to be the buffer name

;; Redrawing the display when there's graphical errors
(global-set-key (kbd "<f6>") 'redraw-display)

(use-package undo-tree
  :ensure (:wait t)
  :config
  (add-to-list 'undo-tree-incompatible-major-modes #'nxml-mode)
  (global-undo-tree-mode)

  :custom
  (undo-tree-history-directory-alist '(("." . "~/.emacs.d/undo"))))

(use-package vundo
  :ensure (:wait t))

(keymap-global-set "C-c j j" #'join-line)

(electric-pair-mode 1)

(use-package dwim-shell-command
  :ensure t
  :bind (([remap shell-command] . dwim-shell-command)
         :map dired-mode-map
         ([remap dired-do-async-shell-command] . dwim-shell-command)
         ([remap dired-do-shell-command] . dwim-shell-command)
         ([remap dired-smart-shell-command] . dwim-shell-command)))

(use-package try
  :ensure (:wait t))

(use-package yasnippet
  :ensure (:wait t)
  :demand t

  :config
  (yas-reload-all)

  :hook
  (sh-mode . yas-minor-mode))

;; install useful snippets
(use-package yasnippet-snippets
  :after yasnippet
  :ensure (:wait t))

(defun sia-clean-whitespace (&optional Begin End)
  "Delete trailing whitespace, and replace repeated blank lines to just 1.
Only space and tab is considered whitespace here.
Works on whole buffer or selection, respects `narrow-to-region'."
  (interactive)
  (let (xbeg xend)
    (seq-setq (xbeg xend)
              (if (and Begin End)
                  (list Begin End)
                (if (region-active-p)
                    (list (region-beginning) (region-end))
                  (list (point-min) (point-max)))))
    (save-excursion
      (save-restriction
        (narrow-to-region xbeg xend)
        (progn
          (goto-char (point-min))
          (while (re-search-forward "[ \t]+\n" nil t) (replace-match "\n")))
        (progn
          (goto-char (point-min))
          (while (re-search-forward "\n\n\n+" nil t) (replace-match "\n\n")))
        (progn
          (goto-char (point-max))
          (while (eq (char-before) 32) (delete-char -1))))))
  (message "done sia-clean-whitespace"))

(add-hook 'before-save-hook 'sia-clean-whitespace)

(use-package load-dir
  :ensure (:wait t))

(use-package cond-let
  :ensure (:wait t))

(use-package keycast
  :ensure (:wait t))

;; SOUNDS
(setq ring-bell-function 'ignore) ;; Disable the bell sound

;; BUFFER FUNCTIONS
(global-auto-revert-mode t) ;; If the file has changed on the disk, then update the buffer as well

;; dired-x is necessary for making counsel-fd work

(use-package counsel
  :ensure (:wait t)
)

(use-package s
  :ensure (:wait t)
  )

(use-package consult
  :ensure (:wait t)
  )

(keymap-global-set "C-c s l" #'consult-line)
(keymap-global-set "C-c s r" #'consult-ripgrep)

(use-package deadgrep
  :ensure (:wait t)
  )

(use-package counsel-fd
  :ensure t
  :after counsel)

(use-package vertico
  :ensure (:wait t)
  :demand t
  :custom
  (vertico-count 13) ; Number of candidates to display
  (vertico-resize t)
  (vertico-cycle t) ; Once passing the last candidate in the list, it will loop back to the first
  :config
  (vertico-mode))

(use-package marginalia
  :ensure (:wait t)
  :init
  (marginalia-mode)
  (setf
    (alist-get 'elpaca-info marginalia-command-categories) 'elpaca))

(use-package orderless
  :ensure (:wait t)
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides
   '((file (styles partial-completion)))))

(use-package company
  :ensure (:wait t))

(use-package prescient
    :ensure (:wait t)
)

(use-package company-prescient
  :ensure (:wait t)
)

(use-package ivy-prescient
  :ensure (:wait t)
)

(use-package selectrum-prescient
  :ensure (:wait t)
)

(use-package vertico-prescient
  :ensure (:wait t)
)

(use-package corfu
  :ensure (:wait t))

(use-package corfu-prescient
  :ensure (:wait t))

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

(defun counsel-recoll-function (string &rest _unused)
  "Issue recallq for STRING."
  (if (< (length string) 3)
      (counsel-more-chars 3)
    (counsel--async-command
     (format "recollq -b '%s'" string))
    nil))

(defun counsel-recoll (&optional initial-input)
  "Search for a string in the recoll database.
You'll be given a list of files that match.
Selecting a file will launch `swiper' for that file.
INITIAL-INPUT can be given as the initial minibuffer input."
  (interactive)
  (ivy-read "recoll: " 'counsel-recoll-function
            :initial-input initial-input
            :dynamic-collection t
            :history 'counsel-git-grep-history
            :action (lambda (x)
                      (when (string-match "file://\\(.*\\)\\'" x)
                        (let ((file-name (match-string 1 x)))
                          (find-file file-name)
                          (unless (string-match "pdf$" x)
                            (swiper ivy-text)))))))

(use-package transient
  :ensure t)

(use-package p-search
  :ensure (:host github :repo "zkry/p-search"))

(use-package websocket
  :ensure (:wait t)
)

(use-package consult-snapfile
  :load-path "~/cloned-utilities/consult-snapfile/emacs"
  :after (consult websocket)
  ;; Optional: bind to your preferred key
  :bind ("C-c s f" . consult-snapfile))

;; Server settings
(setq consult-snapfile-server-port 9876)
(setq consult-snapfile-server-host "127.0.0.1")

;; Max results to return
(setq consult-snapfile-max-results 100)

(use-package helm
    :ensure (:wait t))

(use-package ess
  :ensure t)

(use-package taxy
  :ensure t)

(use-package org-ranker
  :ensure (org-ranker :type git
                    :host github
                    :repo "CSJ7701/org-ranker"))

;; (add-to-list 'load-path "~/.config/emacs-include/cloned-modules/org-dataview")
;; (require 'org-dataview)

(setq org-id-locations-file "~/.config/emacs-include/.org-id-locations")

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

(use-package helm-descbinds
  :ensure (:type git :host github :repo "emacs-helm/helm-descbinds"))

(global-unset-key (kbd "C-z"))

(keymap-global-set "C->" #'indent-rigidly-right-to-tab-stop) ; Indent selection by one tab length
(keymap-global-set "C-<" #'indent-rigidly-left-to-tab-stop)  ; De-indent selection by one tab length

(use-package hydra
  :ensure (:wait t))

(use-package use-package-hydra
  :ensure (:wait t))

(defun sia-dired-sort ()
  "Sort dired dir listing in different ways.
Prompt for a choice.
Works in linux, MacOS, Microsoft Windows."
  (interactive)
  (let ((xmenu '(("date" . "-Al -t")
                 ("size" . "-Al -S")
                 ("name" . "-Al ")
                 ("dir" . "-Al --group-directories-first")))
        xsortBy)
    (setq xsortBy (completing-read "Sort by (default date):" xmenu nil t nil nil (caar xmenu)))
    (dired-sort-other (cdr (assoc xsortBy xmenu)))))

;; Set Dired listing switches for more minimalist output
(setq dired-listing-switches "-aghov --group-directories-first")

(use-package vc-backup
  :ensure (:wait t))

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

(add-hook 'org-mode-hook #'org-indent-mode)

(setq org-startup-folded 'content)

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

(setq org-highlight-latex-and-related '(latex))

(use-package company-math
  :ensure (:wait t)
  :after (org company)
  :hook
  (org-mode . (lambda ()
                (setq-local company-backends (append '((company-math-symbols-latex))
                                                     company-backends)))))

(use-package math-preview
  :ensure (:wait t))

(use-package org-fragtog
  :ensure t)

(use-package org-appear
  :after org
  :ensure (:wait t)
  :hook
  (org-mode . org-appear-mode))

(use-package org-bulletproof
  :ensure (:wait t)
  :after (org org-modern)
  :init
(global-org-bulletproof-mode))

(defface org-checkbox-done-text
  '((t (:foreground "#71696A" :strike-through t)))
  "Face for the text part of a checked org-mode checkbox.")

(font-lock-add-keywords
 'org-mode
 `(("^[ \t]*\\(?:[-+*]\\|[0-9]+[).]\\)[ \t]+\\(\\(?:\\[@\\(?:start:\\)?[0-9]+\\][ \t]*\\)?\\[\\(?:X\\|\\([0-9]+\\)/\\2\\)\\][^\n]*\n\\)"
    1 'org-checkbox-done-text prepend))
 'append)

(use-package spacious-padding
  :ensure t
  :init
  (spacious-padding-mode))

(setq spacious-padding-widths
      '( :internal-border-width 25
         :header-line-width 4
         :mode-line-width 10
         :tab-width 7
         :right-divider-width 30
         :scroll-bar-width 8
         :fringe-width 8))

(setq spacious-padding-subtle-frame-lines
      `( :mode-line-active default
         :mode-line-inactive shadow))

(set-face-attribute 'org-document-title nil
                    :font "Atkinson Hyperlegible"
                    :weight 'bold
                    :height 1.8)

(setq org-support-shift-select t)

(use-package org
    :ensure nil
    :bind
    ;; editing my regular zettels
    ("C-c f n" . org-footnote-new)
    ("C-c f q" . org-footnote-normalize)
    ("C-c l d" . org-toggle-link-display)

    ;; safety nets
    ("C-c s a" . org-save-all-org-buffers)

    ;; working with items (lists)
    ("C-c t i" . org-toggle-item)

    ;; sorting elements
    ("C-c s i" . org-sort-list)

    ;; task-management bindings
    ("C-x t d" . org-do-demote)
)

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

(use-package org-autolist
  :ensure t)

(show-paren-mode 1) ;; Show the closing parens by default --- I actually don't think that this works
(delete-selection-mode 1) ;; The selected text will be overwritten when you start typing

(setq org-link-search-must-match-exact-headline nil)

(setq counsel-outline-display-style 'title)

(setq org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id)

(defun sia-make-id-for-title (title)
  "Return an ID based on TITLE."
  (let* ((new-id (replace-regexp-in-string "[^[:alnum:]]" "-" (downcase title))))
    new-id))

(defun sia-org-custom-id-create ()
  "Create and store CUSTOM_ID for current heading."
  (let* ((title (or (nth 4 (org-heading-components)) ""))
         (new-id (sia-make-id-for-title title)))
    (org-entry-put nil "CUSTOM_ID" new-id)
    (org-id-add-location new-id (buffer-file-name (buffer-base-buffer)))
    new-id))

(defun sia-org-custom-id-get-create (&optional where force)
  "Get or create CUSTOM_ID for heading at WHERE.
  If FORCE is t, always recreate the property."
  (org-with-point-at where
    (let ((old-id (org-entry-get nil "CUSTOM_ID")))
      ;; If CUSTOM_ID exists and FORCE is false, return it
      (if (and (not force) old-id (stringp old-id))
          old-id
        ;; otherwise, create it
        (sia-org-custom-id-create)))))

        ;; Now override counsel-org-link-action
  (defun counsel-org-link-action (x)
    "Insert a link to X.

X is expected to be a cons of the form (title . point), as passed
by `counsel-org-link'.

If X does not have a CUSTOM_ID, create it based on the headline
title."
    (let* ((id (sia-org-custom-id-get-create (cdr x))))
      (org-insert-link nil (concat "#" id) (car x))))

(setq org-directory "~/notes")

(use-package org-special-block-extras
  :ensure t)

(load-file "~/.config/emacs-include/sia-modules/org-extra-emphasis.el")

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-default ((t (:background "#F0B609" :inherit default))))
 '(org-extra-emphasis ((t (:background "#F0B609" :height 1.0 :inherit default :weight bold :width normal))) t)
 '(org-extra-emphasis-01 ((t (:foreground "#003F66" :inherit org-extra-emphasis :underline t))))
 '(org-extra-emphasis-02 ((t (:foreground "#003F66" :inherit org-extra-emphasis :underline t)))))

(defun +org/opened-buffer-files ()
  "Return the list of files currently opened in emacs"
  (delq nil
        (mapcar (lambda (x)
                  (if (and (buffer-file-name x)
                           (string-match "\\.org$"
                                         (buffer-file-name x)))
                      (buffer-file-name x)))
                (buffer-list))))

(setq org-refile-targets '((+org/opened-buffer-files :maxlevel . 9)))

(setq org-refile-use-cache t)

(run-with-idle-timer 300 t (lambda ()
                            (org-refile-cache-clear)
                            (org-refile-get-targets)))

(defun sia-org-tree-to-indirect-buffer (&optional arg)
  "Create indirect buffer and narrow it to current subtree.
The buffer is named after the subtree heading, with the filename
appended.  If a buffer by that name already exists, it is
selected instead of creating a new buffer."
  (interactive "P")
  (let* ((new-buffer-p)
         (pos (point))
         (buffer-name (let* ((heading (org-get-heading t t))
                             (level (org-outline-level))
                             (face (intern (concat "outline-" (number-to-string level))))
                             (heading-string (propertize (org-link-display-format heading)
                                                         'face face)))
                        (concat heading-string "::" (buffer-name))))
         (new-buffer (or (get-buffer buffer-name)
                         (prog1 (condition-case nil
                                    (make-indirect-buffer (current-buffer) buffer-name 'clone)
                                  (error (make-indirect-buffer (current-buffer) buffer-name)))
                           (setq new-buffer-p t)))))
    (switch-to-buffer new-buffer)
    (when new-buffer-p
      ;; I don't understand why setting the point again is necessary, but it is.
      (goto-char pos)
      (rename-buffer buffer-name)
      (org-narrow-to-subtree))))

(defun sia-render-org-table-at-point ()
  (interactive)
  (save-excursion
    (beginning-of-line)
    (if (overlays-at (point))
        ;; this is a rough solution, because there can
        ;; be other overlays at point
        (delete-overlay (car (overlays-at (point))))

      (let* ((element-type (org-element-type (org-element-at-point))))
        (if (and (not (eq element-type 'table))
                 (not (eq element-type 'table-row)))
            (error "not at an org table")

          (while (not (eq 'table (org-element-type (org-element-at-point))))
            (forward-line -1))

          (sia-render-org-table (org-element-at-point)))))))

(defun sia-render-org-table (table)
  (interactive)
  (let* ((begin (org-element-property :begin table))
         (end (let ((pos (org-element-property :end table)))
                (goto-char pos)
                (beginning-of-line)
                ;; skip possible space after table
                (while (not (looking-at " *[|#]"))
                  (setq pos (point))
                  (forward-line -1))
                pos))
         (tabletxt (buffer-substring-no-properties begin end))
         (img (with-temp-buffer
                (insert tabletxt)
                (mark-whole-buffer)
                (org-latex-convert-region-to-latex)
                (org-preview-latex-fragment)
                (goto-char (point-min))
                (overlay-get  (car (overlays-at (point))) 'display)))
         (overlay (make-overlay begin end)))
    (overlay-put overlay 'display img)
    (forward-line -1)))

(defun sia-render-org-tables-in-buffer ()
  (save-excursion
    (org-element-map (org-element-parse-buffer) 'table 'sia-render-org-table)))

(setq org-capture-templates
        '(
          ("l" "Listening log" entry
           (file+datetree "~/notes/inbox/listening-log.org")
           "* %U\n %i\n %a")

          ("t" "Task to the inbox" entry
           (file "~/notes/inbox/inbox-capture.org")
           "* TODO %?\n %i\n %a")

          ("i" "Idea or quick thought to take care of" entry
           (file "~/notes/inbox/thoughts-capture.org"))
))

(global-set-key (kbd "C-c c") #'org-capture)

(global-set-key (kbd "C-x t l")
                (lambda () "Open inbox capture window"
                    (interactive)
                    (org-capture nil "l")))

(global-set-key (kbd "C-x t a")
                (lambda () "Open inbox capture window"
                    (interactive)
                    (org-capture nil "t")))

(global-set-key (kbd "C-x t i")
                (lambda () "Open inbox capture window"
                    (interactive)
                    (org-capture nil "i")))

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
      ("shallow" . ?h) ; I wanted to write this as ?sh but it only accepts one symbol
      ("time-eater" . ?t)))

(setq org-agenda-files
        (list
         "~/notes/area/"
         "~/notes/inbox/" ; this is for tasks that I never actually got to deal with
))

(global-set-key (kbd "C-c o a") 'org-agenda)

(setq org-log-done 'time
      org-log-redeadline 'time
      org-log-reschedule 'time)

(setq org-priority-highest 1
      org-priority-lowest 5
      org-priority-default 4)

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

(setq org-agenda-custom-commands
      '(("p" "Planning"
             ((tags-todo "+@planning"
                         ((org-agenda-overriding-header "Planning Tasks")))
              (tags-todo "-{.*}"
                         ((org-agenda-overriding-header "Untagged Tasks")))
              (todo ".*" ((org-agenda-files '("~/notes/inbox.org"))
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

(use-package elegant-agenda-mode
  :ensure t)

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

(use-package org-edna
  :ensure t
  :config
  (org-edna-mode))

(defun my-set-agenda-files (&rest _)
  (setq org-agenda-files
        (cl-loop for file in (org-mem-all-files)
                 unless (string-search "archive" file)
                 as entries = (org-mem-entries-in-file file)
                 when (seq-find (##or (org-mem-entry-active-timestamps %)
                                      (org-mem-entry-todo-state %)
                                      (org-mem-entry-scheduled %)
                                      (org-mem-entry-deadline %))
                                entries)
                 collect file)))
(add-hook 'org-mem-post-full-scan-functions #'my-set-agenda-files)

(use-package org-gtd
  :ensure (:wait t)
  :after org
  :demand t
  :init
  ;; Suppress upgrade warnings (must be set before package loads)
  (setq org-gtd-update-ack "4.0.0")
  :custom
  ;; Where org-gtd will keep its files (defaults to ~/gtd/)
  (org-gtd-directory "~/notes/areas/org-gtd/")

  ;; Configure TODO keyword states (options like "TODO(t)" or "DONE(d!)" are fine)
  (org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "|" "DONE" "CNCL")))

  ;; Map GTD semantic states to your keywords
  (org-gtd-keyword-mapping '((todo . "TODO")
                             (next . "NEXT")
                             (wait . "WAIT")
                             (canceled . "CNCL")))

  ;; Add org-gtd files to your agenda
  (org-agenda-files (list org-gtd-directory))

  :config
  ;; REQUIRED: Enable org-edna for project dependencies
  (org-edna-mode 1)

  :bind
  ;; Global keybindings (work anywhere in Emacs)
  (("C-c d c" . org-gtd-capture)
   ("C-c d e" . org-gtd-engage)
   ("C-c d p" . org-gtd-process-inbox)
   ("C-c d n" . org-gtd-show-all-next)
   ("C-c d s" . org-gtd-reflect-stuck-projects)

   ;; Keybinding for organizing items (only works in clarify buffers)
   :map org-gtd-clarify-mode-map
   ("C-c c" . org-gtd-organize)

   ;; Quick actions on tasks in agenda views (optional but recommended)
   :map org-agenda-mode-map
   ("C-c ." . org-gtd-agenda-transient)))

(setq org-hierarchical-todo-statistics nil)

(use-package dashboard
  :ensure t
  :init
  (add-hook 'elpaca-after-init-hook #'dashboard-insert-startupify-lists)
  (add-hook 'elpaca-after-init-hook #'dashboard-initialize)
  (dashboard-setup-startup-hook)
  :bind
  ("C-c d d" . dashboard-open))

(setq dashboard-banner-logo-title "Welcome to Emacs Dashboard")
(setq dashboard-startup-banner '3)
(setq dashboard-center-content t)
(setq dashboard-vertically-center-content t)
(setq dashboard-show-shortcuts t)

(setq dashboard-items '((recents   . 5)
                        (bookmarks . 5)
                        (projects  . 5)
                        (agenda    . 7)
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
                                 (bookmarks . "b")
                                 (projects  . "p")
                                 (agenda    . "a")
                                 (registers . "e")))

; (setq dashboard-icon-type 'all-the-icons)  ; use `all-the-icons' package

(setq dashboard-set-heading-icons t)
(setq dashboard-set-file-icons t)

(add-to-list 'dashboard-items '(agenda) t)

(use-package denote
  :ensure t
  :defer t
  :demand t

  :config
  (denote-rename-buffer-mode)
  (setq denote-file-type 'org) ; default is org
  (setq denote-history-completion-in-prompts nil)
  (setq denote-rename-confirmations '(modify-file-name add-front-matter))
  (setq denote-kill-buffers nil)
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
  (:map global-map
      ("M-n c" . denote-open-or-create)
      ("M-n r" . denote-rename-file)
      ("M-n f" . denote-rename-file-using-front-matter)

      :map text-mode-map
      ("M-n I" . denote-add-links)

      :map dired-mode-map
      ("C-c C-d C-i" . denote-link-dired-marked-notes)
      ("C-c C-d C-r" . denote-dired-rename-marked-files)

      ;; these are copied directly from the Emacs Writing Studio configuration
      ("C-c w d b" . denote-find-backlink)
      ("C-c w d d" . denote-date)
      ("C-c w d l" . denote-find-link)
      ("C-c w d i" . denote-link-or-create)
      ("C-c w d k" . denote-rename-file-keywords)))

(setq denote-directory (expand-file-name "~/notes/"))

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

(use-package denote-merge
      :ensure (denote-merge :type git :host github :repo "protesilaos/denote-merge")
      :bind
      ("M-n m f" . denote-merge-file)
      ("M-n m r" . denote-merge-region))

(global-set-key (kbd "C-c z") #'list-denotes)

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

(use-package org-sidebar
  :ensure (:wait t))

(use-package discourse-graphs
  :ensure (discourse-graphs :type git
                            :host github
                            :repo "LuciusChen/discourse-graphs"
                            :files ("*.el"
                            "discourse-graphs-ui/out/*.html"
                            "discourse-graphs-ui/out/assets/*"))
  :config
  (setq dg-directories ;; This is where we scan for nodes
  '("~/notes/")
  )
  (setq dg-recursive t)
  (setq dg-db-file "~/.config/emacs-include/discourse-graphs.db") ;; this is where the SQLite will live

(discourse-graphs-mode 1)
)

;; Use with denote
(setq dg-use-denote t)

(setq dg-context-window-width 0.3)

;; Auto-update context when moving between nodes
(setq dg-context-auto-update t)

;; Maximum lines to display per node in context panel (nil for unlimited)
(setq dg-context-max-lines 30)

;; Show overlays on headings
(setq dg-overlay-enable t)

;; Synthesis dashboard file location
(setq dg-synthesis-file "~/notes/dg-synthesis.org")

(setq dg-discourse-attributes
      '(
        (claim
         . (
            (evidence-score . "{count:Supported By:evidence} - {count:Opposed By:evidence}")
            (robustness . "{count:Supported By:evidence} + {count:Supported By:claim}*0.5 - {count:Opposed By:evidence}")
            (overlay . evidence-score)
                )
           )

        (question
         . (
          (answer-count . "{count:Answered By:claim}")
            (overlay . answer-count)
              )
         )
        ;; ... more types
        )
)

(setq dg-node-types
      '(
        (question . (:short "QUE"
                          :color "lightblue"
                          :desc "Research question"))
        (claim    . (:short "CLM"
                          :color "lightyellow"
                          :desc "Assertion, thesis or position in a debate"))
        (evidence . (:short "EVD"
                          :color "lightgreen"
                          :desc "Argument, proof, or supporting empirical data"))
        (source   . (:short "SRC"
                          :color "lightgray"
                          :desc "Reference material / Philosophical text"))
        (theory   . (:short "THY"
                                  :color "lightcoral"
                          :desc "Theoretical framework"))
        ))

(setq dg-relation-types
      '(
      (supports  . (:inverse "Supported By"
                             :color "green"
                             :style "solid"))
      (opposes   . (:inverse "Opposed By"
                             :color "red"
                             :style "dashed"))
      (informs   . (:inverse "Informed By"
                             :color "blue"
                             :style "solid"))
      (answers   . (:inverse "Answered By"
                             :color "purple"
                             :style "solid"))
      )
      )

(setq dg-relation-patterns
      '((supports . (:source (evidence)
                           :target (claim)))
      (opposes  . (:source (evidence)
                           :target (claim)))
      (informs  . (:source (source)
                           :target (evidence)))
      (answers  . (:source (claim)
                           :target (question)))
      )
        )

;; (use-package org-ql
;;  :ensure t)

(use-package org-mem
  :ensure (:wait t)
  :defer
  :config
  ;; At least one of these two is needed
  (setq org-mem-do-sync-with-org-id t)
  (setq org-mem-watch-dirs
        (list "~/notes/"))
  (org-mem-updater-mode))

(use-package inspector
  :ensure (:wait t)
  )

(use-package org-node
  :ensure (:wait t)
  :init
  ;; Optional key bindings
  ;; Tip: Try changing these to just "M-o"!
  (keymap-global-set "M-o n n" 'org-node-nodeify-entry)
  (keymap-global-set "M-o n i" 'org-node-insert-link)
  :config
  (org-node-cache-mode)
  )

(setq org-node-backlink-do-drawers nil)

(setq org-node-alter-candidates t)

(defgroup ews ()
  "Emacs Writing Studio."
  :group 'files
  :link '(url-link :tag "Homepage" "https://lucidmanager.org/tags/emacs/"))

(defcustom sia-bibtex-directory
  (concat (file-name-as-directory (getenv "HOME")) "/bibliography/")
  "Location of BibTeX files and attachments."
  :group 'ews
  :type 'directory)

(defcustom sia-hunspell-dictionaries "en_US"
  "Comma-separated list of Hunspell dictionaries."
  :group 'ews
  :type 'list)

;;; BIBLIOGRAPHY
(defvar sia-bibtex-files
  (when (file-exists-p sia-bibtex-directory)
    (directory-files sia-bibtex-directory t "^[A-Z|a-z|0-9].+.bib$"))
  "List of BibTeX files. Use `sia-bibtex-register' to configure.")

;;;###autoload
(defun sia-bibtex-register ()
  "Register the contents of the `sia-bibtex-directory' with `sia-bibtex-files`.
Use when adding or removing a BibTeX file from or to `sia-bibtex-directory'."
  (interactive)
  (when (file-exists-p sia-bibtex-directory)
    (let ((bib-files (directory-files sia-bibtex-directory t
				      "^[A-Z|a-z|0-9].+.bib$")))
      (setq sia-bibtex-files bib-files
  	    org-cite-global-bibliography bib-files
	    citar-bibliography bib-files)))
  (message "Registered:\n%s" (mapconcat #'identity sia-bibtex-files "\n")))

(defun sia--bibtex-combined-biblio-lookup ()
  "Combines `biblio-lookup' and `biblio-doi-insert-bibtex'."
  (require 'biblio)
  (let* ((dbs (biblio--named-backends))
         (db-list (append dbs '(("DOI" . biblio-doi-backend))))
         (db-selected (biblio-completing-read-alist
                       "Backend:"
                       db-list)))
    (if (eq db-selected 'biblio-doi-backend)
        (let ((doi (read-string "DOI: ")))
          (biblio-doi-insert-bibtex doi))
      (biblio-lookup db-selected))))

(setq bibtex-autokey-name-separator nil
      bibtex-autokey-name-year-separator nil
      bibtex-autokey-year-length 4
      bibtex-autokey-names 1
      bibtex-autokey-names-stretch 1
      bibtex-autokey-titlewords 0)

(use-package bibtex
  :ensure nil
  :custom
  (bibtex-dialect 'biblatex)
  (bibtex-user-optional-fields
   '(("keywords" "Keywords to describe the entry" "")
     ("file"     "Relative or absolute path to attachments" "" )))
  (bibtex-align-at-equal-sign t)
  :config
  (sia-bibtex-register)
  :bind
  (("C-c w b r" . sia-bibtex-register))
)

(use-package biblio
  :ensure t
  :bind
  (("C-c w b b" . sia-bibtex-biblio-lookup)))

(use-package biblio-gscholar
  :ensure (biblio-gscholar :host github :repo "seanfarley/biblio-gscholar.el"))

(use-package asoc
    :ensure (:type git :host github :repo "troyp/asoc.el"))

(use-package doct
  :ensure t)

(defun yant/elfeed-capture-entry ()
  "Capture selected entries into inbox."
  (interactive)
  (elfeed-search-tag-all 'opened)
  (previous-logical-line)
  (let ((entries (elfeed-search-selected)))
    (cl-loop for entry in entries
             do (elfeed-untag entry 'unread)
             when (elfeed-entry-link entry)
             do (flet ((raise-frame nil nil))
                  (org-protocol-capture (list :template "B"
                                              :url it
                                              :title (format "%s: %s"
                                                             (elfeed-feed-title (elfeed-entry-feed entry))
                                                             (elfeed-entry-title entry))
                                              :elfeed-data entry))))
    (mapc #'elfeed-search-update-entry entries)
    (unless (use-region-p) (forward-line))))

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

         (citar-templates
'((main . "${author editor:30}   ${date year issued:4}    ${title:110}")
  (suffix . "     ${=type=:20}    ${tags keywords keywords:*}")
  (preview . "${author editor} (${year issued date}) ${title}, ${journal journaltitle publisher container-title collection-title}.\n")
  (note . "#+title: Notes on ${author editor}, ${title}") ; For new notes
  ))
;;      (citar-symbols
;;       `((file ,(all-the-icons-faicon "file-o" :face 'all-the-icons-green :v-adjust -0.1) .
;;               ,(all-the-icons-faicon "file-o" :face 'kb/citar-icon-dim :v-adjust -0.1) )
;;         (note ,(all-the-icons-material "speaker_notes" :face 'all-the-icons-blue :v-adjust -0.3) .
;;               ,(all-the-icons-material "speaker_notes" :face 'kb/citar-icon-dim :v-adjust -0.3))
;;         (link ,(all-the-icons-octicon "link" :face 'all-the-icons-orange :v-adjust 0.01) .
;;               ,(all-the-icons-octicon "link" :face 'kb/citar-icon-dim :v-adjust 0.01))))
      (citar-symbol-separator "  ")

         :bind
         (("C-c w b o" . citar-open))
         (:map org-mode-map :package org ("C-c b" . #'org-cite-insert))
         :hook
         (LaTeX-mode . citar-capf-setup)
         (org-mode . citar-capf-setup)
         (markdown-mode . citar-capf-setup))

(setq citar-library-file-extensions nil)

(use-package citar-embark
  :ensure t
  :after (citar embark)
  :no-require
  :config (citar-embark-mode)
  )

(setq citar-at-point-function 'embark-act)

(use-package citar-denote
  :ensure (:wait t)
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

(defvar sia-citar-library-backup-path "~/Documents/literature/backup")

(defun sia-citar-update-pdf-metadata (citekey)
  (interactive (list (citar-select-ref)))
  (citar--check-configuration 'citar-library-paths)
  (unless citar-library-paths
    (user-error "Make sure `citar-library-paths' is non-nil"))
  (let* ((files (gethash cite-key (citar-get-files cite-key))))
    (unless files
      (user-error (format "There are no PDF files associated with %s" citekey)))
    (let ((file (or (unless (cdr files) (car files)) (completing-read "Please select a PDF file: " files)))
          (title (citar-get-value 'title citekey))
          (author (cond ((citar-get-value 'author citekey)
                         (citar-get-value 'author citekey))
                        ((citar-get-value 'editor citekey)
                         (concat (citar-get-value 'editor citekey) " (ed.)")))))
      (progn
        (copy-file file sia-citar-library-backup-path 1)
        (call-process-shell-command
         (concat "exiftool -overwrite_original_in_place -Title='" title "' -Author='" author "' " file))))))

(require 'oc-natbib)
(require 'oc-csl)

(setq org-cite-global-bibliography sia-bibtex-files
      org-cite-insert-processor 'citar
      org-cite-follow-processor 'citar
      org-cite-activate-processor 'citar)

(use-package org-ref
  :ensure t
  :after (ox-pandoc)
)

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

(use-package helm-bibtex
  :ensure (:wait t))

(setq org-ref-default-bibliography '("~/bibliography/master.bib")
      org-ref-pdf-directory "~/Documents/literature/")

;; (setq citar-library-paths "~/Documents/literature")
;; this has to be a list of directories in order to work

(setq citar-library-file-extensions (list "pdf" "jpg")
      citar-file-additional-files-separator "-")

(setq bibtex-completion-bibliography
      '("~/bibliography/master.bib"
        "~/bibliography/thesis.bib"
        "~/bibliography/marx.bib"
        "~/bibliography/hci.bib"
        "~/bibliography/aesthetics.bib"
        "~/bibliography/hegel-prezentare.bib"
        "~/bibliography/modernitate.bib")
        bibtex-completion-library-path '("~/Documents/literature/")
        bibtex-completion-notes-path "~/notes/"
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

(use-package citar-org-node
  :vc ( :url "https://github.com/krisbalintona/citar-org-node.git"
        :rev :newest))

(use-package nov
  :ensure t
  :config
  (setq nov-variable-pitch nil
        nov-text-width 70)
  :init
  (add-to-list 'auto-mode-alist '("\\.epub\\'" . nov-mode)))

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
  :ensure (:wait t))

(use-package olivetti
  :ensure t
  :demand t
  :after org
  :custom
  (olivetti-minimum-body 100)
  (olivetti-body-width 80)
  :bind
  (("C-c w o" . sia-olivetti))
  :hook
  (org-mode . olivetti-mode))

(use-package binder
  :ensure t)

(setq org-latex-compiler "xelatex")
(setq org-latex-pdf-process
      (list (concat "latexmk -"
                    org-latex-compiler
                    " -recorder -synctex=1 -bibtex-cond %b")))

(setq org-latex-listings t)

(setq org-latex-default-packages-alist
      '(("" "graphicx" t)
        ("" "grffile" t)
        ("" "longtable" nil)
        ("" "wrapfig" nil)
        ("" "rotating" nil)
        ("normalem" "ulem" t)
        ("" "amsmath" t)
        ("" "textcomp" t)
        ("" "amssymb" t)
        ("" "capt-of" nil)
        ("" "hyperref" nil)))

(require 'ox-latex)
(unless (boundp 'org-latex-classes)
  (setq org-latex-classes nil))

(with-eval-after-load 'ox-latex
(add-to-list 'org-latex-classes
             '("org-plain-latex"
               "\\documentclass{article}
           [NO-DEFAULT-PACKAGES]
           [PACKAGES]
           [EXTRA]"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
               ("\\paragraph{%s}" . "\\paragraph*{%s}")
               ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))

(setq org-latex-listings 't)

(use-package org-pandoc-import
  :ensure (:host github
               :repo "tecosaur/org-pandoc-import"
               :files ("*.el" "filters" "preprocessors")))

;; animated gif support to spruce things up
(use-package org-inline-anim
  :ensure (:wait t)
  :custom
  (org-inline-anim-loop t))

;; (use-package org-present
;;   :ensure (:wait t)
;;   :after org-inline-anim
;;   :hook
;;   ((org-present-mode . (lambda ()
;;                          (org-present-big)
;;                          (org-display-inline-images)
;;                          (org-present-read-only)
;;                          (centaur-tabs-local-mode)
;;                          (org-inline-anim-mode)
;;                          (org-inline-anim-animate-all)))
;;    (org-present-mode-quit . (lambda ()
;;                               ;; TODO: actually turn on centaur tabs again.
;;                               ;;       Nothing works that I've tried so far
;;                               (org-present-small)
;;                               (org-present-read-write)
;;                               (org-present-show-cursor)))))

(use-package tldr
    :ensure (:wait t))

(use-package devdocs
    :ensure (:wait t))

(use-package helpful
  :ensure t
  :bind
  (("C-h f" . helpful-function)
   ("C-h x" . helpful-command)
   ("C-h k" . helpful-key)
   ("C-h v" . helpful-variable)))

;; Note that the built-in `describe-function' includes both functions
;; and macros. `helpful-function' is functions only, so we provide
;; `helpful-callable' as a drop-in replacement.
(global-set-key (kbd "C-h f") #'helpful-callable)

(global-set-key (kbd "C-h v") #'helpful-variable)
(global-set-key (kbd "C-h k") #'helpful-key)
(global-set-key (kbd "C-h x") #'helpful-command)

;; Lookup the current symbol at point. C-c C-d is a common keybinding
;; for this in lisp modes.
(global-set-key (kbd "C-c C-d") #'helpful-at-point)

;; Look up *F*unctions (excludes macros).
;;
;; By default, C-h F is bound to `Info-goto-emacs-command-node'. Helpful
;; already links to the manual, if a function is referenced there.
(global-set-key (kbd "C-h F") #'helpful-function)

(use-package lexic
  :ensure t)

;; Open link in eww or browser
(defun open-link-at-point-or-minibuffer-with-choice ()
  "Use `consult` to select a link at point, in the buffer, from `consult-omni` results, or prompt for a URL.
  Then choose to open it in macOS default browser or eww.
  If 'eww' is chosen, the link is opened in a window that occupies 80% of the frame height below the current one."
  (interactive)
  (let* ((url (or (thing-at-point 'url)                             ;; Check if there's a URL at point
                (consult--read (thing-at-point--list 'url))       ;; Use consult to select a URL from the buffer
                (consult-omni)                                    ;; Use consult-omni results to select a link
                (read-string "Enter URL: "))))                    ;; Fall back to manual URL entry
    (if url
      (let ((choice (completing-read "Open link in: " '("macOS Browser" "eww"))))
        (cond
         ((string-equal choice "macOS Browser")
          (shell-command (concat "open " (shell-quote-argument url))))
         ((string-equal choice "eww")
          ;; Calculate the height for the top window (20% of the frame height)
          (let ((window (selected-window))
                (top-window-height (floor (* 0.2 (window-total-height)))))
            ;; Split window with 20% height on top and 80% height for eww on the bottom
            (select-window (split-window window top-window-height))
            (eww url)))))
      (message "No URL provided."))))

;; close buffer and window
(defun close-buffer-and-window ()
  "Close the current buffer and the window it's in."
  (interactive)
  (let ((window (selected-window)))
    (kill-buffer)               ;; Kill the current buffer
    (when (window-live-p window) ;; Check if the window is still live
      (delete-window))))         ;; Delete the window if it exists

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

(use-package nerd-icons
  :ensure (:wait t)
  :custom
  ;; The Nerd Font you want to use in GUI defaults to fixed-font:
  (nerd-icons-font-family "Symbols Nerd Font Mono"))

(use-package nerd-icons-ibuffer
  :ensure t
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

(use-package doom-modeline
  :ensure (:wait t)
  :init
  (setq doom-modeline-buffer-encoding nil ; irrelevant for me but shows UTF-8

      ;; identifying the modes we're in
        doom-modeline-major-mode-color-icon t
      doom-modeline-minor-modes nil ; keep identification to the current modes

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
        doom-modeline-lsp-icon t ; this doesn't currently work as I'm not working with code projects
      doom-modeline-enable-word-count t)
   (doom-modeline-mode 1)
)

(use-package elfeed
  :custom
  (elfeed-db-directory
   (expand-file-name "elfeed" user-emacs-directory))
  (elfeed-show-entry-switch 'display-buffer)
  :bind
  ("C-c w e" . elfeed))

(use-package elfeed-org
  :ensure t
  :config
  (elfeed-org)
  :custom
  (setq sia-elfeed-org-files (list "~/Documents/elfeed.org")))

(when (display-graphic-p)
  (context-menu-mode 1)
  (tool-bar-mode -1)
  (scroll-bar-mode -1)
  (horizontal-scroll-bar-mode -1)
  (setq visible-bell 1
        frame-inhibit-implied-resize t))

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
  :ensure (:wait t)
  :config
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-property-value)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'org-special-keyword)
  (add-to-list 'mixed-pitch-fixed-pitch-faces 'font-lock-comment-face)
  :hook (text-mode . mixed-pitch-mode))

(set-face-attribute 'default nil
                  :family "PT Mono"
                  :height 100)

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

(set-face-attribute 'default nil
                  :family "Aporetic Sans Mono"
                  :height 100)

(set-face-attribute 'link nil
                  :family "IntoneMono Nerd Font"
                  :height 100)

(use-package fontaine
  :ensure (:wait t)
  :init
  (fontaine-mode))

(setq prettify-symbols-unprettify-at-point 'right-edge)

(global-prettify-symbols-mode +1)
(prettify-symbols-mode +1)

(add-hook 'text-mode-hook (lambda () (setq-local line-spacing 0.1)))

(set-face-attribute 'org-quote nil
                  :family "Aporetic Serif Mono")

(setq org-ellipsis " [+]")

;; (use-package all-the-icons
;;   :ensure (:wait t)
;;   :if (display-graphic-p))

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
  (modus-themes-load-theme 'ef-melissa-light)
  )

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

(set-face-attribute 'default nil
                  :family "0xProto Nerd Font")

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
  :ensure (:wait t)
  :config
  (balanced-windows-mode)
)

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

(setq tab-bar-new-tab-choice "*dashboard*")
(setq tab-bar-new-tab-to 'right)

(setq tab-bar-new-button-show nil) ; I want to only create tabs from the modeline or through a keybinding

(setq tab-bar-show nil)

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

(defun transpose-buffers (arg)
  "Transpose the buffers shown in two windows."
  (interactive "p")
  (let ((selector (if (>= arg 0) 'next-window 'previous-window)))
    (while (/= arg 0)
      (let ((this-win (window-buffer))
            (next-win (window-buffer (funcall selector))))
        (set-window-buffer (selected-window) next-win)
        (set-window-buffer (funcall selector) this-win)
        (select-window (funcall selector)))
      (setq arg (if (plusp arg) (1- arg) (1+ arg))))))

(global-set-key (kbd "C-x t b") 'transpose-buffers)

;; Main keybindings
(global-set-key (kbd "C-c sl") 'easysession-switch-to)  ; Load
(global-set-key (kbd "C-c ss") 'easysession-save-as)  ; Save

;; Other keybindings
(global-set-key (kbd "C-c sL") 'easysession-switch-to-and-restore-geometry)
(global-set-key (kbd "C-c sd") 'easysession-delete)
(global-set-key (kbd "C-c sr") 'easysession-rename)
(global-set-key (kbd "C-c sR") 'easysession-reset)

;; (use-package emms
;;   :ensure t)

;; (use-package vuiet
;;   :ensure t)

;; (use-package lastfm
;;   :ensure t)

;; (use-package ready-player
;;   :ensure t
;;   :init
;;   (ready-player-mode 1)
;;   :custom
;;   (ready-player-thumbnail-max-pixel-height 200)
;;   (ready-player-autoplay nil)
;;   (ready-player-repeat t)
;;   (ready-player-shuffle t)
;;   (ready-player-open-playback-commands
;;    '(
;;      ("mpv" "--audio-display=no")
;;      ("mplayer")
;;      ("ffplay")
;;      ("vlc")
;;      )))

;; (use-package listen
;;   :ensure t)

(global-set-key (kbd "C-c e b b") 'eval-buffer)

;; Does not work on Windows, but we can just avoid compiling dependencies and using it
;; (if I'm ever forced to use Windows again for work or similar)
(use-package vterm
  :commands vterm
  :custom
  (vterm-always-compile-module t)
  :hook
  (vterm-mode . (lambda ()
                  ;; Settings to mimic dracula I use for zsh.
                  (setq-local buffer-face-mode-face '(:background "#000000" :foreground "#FFFFFF"))
                  (buffer-face-mode 1)
                  (text-scale-adjust 2)))
  :bind
  ("<f7>" . vterm))

;;; MACOS settings

;; This is so that I can actually use the CMD key as my Meta key.

(setq mac-command-modifier 'meta)

(setq mac-option-modifier 'none)

;; Open with a specific MacOS app

(defun dwim-shell-commands-macos-open-with ()
  "Convert all marked images to jpg(s)."
  (interactive)
  (let* ((apps (seq-sort
                #'string-lessp
                (seq-mapcat (lambda (paths)
                              (directory-files-recursively
                               paths "\\.app$" t (lambda (path)
                                                  (not (string-suffix-p ".app" path)))))
                            '("/Applications" "~/Applications" "/System/Applications"))))
         (selection (progn
                      (cl-assert apps nil "No apps found")
                      (completing-read "Open with: "
                                       (mapcar (lambda (path)
                                                 (propertize (file-name-base path) 'path path))
                                               apps)))))
    (dwim-shell-command-on-marked-files
     "Open with"
     (format "open -a '%s' '<<*>>'" (get-text-property 0 'path selection))
     :silent-success t
     :no-progress t
     :utils "open")))

;; kill macos processes right from emacs

(require 'dwim-shell-command)
(require 'map)
(require 'proced)
(require 'seq)

(defun dwim-shell-commands-kill-process ()
  "Select and kill process."
  (interactive)
  (let* ((pid-width 5)
         (comm-width 25)
         (user-width 10)
         (processes (proced-process-attributes))
         (candidates
          (mapcar (lambda (attributes)
                    (let* ((process (cdr attributes))
                           (pid (format (format "%%%ds" pid-width) (map-elt process 'pid)))
                           (user (format (format "%%-%ds" user-width)
                                         (truncate-string-to-width
                                          (map-elt process 'user) user-width nil nil t)))
                           (comm (format (format "%%-%ds" comm-width)
                                         (truncate-string-to-width
                                          (map-elt process 'comm) comm-width nil nil t)))
                           (args-width (- (window-width) (+ pid-width user-width comm-width 3)))
                           (args (map-elt process 'args)))
                      (cons (if args
                                (format "%s %s %s %s" pid user comm (truncate-string-to-width args args-width nil nil t))
                              (format "%s %s %s" pid user comm))
                            process)))
                  processes))
         (selection (map-elt candidates
                             (completing-read "kill process: "
                                              (seq-sort
                                               (lambda (p1 p2)
                                                 (string-lessp (nth 2 (split-string (string-trim (car p1))))
                                                               (nth 2 (split-string (string-trim (car p2))))))
                                               candidates) nil t)))
         (prompt-title (format "%s %s %s"
                               (map-elt selection 'pid)
                               (map-elt selection 'user)
                               (map-elt selection 'comm))))
    (when (y-or-n-p (format "Kill? %s" prompt-title))
      (dwim-shell-command-on-marked-files
       (format "Kill %s" prompt-title)
       (format "kill -9 %d" (map-elt selection 'pid))
       :utils "kill"
       :error-autofocus t
       :silent-success t))))

; Source - https://stackoverflow.com/a/4083987

(when (eq system-type 'darwin)
  (require 'ls-lisp)
  (setq ls-lisp-use-insert-directory-program nil))

;; HTTP library

(use-package plz
  :ensure (:wait t))

;; AI implementation

(use-package gptel
  :ensure (:wait t))

;; org-db

;; (add-to-list 'load-path "~/.config/emacs-include/cloned-modules/org-db-v3/elisp/")
;; (require 'org-db-v3)

;; Bind the menu to a convenient key
(global-set-key (kbd "H-v") 'org-db-menu)

;; Auto-start server when Emacs starts (optional)
;; (setq org-db-v3-auto-start-server t)
;; Optional: Enable gptel integration for AI-powered search
;; (when (featurep 'gptel)
;;  (require 'org-db-v3-gptel-tools)
;;  (org-db-v3-gptel-register-tools))

(use-package vulpea
  :ensure (:wait t)
  :init
  (keymap-global-set "M-o f" 'vulpea-find)
  (keymap-global-set "M-o n a" 'vulpea-buffer-alias-add)
)

(setq vulpea-db-sync-directories '("~/notes/"))

(setq vulpea-db-parse-method 'single-temp-buffer)

(vulpea-db-autosync-mode +1) ;; this makes sure that the vault is being updated on each startup.

(setq vulpea-buffer-alias-property "ROAM_ALIASES") ;; By default, aliases are stored in ALIASES. To use ROAM_ALIASES for org-roam compatibility:

(vulpea-db-query-by-tags-every '("project" "active")) ;; Query all active projects

;; Configuring the display of notes in the minibuffer
;; "My Notes → Projects → Task"
(setq vulpea-select-describe-fn #'vulpea-select-describe-outline-full)

;; Default annotation: "(primary title) #tag1 #tag2"
(setq vulpea-select-annotate-fn #'vulpea-select-annotate)

;; Schema definition
;; Schema for albums
(vulpea-schema-define 'album
  :predicate (lambda (note) (member "album" (vulpea-note-tags note)))
  :fields
  '(
    (:key "creator" :type note   :required t :target-tags ("musician" "person" "group"))
    (:key "name"     :type string :required nil)
    (:key "genre"   :type note :required t :multiple t :target-tags ("genre"))
    (:key "genre-influences" :type note :multiple t :target-tags ("genre"))
    (:key "year"   :type number   :required t :multiple nil)
    (:key "rating"   :type number   :required nil :multiple nil)
))

;; Schema for inquiries
(vulpea-schema-define 'inquiry
  :predicate (lambda (note) (member "inquiry" (vulpea-note-tags note)))
  :fields
  '(
    (:key "q-status" :type string :required t :one-of (solved unsolved))
))

(vulpea-schema-define 'question
		      :predicate (lambda (note) (member "question" (vulpea-note-tags note)))
		      :include 'inquiry)

(vulpea-schema-define 'error
		      :predicate (lambda (note) (member "error" (vulpea-note-tags note)))
		      :include 'inquiry)

(vulpea-schema-define 'research-q
		      :predicate (lambda (note) (member "research-q" (vulpea-note-tags note)))
		      :include 'inquiry)

(vulpea-schema-define 'exploratory ;; not as serious as a research question
		      :predicate (lambda (note) (member "exploratory" (vulpea-note-tags note)))
		      :include 'inquiry)

;; Schema for people
(vulpea-schema-define 'person
		      :predicate (lambda (note) (member "person" (vulpea-note-tags note)))
		      :fields
		      '((:key "DOB" :type number)
			(:key "DOD" :type number))
		      )

(vulpea-schema-define 'musician
		      :predicate (lambda (note) (member "musician" (vulpea-note-tags note)))
		      :include 'person)

;; Schema for groups
(vulpea-schema-define 'group
		      :predicate (lambda (note) (member "group" (vulpea-note-tags note)))
		      :fields
		      '((:key "members" :type note :multiple t))
		      )

(vulpea-schema-define 'institution
		      :predicate (lambda (note) (member "institution" (vulpea-note-tags note)))
		      :include 'group
		      )

(vulpea-schema-define 'company
		      :predicate (lambda (note) (member "company" (vulpea-note-tags note)))
		      :include 'group
		      )

;; Schema for software-related stuff
(vulpea-schema-define 'software
		      :predicate (lambda (note) (member "software" (vulpea-note-tags note)))
		      :fields
		      '((:key "source" :type string :required t :one-of ("closed-source" "open-source"))
			(:key "languages" :type note :required nil :multiple t)
			(:key "maintenance" :type string :required t :one-of ("current" "abandoned" "spotty")))
		      )

(vulpea-schema-define 'package
		      :predicate (lambda (note) (member "package" (vulpea-note-tags note)))
		      :fields
		      '((:key "(m)elpa" :type string :required nil :one-of (yes no)))) ;; change this to boolean

;; Schema for literature notes
(vulpea-schema-define 'base-text
		      :predicate (lambda (note) (member "text" (vulpea-note-tags note)))
		      :fields
		      '((:key "pub-author" :type note :multiple t)
			(:key "pub-year" :type number :required t)
			(:key "pub-title" :type string :required t)
			(:key "relevance" :type string :required nil))
)

(vulpea-schema-define 'article
		      :predicate (lambda (note) (member "journalarticle" (vulpea-note-tags note)))
		      :include 'base-text
		      :fields
		      '((:key "pub-pages" :type string :required nil))
)

(vulpea-schema-define 'booksection
		      :predicate (lambda (note) (member "booksection" (vulpea-note-tags note)))
		      :include 'base-text
		      :fields
		      '((:key "pub-pages" :type string :required nil)
		      (:key "bib-parent" :type note :required t :target-tags ("book")))
		      )

(vulpea-schema-define 'collection
		      :predicate (lambda (note) (member "collection" (vulpea-note-tags note)))
		      :include 'base-text
		      :fields
		      '((:key "pub-editor" :type note :required t))
)

(vulpea-schema-define 'incollection
		      :predicate (lambda (note) (member "incollection" (vulpea-note-tags note)))
		      :include 'base-text
		      :fields
		      '((:key "pub-pages" :type string :required nil)
		      (:key "bib-parent" :type note :required t :target-tags ("collection"))
		      (:key "pub-author" :type note :required t))
		      )

;; UI functions
(use-package vulpea-ui
  :ensure (:wait t)
  :after vulpea)

;; opening the vulpea sidebar
(global-set-key (kbd "C-c v s") #'vulpea-ui-sidebar-toggle)

;; Position: 'right (default), 'left, 'top, 'bottom
(setq vulpea-ui-sidebar-position 'right)

;; Size as fraction of frame (0.0-1.0)
(setq vulpea-ui-sidebar-size 0.33)

;; Maximum heading depth (nil = unlimited)
(setq vulpea-ui-outline-max-depth 3)

;; Utility functions for vulpea-ui
(setq vulpea-ui-auto-refresh t) ;; So you don't have to constantly do a manual refresh.

;; Dealing with narrowed Org files

;; Respect narrowing in the sidebar
(setq vulpea-ui-respect-narrowing t)

;; Emacs has no narrowing hook, so the sidebar notices a narrow or widen on the next idle
;; refresh. If you want it instantly, refresh right after toggling:

(defun my/org-toggle-narrow-and-sidebar ()
  "Toggle subtree narrowing and refresh the sidebar immediately."
  (interactive)
  (org-toggle-narrow-to-subtree)
  (vulpea-ui-sidebar-refresh))

(define-key org-mode-map (kbd "M-<insert>") #'my/org-toggle-narrow-and-sidebar)

;; the backlinks widget

;; Show/hide content previews
(setq vulpea-ui-backlinks-show-preview t)

;; Characters before/after link in prose previews
(setq vulpea-ui-backlinks-prose-chars-before 30)
(setq vulpea-ui-backlinks-prose-chars-after 50)

;; Filter which notes appear in backlinks
;; (function receiving vulpea-note, return non-nil to include)
(setq vulpea-ui-backlinks-note-filter
      (lambda (note)
        (not (member "archive" (vulpea-note-tags note)))))

;; Filter by context type
;; t = all types, or a list of: meta, header, table, list, quote, code, footnote, prose
(setq vulpea-ui-backlinks-context-types t)

;; Sorting: nil (no sorting), 'title-asc, 'title-desc, or custom function
(setq vulpea-ui-backlinks-sort 'title-asc)

;; Collection views
(setq vulpea-ui-collection-views
      '(
        ("thesis-reading-list" . (:filter (:tags-all ("book")
					                          :level 0 ;; this is what will bring file-level notes
					                          ;; :meta ("read-status" . t) ;; this one doesn't work yet for some reason
                                    :meta ("bib-project" . "[[ID:806b08ac-3ed1-4338-a26e-3af9e0e9328c][Devalorizarea artei în capitalismul de platformă]]")
                                    )
			                :columns (title (meta "pub-title") (meta "pub-author") (meta "read-status") links tags modified)
			                :sort ("Modified" . t)))
        
        ("open-questions" . (:filter (:tags-all ("question)
                                      :level 1 ;; this will only bring up headings at first
                                      )
                             :columns (title (meta "q-status) links tags modified)
                             :sort ("Modified" . t)
        ))
        
        ("music" . (:filter (:tags-all ("music")
                            :level 0)
                    :columns (title (meta "year") (meta "genre") tags modified)
                    :sort ("title" . t)))
        
        ("albums" . (:filter (:tags-all ("album"))
                     :columns (title
                                (meta "creator" :width 60)
                                (meta "year")
                                (meta "genre")
                                (meta "genre-influences")
                                (meta "rating"
                                (meta "review")
                                context tags modified)
                     :sort ("title" . t)))
        )))

;; JOURNALING
(use-package vulpea-journal
  :ensure (:wait t)
  :after vulpea)

;; Templating for Vulpea

(setq vulpea-create-default-function
      (lambda (title)
        (list :file-name (format "%s_%s.org"
                                 (format-time-string "%Y%m%d%H%M%S")
                                 (vulpea-title-to-slug title))
              :tags (if (string-match-p "TODO" title)
                        '("task")
                      '("note")))))

;; Integration with other packages

(let ((dir "~/.config/emacs-include/cloned-modules/"))
  (dolist (file (directory-files-recursively dir "\\.el\\'"))
    (add-to-list 'load-path (file-name-directory file))
    (load (file-name-sans-extension file))))

(require 'embark-vulpea)

(use-package consult-vulpea
  :ensure (:wait t)
  :after vulpea
  :config
  (consult-vulpea-mode 1)
)

(require 'vulpea-para)
(vulpea-para-agenda-mode)

(vulpea-para-setup-defaults)

;; keep a cemetery (or anything) out of the agenda file list
(setq vulpea-para-agenda-files-filter
      (lambda (note)
        (not (vulpea-note-tagged-any-p note "cemetery"))))

;; Getting the custom agenda view for vulpea-para

(setq org-agenda-custom-commands
      `((" " "Agenda"
         (,vulpea-para-agenda-cmd-refile
          ,vulpea-para-agenda-cmd-today
          ,vulpea-para-agenda-cmd-focus
          ,vulpea-para-agenda-cmd-stuck-projects
          ,vulpea-para-agenda-cmd-waiting
          ,(vulpea-para-agenda-cmd-current-quarter)))))

;; the Area > Project prefix in the agenda
(setq org-agenda-prefix-format
      '((agenda . " %(vulpea-para-agenda-category 36) %?-12t %12s")
        (todo   . " %(vulpea-para-agenda-category 36) ")))

;; Other modules for vulpea

;; (use-package vulpea-capf
;;   :ensure (:wait t)
;;   :hook (org-mode . vulpea-capf-mode)
;;   )

;; (setq vulpea-capf-everywhere nil)   ; only complete inside [[...]]
;; (setq vulpea-capf-in-brackets t)

;; (setq vulpea-capf-annotate-function t)

(use-package rg
  :ensure (:wait t)
  )

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(bibtex-aux-opt-alist
   '(("keywords" "Keywords to describe the entry" "")
     ("file" "Relative or absolute path to attachments" "")) nil nil "Customized with use-package bibtex")
 '(custom-safe-themes
   '("acd363510d3e4b638db178783bde3d4492574c0f5c889f845251949f43567d16"
     "f2f42f0b7c53736840fc3ff5751235e3b87cc535b04ddaf3423e2926548bfbb4"
     default)))

;; ENVIRONMENT VARIABLES

(use-package exec-path-from-shell
  :ensure (:wait t))

(when (memq window-system '(mac ns x pgtk)) (exec-path-from-shell-initialize))

(when (daemonp)
  (exec-path-from-shell-initialize))

;; EXTRACT FUNCTION

;;; sia-move-region-to-heading.el --- Move a region under a heading in another file, leaving a link behind -*- lexical-binding: t; -*-

(require 'vulpea)
(require 'org-id)
(require 'denote)

(defconst sia--new-heading-candidate "[+ Create new heading here]"
  "Special entry in the heading-selection prompt.
Choosing it creates a new top-level heading at the end of the
file instead of picking one of the existing headings.")

(defun sia--denote-create-and-get-path (title)
  "Create a new Denote note titled TITLE and return its file path.
The note is created with `denote' using default keywords/subdirectory/etc.
(rename it afterwards with your usual `denote-rename-file' /
`denote-rename-file-using-front-matter' bindings if needed). The
creation buffer is not left on screen -- window layout is
restored once the file path is captured."
  (let (path)
    (save-window-excursion
      (denote title)
      (setq path (buffer-file-name)))
    path))

(defun sia--vulpea-select-or-create-file ()
  "Select an existing note via Vulpea, or create one with Denote.
Uses the same note database and prompt UI as `vulpea-find'. If
your input at the prompt doesn't match any existing note (i.e.
nothing in the completion corresponds to an actual file), you're
asked to confirm creating a new Denote note with that text as
its title; the new note becomes the target file."
  (let ((selection (vulpea-select "Move region to note: ")))
    (cond
     ;; An existing note was chosen.
     ((and (vulpea-note-p selection) (vulpea-note-path selection))
      (vulpea-note-path selection))
     ;; Vulpea couldn't match anything -- it may hand back a stub
     ;; note with no path, a plain string, or nil, depending on
     ;; how the prompt was left. Offer to create a note either way.
     (t
      (let ((title (cond ((vulpea-note-p selection) (vulpea-note-title selection))
                          ((stringp selection) selection)
                          (t (read-string "Title for new note: ")))))
        (unless (and title (not (string-empty-p title)))
          (user-error "No target selected"))
        (unless (y-or-n-p
                 (format "No note found for \"%s\" -- create it with Denote? " title))
          (user-error "No target selected"))
        (sia--denote-create-and-get-path title))))))

(defun sia--org-heading-candidates (file)
  "Return an alist of (OUTLINE-PATH . MARKER) for each heading in FILE.
OUTLINE-PATH is the full ancestor chain joined with \" > \", so
headings with the same text under different parents are shown
distinctly. Returns nil if FILE has no headings."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (org-map-entries
      (lambda ()
        (cons (mapconcat #'identity
                          (append (org-get-outline-path)
                                  (list (org-get-heading t t t t)))
                          " > ")
              (point-marker)))))))

(defun sia--create-heading-at-end (file)
  "Prompt for a title and insert a new top-level heading at the end of FILE.
Return a cons cell (MARKER . TITLE)."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (let ((title (read-string "New heading title: ")))
        (insert "* " title "\n")
        (cons (point-marker) title)))))

(defun sia--read-org-heading (file)
  "Prompt for a heading in FILE with completion.
Return a cons cell (MARKER . PATH), where PATH is the full
outline path string (used later as the link description).

If FILE has no headings at all, the prompt is skipped entirely
and a new top-level heading is created directly. Otherwise, the
prompt includes an extra option to create a new heading at the
end of the file instead of picking an existing one."
  (let ((candidates (sia--org-heading-candidates file)))
    (if (null candidates)
        (sia--create-heading-at-end file)
      (let ((choice (completing-read
                     "Under heading: "
                     (cons sia--new-heading-candidate candidates)
                     nil t)))
        (if (string= choice sia--new-heading-candidate)
            (sia--create-heading-at-end file)
          (cons (cdr (assoc choice candidates)) choice))))))

(defun sia--org-file-title ()
  "Return the #+title: keyword of the current buffer.
Falls back to the file name if no #+title: line is present."
  (or (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" nil t)
          (string-trim (match-string 1))))
      (file-name-nondirectory (or (buffer-file-name) ""))))

(defun sia--org-file-id ()
  "Return the file-level :ID: of the current buffer, creating one if needed.
This lives in the file's own property drawer, before the first
heading, and is what a whole-file id: link points at."
  (save-excursion
    (goto-char (point-min))
    (org-id-get-create)))

(defun sia--resources-heading-p (title)
  "Non-nil if TITLE (a clean heading string, tags/TODO/priority stripped) is
\"Resources\", regardless of case (so \"resources\", \"RESOURCES\",
\"ReSoUrCeS\", etc. all match)."
  (string-equal (downcase title) "resources"))

(defun sia--link-target-at-point (path)
  "Return (ID . DESCRIPTION) to link to for the heading at point.
Normally this is the heading itself: an ID is created for it if
needed (via `org-id-get-create'), and PATH (its outline path, or
its title if newly created) is used as the description.

But if the heading is called \"Resources\", in any case (see
`sia--resources-heading-p'), it's treated as a generic bucket
that shouldn't be linked to directly, and no ID is added to it
at all:
 - a level-1 \"Resources\" heading falls back to the file itself
   (file-level ID and #+title:);
 - a lower-level \"Resources\" heading falls back to its parent
   heading (or, in the unusual case that it has no parent, to
   the file itself)."
  (let ((heading-title (org-get-heading t t t t)))
    (if (sia--resources-heading-p heading-title)
        (if (eql (org-current-level) 1)
            (cons (sia--org-file-id) (sia--org-file-title))
          (save-excursion
            (if (org-up-heading-safe)
                (cons (org-id-get-create) (org-get-heading t t t t))
              (cons (sia--org-file-id) (sia--org-file-title)))))
      (cons (org-id-get-create) path))))

(defun sia-move-region-to-heading (start end target path)
  "Cut the region from START to END and insert it under the heading at TARGET.
TARGET is a marker pointing at the chosen heading; PATH is its
full outline path (or its title, if newly created). Prompts for
a target note via Vulpea's ID-based selection (so you search by
title/ID rather than navigating directories); if nothing
matches, offers to create a new Denote note on the spot. Then
prompts for a heading within that note (with completion,
disambiguated by full outline path, plus an option to create a
new heading) -- or, if the note has no headings yet, skips
straight to creating one.

The text is always inserted as the last content of the TARGET
heading's subtree -- after any existing body text or
sub-headings, but before the next heading of equal or higher
level.

The link left behind at point in the source buffer normally
points to TARGET itself. The exception is a heading literally
named \"Resources\" (see `sia--link-target-at-point'): no ID is
added to it, and the link instead points to the file (for a
level-1 \"Resources\" heading) or to its parent heading
(otherwise) -- Resources sections are treated as a generic
bucket, not something worth linking to directly."
  (interactive
   (let* ((start (region-beginning))
          (end (region-end))
          (file (sia--vulpea-select-or-create-file))
          (result (sia--read-org-heading file))
          (target (car result))
          (path (cdr result)))
     (list start end target path)))
  (let ((text (buffer-substring-no-properties start end))
        id desc)
    (delete-region start end)
    (with-current-buffer (marker-buffer target)
      (save-excursion
        (goto-char target)
        (pcase-let ((`(,link-id . ,link-desc) (sia--link-target-at-point path)))
          (setq id link-id
                desc link-desc))
        (goto-char target)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n"))
        (insert text)
        (unless (string-suffix-p "\n" text) (insert "\n")))
      (save-buffer))
    (insert (org-link-make-string (concat "id:" id) desc))))

(keymap-global-set "M-a" #'sia-move-region-to-heading)

(provide 'sia-move-region-to-heading)
;;; sia-move-region-to-heading.el ends here

;; Suppress unnecessary warnings

;; You can set minimum severity level for displaying the warning buffer to :error or :emergency:
;; https://emacs.stackexchange.com/questions/78800/how-to-disable-automatic-appearance-of-warnings-buffer-in-emacs

(setq warning-minimum-level :error)

;; Autochange theme with dark mode

(defun my-load-theme (appearance)
  (mapc #'disable-theme custom-enabled-themes)
  (pcase appearance
    ('light (load-theme 'ef-melissa-light t))
    ('dark  (load-theme 'ef-dream t))))

(add-hook 'ns-system-appearance-change-functions #'my-load-theme)

;; Create dataview-like tables through the vulpea query system



;;; sia-vulpea-dblock.el --- Dataview-style property tables, backed by Vulpea -*- lexical-binding: t; -*-

(require 'vulpea)
(require 'org-table)

(defun sia-vulpea-dblock--cell (note column)
  "Return a display string for COLUMN of NOTE.
COLUMN is either a keyword naming a built-in field:
  :title  :tags  :id  :file
or a string naming a Vulpea meta key -- i.e. a \"KEY :: value\"
description-list entry in the note, read via
`vulpea-note-meta-get-list'. Multiple values for the same key are
joined with \", \"."
  (pcase column
    (:title (or (vulpea-note-title note) ""))
    (:tags (mapconcat #'identity (vulpea-note-tags note) ", "))
    (:id (vulpea-note-id note))
    (:file (file-name-nondirectory (vulpea-note-path note)))
    ((pred stringp)
     (mapconcat #'identity
                (or (vulpea-note-meta-get-list note column) '(""))
                ", "))
    (_ "")))

(defun sia-vulpea-dblock--header-label (column)
  "Return a display label for COLUMN (see `sia-vulpea-dblock--cell')."
  (if (keywordp column) (capitalize (substring (symbol-name column) 1)) column))

(defun sia-vulpea--resolve-parent-of (parent-of)
  "Resolve PARENT-OF to a literal note ID.
If PARENT-OF is the string \"self\" or the symbol `self', resolve
it to the ID of the note visited by the *current buffer*
(creating one via `org-id-get-create' at the top of the file if
it doesn't have one yet). Any other value -- nil, or an actual
ID string -- is returned unchanged."
  (if (member parent-of '("self" self))
      (save-excursion (goto-char (point-min)) (org-id-get-create))
    parent-of))

(defun sia-vulpea--note-matches-p (note tags parent-of parent-prop)
  "Non-nil if NOTE matches TAGS and, if given, PARENT-OF.
TAGS is a list NOTE's tags must all include (nil matches
everything). PARENT-OF, if non-nil, must already be a resolved
literal ID (see `sia-vulpea--resolve-parent-of') -- NOTE matches
only if its PARENT-PROP meta property (default \"parents\")
links to that ID."
  (and (or (null tags)
           (seq-every-p (lambda (tag) (seq-contains-p (vulpea-note-tags note) tag)) tags))
       (or (null parent-of)
           (seq-contains-p (vulpea-note-meta-get-list note (or parent-prop "parents") 'link)
                            parent-of))))

(defun sia-vulpea--note-tag-annotation (note)
  "Return a tag annotation string for NOTE, or \"\" if it has none.
`vulpea-note-tags' already reflects the right source depending on
NOTE's level -- filetags for a file-level note, heading tags for
a heading-level one -- so this shows the correct tags either way
without needing to special-case it, mirroring the sort of
tag-annotated candidates `org-node' shows in its completion."
  (let ((tags (vulpea-note-tags note)))
    (if tags
        (propertize (format "  :%s:" (mapconcat #'identity tags ":"))
                    'face 'org-tag)
      "")))

(defun sia-vulpea-select-note (prompt)
  "Select a Vulpea note via completion, annotated with its tags.
Built directly on `vulpea-db-query' and `completing-read' with a
plain `:annotation-function' -- standard completion metadata that
Vertico (and other UIs) already understand -- rather than
`vulpea-select', since I couldn't confirm that function exposes
a documented hook for customizing candidate display; this gets
the same practical result (see PROMPT; tags shown per
candidate) without depending on unconfirmed internals. Returns
the selected `vulpea-note', or nil if PROMPT was aborted."
  (let* ((notes (vulpea-db-query))
         (cands (mapcar (lambda (n) (cons (vulpea-note-title n) n)) notes))
         (completion-extra-properties
          (list :annotation-function
                (lambda (title) (sia-vulpea--note-tag-annotation (cdr (assoc title cands)))))))
    (cdr (assoc (completing-read prompt cands nil t) cands))))

(defun sia-vulpea-read-parent (&optional allow-self)
  "Interactively choose a parent-of value, returning nil/\"self\"/an ID.
Offers: no filtering, the current note itself (only if
ALLOW-SELF), or `sia-vulpea-select-note' to pick any note (tags
shown per candidate, to disambiguate same-titled notes). \"self\"
is returned literally, unresolved -- callers that need it
resolved immediately should still run it through
`sia-vulpea--resolve-parent-of'."
  (let* ((choices (append '("None")
                           (when allow-self '("Current note (self)"))
                           '("Choose a note...")))
         (choice (completing-read "Filter to children of: " choices nil t)))
    (cond
     ((string= choice "None") nil)
     ((string= choice "Current note (self)") "self")
     (t (let ((note (sia-vulpea-select-note "Parent note: ")))
          (and note (vulpea-note-id note)))))))

(defun org-dblock-write:vulpea-table (params)
  "Write a Dataview-style table of Vulpea notes into the current dynamic block.
Recognized PARAMS:

  :tags      List of tags to filter by; a note must have ALL of
             them to be included. Omit (or nil) for every note.

  :columns   List of columns to show, in order. Each entry is
             either a keyword (:title, :tags, :id, :file) or a
             string naming a Vulpea meta key (e.g. \"status\",
             \"author\", \"rating\"). Defaults to just (:title).

  :sort-by   A single column (same shape as above) to sort rows
             by, ascending, as a string comparison. Optional.

  :parent-of An ID, or the literal string \"self\", to filter
             by: only notes whose :parent-prop meta property
             links to this ID are included. \"self\" resolves
             dynamically, on every write, to the ID of the note
             this dblock itself lives in -- so a block placed in
             a parent note always shows its current children.
             Optional; omit for no such filtering.

  :parent-prop  Which meta property to check for :parent-of.
             Defaults to \"parents\".

Example block, written by hand or via `org-create-dblock':

  #+BEGIN: vulpea-table :tags (\"book\") :columns (:title \"author\" \"rating\") :sort-by \"rating\"
  #+END:

  #+BEGIN: vulpea-table :parent-of self :columns (:title)
  #+END:

Regenerate with `org-dblock-update' (C-c C-c on the #+BEGIN
line) or `org-update-all-dblocks' for every block in the buffer."
  (let* ((tags (plist-get params :tags))
         (columns (or (plist-get params :columns) '(:title)))
         (sort-by (plist-get params :sort-by))
         (parent-of (sia-vulpea--resolve-parent-of (plist-get params :parent-of)))
         (parent-prop (plist-get params :parent-prop))
         (notes (vulpea-db-query
                 (lambda (note)
                   (sia-vulpea--note-matches-p note tags parent-of parent-prop))))
         (notes (if sort-by
                    (seq-sort-by (lambda (n) (sia-vulpea-dblock--cell n sort-by))
                                 #'string< notes)
                  notes)))
    (insert "| " (mapconcat #'sia-vulpea-dblock--header-label columns " | ") " |\n")
    (insert "|-\n")
    (dolist (note notes)
      (insert "| "
              (mapconcat (lambda (c) (sia-vulpea-dblock--cell note c)) columns " | ")
              " |\n"))
    (when notes
      (delete-char -1))
    (org-table-align)))

(defun sia-insert-vulpea-table ()
  "Insert a new vulpea-table dynamic block at point, prompting for params.
A quick way to get a starting block without hand-typing the
#+BEGIN: line; edit the params afterwards as needed."
  (interactive)
  (let* ((tags (split-string (read-string "Filter by tags (space-separated, blank for all): ") nil t))
         (columns-raw (split-string
                       (read-string "Columns (space-separated; :title/:tags/:id/:file or meta keys): "
                                    ":title")
                       nil t))
         (columns (mapcar (lambda (c) (if (string-prefix-p ":" c) (intern c) c)) columns-raw))
         (sort-by (let ((s (read-string "Sort by column (blank for none): ")))
                    (unless (string-empty-p s)
                      (if (string-prefix-p ":" s) (intern s) s)))))
    (org-create-dblock
     (list :name "vulpea-table"
           :tags tags
           :columns columns
           :sort-by sort-by))
    (org-update-dblock)))

(provide 'sia-vulpea-dblock)
;;; sia-vulpea-dblock.el ends here

;;; sia-vulpea-vui-table.el --- Interactive Vulpea property tables via vui.el -*- lexical-binding: t; -*-

(require 'vui)
(require 'vulpea)
(require 'sia-vulpea-dblock) ; for sia-vulpea--resolve-parent-of / sia-vulpea--note-matches-p

;;; Cross-buffer refresh broadcasting ----------------------------------

(defvar sia-vulpea-table-refresh-functions nil
  "Abnormal hook: functions called with no arguments to signal that
open live Vulpea tables should refresh. Each mounted
`sia-vulpea-table' instance subscribes to this while it's alive
(via `vui-use-effect') and unsubscribes on unmount.")

(defun sia-vulpea-refresh-all-tables ()
  "Signal every open live Vulpea table to refresh itself."
  (interactive)
  (run-hook-with-args 'sia-vulpea-table-refresh-functions))

(defvar sia-vulpea--refresh-after-save-timer nil)

(defun sia-vulpea--schedule-refresh-after-save ()
  "Debounced trigger for `sia-vulpea-refresh-all-tables' after a note is saved.
There's no confirmed public \"Vulpea db sync completed\" hook to
key off of directly, so this waits half a second after any Org
save -- on the assumption your existing `vulpea-db-autosync'
setup updates the db synchronously (or near enough) on save --
before broadcasting the refresh. If tables sometimes reload with
stale data, this delay is the first thing to lengthen."
  (when (and buffer-file-name (derived-mode-p 'org-mode))
    (when (timerp sia-vulpea--refresh-after-save-timer)
      (cancel-timer sia-vulpea--refresh-after-save-timer))
    (setq sia-vulpea--refresh-after-save-timer
          (run-with-timer 0.5 nil #'sia-vulpea-refresh-all-tables))))

(add-hook 'after-save-hook #'sia-vulpea--schedule-refresh-after-save)

;;; Writing a meta property back to its note ----------------------------

(defun sia-vulpea--write-meta (note key value)
  "Set NOTE's meta property KEY to VALUE, in NOTE's own file.
Rewrites the existing \"- KEY :: ...\" description-list line if
one exists; otherwise inserts a new one just before the first
heading (or at the end of the file, if there is no heading).

I could not confirm a public Vulpea function for writing this
description-list metadata format -- only the older #+KEYWORD:
file-property system (`vulpea-buffer-prop-set') is documented --
so this edits the line directly, in the same format
`vulpea-note-meta-get-list' reads. Saves the buffer; relies on
your existing autosync to pick the change up (which, via
`sia-vulpea--schedule-refresh-after-save' above, also refreshes
every open live table -- including this one)."
  (with-current-buffer (find-file-noselect (vulpea-note-path note))
    (save-excursion
      (goto-char (point-min))
      (let* ((case-fold-search t)
             (re (format "^\\(-[ \t]+%s[ \t]+::[ \t]*\\).*$" (regexp-quote key)))
             (escaped (replace-regexp-in-string "\\\\" "\\\\\\\\" value)))
        (if (re-search-forward re nil t)
            (replace-match (concat "\\1" escaped) t)
          (goto-char (point-min))
          (if (re-search-forward "^\\*" nil t)
              (progn (beginning-of-line) (insert (format "- %s :: %s\n" key value)))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert (format "- %s :: %s\n" key value))))))
    (save-buffer)))

(defun sia-vulpea-vui--cell (note column)
  "Return a display string for COLUMN of NOTE.
Same COLUMN shapes as the dblock version: a keyword for a
built-in field (:tags, :id, :file), or a string naming a Vulpea
meta key. :title is handled separately by the caller, since it
becomes a button rather than plain text."
  (pcase column
    (:tags (mapconcat #'identity (vulpea-note-tags note) ", "))
    (:id (vulpea-note-id note))
    (:file (file-name-nondirectory (vulpea-note-path note)))
    ((pred stringp)
     (mapconcat #'identity (or (vulpea-note-meta-get-list note column) '(""))
                ", "))
    (_ "")))

(defun sia-vulpea-vui--header-label (column)
  "Return a display label for COLUMN."
  (if (keywordp column) (capitalize (substring (symbol-name column) 1)) column))

(vui-defcomponent sia-vulpea-table (tags columns sort-by parent-of parent-prop parent-title)
  "A live, clickable, editable table of Vulpea notes.
TAGS filters notes (must have all of them). COLUMNS is the
ordered list of fields to show -- :title is always a button that
opens the note; :tags/:id/:file are read-only; a string (a meta
key) is rendered as an editable field that writes straight back
to the note on submit (see `sia-vulpea--write-meta'). SORT-BY is
the initial sort column; click any column's button in the \"Sort
by:\" row to change it live, or click it again to reverse
direction -- this overrides SORT-BY once clicked (mirrors what
you called \"overwriting the :sort property\"). PARENT-OF/
PARENT-PROP/PARENT-TITLE are as in `sia-vulpea--note-matches-p'
and the parent-display line.

The table also refreshes automatically: it subscribes to
`sia-vulpea-table-refresh-functions' while mounted, which fires
after any note is saved (see `sia-vulpea--schedule-refresh-after-save')."
  :state ((refresh-tick 0)
          (sort-override nil)
          (sort-desc nil))
  :render
  (progn
    (vui-use-effect ()
      (let ((fn (lambda () (vui-set-state :refresh-tick #'1+))))
        (add-hook 'sia-vulpea-table-refresh-functions fn)
        (lambda () (remove-hook 'sia-vulpea-table-refresh-functions fn))))
    (let* ((effective-sort (or sort-override sort-by))
           (notes (vulpea-db-query
                   (lambda (note)
                     (sia-vulpea--note-matches-p note tags parent-of parent-prop))))
           (notes (if effective-sort
                      (let ((sorted (seq-sort-by
                                     (lambda (n) (sia-vulpea-vui--cell n effective-sort))
                                     #'string< notes)))
                        (if sort-desc (reverse sorted) sorted))
                    notes))
           (vui-columns (mapcar (lambda (c)
                                   (list :header (sia-vulpea-vui--header-label c) :width 24))
                                 columns))
           (rows (mapcar
                  (lambda (note)
                    (mapcar
                     (lambda (c)
                       (cond
                        ((eq c :title)
                         (vui-button (vulpea-note-title note)
                                     :on-click (lambda () (find-file (vulpea-note-path note)))))
                        ((keywordp c) (sia-vulpea-vui--cell note c))
                        (t
                         ;; A meta key: editable. NOTE: I'm not fully
                         ;; certain `vui-field' uses :on-change for its
                         ;; commit callback -- check `describe-function
                         ;; vui-field' if edits don't seem to take.
                         (vui-field
                          :value (car (or (vulpea-note-meta-get-list note c) '("")))
                          :on-change (lambda (val)
                                       (sia-vulpea--write-meta note c val)
                                       (vui-set-state :refresh-tick #'1+))))))
                     columns))
                  notes)))
      (vui-vstack
       (when parent-title
         (vui-text (format "Parent: %s" parent-title) :face 'bold))
       (vui-text (format "%d note%s" (length notes) (if (= (length notes) 1) "" "s"))
                  :face 'shadow)
       (vui-newline)
       (apply #'vui-hstack
              (vui-text "Sort by: " :face 'shadow)
              (mapcar
               (lambda (c)
                 (vui-button
                  (concat (sia-vulpea-vui--header-label c)
                          (cond ((not (equal effective-sort c)) "")
                                (sort-desc " \u2193") (t " \u2191")))
                  :on-click (lambda ()
                              (if (equal sort-override c)
                                  (vui-set-state :sort-desc (not sort-desc))
                                (progn (vui-set-state :sort-override c)
                                       (vui-set-state :sort-desc nil))))))
               columns))
       (vui-newline)
       (vui-table :columns vui-columns :rows rows :border :ascii)))))

(defun sia-vulpea--table-buffer-name (view-name parent-of)
  "Return a buffer name for a live Vulpea table.
VIEW-NAME, if given, names it directly (so each saved view gets
its own persistent buffer instead of all views sharing one).
Otherwise, if PARENT-OF is set, name it after that note's title
so ad-hoc \"children of X\" queries are still distinguishable.
Falls back to a generic name."
  (cond
   (view-name (format "*vulpea: %s*" view-name))
   (parent-of
    (let ((note (ignore-errors (vulpea-db-get-by-id parent-of))))
      (format "*vulpea: children of %s*" (if note (vulpea-note-title note) parent-of))))
   (t "*vulpea table*")))

(defun sia-vulpea-open-table (&optional tags columns sort-by parent-of parent-prop view-name)
  "Open a live, clickable table of Vulpea notes in its own buffer.
Prompts for TAGS/COLUMNS/SORT-BY/PARENT-OF/PARENT-PROP when
called interactively (same shapes as the vulpea-table dblock --
see `org-dblock-write:vulpea-table'). PARENT-OF is chosen via
`sia-vulpea-read-parent' (pick \"self\", or any note through
`sia-vulpea-select-note', tag-annotated); if it comes back as
\"self\", it's resolved against the buffer you called this from
-- i.e. whichever note you were visiting -- *before* the new
table buffer takes over, so \"self\" means what you'd expect even
though the table itself opens somewhere else.

VIEW-NAME (only meaningful when called non-interactively, e.g.
from `sia-vulpea-open-saved-table') gives the resulting buffer
its own name, so different saved views stay in separate,
independently reusable buffers rather than overwriting each
other. The buffer also displays which parent note it's scoped
to, when PARENT-OF is set.

Click a title to open that note; press `g' in the resulting
buffer to refresh against the current state of the Vulpea db."
  (interactive
   (let* ((tags (split-string (read-string "Filter by tags (space-separated, blank for all): ") nil t))
          (columns-raw (split-string
                        (read-string "Columns (space-separated; :title/:tags/:id/:file or meta keys): "
                                     ":title")
                        nil t))
          (columns (mapcar (lambda (c) (if (string-prefix-p ":" c) (intern c) c)) columns-raw))
          (sort-by (let ((s (read-string "Sort by column (blank for none): ")))
                     (unless (string-empty-p s)
                       (if (string-prefix-p ":" s) (intern s) s))))
          (parent-of (sia-vulpea-read-parent t))
          (parent-prop (let ((s (read-string "Parent meta property (blank for \"parents\"): ")))
                          (unless (string-empty-p s) s))))
     ;; Resolve "self" now, in the buffer this command was called
     ;; from -- by the time vui-mount switches buffers below, we'd
     ;; have lost that context.
     (list tags columns sort-by (sia-vulpea--resolve-parent-of parent-of) parent-prop)))
  (let ((parent-title (and parent-of
                            (let ((note (ignore-errors (vulpea-db-get-by-id parent-of))))
                              (and note (vulpea-note-title note))))))
    (vui-mount (vui-component 'sia-vulpea-table
                 :tags tags :columns columns :sort-by sort-by
                 :parent-of parent-of :parent-prop parent-prop :parent-title parent-title)
               (sia-vulpea--table-buffer-name view-name parent-of))))

(provide 'sia-vulpea-vui-table)
;;; sia-vulpea-vui-table.el ends here

;;; sia-vulpea-table-views.el --- Named views + inline mounting for Vulpea vui tables -*- lexical-binding: t; -*-

;; Requires the two earlier pieces to already be loaded (either as
;; separate files with their own (provide ...), or pasted into
;; init.el before this, in order):
;;   - sia-vulpea-dblock.el     (org-dblock-write:vulpea-table, the
;;                                static-text fallback)
;;   - sia-vulpea-vui-table.el  (the sia-vulpea-table vui component,
;;                                sia-vulpea-open-table)

(require 'vui)
(require 'vulpea)
(require 'sia-vulpea-vui-table)
(require 'sia-vulpea-dblock)

;;; Named views ---------------------------------------------------------

(defcustom sia-vulpea-table-views-file
  (expand-file-name "sia-vulpea-table-views.el" user-emacs-directory)
  "File where named Vulpea table views are persisted."
  :type 'file
  :group 'vulpea)

(defvar sia-vulpea-table-views nil
  "Alist of (NAME . (TAGS COLUMNS SORT-BY)) for saved Vulpea table views.")

(defun sia-vulpea-table-views-load ()
  "Load saved views from `sia-vulpea-table-views-file', if present."
  (setq sia-vulpea-table-views
        (when (file-exists-p sia-vulpea-table-views-file)
          (with-temp-buffer
            (insert-file-contents sia-vulpea-table-views-file)
            (read (current-buffer))))))

(defun sia-vulpea--insert-view-entry (entry)
  "Insert ENTRY -- a (NAME TAGS COLUMNS SORT-BY PARENT-OF PARENT-PROP)
list, as stored in `sia-vulpea-table-views' -- as one annotated,
indented Lisp form, each field on its own line with a trailing
comment naming it."
  (pcase-let ((`(,name ,tags ,columns ,sort-by ,parent-of ,parent-prop) entry))
    (insert (format " (%S\n" name))
    (insert (format "  %-28S ; tags\n" tags))
    (insert (format "  %-28S ; columns\n" columns))
    (insert (format "  %-28S ; sort-by\n" sort-by))
    (insert (format "  %-28S ; parent-of\n" parent-of))
    (insert (format "  %-28S) ; parent-prop\n" parent-prop))))

(defun sia-vulpea-table-views-save-to-disk ()
  "Persist `sia-vulpea-table-views' to `sia-vulpea-table-views-file'.
Written as annotated, human-readable Lisp rather than a single
compact `prin1' dump -- comments are transparent to the Lisp
reader, so `sia-vulpea-table-views-load' still reads this back
as one plain sexp, but the file itself can also be read (or
hand-edited) without decoding a bare space-separated property
list."
  (with-temp-file sia-vulpea-table-views-file
    (insert ";; Saved Vulpea table views -- generated by `sia-vulpea-table-view-save'.\n")
    (insert ";; Each entry below: (NAME TAGS COLUMNS SORT-BY PARENT-OF PARENT-PROP)\n")
    (insert ";;   NAME         view name, as typed when saving\n")
    (insert ";;   TAGS         list of tags a note must have ALL of (nil = no filter)\n")
    (insert ";;   COLUMNS      ordered fields to show: :title/:tags/:id/:file, or a\n")
    (insert ";;                string naming a meta key\n")
    (insert ";;   SORT-BY      column to sort by (nil = unsorted)\n")
    (insert ";;   PARENT-OF    a note ID, the literal \"self\", or nil (no parent filter)\n")
    (insert ";;   PARENT-PROP  meta key checked against PARENT-OF (nil = default \"parents\")\n")
    (insert "(\n")
    (dolist (entry sia-vulpea-table-views)
      (sia-vulpea--insert-view-entry entry))
    (insert ")\n")))

(sia-vulpea-table-views-load)

(defun sia-vulpea--read-column-list (&optional prompt)
  "Read a space-separated list of columns as keywords/strings."
  (mapcar (lambda (c) (if (string-prefix-p ":" c) (intern c) c))
          (split-string (read-string (or prompt "Columns: ") ":title") nil t)))

(defun sia-vulpea--read-tags ()
  "Read a space-separated list of tags."
  (split-string (read-string "Filter by tags (space-separated, blank for all): ") nil t))

(defun sia-vulpea--read-sort-by ()
  "Read an optional single sort column."
  (let ((s (read-string "Sort by column (blank for none): ")))
    (unless (string-empty-p s) (if (string-prefix-p ":" s) (intern s) s))))

(defun sia-vulpea-table-view-save (name tags columns sort-by parent-of parent-prop)
  "Save (or overwrite) a named Vulpea table view, persisted to disk.
PARENT-OF is chosen via `sia-vulpea-read-parent' -- \"None\",
\"Current note (self)\", or any note picked through
`sia-vulpea-select-note' (candidates show their tags). A
\"self\" choice is stored as-typed, not resolved now -- it's
resolved fresh every time the view is opened, so a \"self\" view
means \"children of whatever note I'm in right now\", wherever
you invoke it from."
  (interactive
   (list (read-string "Save view as: ")
         (sia-vulpea--read-tags)
         (sia-vulpea--read-column-list
          "Columns (space-separated; :title/:tags/:id/:file or meta keys): ")
         (sia-vulpea--read-sort-by)
         (sia-vulpea-read-parent t)
         (let ((s (read-string "Parent meta property (blank for \"parents\"): ")))
           (unless (string-empty-p s) s))))
  (setf (alist-get name sia-vulpea-table-views nil nil #'string=)
        (list tags columns sort-by parent-of parent-prop))
  (sia-vulpea-table-views-save-to-disk)
  (message "Saved Vulpea table view \"%s\"" name))

(defun sia-vulpea-table-view-delete (name)
  "Delete a saved Vulpea table view by NAME, with completion."
  (interactive (list (completing-read "Delete view: "
                                       (mapcar #'car sia-vulpea-table-views) nil t)))
  (setq sia-vulpea-table-views (assoc-delete-all name sia-vulpea-table-views))
  (sia-vulpea-table-views-save-to-disk)
  (message "Deleted Vulpea table view \"%s\"" name))

(defun sia-vulpea--select-view ()
  "Prompt for a saved view name with completion.
Return (TAGS COLUMNS SORT-BY PARENT-OF PARENT-PROP), PARENT-OF
still unresolved (may literally be \"self\")."
  (unless sia-vulpea-table-views
    (user-error "No saved Vulpea table views yet -- use `sia-vulpea-table-view-save' first"))
  (let ((name (completing-read "View: " (mapcar #'car sia-vulpea-table-views) nil t)))
    (cdr (assoc name sia-vulpea-table-views))))

(defun sia-vulpea-open-saved-table ()
  "Select a saved Vulpea table view (minibuffer completion) and open it live.
Opens into a buffer named after the view (e.g. \"*vulpea:
NAME*\"), so different saved views stay in their own separate,
independently reusable buffers rather than sharing one. A
\"self\" parent-of in the view is resolved against the buffer
this command was called from, before the new table buffer takes
over -- same reasoning as in `sia-vulpea-open-table'."
  (interactive)
  (unless sia-vulpea-table-views
    (user-error "No saved Vulpea table views yet -- use `sia-vulpea-table-view-save' first"))
  (let* ((name (completing-read "View: " (mapcar #'car sia-vulpea-table-views) nil t))
         (view (cdr (assoc name sia-vulpea-table-views))))
    (pcase-let ((`(,tags ,columns ,sort-by ,parent-of ,parent-prop) view))
      (sia-vulpea-open-table tags columns sort-by
                             (sia-vulpea--resolve-parent-of parent-of)
                             parent-prop
                             name))))

;;; Inline mounting -------------------------------------------------------

(defvar-local sia-vulpea--inline-table-instances nil
  "Alist of (MARKER . VUI-INSTANCE) for live inline Vulpea tables
currently mounted in this buffer.")

(defvar-local sia-vulpea--inline-tables-active nil
  "Non-nil if inline Vulpea tables are meant to stay live in this
buffer -- survives save/reopen via the hooks below.")

(defun sia-vulpea--dblock-vulpea-table-regions ()
  "Return (PARAMS CONTENT-BEGIN CONTENT-END) for each vulpea-table
dblock in the buffer, top-to-bottom."
  (let (blocks)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*#\\+BEGIN:[ \t]+vulpea-table\\(.*\\)$" nil t)
        (let* ((params-str (match-string 1))
               (params (ignore-errors (car (read-from-string (format "(%s)" params-str)))))
               (content-begin (progn (forward-line 1) (point)))
               (content-end (if (re-search-forward "^[ \t]*#\\+END:" nil t)
                                 (line-beginning-position)
                               (point))))
          (when params (push (list params content-begin content-end) blocks)))))
    (nreverse blocks)))

(defun sia-vulpea-inline-tables-mount ()
  "Replace every vulpea-table dblock's content in this buffer with a
live, clickable `sia-vulpea-table' component. Blocks are processed
bottom-to-top so earlier positions stay valid as later ones are
rewritten."
  (interactive)
  (sia-vulpea--inline-tables-clear)
  (dolist (block (reverse (sia-vulpea--dblock-vulpea-table-regions)))
    (pcase-let ((`(,params ,cbeg ,cend) block))
      (let ((tags (plist-get params :tags))
            (columns (plist-get params :columns))
            (sort-by (plist-get params :sort-by))
            ;; Resolved here, in this note's own buffer, so "self"
            ;; means this note -- same as the dblock writer does.
            (parent-of (sia-vulpea--resolve-parent-of (plist-get params :parent-of)))
            (parent-prop (plist-get params :parent-prop)))
        (goto-char cbeg)
        (delete-region cbeg cend)
        (let* ((component (vui-component 'sia-vulpea-table
                            :tags tags
                            :columns columns
                            :sort-by sort-by
                            :parent-of parent-of
                            :parent-prop parent-prop))
               (instance (vui-mount-inline component)))
          (push (cons (copy-marker cbeg) instance) sia-vulpea--inline-table-instances)))))
  (setq sia-vulpea--inline-tables-active t))

(defun sia-vulpea--inline-tables-clear ()
  "Unmount live inline tables and regenerate plain dblock text in
their place, without touching `sia-vulpea--inline-tables-active'."
  (dolist (cell sia-vulpea--inline-table-instances)
    (vui-unmount (cdr cell)))
  (setq sia-vulpea--inline-table-instances nil)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*#\\+BEGIN:[ \t]+vulpea-table" nil t)
      (beginning-of-line)
      (ignore-errors (org-dblock-update)))))

(defun sia-vulpea-inline-tables-unmount ()
  "Unmount all live inline Vulpea tables in this buffer, restoring
plain (static) dblock text so the buffer has real content to save."
  (interactive)
  (sia-vulpea--inline-tables-clear)
  (setq sia-vulpea--inline-tables-active nil))

(defun sia-vulpea-inline-tables-toggle ()
  "Toggle live, clickable inline Vulpea tables in the current buffer."
  (interactive)
  (if sia-vulpea--inline-tables-active
      (progn (sia-vulpea-inline-tables-unmount)
             (message "Inline Vulpea tables: off"))
    (sia-vulpea-inline-tables-mount)
    (message "Inline Vulpea tables: on")))

(defun sia-vulpea--inline-tables-before-save ()
  "Unmount live inline tables before saving, so the file gets real
text instead of ephemeral widget state."
  (when sia-vulpea--inline-table-instances
    (sia-vulpea--inline-tables-clear)))

(defun sia-vulpea--inline-tables-after-save ()
  "Remount live inline tables after saving, if they were active."
  (when sia-vulpea--inline-tables-active
    (sia-vulpea-inline-tables-mount)))

(add-hook 'org-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'sia-vulpea--inline-tables-before-save nil t)
            (add-hook 'after-save-hook #'sia-vulpea--inline-tables-after-save nil t)))

;;; Insert a dblock from a saved view --------------------------------------

(defun sia-vulpea-insert-table-from-view ()
  "Insert a vulpea-table dblock at point, using a saved view
selected via minibuffer completion. PARENT-OF is inserted as-is
(including a literal \"self\") -- the dblock writer resolves it
fresh on every update, so a \"self\" view dropped into a note
always tracks that note's own children, not whichever note it
was inserted from."
  (interactive)
  (pcase-let ((`(,tags ,columns ,sort-by ,parent-of ,parent-prop) (sia-vulpea--select-view)))
    (org-create-dblock (list :name "vulpea-table" :tags tags :columns columns
                              :sort-by sort-by :parent-of parent-of :parent-prop parent-prop))
    (org-update-dblock)))

(keymap-global-set "C-c w t" #'sia-vulpea-inline-tables-toggle)
(keymap-global-set "C-c w v" #'sia-vulpea-open-saved-table)
(keymap-global-set "C-c w V" #'sia-vulpea-table-view-save)

(provide 'sia-vulpea-table-views)
;;; sia-vulpea-table-views.el ends here

;; Batch converting properties to plug into vulpea instead

;;; sia-vulpea-convert-properties.el --- Convert drawer properties to Vulpea meta lines -*- lexical-binding: t; -*-

(require 'org)
(require 'vulpea)

(defvar sia-vulpea-convert-property-blocklist
  '("ID" "CUSTOM_ID" "CATEGORY" "ARCHIVE" "ROAM_REFS" "ROAM_ALIASES"
    "ROAM_EXCLUDE" "ROAM_PLANNING" "BLOCKER" "TRIGGER" "ORDERED"
    "COOKIE_DATA" "LOG_INTO_DRAWER" "LOGGING" "VISIBILITY"
    "EXPORT_FILE_NAME" "EXPORT_TITLE" "DIR" "UNNUMBERED" ;; these were the ones that were added by Claude directly
    "CREATED" ;; this one is for the date that is added by org-node when you nodeify an entry
    )
  "Property names never converted to meta lines (case-insensitive).
These are properties Org, org-roam, or Vulpea itself read
directly out of the property drawer -- converting them to meta
lines would break that machinery (most importantly ID: Vulpea's
whole notion of \"a node\" depends on it staying a real
property). Add to this list before running a conversion if your
notes use other drawer properties something else depends on.")

;;; Low-level: one node at a time ---------------------------------------

(defun sia-vulpea--after-property-drawer-pos ()
  "Return the position right after the property drawer of the node at point.
\"Node at point\" is the heading at or above point, or the
file-level node if point is before the first heading.

For a heading, this is simply right after its own drawer (or
right after the heading line, if it has none).

For the file-level node, this additionally skips past any
leading #+KEYWORD: lines (#+title:, #+date:, #+filetags:, etc.)
in whatever order they appear relative to the property drawer.
Without this, meta lines inserted \"right after the drawer\"
would land *above* #+title:/#+date: whenever the drawer happens
to come first in the file -- which is exactly the bug this
guards against."
  (save-excursion
    (if (org-before-first-heading-p)
        (progn
          (goto-char (point-min))
          (let (moved)
            (setq moved t)
            (while moved
              (setq moved nil)
              (cond
               ((looking-at "^[ \t]*:PROPERTIES:[ \t]*$")
                (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                (forward-line 1)
                (setq moved t))
               ((looking-at "^[ \t]*#\\+[a-zA-Z_-]+:.*$")
                (forward-line 1)
                (setq moved t)))))
          (point))
      (org-back-to-heading t)
      (forward-line 1)
      (if (looking-at "^[ \t]*:PROPERTIES:[ \t]*$")
          (progn (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                 (forward-line 1)
                 (point))
        (point)))))

(defun sia-vulpea--insert-or-update-meta-line (key value)
  "Insert or update a \"- KEY :: VALUE\" meta line for the node at point.
Placed right after that node's property drawer. If a meta line
for KEY already exists between the drawer and the next heading
(or end of file, for the file-level node), its value is replaced
instead of adding a duplicate -- so re-running a conversion is
safe and idempotent."
  (let* ((start (sia-vulpea--after-property-drawer-pos))
         (end (save-excursion
                (goto-char start)
                (if (re-search-forward "^\\*" nil t) (line-beginning-position) (point-max))))
         (re (format "^\\(-[ \t]+%s[ \t]+::[ \t]*\\).*$" (regexp-quote key))))
    (save-excursion
      (goto-char start)
      (if (re-search-forward re end t)
          (replace-match (concat "\\1" value) t)
        (goto-char start)
        (insert (format "- %s :: %s\n" key value))))))

(defun sia-vulpea--ensure-blank-line-before-meta ()
  "Ensure a blank line separates the node at point's property
drawer (and, for the file-level node, its #+KEYWORD: lines) from
the meta block that begins right after them -- see
`sia-vulpea--after-property-drawer-pos'. Only inserts a newline
if the line immediately before that position isn't already
blank, so re-running a conversion never piles up extra blank
lines."
  (save-excursion
    (goto-char (sia-vulpea--after-property-drawer-pos))
    (unless (or (bobp)
                (save-excursion (forward-line -1) (looking-at "^[ \t]*$")))
      (insert "\n"))))

(defun sia-vulpea--convert-node-properties (&optional keep-original)
  "Convert the node at point's own drawer properties to meta lines.
\"Node at point\" is the heading at or above point, or the
file-level node if point is before the first heading. Only
properties not in `sia-vulpea-convert-property-blocklist', and
with a non-empty value, are converted; the property name is
downcased for the meta key. Unless KEEP-ORIGINAL is non-nil, each
converted property is then deleted from the drawer. If anything
was converted, a blank line is inserted before the meta block
(once, however many properties were converted) to separate it
from the drawer/front matter above -- see
`sia-vulpea--ensure-blank-line-before-meta'. Returns the list of
property names converted (empty if none)."
  (save-excursion
    (unless (org-before-first-heading-p) (org-back-to-heading t))
    (let ((converted nil))
      (dolist (prop (org-entry-properties (point) 'standard))
        (let ((name (car prop)) (value (cdr prop)))
          (unless (or (member (upcase name) sia-vulpea-convert-property-blocklist)
                      (null value)
                      (string-empty-p value))
            (sia-vulpea--insert-or-update-meta-line (downcase name) value)
            (push name converted)
            (unless keep-original (org-entry-delete (point) name)))))
      (when converted
        (sia-vulpea--ensure-blank-line-before-meta))
      (nreverse converted))))

(defun sia-vulpea-convert-properties-at-point (&optional keep-original)
  "Convert the drawer properties of the node at point to meta lines.
With KEEP-ORIGINAL (\\[universal-argument]), keep the properties
in the drawer too, instead of deleting each one as it's
converted."
  (interactive "P")
  (let ((converted (sia-vulpea--convert-node-properties keep-original)))
    (if converted
        (message "Converted: %s" (string-join converted ", "))
      (message "Nothing to convert here (all properties are blocklisted, or there are none)"))))

;;; Whole buffer, and every node in it -----------------------------------

(defun sia-vulpea-convert-buffer-properties-to-meta (&optional keep-original)
  "Convert drawer properties to meta lines for every recognized node
in the current buffer -- the file-level node (if it has an :ID:)
and every heading with an :ID:, i.e. every node Vulpea/org-roam
actually indexes here. Saves the buffer afterwards."
  (interactive "P")
  (let ((count 0))
    (save-excursion
      (goto-char (point-min))
      (when (org-entry-get (point-min) "ID")
        (when (sia-vulpea--convert-node-properties keep-original)
          (setq count (1+ count))))
      (org-map-entries
       (lambda ()
         (when (org-entry-get (point) "ID")
           (when (sia-vulpea--convert-node-properties keep-original)
             (setq count (1+ count)))))))
    (when (called-interactively-p 'any)
      (message "Converted properties on %d node%s in this buffer"
               count (if (= count 1) "" "s")))
    (save-buffer)
    count))

;;; Preview + real run across every Vulpea note ---------------------------

(defun sia-vulpea-preview-convert-all-notes-properties ()
  "Report, without changing anything, what a full conversion would do.
Lists, per note file, which non-blocklisted properties were
found on its recognized nodes. Run this before
`sia-vulpea-convert-all-notes-properties-to-meta' to sanity-check
`sia-vulpea-convert-property-blocklist' first -- nothing here
writes to any file."
  (interactive)
  (let ((files (seq-uniq (mapcar #'vulpea-note-path (vulpea-db-query))))
        (report nil))
    (dolist (file files)
      (with-current-buffer (find-file-noselect file)
        (save-excursion
          (let (found)
            (goto-char (point-min))
            (when (org-entry-get (point-min) "ID")
              (dolist (p (org-entry-properties (point-min) 'standard))
                (unless (member (upcase (car p)) sia-vulpea-convert-property-blocklist)
                  (push (car p) found))))
            (org-map-entries
             (lambda ()
               (when (org-entry-get (point) "ID")
                 (dolist (p (org-entry-properties (point) 'standard))
                   (unless (member (upcase (car p)) sia-vulpea-convert-property-blocklist)
                     (push (car p) found))))))
            (when found
              (push (format "%s: %s" (file-name-nondirectory file)
                            (string-join (seq-uniq found) ", "))
                    report))))))
    (if report
        (with-current-buffer (get-buffer-create "*vulpea property conversion preview*")
          (erase-buffer)
          (insert (string-join (nreverse report) "\n"))
          (goto-char (point-min))
          (display-buffer (current-buffer)))
      (message "Nothing would be converted -- every property found is blocklisted."))))

(defun sia-vulpea-convert-all-notes-properties-to-meta (&optional keep-original)
  "Convert drawer properties to meta lines across every Vulpea note.
Runs `sia-vulpea-convert-buffer-properties-to-meta' over every
file Vulpea currently knows about, saving each one. This edits
and saves your entire note collection -- run
`sia-vulpea-preview-convert-all-notes-properties' first, and back
up your notes (or commit, if under version control) before
running this, especially with KEEP-ORIGINAL nil (the default),
which deletes each converted property from its drawer as it goes."
  (interactive "P")
  (unless (y-or-n-p "This will edit and save every Vulpea note. Continue? ")
    (user-error "Aborted"))
  (let* ((files (seq-uniq (mapcar #'vulpea-note-path (vulpea-db-query))))
         (total 0))
    (dolist (file files)
      (with-current-buffer (find-file-noselect file)
        (setq total (+ total (sia-vulpea-convert-buffer-properties-to-meta keep-original)))))
    (message "Converted properties across %d node%s in %d note file%s"
             total (if (= total 1) "" "s")
             (length files) (if (= (length files) 1) "" "s"))))

(keymap-global-set "C-c w c" #'sia-vulpea-convert-properties-at-point)

(provide 'sia-vulpea-convert-properties)
;;; sia-vulpea-convert-properties.el ends here