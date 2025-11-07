;; This file has been generated from an org-mode file (=literate-config.org=)
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

;; Local Variables:
;; no-byte-compile: t
;; no-native-compile: t
;; no-update-autoloads: t

(setq load-path (cons "~/.config/emacs-literate/sia-modules" load-path))

;; (require 'sensible-defaults)
;; (require 'sia-keybindings)
;; (require 'sia-minibuffer)
;; (require 'sia-appearance)
;; (require 'sia-academic) ; haven't set this one up yet

(use-package which-key)

(setq custom-file (make-temp-file "emacs-custom-"))

(use-package counsel)

(elpaca-wait)

(use-package elpher)
(use-package elfeed)
(use-package elfeed-org)

(use-package magit)

(use-package transient)

(use-package git-gutter
  :ensure t
  :hook
  (prog-mode . git-gutter-mode)
  :config
  (setq git-gutter:update-interval 0.02))

(use-package git-gutter-fringe
  :ensure t)

(use-package consult) ;Consulting completing-read

(use-package avy)
(use-package helm)
;; (use-package ivy) (Deprecated, this package doesn't seem to be in usage anymore)

(use-package prescient)
(use-package company-prescient)
(use-package ivy-prescient)
(use-package selectrum-prescient)
(use-package vertico-prescient)

(use-package embark)
(use-package embark-consult)

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

;; Adding global shift-select support in Org buffers (bypassing other SHIFT bindings)
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

(show-paren-mode 1) ;; Show the closing parens by default --- I actually don't think that this works
(delete-selection-mode 1) ;; The selected text will be overwritten when you start typing

(add-hook 'before-save-hook
          'delete-trailing-whitespace) ;; On file save, delete the trailing whitespace --- THIS BASICALLY WORKS LIKE LINTING

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

(global-unset-key (kbd "C-z"))

;; (keymap-global-set [mouse-3] 'mouse-popup-menubar-stuff) ;; This will give right-click a context menu

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

(use-package corg
  :ensure
  (:host github :repo "isamert/corg.el"))

(add-hook 'org-mode-hook #'corg-setup)

;; Visual packages (for navigation)
(use-package org-sidebar)

(use-package calibredb
  :defer t
  :config
  (setq calibredb-root-dir "~/Documents/calibre-library")
  (setq calibredb-db-dir "~/Documents/calibre-library/metadata.db")
  )

(use-package pdf-tools)

(use-package howm)
;; (straight-use-package 'phi-notes) ;; can't actually find the package (it has to be installed manually)

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

(use-package org-noter)
(use-package djvu) ; apparently needed for org-noter

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

(with-eval-after-load 'org
  (setq org-startup-indented t) ; Enable `org-indent-mode' by default
  (add-hook 'org-mode-hook #'visual-line-mode))

(electric-indent-mode 0)

(use-package binder)

(use-package org-remark-global-tracking
  ;; It is recommended that `org-remark-global-tracking-mode' be
  ;; enabled when Emacs initializes. You can set it in
  ;; `after-init-hook'.
  :hook after-init
  :config
  ;; Selectively keep or comment out the following if you want to use
  ;; extensions for Info-mode, EWW, and NOV.el (EPUB) respectively.
  (use-package org-remark-info :after info :config (org-remark-info-mode +1))
  (use-package org-remark-eww  :after eww  :config (org-remark-eww-mode +1))
  (use-package org-remark-nov  :after nov  :config (org-remark-nov-mode +1)))

(use-package org-remark
  :bind (;; :bind keyword also implicitly defers org-remark itself.
         ;; Keybindings before :map is set for global-map. Adjust the keybinds
         ;; as you see fit.
         ("C-c n m" . org-remark-mark)
         ("C-c n l" . org-remark-mark-line)
         :map org-remark-mode-map
         ("C-c n o" . org-remark-open)
         ("C-c n ]" . org-remark-view-next)
         ("C-c n [" . org-remark-view-prev)
         ("C-c n r" . org-remark-remove)
         ("C-c n d" . org-remark-delete)))

(use-package org-ref)
(use-package helm-bibtex)
(use-package citar)
(use-package ebib)

(setq bibtex-completion-bibliography
      '("~/Documents/bibliography/thesis.bib"
        "~/Documents/bibliography/marx.bib"
        "~/Documents/bibliography/hci.bib"
        "~/Documents/bibliography/aesthetics.bib")
	  bibtex-completion-library-path '("~/Documents/literature/")
	  bibtex-completion-notes-path "~/Documents/org/"
	  bibtex-completion-notes-template-multiple-files "* ${author-or-editor}, ${title}, ${journal}, (${year}) :${=type=}: \n\nSee [[cite:&${=key=}]]\n"

    ;; this bit was copied directly from the GitHub page, I don't actually understand what it does
	  bibtex-completion-additional-search-fields '(keywords)
	  bibtex-completion-display-formats
	  '((article       . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*} ${journal:40}")
	    (inbook        . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*} Chapter ${chapter:32}")
	    (incollection  . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*} ${booktitle:40}")
	    (inproceedings . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*} ${booktitle:40}")
	    (t             . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*}"))
	  bibtex-completion-pdf-open-function
	  (lambda (fpath)
	    (call-process "open" nil 0 nil fpath)))

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

(use-package perspective
  :ensure t  ; use `:straight t` if using straight.el!
  :bind
  ("C-x k" . persp-kill-buffer*)
  :custom
  (persp-mode-prefix-key (kbd "C-c M-p"))  ; pick your own prefix key here
  :init
  (persp-mode))

(use-package ace-window)

(use-package consult-recoll)

;; Optional: ag is nice alternative to using grep with Projectile
(use-package ag
  :ensure t)

;; Optional: which-key will show you options for partially completed keybindings
;; It's extremely useful for packages with many keybindings like Projectile.
(use-package which-key
  :ensure t
  :config
  (which-key-mode +1))

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
