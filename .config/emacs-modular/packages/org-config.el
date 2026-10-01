;; -*- lexical-binding: t; -*-

;; -*- lexical-binding: t; -*-

(use-package org
  :ensure nil
  :defer t
  :bind
  (:map org-mode-map
        ("C-c ." . 'org-time-stamp))
  :hook
  (org-mode . siapip/org-setup-deadline-highlighting)
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((shell . t)))
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

(use-package org-node
  :hook (after-init . org-node-cache-mode))

(use-package org-modern
  :ensure t
  :defer t
  :hook ((org-mode . org-modern-mode)))

(use-package org-appear
  :hook (org-mode . org-appear-mode))

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
  (org-gtd-directory "~/notes/area/org-gtd/")

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

;; animated gif support to spruce things up
(use-package org-inline-anim
  :ensure (:wait t)
  :custom
  (org-inline-anim-loop t))

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

;; (use-package org-ql
;;  :ensure t)