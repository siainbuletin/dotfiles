;;; sp-agenda-views.el --- Custom agenda views and agenda keys -*- lexical-binding: t; -*-

;;; Commentary:

;; Every custom agenda view and every agenda key in one place.
;; `org-agenda-custom-commands' is assigned once, here.  Load this module
;; after sp-vulpea-para and sp-org-issues, whose functions the views call.
;; Views that restrict `org-agenda-files' themselves also bind
;; `vulpea-para-agenda-inhibit-files-update', or vulpea-para would put the
;; PARA agenda files back before the block runs.

;;; Code:

(require 'org-agenda)
(require 'seq)
(require 'subr-x)
(require 'vulpea-para)

(defvar sp-yadm-repo)

(declare-function sp-org-issues--agenda-files "sp-org-issues")
(declare-function org-gtd-agenda-transient "org-gtd")

;;;; Keys
(keymap-global-set "C-c o a" #'org-agenda)
(keymap-global-set "C-c a" #'org-agenda)

(with-eval-after-load 'org-agenda
  (keymap-set org-agenda-mode-map "C-c ." #'org-gtd-agenda-transient))

(defconst sp-agenda-views-day-groups
  '((:name "Accomplishments"
     :todo ("DONE" "CNCL" "CANCELLED")
     :order 4)
    (:name "End of Day"
     :habit t
     :order 2)
    (:name "Uncompleted Work"
     :todo ("PROG" "DOING")
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
     :order 3))
  "`org-super-agenda' groups of the Daily Agenda view.")

