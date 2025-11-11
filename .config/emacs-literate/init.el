;; This file has been generated from an org-mode file (=literate-config.org=)
;; DO NOT EDIT DIRECTLY, IT WILL BE OVERWRITTEN

(setq initial-major-mode 'org-mode
      initial-scratch-message (concat "#+title: Emacs Writing Studio\n"
					"#+subtitle: Scratch Buffer\n\n"
					"The text in this buffer is not saved "
					"when exiting Emacs!\n\n"))

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

;; Local Variables:
;; no-byte-compile: t
;; no-native-compile: t
;; no-update-autoloads: t

(setq load-path (cons "~/.config/emacs-literate/sia-modules" load-path))

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

(setq custom-file (make-temp-file "emacs-custom-"))

(use-package mixed-pitch
  :hook
  (org-mode . mixed-pitch-mode))

(use-package counsel)

(elpaca-wait)

(when (display-graphic-p)
    (context-menu-mode 1)
    (tool-bar-mode -1) ; If this were on, then I would get TWO toolbars at the same time, which is just crazy.
    (scroll-bar-mode -1)
    (horizontal-scroll-bar-mode -1)
    (setq visible-bell 1
          frame-inhibit-implied-resize t)
)

(package-initialize)

;; Path to the NANO emacs modules
(add-to-list 'load-path "~/.config/emacs-literate/nano")
(add-to-list 'load-path ".")

;; Default layout (optional)
(require 'nano-layout)

;; Theming Command line options (this will cancel warning messages)
(add-to-list 'command-switch-alist '("-dark"   . (lambda (args))))
(add-to-list 'command-switch-alist '("-light"  . (lambda (args))))
(add-to-list 'command-switch-alist '("-default"  . (lambda (args))))
(add-to-list 'command-switch-alist '("-no-splash" . (lambda (args))))
(add-to-list 'command-switch-alist '("-no-help" . (lambda (args))))
(add-to-list 'command-switch-alist '("-compact" . (lambda (args))))

;; Customize support for 'emacs -q' (Optional)
;; You can enable customizations by creating the nano-custom.el file
;; with e.g. `touch nano-custom.el` in the folder containing this file.
(let* ((this-file  (or load-file-name (buffer-file-name)))
       (this-dir  (file-name-directory this-file))
       (custom-path  (concat this-dir "nano-custom.el")))
  (when (and (eq nil user-init-file)
             (eq nil custom-file)
             (file-exists-p custom-path))
    (setq user-init-file this-file)
    (setq custom-file custom-path)
    (load custom-file)))

;; Theme
(require 'nano-faces)
(require 'nano-theme)
(require 'nano-theme-dark)
(require 'nano-theme-light)

(cond
 ((member "-default" command-line-args) t)
 ((member "-dark" command-line-args) (nano-theme-set-dark))
 (t (nano-theme-set-light)))
(call-interactively 'nano-refresh-theme)

(set-face-attribute 'default t
                    :family "Liberation Serif"
                    :weight 'bold)

(require 'nano-defaults) ; Nano default settings (optional)
(require 'nano-session) ; Nano session saving (optional)
(require 'nano-modeline) ; Nano header & mode lines (optional)
;; (require 'nano-bindings) ; Nano key bindings modification (optional)

;; Compact layout (need to be loaded after nano-modeline)
(when (member "-compact" command-line-args)
  (require 'nano-compact))

;; Nano counsel configuration (optional)
;; (require 'nano-counsel)

(require 'nano-splash)
(require 'nano-help)

(let ((inhibit-message t))
  (message "Welcome to GNU Emacs / N Λ N O edition")
  (message (format "Initialization time: %s" (emacs-init-time))))

(use-package dracula-theme)
(use-package suscolors-theme) ; like an overarall-warmer gruvbox

(use-package all-the-icons
  :ensure t)

(use-package openwith
  :config
  (openwith-mode t)
  :custom
  (openwith-associations nil))

(use-package cond-let)

(use-package transient)

(use-package magit
  :after transient)

(use-package git-gutter
  :ensure t
  :hook
  (prog-mode . git-gutter-mode)
  :config
  (setq git-gutter:update-interval 0.02))

(use-package git-gutter-fringe
  :ensure t)

(use-package helpful
  :bind
  (("C-h f" . helpful-function)
   ("C-h x" . helpful-command)
   ("C-h k" . helpful-key)
   ("C-h v" . helpful-variable)))

(use-package consult)

;; (use-package avy) ;; is this still useful for anything?
(use-package helm)
;; (use-package ivy) (Deprecated, this package doesn't seem to be in usage anymore)

(use-package deadgrep)

(use-package prescient)
(use-package company-prescient)
(use-package ivy-prescient)
(use-package selectrum-prescient)
(use-package vertico-prescient)

(use-package embark)
(use-package embark-consult)

(setq org-todo-keywords
      '((sequence "TODO(t)" "PROG(p)" "DONE(d)")))

(use-package org-super-agenda)

(require 'org-inlinetask)

(setq-default cursor-type 'bar) ;; this will make the cursor similar to other text editors

;; WINDOW FUNCTIONS
(setq-default frame-title-format '("%b")) ;; Make the window title to be the buffer name

;; SOUNDS
(setq ring-bell-function 'ignore) ;; Disable the bell sound

;; BUFFER FUNCTIONS
(global-auto-revert-mode t) ;; If the file has changed on the disk, then update the buffer as well

;; UNDO TREE
(use-package undo-tree
                      :init (global-undo-tree-mode)
                      :config (setq undo-tree-auto-save-history nil))

(defun reload-init-file ()
  (interactive)
  (load-file user-init-file))
;; this actually doesn't seem to work for absolutely everything
;; for example trying to load a different default font in the init
;; file isn't seen unless you reload the entire instance of Emacs.

;; set shortcut for the reloading
(keymap-global-set "<f5>" 'reload-init-file)

;; Redrawing the display when there's graphical errors
(global-set-key (kbd "<f6>") 'redraw-display)

;;; Lockfiles unfortunately cause more pain than benefit
(setq create-lockfiles nil)

(use-package vc-backup)

(setq backup-directory-alist
    `(("." . ,(expand-file-name "backups" user-emacs-directory)))
      make-backup-files t
      vc-make-backup-files t ; Won't create backup of files that are already under version control
      backup-by-copying t ; Avoid symlinks
      delete-old-versions t
      delete-by-moving-to-trash t ; This makes sure that the files aren't permanently deleted
      kept-new-versions 6
      kept-old-versions 3
      version-control t)

(setq org-support-shift-select t)

(visual-line-mode)
; is this actually enabled just for org buffers or is it enabled globally?

;; visual-fill-column for a nice soft wrap
(use-package visual-fill-column
  :commands visual-fill-column-mode

  :custom
  (fill-column-enable-sensible-window-split t)

  :bind
  (("C-x p" . 'visual-fill-column-mode)))

(use-package text-mode
  :ensure nil
  ;; :hook
  ;; (text-mode . visual-line-mode) ; Would this function enable text mode in all text buffers, and not just org-mode?
  :init
  (delete-selection-mode t)
  :custom
  (sentence-end-double-space nil)
  (scroll-error-top-bottom t)
  (save-interprogram-paste-before-kill t))

(add-hook 'org-mode-hook #'org-num-mode)

(show-paren-mode 1) ;; Show the closing parens by default --- I actually don't think that this works
(delete-selection-mode 1) ;; The selected text will be overwritten when you start typing

(add-hook 'before-save-hook
          'delete-trailing-whitespace) ;; On file save, delete the trailing whitespace --- THIS BASICALLY WORKS LIKE LINTING

(global-unset-key (kbd "C-z"))

(keymap-global-set "C->" 'indent-rigidly-right-to-tab-stop) ; Indent selection by one tab length
(keymap-global-set "C-<" 'indent-rigidly-left-to-tab-stop)  ; De-indent selection by one tab length

(use-package company)

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

;; Visual packages (for navigation)
(use-package org-sidebar)

(use-package calibredb
  :defer t
  :config
  (setq calibredb-root-dir "~/Documents/calibre-library")
  (setq calibredb-db-dir "~/Documents/calibre-library/metadata.db")
  )

(use-package pdf-tools)

(setopt pdf-view-continuous nil)

(use-package deft
  :bind
  (("C-c d" . deft)))

(setq deft-directory
      (file-truename "~/Documents/notes"))
(setq deft-extensions
      '("md" "org" "txt"))
(setq deft-default-extension "org")
(setq deft-recursive t)

(defun efls/deft-open-other ()
 (interactive)
 (deft-open-file-other-window t))

(defun efls/deft-open-preview ()
 (interactive)
 (deft-open-file-other-window))

(use-package zetteldeft
  :after deft
  :config
  (defun sodaware/dteft-open-preview ()
    (interactive)
    (deft-open-file-other-window))
  (zetteldeft-set-classic-keybindings)

(font-lock-add-keywords
 'org-mode
 `((,zetteldeft-id-regex  . fontt-lock-warning-face)
   (,zetteldeft-tag-regex . font-lock-warning-face))))

;; Add custom `zdlink` to handle zettledeft links.
(eval-after-load 'org
  (lambda ()
    (require 'zetteldeft)
    (org-link-set-parameters
     "zdlink"
     :follow
     (lambda (str) (zetteldeft--search-filename
		    (zetteldeft--lift-id str)))
     :complete  #'sodaware/zd-complete-link
     :help-echo "Searches provided ID in Zetteldeft")))

(defun sodaware/zd-complete-link ()
  "Link completion for `zdlink' type links."
  (let* ((file (completing-read "File to link to: "
				(deft-find-all-files-no-prefix)))
	 (link (zetteldeft--lift-id file)))
    (unless link (user-error "No file selected"))
    (concat "zdlink:" link)))

;; Default recent to sorting by mtime
(advice-add 'howm-list-recent :after #'howm-view-sort-by-mtime)
;; Default all to sorting by creation, newest first
(advice-add 'howm-list-all :after #'(lambda () (howm-view-sort-by-date t)))

;;; Define many keys in many key maps
(use-package denote
  :ensure t
  :bind
  ( :map global-map
    ("C-c n n" . denote)
    ("C-c n r" . denote-rename-file)

    :map text-mode-map
    ("C-c n i" . denote-link) ; "insert" mnemonic
    ("C-c n I" . denote-add-links)

    :map dired-mode-map
    ("C-c C-d C-i" . denote-link-dired-marked-notes)
    ("C-c C-d C-r" . denote-dired-rename-marked-files)))

(use-package denote-journal)

(use-package denote-sequence)

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

(setq org-directory "~/Documents/org")
(setq org-default-notes-file "~/Documents/org/org-capture.org")

(use-package org-journal)

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

(with-eval-after-load 'org
  (setq org-startup-indented t) ; Enable `org-indent-mode' by default
  (add-hook 'org-mode-hook #'visual-line-mode))

(setq org-hide-emphasis-markers t)
  (setq org-hide-leading-stars t)
  (setq org-startup-with-inline-images t)
  ;; (setq org-image-actual-width '(450))
  (setq org-pretty-entities t) ; What makes them pretty?
  (setq org-use-sub-superscripts "{}")
  (setq org-id-link-to-org-use-id t) ; What exactly does this do to the links?
  (setq org-fold-catch-invisible-edits 'show) ; What exactly are invisible edits in org?
(setq org-ellipsis "  ·")

(use-package org-appear
  :hook
  (org-mode . org-appear-mode))

(electric-indent-mode 0)

(use-package org-modern
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
   "⭠ now ─────────────────────────────────────────────────")

  (global-org-modern-mode))

(use-package org-superstar
  :config
  (setq org-superstar-leading-bullet " ")
  (setq org-superstar-special-todo-items t) ;; Makes TODO header bullets into boxes
  (setq org-superstar-todo-bullet-alist '(("TODO" . 9744)
                                          ("PROG" . 9744)
                                          ("DONE" . 9744))))

(dolist (face '((org-level-1 . 1.5)
                (org-level-2 . 1.4)
                (org-level-3 . 1.3)
                (org-level-4 . 1.1)
                (org-level-5 . 1.1)
                (org-level-6 . 1.1)
                (org-level-7 . 1.1)
                (org-level-8 . 1.1)))
  (set-face-attribute (car face) nil :font "Gill Sans" :weight 'bold :height (cdr face)))

(set-face-attribute 'org-document-title nil
:font "Roboto Mono"
:weight 'bold
:height 1.8)

(require 'org-indent)
(set-face-attribute 'org-indent nil :inherit '(org-hide fixed-pitch))

(set-face-attribute 'org-block nil
                    :foreground nil
                    :background "#ffdf00"
                    :inherit 'fixed-pitch
                    :height 0.85)

(set-face-attribute 'org-code nil             :inherit '(shadow fixed-pitch) :height 0.85)

(set-face-attribute 'org-indent nil           :inherit '(org-hide fixed-pitch) :height 0.85)

(set-face-attribute 'org-verbatim nil         :inherit '(shadow fixed-pitch) :height 0.85)

(set-face-attribute 'org-special-keyword nil  :inherit '(font-lock-comment-face
fixed-pitch))

(set-face-attribute 'org-meta-line nil        :inherit '(font-lock-comment-face fixed-pitch))
(set-face-attribute 'org-checkbox nil         :inherit 'fixed-pitch)

(add-hook 'org-mode-hook 'variable-pitch-mode)

(defun org-add-my-extra-markup ()
  "Add highlight emphasis."
  (add-to-list 'org-font-lock-extra-keywords
               '("[^\\w]\\(:\\[^\n\r\t]+:\\)[^\\w]"
                 (1 '(face highlight invisible nil)))))

(add-hook 'org-font-lock-set-keywords-hook #'org-add-my-extra-markup)

(use-package org-grapher
  :ensure (:type git :host github :repo "SenkiReign/org-grapher"))

(setq org-grapher-notes-directory "~/Documents/org"
      org-grapher-recursive t
      org-grapher-output-file "~/.cache/org-graph.html")

(setq org-grapher--tag-colors
  '("emacs" "#d65d0e"
    "work" "#458588"
    "personal" "#98971a"))

(use-package olivetti
  :ensure t
  :demand t
  :bind
  (("C-c w o" . sia-olivetti)))

(use-package binder)

(require 'oc-natbib)
(require 'oc-csl)

(setq org-cite-global-bibliography sia-bibtex-files
      org-cite-insert-processor 'citar
      org-cite-follow-processor 'citar
      org-cite-activate-processor 'citar)

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

(use-package biblio
  :bind
  (("C-c w b b" . sia-bibtex-biblio-lookup)))

(use-package citar
  :ensure t
  :defer t ; what's the point of defering in this case?
  :custom (citar-bibliography sia-bibtex-files)
  :bind
  (("C-c w b o" . citar-open))
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
(setq ebib-notes-directory "~/Documents/ebib-literature-notes")
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

(use-package org-ref)
  ;;(advice-add #'completing-read-multiple :override #'consult-completing-read-multiple)
  ;;(require 'org-ref)
  ;;(require 'doi-utils) ; this was taken from a different config

(use-package helm-bibtex)

(setq org-ref-default-bibliography '("~/Documents/bibliography/master.bib")
      org-ref-pdf-directory "~/Documents/literature/")

(setq bibtex-entry-format
      `(page-dashes required-fields
         numerical-fields whitespace last-comma delimiters
         unify-case sort-fields))

(setq bibtex-field-delimiters 'double-quotes)
(setq bibtex-entry-delimiters 'braces)

;; I prefer closing brace on its own line after cleaning BibTeX entry.
(setq bibtex-clean-entry-hook 'mybibtex-clean-extra)
(defun mybibtex-clean-extra ()
  "Move final right brace to a line of its own."
  (progn (bibtex-end-of-entry) (left-char) (newline-and-indent)
         (insert "      ")))

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

;; CONFIGURING BIBTEX-CAPF
(use-package bibtex-capf
:ensure (:type git :host github :repo "mclear-tools/bibtex-capf")
:hook ((org-mode markdown-mode tex-mode latex-mode reftex-mode). bibtex-capf-mode)
:custom
(bibtex-capf-bibliography
 '("~/Documents/bibliography/marx.bib")))

(use-package citar-embark
  :ensure t
  :after citar embark
  :no-require
  :config (citar-embark-mode)
  )

(use-package consult-recoll)

(desktop-save-mode 1)

(setq split-width-threshold 120
      split-height-threshold nil)

(use-package dimmer
  :custom
  (dimmer-adjustment-mode :foreground)

  :config
  (dimmer-configure-which-key)    ; Do not dim these special windows
  (dimmer-configure-hydra)
  (dimmer-configure-magit)

  (dimmer-mode t))

(use-package perspective
  :ensure t  ; use `:straight t` if using straight.el!
  :bind
  ("C-x k" . persp-kill-buffer*)
  :custom
  (persp-mode-prefix-key (kbd "C-c M-p"))  ; pick your own prefix key here
  :init
  (persp-mode))

(use-package ace-window)

(use-package org-fragtog
  :after org
  :hook
  (org-mode . org-fragtog-mode)
  :custom
  (org-startup-with-latex-preview nil)
  (org-format-latex-options
   (plist-put org-format-latex-options :scale 2)
   (plist-put org-format-latex-options :foreground 'auto)
   (plist-put org-format-latex-options :background 'auto)))

;; Optional: ag is nice alternative to using grep with Projectile
(use-package ag
  :ensure t)

(use-package projectile
  :ensure t
  :init
  (setq projectile-project-search-path
        '("~/writing-prokects/"
          "~/work/"
          "~/playground"))
  :config
  ;; These are the configurations to use on Linux for projectile
  (define-key projectile-mode-map (kbd "C-c C-p") 'projectile-command-map)
  (global-set-key (kbd "C-c p") 'projectile-command-map)
  (projectile-mode +1))

(use-package elpher)

(use-package elfeed
  :custom
  (elfeed-db-directory
   (expand-file-name "elfeed" user-emacs-directory))
  (elfeed-show-entry-switch 'display-buffer)
  :bind
  ("C-c w e" . elfeed))

(use-package elfeed-org
  :config
  (elfeed-org)
  :custom
  (rmh-elfeed-org-files
   (list (concat (file-name-as-directory (getenv "HOME"))
		         "elfeed.org"))))

(use-package dashboard
  :ensure t
  :config
  (add-hook 'elpaca-after-init-hook #'dashboard-insert-startupify-lists)
  (add-hook 'elpaca-after-init-hook #'dashboard-initialize)
  (dashboard-setup-startup-hook))

;; Set the title
(setq dashboard-banner-logo-title "Welcome to Emacs Dashboard")

;; Set the banner
(setq dashboard-startup-banner '3)
;; Value can be:
;;  - 'official which displays the official emacs logo.
;;  - 'logo which displays an alternative emacs logo.
;;  - an integer which displays one of the text banners
;;    (see dashboard-banners-directory files).
;;  - a string that specifies a path for a custom banner
;;    currently supported types are gif/image/text/xbm.
;;  - a cons of 2 strings which specifies the path of an image to use
;;    and other path of a text file to use if image isn't supported.
;;    (cons "path/to/image/file/image.png" "path/to/text/file/text.txt").
;;  - a list that can display an random banner,
;;    supported values are: string (filepath), 'official, 'logo and integers.

;; Content is not centered by default. To center, set
(setq dashboard-center-content t)
;; vertically center content
(setq dashboard-vertically-center-content t)

;; To disable shortcut "jump" indicators for each section, set
(setq dashboard-show-shortcuts nil)

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

(use-package neotree
  :ensure t)

(setq neo-theme (if (display-graphic-p) 'icons 'arrow))
