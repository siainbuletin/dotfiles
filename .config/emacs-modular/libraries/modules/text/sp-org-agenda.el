;;; sp-org-agenda.el --- Org agenda settings and views -*- lexical-binding: t; -*-

;;; Commentary:

;; Configures Org's agenda: the prefix format of agenda lines, visual styling
;; of the time grid and tags, scheduling and sorting rules, and the
;; `org-super-agenda' mode (groups are set per view). The agenda files are owned by vulpea-para
;; (sp-vulpea-para) and the keys are in sp-agenda-views. It
;; also adds a command to jump to the daily view, automatic refresh of the
;; agenda after a capture, and an alphapapa recipe for showing an agenda
;; limited to the current subtree or region.

;;; Code:

(require 'sp-org-id-link)

;;;; Org Agenda
;;;;; Agenda Settings
(use-package org-agenda
  :ensure nil
  :commands (org-agenda)
  :custom
  ;; Agenda logging
  (org-agenda-start-with-log-mode t)

  ;; The Area > Project category is evaluated when an agenda is built, so
  ;; vulpea-para does not have to be loaded yet.
  (org-agenda-prefix-format
   '((agenda . " %(vulpea-para-agenda-category 36) %?-12t %12s")
     (todo   . " %(vulpea-para-agenda-category 36) ")
     (tags   . " %(vulpea-para-agenda-category 36) ")
     (search . " %i %(vulpea-para-agenda-category 36) ")))
  (org-agenda-tags-column 0)  ;; Put tags next to heading
  (org-agenda-breadcrumbs-separator "  ")
  (org-agenda-block-separator " ")  ;; No default block seperator
  (org-agenda-time-grid
   '((daily today require-timed)
     (800 1000 1200 1400 1600 1800 2000)
     " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"))
  (org-agenda-current-time-string
   "–––––––––––––– Now")
  (org-agenda-tags-column org-tags-column)
  (org-agenda-show-inherited-tags nil)
  (org-agenda-window-setup 'only-window)
  (org-agenda-restore-windows-after-quit t)
  (org-agenda-skip-scheduled-if-done t)
  (org-agenda-skip-timestamp-if-done t)
  (org-agenda-todo-ignore-scheduled 'future)
  (org-agenda-todo-ignore-deadlines 'far)
  (org-agenda-sorting-strategy
   '((agenda time-up) (todo time-up) (tags time-up) (search time-up)))
)

;;;; Org other agenda (yibie)
(use-package org-other-agenda
  :ensure (:host github :repo "yibie/org-other-agenda"))

;; Show links in the rows by their description, as an Org buffer does,
;; with the helper the query tables use (`sp-org-link-linkify').
(defun sp-org-agenda-linkify-title (title)
  "Return the row TITLE of `org-other-agenda' with its Org links described."
  (sp-org-link-linkify title))