(defconst sp-agenda-views-native
  '(("d" "Dashboard"
     ((agenda "" ((org-agenda-span 'day)))
      (tags-todo "DEADLINE=\"<today>\""
                 ((org-agenda-overriding-header "Due Today!")))
      (tags-todo "+DEADLINE<\"<+5d>\"+DEADLINE>\"<today>\""
                 ((org-agenda-overriding-header "Due Soon")))
      (todo "NEXT"
            ((org-agenda-overriding-header "Next Tasks")))
      (tags-todo "email" ((org-agenda-overriding-header "Email")))))

    ("p" "Planning"
     ((tags-todo "+@planning"
                 ((org-agenda-overriding-header "Planning Tasks")))
      (tags-todo "-{.*}"
                 ((org-agenda-overriding-header "Untagged Tasks")))
      (todo ".*" ((org-agenda-files (list (sp-path sp-notes-dir "inbox.org")))
                  (vulpea-para-agenda-inhibit-files-update t)
                  (org-agenda-overriding-header "Unprocessed Inbox Items")))))

    ("D" "Daily Agenda"
     ((agenda "" ((org-agenda-span 'day)
                  (org-deadline-warning-days 7)
                  (org-super-agenda-groups sp-agenda-views-day-groups)))
      (tags-todo "+PRIORITY=\"A\""
                 ((org-agenda-overriding-header "High Priority Tasks")))))

    ("n" "Next Tasks"
     ((todo "NEXT"
            ((org-agenda-overriding-header "Next Tasks")))))

    ("W" "Work Tasks" tags-todo "+work")

    ;; The splash screen opens this one
    ("l" "Coming deadlines" agenda ""
     ((org-agenda-span 30)
      (org-agenda-entry-types '(:deadline))
      (org-deadline-warning-days 30)
      (org-agenda-overriding-header "Coming deadlines")))

    ;; Low-effort next actions
    ("e" tags-todo "+TODO=\"NEXT\"+Effort<15&+Effort>0"
     ((org-agenda-overriding-header "Low Effort Tasks")
      (org-agenda-max-todos 20)))

    ("w" "Workflow Status"
     ((todo "PROG"
            ((org-agenda-overriding-header "In Progress")))
      (todo "WAIT"
            ((org-agenda-overriding-header "Waiting on External")))
      (todo "REVIEW"
            ((org-agenda-overriding-header "In Review")))
      (todo "ACTIVE"
            ((org-agenda-overriding-header "Active Projects")))))

    ("R" "Weekly Review"
     ((agenda ""
              ((org-agenda-overriding-header "Completed Tasks")
               (org-agenda-skip-function '(org-agenda-skip-entry-if 'nottodo 'done))
               (org-agenda-span 'week)))

      (agenda ""
              ((org-agenda-overriding-header "Unfinished Scheduled Tasks")
               (org-agenda-skip-function '(org-agenda-skip-entry-if 'todo 'done))
               (org-agenda-span 'week)))))

    ("r" "Research and university" tags-todo "+@research @reading @uni")

    ("u" "Untagged Tasks" tags-todo "-{.*}"))
  "The native views, as `org-agenda-custom-commands' entries.")

(defconst sp-agenda-views-issues
  '(("i" . "Issues")
    ("ii" "Issue board"
     ((todo "PROG" ((org-agenda-overriding-header "In progress")))
      (todo "NEXT" ((org-agenda-overriding-header "Next")))
      (todo "WAIT" ((org-agenda-overriding-header "Waiting on review or a reply")))
      (todo "TODO" ((org-agenda-overriding-header "Open"))))
     ((org-agenda-files (sp-org-issues--agenda-files))
      (vulpea-para-agenda-inhibit-files-update t)
      (org-agenda-buffer-name "*Issues*")))
    ("ib" "Issues with a branch" tags-todo "BRANCH<>\"\""
     ((org-agenda-files (sp-org-issues--agenda-files))
      (vulpea-para-agenda-inhibit-files-update t)
      (org-agenda-overriding-header "Issues with a branch"))))
  "The issue views, as `org-agenda-custom-commands' entries.")

;;;; Config files

(defcustom sp-agenda-views-config-source 'yadm
  "Where the config view finds the Org files it searches for TODO headings.
`yadm' means the Org files tracked by the yadm repository (`sp-yadm-repo'),
and `dirs' means every Org file below `sp-agenda-views-config-dirs'."
  :type '(choice (const :tag "Org files tracked by yadm" yadm)
                 (const :tag "Org files below the listed folders" dirs))
  :group 'spcustom)

(defcustom sp-agenda-views-config-dirs
  '("~/.config/emacs-modular/" "~/adr/")
  "Folders searched by the config view when the source is `dirs'."
  :type '(repeat directory)
  :group 'spcustom)

(defun sp-agenda-views--yadm-org-files ()
  "Return the Org files tracked by yadm, as absolute names."
  (let ((default-directory (file-name-as-directory (expand-file-name "~"))))
    (with-temp-buffer
      (when (zerop (process-file "git" nil t nil
                                 (concat "--git-dir=" (expand-file-name sp-yadm-repo))
                                 (concat "--work-tree=" default-directory)
                                 "ls-files" "-z" "--" "*.org"))
        (mapcar (lambda (file) (expand-file-name file default-directory))
                (split-string (buffer-string) "\0" t))))))

(defun sp-agenda-views--dirs-org-files ()
  "Return the Org files below `sp-agenda-views-config-dirs'."
  (seq-mapcat (lambda (dir)
                (when (file-directory-p dir)
                  (directory-files-recursively (expand-file-name dir) "\\.org\\'")))
              sp-agenda-views-config-dirs))

(defun sp-agenda-views-config-files ()
  "Return the existing Org files of my configuration, without lock files."
  (let ((files (seq-filter
                (lambda (file)
                  (and (file-regular-p file)
                       (not (string-prefix-p ".#" (file-name-nondirectory file)))))
                (if (eq sp-agenda-views-config-source 'yadm)
                    (sp-agenda-views--yadm-org-files)
                  (sp-agenda-views--dirs-org-files)))))
    (or (delete-dups files)
        (user-error "No Org files found for the config view (source: %s)"
                    sp-agenda-views-config-source))))

(defun sp-agenda-views-file-title ()
  "Return the `#+title:' of the current buffer, as a 36 character column.
Fall back to the file name when the file has no title.  Meant for
`org-agenda-prefix-format', which runs it with point on the entry."
  (let ((title (save-excursion
                 (save-restriction
                   (widen)
                   (goto-char (point-min))
                   (when (re-search-forward "^#\\+title:[ \t]*\\(.+\\)$" nil t)
                     (string-trim (match-string 1)))))))
    (truncate-string-to-width
     (or title (file-name-base (or (buffer-file-name (buffer-base-buffer)) "")))
     36 nil ?\s "…")))

(defconst sp-agenda-views-config
  '(("c" "Config TODOs" todo ""
     ((org-agenda-files (sp-agenda-views-config-files))
      (vulpea-para-agenda-inhibit-files-update t)
      (org-agenda-prefix-format '((todo . " %(sp-agenda-views-file-title) ")))
      (org-agenda-overriding-header "TODOs in the config files")
      (org-agenda-buffer-name "*Config TODOs*"))))
  "The config view, as an `org-agenda-custom-commands' entry.")

(autoload 'org-ql-block "org-ql")

(defconst sp-agenda-views-ql
  '(("q" "Queries (org-ql)"
     ((org-ql-block '(and (todo "NEXT") (not (scheduled)) (not (deadline)))
                    ((org-ql-block-header "Next actions without a date")))
      (org-ql-block '(todo "WAIT")
                    ((org-ql-block-header "Waiting")))
      (org-ql-block '(and (done) (closed :from -7))
                    ((org-ql-block-header "Done in the last 7 days"))))))
  "The org-ql views, as `org-agenda-custom-commands' entries.")

(defconst sp-agenda-views-para
  `((" " "Agenda"
     (,vulpea-para-agenda-cmd-refile
      ,vulpea-para-agenda-cmd-today
      ,vulpea-para-agenda-cmd-focus
      ,vulpea-para-agenda-cmd-stuck-projects
      ,vulpea-para-agenda-cmd-waiting
      ,(vulpea-para-agenda-cmd-current-quarter))))
  "The main PARA view, as an `org-agenda-custom-commands' entry.")

(setq org-agenda-custom-commands
      (append sp-agenda-views-para
              sp-agenda-views-native
              sp-agenda-views-ql
              sp-agenda-views-config
              (when (featurep 'sp-org-issues)
                sp-agenda-views-issues)))

(provide 'sp-agenda-views)
;; sp-agenda-views.el ends here
