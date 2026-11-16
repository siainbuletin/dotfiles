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
(declare-function sp-dotfiles-work-tree "sp-globals")

(declare-function sp-org-issues--agenda-files "sp-org-issues")
(declare-function org-gtd-agenda-transient "org-gtd")

;;;; Keys
(keymap-global-set "C-c o a" #'org-agenda)
(keymap-global-set "C-c a" #'org-agenda)
(keymap-global-set "C-c o x" #'sp-agenda-views-inline)
(keymap-global-set "C-c o X" #'sp-agenda-views-inline-menu)

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

;;;; Inline keywords

(defvar sp-writing-projects)

(defcustom sp-agenda-views-inline-keywords '("FIXME" "CITE" "TK" "XXX" "SOURCEREFS")
  "Words that mark a problem inside the text of an Org entry.
- The inline view lists every entry whose text or heading holds one of them.
- SOURCEREFS marks a reference made in the PDF being read, for which a
  literature note is being written.  It has its own keyword so CITE stays
  for references in one's own text.
- Words are matched whole, so \"TK\" does not hit \"Atkins\".
- Org's search view decides whether the match ignores case."
  :type '(repeat string)
  :group 'spcustom
  :set (lambda (symbol value)
         (set-default symbol value)
         (when (fboundp 'sp-agenda-views--inline-install)
           (sp-agenda-views--inline-install))))

(defvar sp-notes-dir)

(defcustom sp-agenda-views-inline-extra-dirs
  (list sp-writing-projects
        (expand-file-name "litnotes/" (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes")))
  "Folders (or single files) the inline view scans besides the agenda files.
Drafts and the literature notes live there, and they are not always agenda files."
  :type '(repeat file)
  :group 'spcustom)

(defcustom sp-agenda-views-inline-exclude-regexp
  "/\\(?:\\.\\|#\\|archives?/\\|backups?/\\|[^/]*~\\'\\|[^/]*\\.org_archive\\'\\)"
  "Paths below the extra folders that the inline view skips.
It is matched against the path relative to the folder, with a leading slash:
hidden files and folders, Emacs lock and backup files, archive and backup
folders and `.org_archive' files."
  :type 'regexp
  :group 'spcustom)

(defvar sp-agenda-views-inline-filter nil
  "The one keyword the inline view is narrowed to, or nil for all of them.
Set it with `sp-agenda-views-inline-filter-set', clear it with
`sp-agenda-views-inline-filter-clear'.")

(defun sp-agenda-views-inline--words ()
  "Return the words the inline view searches for now."
  (if (member sp-agenda-views-inline-filter sp-agenda-views-inline-keywords)
      (list sp-agenda-views-inline-filter)
    sp-agenda-views-inline-keywords))

(defun sp-agenda-views-inline-regexp ()
  "Return the search-view term matching the words of the inline view.
These are `sp-agenda-views-inline-keywords', or only
`sp-agenda-views-inline-filter' when it is set."
  (concat "{\\_<" (regexp-opt (sp-agenda-views-inline--words)) "\\_>}"))

(defun sp-agenda-views-inline--org-files (place)
  "The Org files of PLACE, a file or a folder, minus the excluded paths."
  (cond
   ((and place (file-regular-p place)) (list (expand-file-name place)))
   ((and place (file-directory-p place))
    (let* ((root (file-name-as-directory (expand-file-name place)))
           (skip (lambda (path)
                   (string-match-p sp-agenda-views-inline-exclude-regexp
                                   (concat "/" (file-relative-name path root))))))
      (seq-remove skip
                  (directory-files-recursively
                   root "\\.org\\'" nil
                   (lambda (dir) (not (funcall skip (file-name-as-directory dir))))))))))

(defun sp-agenda-views-inline--rg-pattern ()
  "The ripgrep pattern for the words of the inline view."
  (concat "(?:"
          (mapconcat (lambda (word)
                       (replace-regexp-in-string "[][(){}.*+?^$|\\\\]" "\\\\\\&" word))
                     (sp-agenda-views-inline--words) "|")
          ")"))

(defun sp-agenda-views-inline--prefilter (files)
  "The FILES that hold one of the words of the inline view.
Ripgrep tells which; without it, or when it fails, all FILES are returned.
This keeps the search view from opening every litnote."
  (let ((rg (executable-find "rg"))
        (pattern (sp-agenda-views-inline--rg-pattern))
        (kept nil))
    (if (or (null rg) (null files))
        files
      (catch 'failed
        (while files
          (let ((chunk (seq-take files 400)))
            (setq files (nthcdr 400 files))
            (with-temp-buffer
              (let ((status (apply #'call-process rg nil t nil
                                   "-l" "-i" "-w" "-e" pattern "--" chunk)))
                (cond ((eq status 0)
                       (setq kept (append kept (split-string (buffer-string) "\n" t))))
                      ((eq status 1))
                      (t (throw 'failed (append kept chunk files))))))))
        kept))))

(defun sp-agenda-views-inline-files ()
  "Return the agenda files plus the Org files of the extra folders.
Of the extra folders only the files that hold an inline word are returned."
  (let ((agenda (mapcar #'expand-file-name (org-agenda-files)))
        (extra (sp-agenda-views-inline--prefilter
                (seq-mapcat #'sp-agenda-views-inline--org-files
                            sp-agenda-views-inline-extra-dirs))))
    (seq-uniq (append agenda extra) (lambda (a b) (file-equal-p a b)))))

(defun sp-agenda-views--inline-entry ()
  "Return the inline view, as an `org-agenda-custom-commands' entry."
  `("x" "Inline keywords to fix" search ,(sp-agenda-views-inline-regexp)
    ((org-agenda-files (sp-agenda-views-inline-files))
     (vulpea-para-agenda-inhibit-files-update t)
     (org-agenda-prefix-format '((search . " %(sp-agenda-views-file-title) ")))
     (org-agenda-overriding-header
      (if sp-agenda-views-inline-filter
          (format "Inline keyword to fix: %s" sp-agenda-views-inline-filter)
        "Inline keywords to fix"))
     (org-agenda-buffer-name "*Inline keywords*"))))

(defun sp-agenda-views-inline ()
  "Show the entries that hold an inline keyword, in the agenda."
  (interactive)
  (org-agenda nil "x"))

(defun sp-agenda-views-inline-grep ()
  "List every line with an inline word, also before the first heading of a file.
The search view skips that part of a file, so this complements it.  It needs
ripgrep; the hits are a grep buffer, so `RET' jumps to the line."
  (interactive)
  (let ((rg (or (executable-find "rg") (user-error "Ripgrep (rg) is not installed")))
        (files (sp-agenda-views-inline-files)))
    (unless files (user-error "No file to search"))
    (compilation-start
     (mapconcat #'shell-quote-argument
                (append (list rg "-n" "--no-heading" "--with-filename" "-i" "-w"
                              "-e" (sp-agenda-views-inline--rg-pattern) "--")
                        files)
                " ")
     'grep-mode)))

(defun sp-agenda-views--inline-install ()
  "Put the inline view into `org-agenda-custom-commands', replacing any old one."
  (setq org-agenda-custom-commands
        (append (seq-remove (lambda (cmd) (equal (car cmd) "x"))
                            org-agenda-custom-commands)
                (list (sp-agenda-views--inline-entry)))))

(defun sp-agenda-views-inline-filter-set (keyword)
  "Narrow the inline view to KEYWORD and open it.
Completion offers `sp-agenda-views-inline-keywords'."
  (interactive
   (list (completing-read "Inline keyword: " sp-agenda-views-inline-keywords
                          nil t nil nil sp-agenda-views-inline-filter)))
  (unless (member keyword sp-agenda-views-inline-keywords)
    (user-error "\"%s\" is not in `sp-agenda-views-inline-keywords'" keyword))
  (setq sp-agenda-views-inline-filter keyword)
  (sp-agenda-views--inline-install)
  (sp-agenda-views-inline))

(defun sp-agenda-views-inline-filter-clear ()
  "Show every inline keyword again and open the view."
  (interactive)
  (setq sp-agenda-views-inline-filter nil)
  (sp-agenda-views--inline-install)
  (sp-agenda-views-inline))

(require 'transient)

(transient-define-prefix sp-agenda-views-inline-menu ()
  "Inline keyword view and its filter."
  [:description
   (lambda ()
     (format "Inline keywords (filter: %s)"
             (or sp-agenda-views-inline-filter "none")))
   ("x" "Open the view" sp-agenda-views-inline)
   ("f" "Filter to one keyword" sp-agenda-views-inline-filter-set)
   ("c" "Clear the filter" sp-agenda-views-inline-filter-clear)
   ("g" "Grep the lines (also before the first heading)" sp-agenda-views-inline-grep)])

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
  (let ((default-directory (file-name-as-directory (expand-file-name (sp-dotfiles-work-tree)))))
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
                sp-agenda-views-issues)
              (list (sp-agenda-views--inline-entry))))

(provide 'sp-agenda-views)
;; sp-agenda-views.el ends here