(with-eval-after-load 'org-other-agenda
  (advice-add 'org-other-agenda--clean-title :filter-return
              #'sp-org-agenda-linkify-title))

;;;; Org other agenda: colours from the theme
(defgroup sp-org-agenda-board nil
  "Colours of the `org-other-agenda' board, taken from the theme in use."
  :group 'faces)

(defcustom sp-org-agenda-board-accents
  '((urgent   sp-urgent error)
    (crucial  sp-crucial warning)
    (focus    sp-focus link)
    (positive success)
    (calm     font-lock-type-face)
    (meek     sp-meek shadow)
    (mild     sp-mild shadow))
  "The accents of the board, an alist of (ACCENT FACE...).
The colour of an accent is the foreground of the first FACE that has one
in the current theme: a semantic face of the `sp' themes first, then a
standard face that every theme defines."
  :group 'sp-org-agenda-board
  :type '(alist :key-type symbol :value-type (repeat face))
  :set (lambda (symbol value)
         (set-default symbol value)
         (when (fboundp 'sp-org-agenda-board-apply)
           (sp-org-agenda-board-apply))))

(defcustom sp-org-agenda-board-roles
  '((org-other-agenda-day            focus    bold)
    (org-other-agenda-today          crucial  bold)
    (org-other-agenda-a              urgent   bold)
    (org-other-agenda-overdue        urgent)
    (org-other-agenda-clock          positive bold)
    (org-other-agenda-tag            calm)
    (org-other-agenda-query          crucial)
    (org-other-agenda-dim            meek)
    (org-other-agenda-tab            meek)
    (org-other-agenda-hour           meek)
    (org-other-agenda-blocked        mild)
    (org-other-agenda-halfhour       mild)
    (org-other-agenda-active-tab     focus    tab)
    (org-other-agenda-blk-a          focus    block)
    (org-other-agenda-blk-b          positive block)
    (org-other-agenda-blk-c          calm     block)
    (org-other-agenda-marked         crucial  wave))
  "Which accent each face of the board uses, a list of (FACE ACCENT [KIND]).
KIND is `bold' (bold text), `tab' (the accent as background), `block' (a
tinted background), `wave' (an underline) or nil (plain text)."
  :group 'sp-org-agenda-board
  :type '(repeat (list face symbol (choice (const nil) symbol)))
  :set (lambda (symbol value)
         (set-default symbol value)
         (when (fboundp 'sp-org-agenda-board-apply)
           (sp-org-agenda-board-apply))))

(defcustom sp-org-agenda-board-block-mix 0.18
  "How much of the accent goes into the background of a time block (0 to 1)."
  :group 'sp-org-agenda-board
  :type 'float)

(defun sp-org-agenda-board--faces (accent)
  "Return the theme faces of ACCENT."
  (or (cdr (assq accent sp-org-agenda-board-accents))
      (error "No accent %s in `sp-org-agenda-board-accents'" accent)))

(defun sp-org-agenda-board--colour (accent)
  "Return the colour of ACCENT in the current theme."
  (or (seq-some (lambda (face)
                  (let ((colour (and (facep face)
                                     (face-attribute face :foreground nil t))))
                    (and (stringp colour) colour)))
                (sp-org-agenda-board--faces accent))
      (face-attribute 'default :foreground nil)))

(defun sp-org-agenda-board--mix (colour other amount)
  "Return COLOUR with AMOUNT (0 to 1) of OTHER mixed in, as #rrggbb."
  (let ((a (color-name-to-rgb colour))
        (b (color-name-to-rgb other)))
    (if (and a b)
        (apply #'color-rgb-to-hex
               (append (cl-mapcar (lambda (x y) (+ (* (- 1 amount) x) (* amount y)))
                                  a b)
                       '(2)))
      colour)))

(defun sp-org-agenda-board--spec (accent kind)
  "Return the face spec of a face using ACCENT as KIND.
The package's own colours are cleared with `unspecified': a spec added
on top of a `defface' spec does not replace it, it is merged into it."
  (let* ((faces (seq-filter #'facep (sp-org-agenda-board--faces accent)))
         (colour (sp-org-agenda-board--colour accent))
         (background (face-attribute 'default :background nil))
         (foreground (face-attribute 'default :foreground nil))
         (attrs (list :inherit faces :foreground 'unspecified
                      :background 'unspecified :weight 'unspecified
                      :underline 'unspecified)))
    (pcase kind
      ('tab   (setq attrs (plist-put attrs :foreground background))
              (setq attrs (plist-put attrs :background colour))
              (setq attrs (plist-put attrs :weight 'bold)))
      ('block (setq attrs (plist-put attrs :inherit nil))
              (setq attrs (plist-put attrs :foreground foreground))
              (setq attrs (plist-put attrs :background
                                     (sp-org-agenda-board--mix
                                      background colour
                                      sp-org-agenda-board-block-mix))))
      ('wave  (setq attrs (plist-put attrs :inherit nil))
              (setq attrs (plist-put attrs :underline
                                     (list :color colour :style 'wave))))
      ('bold  (setq attrs (plist-put attrs :weight 'bold))))
    (list (cons t attrs))))

(defun sp-org-agenda-board-apply (&rest _)
  "Set the faces of the board from the accents of the current theme."
  (pcase-dolist (`(,face ,accent ,kind) sp-org-agenda-board-roles)
    (face-spec-set face (sp-org-agenda-board--spec accent kind))))

(with-eval-after-load 'org-other-agenda
  (sp-org-agenda-board-apply)
  (add-hook 'sp-after-load-theme-hook #'sp-org-agenda-board-apply 90))

;;;;; Agenda Jump to Dashboard
(defun lem-jump-to-org-dashboard ()
  (interactive)
  (require 'org)
  (org-agenda nil "d"))

;;;;; Agenda Refresh
;; automatically refresh the agenda after adding a task
(defun lem-org-agenda-refresh ()
  (interactive)
  (when (get-buffer "*Org Agenda*")
    (with-current-buffer "*Org Agenda*"
      (org-agenda-redo)
      (message "[org agenda] refreshed!"))))
(add-hook 'org-capture-after-finalize-hook 'lem-org-agenda-refresh)

;; A wrapping menu that layered two-letter mnemonics over
;; `org-agenda-mode-map' (`ds' schedule, `dd' deadline, `vw' week, etc.)
;; was deleted in Spec 09. Native agenda bindings cover the most common
;; operations. If any of the deleted mnemonics prove load-bearing,
;; restore them as direct `org-agenda-mode-map' bindings (Spec 09 O7).
;; See git history for the prior implementation.

;;;; Appearance of the agenda and rendering
;; Agenda styling
  (setq org-auto-align-tags nil)            ;; Don't align tags

(use-package elegant-agenda-mode
  :ensure t)

;; Display properties

;;;; CONFIGURING THE FUNCTIONALITY
;; Scheduling with org-agenda

  (setq org-agenda-skip-scheduled-if-done t)
  (setq org-agenda-skip-timestamp-if-done t)
  (setq org-agenda-todo-ignore-scheduled 'future)
  (setq org-agenda-todo-ignore-deadlines 'far)
  (setq org-agenda-sorting-strategy
   '((agenda time-up) (todo time-up) (tags time-up) (search time-up)))
  ;; Moved to `sp-globals': `sp-calendar-week-start-day' (1, Monday).

;;;; EXTENSIONS FOR ORG-AGENDA
(use-package org-super-agenda
  :after org
  :ensure (:wait t)
  :init
  (setq org-super-agenda-date-format "%A (%e)")
  :config
  (org-super-agenda-mode 1))

;; org-ql requires org-super-agenda, so it has to be declared after it:
;; the other way round, Elpaca queues org-super-agenda as a dependency first
;; and warns that the explicit declaration came too late.
(use-package org-ql
 :ensure t)

;;;; Display an agenda file for the current subtree
;; source: https://github.com/alphapapa/unpackaged.el#agenda-for-subtree-or-region
(defvar org-agenda-overriding-header)
(defvar org-agenda-sorting-strategy)
(defvar org-agenda-restrict)
(defvar org-agenda-restrict-begin)
(defvar org-agenda-restrict-end)

;;;###autoload
(defun sp-org-agenda-current-subtree-or-region (only-todos)
  "Display an agenda view for the current subtree or region.
 With prefix, display only TODO-keyword items."
  (interactive "P")
  (let ((starting-point (point))
        header)
    (with-current-buffer (or (buffer-base-buffer (current-buffer))
                             (current-buffer))
      (if (use-region-p)
          (progn
            (setq header "Region")
            (put 'org-agenda-files 'org-restrict (list (buffer-file-name (current-buffer))))
            (setq org-agenda-restrict (current-buffer))
            (move-marker org-agenda-restrict-begin (region-beginning))
            (move-marker org-agenda-restrict-end
                         (save-excursion
                           ;; If point is at beginning of line, include
                           ;; heading on that line by moving forward 1.
                           (goto-char (1+ (region-end)))
                           (org-end-of-subtree))))
        ;; No region; restrict to subtree.
        (save-excursion
          (save-restriction
            ;; In case the command was called from an indirect buffer, set point
            ;; in the base buffer to the same position while setting restriction.
            (widen)
            (goto-char starting-point)
            (setq header "Subtree")
            (org-agenda-set-restriction-lock))))
      ;; NOTE: Unlike other agenda commands, binding `org-agenda-sorting-strategy'
      ;; around `org-search-view' seems to have no effect.
      (let ((org-agenda-sorting-strategy '(priority-down timestamp-up))
            (org-agenda-overriding-header header))
        (org-search-view (if only-todos t nil) "*"))
      (org-agenda-remove-restriction-lock t)
      (message nil))))

(provide 'sp-org-agenda)
;; sp-org-agenda.el ends here
