(require 'org-inlinetask)

;; CONFIGURING BIBTEX-CAPF
(use-package bibtex-capf
  :straight (:type git :host github :repo "mclear-tools/bibtex-capf")
  :hook ((org-mode markdown-mode tex-mode latex-mode reftex-mode). bibtex-capf-mode)
  :custom
  (bibtex-capf-bibliography
   '("~/Documents/bibliography/marx.bib")))

;; ORG-REF CONFIGURATION

(setq bibtex-completion-bibliography '("~/Documents/bib-files/master.bib"
					                   "~/Documents/bib-files/thesis.bib"
                                       "~/Documents/bib-files/marx.bib"
                                       "~/Documents/bib-files/hci.bib"
                                       "~/Documents/bib-files/aesthetics.bib")
	bibtex-completion-library-path '("~/Documents/literature/")
	bibtex-completion-notes-path "~/Documents/org-files/"
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

(setq nano-font-family-monospaced "0xProto Nerd Font Mono")
(setq nano-font-family-proportional "Roboto Slab")

(straight-use-package 'dracula-theme)

;; this one is like an overall-warmer gruvbox
(straight-use-package 'suscolors-theme)

(setq initial-major-mode 'org-mode
      initial-scratch-message (concat "#+title: Emacs Writing Studio\n"
					"#+subtitle: Scratch Buffer\n\n"
					"The text in this buffer is not saved "
					"when exiting Emacs!\n\n"))

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


(defun jcs-execute-all-buffers ()
  (interactive)
  (let ((org-confirm-babel-evaluate nil))
    (org-babel-execute-buffer)))

(when (display-graphic-p)
    (context-menu-mode 1)
    (tool-bar-mode -1) ; If this were on, then I would get TWO toolbars at the same time, which is just crazy.
    (scroll-bar-mode -1)
    (horizontal-scroll-bar-mode -1)
    (setq visible-bell 1
          frame-inhibit-implied-resize t)
)

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
                    :family "Adwaita Mono"
                    :weight 'regular)

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

(use-package openwith
  :config
  (openwith-mode t)
  :custom
  (openwith-associations nil))

(require 'org-inlinetask)


;; UNDO TREE
(use-package undo-tree
                      :init (global-undo-tree-mode)
                      :config (setq undo-tree-auto-save-history nil))


(setq org-support-shift-select t)

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

(setopt pdf-view-continuous nil)

(require 'org-id) ; for creating ids
(require 'org-tempo) ; for template expansion

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

(dolist (face '((org-level-1 . 1.35)
                (org-level-2 . 1.3)
                (org-level-3 . 1.2)
                (org-level-4 . 1.1)
                (org-level-5 . 1.1)
                (org-level-6 . 1.1)
                (org-level-7 . 1.1)
                (org-level-8 . 1.1)))
  (set-face-attribute (car face) nil :font "Gill Sans" :weight 'bold :height (cdr face)))

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


;; I prefer closing brace on its own line after cleaning BibTeX entry.
(setq bibtex-clean-entry-hook 'mybibtex-clean-extra)
(defun mybibtex-clean-extra ()
  "Move final right brace to a line of its own."
  (progn (bibtex-end-of-entry) (left-char) (newline-and-indent)
         (insert "      ")))


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

;; CONFIGURING BIBTEX-CAPF
(use-package bibtex-capf
:ensure (:type git :host github :repo "mclear-tools/bibtex-capf")
:hook ((org-mode markdown-mode tex-mode latex-mode reftex-mode). bibtex-capf-mode)
:custom
(bibtex-capf-bibliography
 '("~/Documents/bibliography/marx.bib")))

(desktop-save-mode 1)

(setq split-width-threshold 120
      split-height-threshold nil)

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

(use-package neotree
  :ensure t)

(setq neo-theme (if (display-graphic-p) 'icons 'arrow))