;; -*- lexical-binding: t; -*-

;; This file only sets up the very basic extensions for org mode.
;; I also use many other packages, they will be required later on.
;; This includes the:
;; - vulpea ecosystem (sp-vulpea-base.el) with the actual extensions at sp-vulpea-ext.el
;; - org-node (and the org-mem package)
;; - all the org-agenda stuff that will help with taks management (see also taskman.el)

;; Basic settings for text-mode - getting text to work well
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

;;; Should be default settings for writing (also called linting)
;; (add-hook 'before-save-hook
;;          'delete-trailing-whitespace) ;; On file save, delete the trailing whitespace --- THIS BASICALLY WORKS LIKE LINTING
;; Disabled because it introduces issues once paired with the vulpea-db-auto-sync (can't make some edits at all)


(defun sp-single-space-after-periods ()
  "Don't assume that sentences should have two spaces after
periods. This ain't a typewriter."
  (setq sentence-end-double-space nil))
  
;;; Useful writing functions 
(show-paren-mode 1) ;; Show the closing parens by default --- I actually don't think that this works
(delete-selection-mode 1) ;; The selected text will be overwritten when you start typing

(setq org-link-search-must-match-exact-headline nil)

(setq counsel-outline-display-style 'title)

(setq org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id)

(setq org-directory "~/notes")

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
   ;; Reorganising notes through vulpea
   ("C-x s t" . sp-split-leave-parents)
 
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
  ;; Footnotes
  (org-footnote-section nil)

  ;; Editing
  (setq org-catch-invisible-edits 'show-and-error) ;; prevent editing invisible area ;;; Does this actually work?

  ;; Indentation
  (org-adapt-indentation t) ;; adapt indentation
  (org-startup-indented t) ;; start with indentation of headlines
  (org-src-preserve-indentation t) ;; preserve code indentation

  ;; Insertion/Yanking
  (org-insert-heading-respect-content t) ;; insert new headings after subtree
  (org-M-RET-may-split-line '((default . t)))  ;; don't split line when creating a new headline, list item, or table field
  (org-yank-adjusted-subtrees nil)  ;; adjust subtrees to depth when yanked
  (org-yank-folded-subtrees nil) ;; fold subtrees on yank

  ;; Lists
  (org-list-allow-alphabetical t) ;; allow alphabetical list
  ;; Demote sequence for list bullets
  (org-list-demote-modify-bullet '(("+" . "-") ("-" . "+") ("*" . "+")))
  (org-list-indent-offset 1) ;; increase sub-item indentation

  ;; Movement
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
  (org-mode . sp-org-deadline-highlighting)
  :config
  )

(defface siapip/org-deadline-highlight
  '((t . (:background "#4c1f24")))
  "Highlight face for today's deadlines")

(defun sp-org-highlight-todays-deadlines ()
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

(defun sp-org-deadline-highlighting ()
  (add-hook 'after-save-hook #'sp-org-highlight-todays-deadlines nil t)
  (sp-org-highlight-todays-deadlines))
  
(add-hook 'org-mode-hook #'org-indent-mode)

(setq org-agenda-breadcrumbs-separator " ) ")

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

(setq org-support-shift-select t)

(global-unset-key (kbd "C-x t i"))

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
    ("C-x t i" . org-toggle-item)

    ;; sorting elements
    ("C-c s i" . org-sort-list)

    ;; task-management bindings
    ("C-x t d" . org-do-demote)
)

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

(defun +org/opened-buffer-files ()
  "Return the list of files currently opened in emacs"
  (delq nil
        (mapcar (lambda (x)
                  (if (and (buffer-file-name x)
                           (string-match "\\.org$"
                                         (buffer-file-name x)))
                      (buffer-file-name x)))
                (buffer-list))))

;; Working with indirect buffers
(defun sp-org-tree-to-indirect-buffer (&optional arg)
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

;; animated gif support to spruce things up
(use-package org-inline-anim
  :ensure (:wait t)
  :custom
  (org-inline-anim-loop t))

;; (use-package org-ql
;;  :ensure t)

;; Time logging for org-mode

(setq org-use-fast-todo-selection 'expert) ;; don't use popup window for todos
;; don't set to DONE if children aren’t DONE
(setq org-enforce-todo-dependencies t)
(setq org-enforce-todo-checkbox-dependencies t)

;; Logging
(setq org-log-done 'time)
(setq org-log-into-drawer t)
(setq org-log-state-notes-insert-after-drawers nil)
(setq org-log-redeadline nil) ;; don't log the time a task was rescheduled/redeadlined.
(setq org-log-reschedule nil)

;; Lambda emacs

;; Core settings for org-mode in 𝛌-Emacs This file is for configuring org and
;; related files that are part of org. Other extensions to org can be found in
;; ~sp-org-ext.el~. This file is called in ~init.el~ instead of being required in here.

;; Note that configuring that is heavily user-specific, such as capture
;; templates, is not put here, but should be put in the user's configuration
;; file (or user library). For an example of how to configure capture templates
;; see:
;; https://systemcrafters.cc/emacs-from-scratch/organize-your-life-with-org-mode/#capture-templates

;; What does this eval after load mean?
;;;; Org Modules
(with-eval-after-load 'org
;; Load additional org modules
(add-to-list 'org-modules 'org-habit t)
(add-to-list 'org-modules 'org-tempo t)
(add-to-list 'org-modules 'org-protocol t))

;;;; Open Files in Default Application
;;Open files in their default applications (ms word being the prime example)
(customize-set-variable 'org-file-apps
                        '(("\\.docx\\'" . default)
                          ("\\.mm\\'" . default)
                          ("\\.x?html?\\'" . default)
                          ("\\.pdf\\'" . emacs)
                          (auto-mode . emacs)))

;;;;; Goto Org Files
(defun sp-goto-org-files ()
  "goto org-files directory"
  (interactive)
  (let ((default-directory org-directory))
    (call-interactively 'find-file)))
(defun sp-goto-inbox.org ()
  "goto org-inbox"
  (interactive)
  (find-file (concat org-directory "inbox.org")))
(defun sp-goto-todo.org ()
  "goto org-todo"
  (interactive)
  (find-file (concat org-directory "todo.org")))
(defun sp-goto-conferences.org ()
  "goto org-conferences"
  (interactive)
  (find-file (concat org-directory "conferences.org")))
(defun sp-goto-referee-reports.org ()
  "goto org referee reports"
  (interactive)
  (find-file (concat org-directory "referee-reports.org")))
(defun sp-goto-reference.org ()
  "goto org reference notes"
  (interactive)
  (find-file (concat org-directory "reference.org")))
(defun sp-goto-someday.org ()
  "goto org-someday"
  (interactive)
  (find-file (concat org-directory "someday.org")))
(defun sp-goto-reading.org ()
  "goto reading list"
  (interactive)
  (find-file (concat org-directory "reading.org")))
(defun sp-goto-writing.org ()
  "goto writing list"
  (interactive)
  (find-file (concat org-directory "writing.org")))
(defun sp-goto-teaching.org ()
  "goto teaching file"
  (interactive)
  (find-file (concat org-directory "teaching.org")))

;;;;; Org Create Check Box From List Item
;; A useful macro for converting list items to checkboxes
(fset 'sp-org-checkbox-from-list
      [?a ?  ?\[ ?  ?\] escape ?\M-x return])

;;;;; Org Tag Selection

(defun sp-org-select-tags-completing-read ()
  "Select tags to add to headline."
  (interactive)
  (let* ((current (org-get-tags (point)))
         (selected (completing-read-multiple "Select org tag(s): " (org-get-buffer-tags))))
    (alet (-uniq (append (-difference current selected)
                         (-difference selected current)))
      (org-set-tags it))))

;;;;; Uncheck Org boxes
;;see https://www.reddit.com/r/emacs/comments/r107bg/comment/hlx54vf/?utm_source=share&utm_medium=web2x&context=3
(defun sp-copy-and-uncheck (start end)
  "copy a region of regularly repeating checkbox items forward from
one week to the next, unchecking them at the same time"
  (interactive "r")
  (kill-new (replace-regexp-in-string (rx "[X]") "[ ]" (buffer-substring start end)))
  (setq deactivate-mark t))

;;;;; Org Tree/Heading to New File
(defun sp-org-tree-to-new-file ()
  "Move an org subtree to a new file"
  (interactive)
  (org-copy-subtree nil t)
  (find-file-other-window
   (read-file-name "Move subtree to file:" ))
  (org-paste-subtree))

;;;;; Org Wrap in Block Template
;; A helpful function I found for wrapping text in a block template.
;; http://pragmaticemacs.com/emacs/wrap-text-in-an-org-mode-block/

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; function to wrap blocks of text in org templates                       ;;
;; e.g. latex or src etc                                                  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun org-block-wrap ()
  "Make a template at point."
  (interactive)
  (if (org-at-table-p)
      (call-interactively 'org-table-rotate-recalc-marks)
    (let* ((choices '(
                      ("a" . "ascii")
                      ("c" . "comment")
                      ("C" . "center")
                      ("e" . "example")
                      ("E" . "src emacs-lisp")
                      ("h" . "html")
                      ("l" . "laTeX")
                      ("n" . "notes")
                      ("q" . "quote")
                      ("s" . "src")
                      ("v" . "verse")
                      ))
           (key
            (key-description
             (vector
              (read-key
               (concat (propertize "Template type: " 'face 'minibuffer-prompt)
                       (mapconcat (lambda (choice)
                                    (concat (propertize (car choice) 'face 'font-lock-type-face)
                                            ": "
                                            (cdr choice)))
                                  choices
                                  ", ")))))))
      (let ((result (assoc key choices)))
        (when result
          (let ((choice (cdr result)))
            (cond
             ((region-active-p)
              (let ((start (region-beginning))
                    (end (region-end)))
                (goto-char end)
                (insert "#+end_" choice "\n")
                (goto-char start)
                (insert "#+begin_" choice "\n")))
             (t
              (insert "#+begin_" choice "\n")
              (save-excursion (insert "#+end_" choice))))))))))

;;; Only follow links in org-mode if it's strictly in the link itself, not at the edges
(defun sp-org-point-strictly-in-link-p ()
  "Non-nil if point is inside a link, not at its edges or trailing blanks."
  (let ((ctx (org-element-context)))
    (and (eq (org-element-type ctx) 'link)
         (> (point) (org-element-property :begin ctx))
         (< (point) (- (org-element-property :end ctx)
                       (org-element-property :post-blank ctx))))))

(define-advice org-return (:around (fn &rest args) strict-link-follow)
  (let ((org-return-follows-link
         (and org-return-follows-link
              (sp-org-point-strictly-in-link-p))))
    (apply fn args)))

;;; Provide:

(provide 'sp-org-base)
;; sp-org-base.el ends here.