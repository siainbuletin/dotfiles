;; -*- lexical-binding: t; -*-

;; This file only sets up the very basic extensions for org mode.
;; I also use many other packages, they will be required later on.
;; This includes the:
;; - vulpea ecosystem (sia-set-vulpea-base.el) with the actual extensions at sia-set-vulpea-ext.el
;; - org-node (and the org-mem package)
;; - all the org-agenda stuff that will help with taks management (see also taskman.el)

;; Use Org from source rather than built in
(use-package org
  :ensure nil
  :defer t

  :commands (org-mode)
  :mode (("\\.org$" . org-mode))
 
  :bind
  (:map global-map
   ("C-c a" . org-agenda))
 
  (:map org-mode-map
   ("C-M-k" . org-metaup)
   ("C-M-j" . org-metadown)
   ("C-M-l" . org-metaright)
   ("C-M-h" . org-metaleft)
   ("M-J" . org-shiftdown)
   ("M-K" . org-shiftup)
   ("M-L" . org-shiftright)
   ("M-H" . org-shiftleft)
 
   ;; easily emphasize text
   ("s-b" . (lambda () (interactive) (org-emphasize-dwim ?*)))
   ("s-i" . (lambda () (interactive) (org-emphasize-dwim ?/)))
   ("s-M-`" . org-emphasize-with-verbatim-dwim)
   ("s-M-~" . org-emphasize-with-code-dwim)
   
   ;; better pasting behavior in org-mode
   ("s-v" . org-yank))

  :init
  ;; Org-Emphasis-Regex settings. Set regex boundaries for emphasis.
  ;; Load this before org-mode is loaded.
  ;; See https://emacs.stackexchange.com/q/54673/11934
  ;; https://emacs.stackexchange.com/q/54632/11934

  (setq org-emphasis-regexp-components
        '("-—[:space:]('\"{["
          "\][:space:].,:!?;'\")}\\[-"
          "[:space:]"
          "."
          1))

  :custom
  ;; Aesthetics & UI
  (org-auto-align-tags nil) ;; don't auto-align tags
  (org-catch-invisible-edits 'smart) ;; prevent editing invisible area
  (org-cycle-separator-lines 0) ;; no empty lines in collapsed view
  (org-ellipsis "…") ;; nicer elipses "↷" "↴" "▼"
  (org-fontify-quote-and-verse-blocks t) ;; make quotes stand out
  (org-hide-emphasis-markers t)  ;; hide emph markers
  (org-hide-leading-stars t)  ;; hide leading stars
  (org-image-actual-width  500) ;; show all images at 500px using imagemagik
  (org-pretty-entities t) ;; make latex look good, etc.
  (org-pretty-entities-include-sub-superscripts t) ;; prettify sub/superscripts
  (org-read-date-prefer-future 'time) ;; Incomplete dates refer to future dates & times
  (org-startup-folded nil) ;; Don't start org in outline
  (org-tags-column 0) ;; place tags directly next to headline text

  ;; Footnotes
  (org-footnote-section nil) ;; place footnotes locally
  (org-footnote-auto-adjust t) ;; renumber footnotes

  ;; Indentation
  (org-adapt-indentation t) ;; adapt indentation
  (org-startup-indented t) ;; start with indentation of headlines
  (org-src-preserve-indentation t) ;; preserve code indentation

  ;; Insertion/Yanking
  (org-insert-heading-respect-content t) ;; insert new headings after subtree
  (org-M-RET-may-split-line '((default . t)))  ;; don't split line when creating a new headline, list item, or table field
  (org-yank-adjusted-subtrees t)  ;; adjust subtrees to depth when yanked
  (org-yank-folded-subtrees t) ;; fold subtrees on yank

  ;; Lists
  (org-list-allow-alphabetical t) ;; allow alphabetical list
  ;; Demote sequence for list bullets
  (org-list-demote-modify-bullet '(("+" . "-") ("-" . "+") ("*" . "+")))
  (org-list-indent-offset 1) ;; increase sub-item indentation

  ;; Movement
  (org-return-follows-link t) ;; make RET follow links
  (org-special-ctrl-a/e t)  ;; better movement in headers

  ;; Searching
  (org-imenu-depth 8) ;; scan to depth 8 w/imenu
  (imenu-auto-rescan t) ;; make sure imenu refreshes

  ;; Source block settings
  (org-src-fontify-natively t) ;; use lang-specific fontification
  (org-src-window-setup 'other-window) ;; edit source in other window
  (org-src-tab-acts-natively t) ;; use lang bindings
  (org-confirm-babel-evaluate t) ;; confirm evaluation

  :config
  ;; Map vimrc source blocks to vimrc-mode for correct tangle comment syntax
  (add-to-list 'org-src-lang-modes '("vimrc" . vimrc))

  (org-babel-do-load-languages
   'org-babel-load-languages
   '((shell . t)))
  
  ;; Don't auto-pair `<' in org buffers (it interferes with structure
  ;; templates like `<s' and headlines). Only adjust the predicate if
  ;; `elec-pair' has actually been loaded -- otherwise the var is void
  ;; and the hook raises a void-variable error during org-mode init.
  (add-hook 'org-mode-hook
            (lambda ()
              (when (boundp 'electric-pair-inhibit-predicate)
                (setq-local electric-pair-inhibit-predicate
                            `(lambda (c)
                               (if (char-equal c ?<) t
                                 (,electric-pair-inhibit-predicate c)))))))
  )

(electric-indent-mode 0)

(use-package org
  :bind
  (:map org-mode-map
        ("C-c ." . 'org-time-stamp))
  :hook
  (org-mode . siapip/org-setup-deadline-highlighting)
  :config
  )

(use-package org-journal
  :defer t
  :bind
  (("C-M-S-j" . (lambda () (interactive) (org-journal-new-entry nil nil t)))
   ("C-M-S-i" . (lambda () (interactive) (org-journal-new-entry nil))))
  :init
  (setq org-journal-dir "~/org/journal"
        org-journal-date-format "%Y-%m-%d"
        org-journal-enable-agenda-integration t
        org-journal-carryover-items "TODO={TODO\\|WAITING\\|DOING}"))

;;(use-package ox-search
;;  :ensure nil
;;  :hook (org-mode . ox-search-mode))



;; Creating different TODO keywords for better readability
(setq org-confirm-babel-evaluate nil
        org-hide-emphasis-markers t
        org-todo-keywords '((sequence "TODO" "WAITING" "DOING" "|" "DONE" "CANCELLED"))
        org-modern-todo-faces '(("TODO" :foreground "white" :background "darkgreen" :weight bold)
                                ("DOING" :foreground "white" :background "orange" :weight bold)
                                ("WAITING" :foreground "white" :background "blue")))

(defun org-babel-nushell--list-includes (params)
  "Extract values from all :include keys in PARAMS alist."
  (let ((result nil))
    (dolist (pair params result)
      (when (and (consp pair)
                 (eq (car pair) :include))
        (push (cdr pair) result)))))

(defun org-babel-nushell--read-includes (params)
  "Read all includes"
  (let ((result '()))
    (dolist (name (org-babel-nushell--list-includes params))
      (let ((block-position (org-babel-find-named-block name)))
        (when block-position
          (save-excursion
            (goto-char block-position)
            (let ((data (org-babel-get-src-block-info)))
              (when data
                (push (nth 1 data) result)))))))
    (string-join (nreverse result) "\n")))

(defun org-babel-nushell-var-to-nushell (params)
  (format "let $%s = %s" (car params) (json-encode (cdr params))))

(defcustom org-babel-nushell-eval-shell-file-name "/bin/sh"
  "Shell executable used by `org-babel-eval' to execute Nushell source blocks.
This shell is used to execute the Nushell command."
  :type 'string
  :group 'siapip)

(defun org-babel-execute:nushell (body params)
  "Execute a block of nushell code"
  (let* ((shell-file-name org-babel-nushell-eval-shell-file-name)
         (cmd (or (cdr (assoc :cmd params)) "nu"))
         (args (or (cdr (assoc :args params)) "-c"))
         (vars (mapcar
                'org-babel-nushell-var-to-nushell
                (org-babel--get-vars params)))
         (included-code (org-babel-nushell--read-includes params))
         (code (string-join (list (or included-code "") (org-babel-chomp body)) "\n"))
         (full-code (if vars
                        (concat (string-join vars "\n") "\n" code)
                      code))
         (command (format "%s %s %s" cmd args (shell-quote-argument full-code))))
    (org-babel-eval command "")))

(defun org-babel-execute:jinja (body params)
  "Execute a jinja2 template"
  (let* ((script (shell-quote-argument "import sys, jinja2 as j2; print(j2.Template(sys.argv[1]).render())"))
         (code (shell-quote-argument (org-babel-chomp body)))
         (command (format "python3 -c %s %s" script code)))
    (org-babel-eval command "")))

(defface siapip/org-deadline-highlight
  '((t . (:background "#4c1f24")))
  "Highlight face for today's deadlines")

(defun siapip/org-highlight-todays-deadlines ()
  "Highlight headlines with a deadline of today or earlier in Org mode."
  (interactive)
  (remove-overlays (point-min) (point-max) 'siapip/deadline t)
  (let ((today (calendar-absolute-from-gregorian (calendar-current-date))))
    (org-element-map (org-element-parse-buffer 'headline) 'headline
      (lambda (hl)
        (when-let* ((deadline     (org-element-property :deadline hl))
                    (year         (org-element-property :year-start deadline))
                    (month        (org-element-property :month-start deadline))
                    (day          (org-element-property :day-start deadline))
                    (deadline-abs (calendar-absolute-from-gregorian (list month day year))))
          (when (and (not (eq (org-element-property :todo-type hl) 'done))
                     (<= deadline-abs today))
            (let* ((start (org-element-property :begin hl))
                   (end (save-excursion (goto-char start) (line-end-position)))
                   (ov (make-overlay start end)))
              (overlay-put ov 'siapip/deadline t)
              (overlay-put ov 'face 'siapip/org-deadline-highlight))))))))

(defun siapip/org-setup-deadline-highlighting ()
  (add-hook 'after-save-hook #'siapip/org-highlight-todays-deadlines nil t)
  (siapip/org-highlight-todays-deadlines))
  

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

(use-package org-ranker
  :ensure (org-ranker :type git
                    :host github
                    :repo "CSJ7701/org-ranker"))

;; (add-to-list 'load-path "~/.config/emacs-include/cloned-modules/org-dataview")
;; (require 'org-dataview)

(setq org-id-locations-file "~/.config/emacs-include/.org-id-locations")

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

;; (load-file "~/.config/emacs-include/sia-modules/org-extra-emphasis.el")

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

(setq org-hierarchical-todo-statistics nil)

;; animated gif support to spruce things up
(use-package org-inline-anim
  :ensure (:wait t)
  :custom
  (org-inline-anim-loop t))

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

;; (use-package org-ql
;;  :ensure t)

;; Time logging for org-mode

(org-use-fast-todo-selection 'expert) ;; don't use popup window for todos
;; don't set to DONE if children aren’t DONE
(org-enforce-todo-dependencies t)
(org-enforce-todo-checkbox-dependencies t)

;; Logging
(org-log-done 'time)
(org-log-into-drawer t)
(org-log-state-notes-insert-after-drawers nil)
(org-log-redeadline nil) ;; don't log the time a task was rescheduled/redeadlined.
(org-log-reschedule nil)

;; All of the other org-mode packages are required with the base configuration here:
(require 'sia-set-org-appearance)

(require 'sia-set-org-capture)
(require 'sia-set-org-babel)
(require 'sia-set-org-agenda)

(require 'sia-set-org-ext)

;; for zettelkasten
(require 'sia-set-org-node-mem)
(require 'sia-set-vulpea-base)
(require 'sia-set-vulpea-ext)

