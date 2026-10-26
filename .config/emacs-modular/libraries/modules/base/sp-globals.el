;;; sp-globals.el --- My most important settings, in one place -*- lexical-binding: t; -*-

;;; Commentary:

;; The settings that are mine rather than a package's: where my files live,
;; which credentials file Emacs reads, who I am, what stays private on the
;; dashboard, and the habits (prompts, bells, backups) I would otherwise have to
;; chase down in the module that happens to use them.  This is the one file to
;; open when one of them has to change.
;;
;; The locations that used to be in `sp-paths' are here as well.  They should
;; have been a module of their own, but are combined with the other settings for
;; the sake of simplicity and brevity.  `sp-paths' is no longer a module; it is
;; still provided as a feature so that an old (require 'sp-paths) keeps working.
;;
;; Every location can be overridden from the environment before Emacs starts,
;; e.g. SP_NOTES_DIR=/tmp/notes emacs, which is how a test run is kept away from
;; the real notes.  The defaults sit under the home folder and are built with
;; `expand-file-name', so they are right on macOS, Linux and Windows alike.  All
;; of them are directories with a trailing slash.  Use `sp-path' to build a path
;; below one of them.
;;
;; Each setting is a `defcustom' in the `spcustom' group.  When it controls a
;; variable of Emacs or of a package, its :set function also applies the value
;; there, so editing the default below and changing it with Customize have the
;; same effect.  It depends on no module, only on `sp-var-dir' and
;; `sp-cache-dir' from early-init.el, and it is the first core module, because
;; the modules that read these settings need them while they load.
;;
;; Where a setting used to live, the old place now carries a comment that
;; points here.  Still in their modules, on purpose: `sp-headless-host'
;; (early-init.el) and `sp-defer-late-modules' (init.el), which are read before
;; the module lists run, the settings of a single package (the :custom of its
;; `use-package'), and platform settings such as `mac-command-modifier'.

;;; Code:

(defgroup sp-paths nil
  "Locations of my notes, documents and checkouts."
  :group 'files)

(defun sp-paths--dir (env default)
  "Directory named by environment variable ENV, or DEFAULT (relative to ~)."
  (file-name-as-directory
   (expand-file-name (or (getenv env) default))))

(defun sp-path (dir &rest parts)
  "Join PARTS below the directory DIR (a variable's value) into one path."
  (let ((path (expand-file-name dir)))
    (dolist (part parts path)
      (setq path (expand-file-name part path)))))

(defun sp-globals--set (target &optional skip-nil)
  "Return a :set function that stores the value in its symbol and in TARGET.
With SKIP-NIL, a nil value leaves TARGET alone."
  (lambda (symbol value)
    (set-default symbol value)
    (unless (and skip-nil (null value))
      (set-default target value))))

(defcustom sp-notes-dir (sp-paths--dir "SP_NOTES_DIR" "~/notes")
  "Root of the notes (the Zettelkasten, inbox, areas)."
  :type 'directory :group 'spcustom)

(defcustom sp-documents-dir (sp-paths--dir "SP_DOCUMENTS_DIR" "~/Documents")
  "The documents folder (calibre library, writing, elfeed.org)."
  :type 'directory :group 'spcustom)

(defcustom sp-literature-dir (sp-path sp-documents-dir "literature/")
  "Folder with the PDFs and attachments of the bibliography."
  :type 'directory :group 'spcustom)

(defcustom sp-bibliography-dir (sp-paths--dir "SP_BIBLIOGRAPHY_DIR" "~/Documents/bibliography")
  "Folder with the .bib files."
  :type 'directory :group 'spcustom)

(defcustom sp-org-dir (sp-paths--dir "SP_ORG_DIR" "~/org")
  "Folder for org files kept outside the notes (the journal)."
  :type 'directory :group 'spcustom)

(defcustom sp-src-dir (sp-paths--dir "SP_SRC_DIR" "~/src")
  "Where source checkouts and git worktrees live."
  :type 'directory :group 'spcustom)

(defcustom sp-git-dir (sp-paths--dir "SP_GIT_DIR" "~/git")
  "Where my own git projects live."
  :type 'directory :group 'spcustom)

(defcustom sp-clones-dir (sp-paths--dir "SP_CLONES_DIR" "~")
  "Folder holding the cloned-utilities and cloned-scan-ai checkouts."
  :type 'directory :group 'spcustom)

(defcustom sp-data-home
  (sp-paths--dir "XDG_DATA_HOME" "~/.local/share")
  "The user data folder (XDG_DATA_HOME, defaulting to ~/.local/share)."
  :type 'directory :group 'spcustom)

(defcustom sp-yadm-repo (sp-path sp-data-home "yadm/repo.git")
  "The bare repository of the yadm dotfiles."
  :type 'directory :group 'spcustom)

(defcustom sp-chrome-history-file
  (expand-file-name
   (pcase system-type
     ('darwin "~/Library/Application Support/Google/Chrome/Default/History")
     ('windows-nt (concat (or (getenv "LOCALAPPDATA") "~/AppData/Local")
                          "/Google/Chrome/User Data/Default/History"))
     (_ "~/.config/google-chrome/Default/History")))
  "Chrome's browsing history database."
  :type 'file :group 'spcustom)

;; Moved here from sp-trails.el.
(defcustom sp-trails-chrome-history
  sp-chrome-history-file
  "Chromium-family History database read by `sp-trails-import-chrome'."
  :type 'file
  :group 'spcustom)

;; Moved here from sp-scratch.el.
(defcustom sp-scratch-save-dir sp-cache-dir
  "Default directory for saving scratch file."
  :group 'spcustom
  :type 'string)

;; Moved here from sp-treemacs.el.
(defcustom sp-treemacs-root user-emacs-directory
  "Folder shown in the treemacs side window by `sp-treemacs-toggle'."
  :type 'directory
  :group 'spcustom)

;; Moved here from sp-tab-inbox.el.
(defcustom sp-tab-inbox-dir (sp-path sp-notes-dir "inbox/tabs/")
  "Directory of plain files with unsorted links."
  :type 'directory
  :group 'spcustom)

;; Moved here from sp-emoji-font.el.
(defcustom sp-emoji-font-install-dir
  (sp-path sp-data-home "fonts/sp-emoji/")
  "Directory the emoji font is installed into on Linux."
  :type 'directory
  :group 'spcustom)

(defcustom sp-auth-sources '("~/.authinfo")
  "Where Emacs looks for credentials, as in `auth-sources'.
The default is the plain-text file ~/.authinfo only, so ~/.authinfo.gpg and
the keychain are not read.  Forge, for example, takes its GitHub token from
here."
  :type '(repeat sexp)
  :set (sp-globals--set 'auth-sources)
  :group 'spcustom)

(defcustom sp-user-full-name nil
  "My full name, as in `user-full-name', or nil to leave Emacs's own value."
  :type '(choice (const :tag "Emacs's own value" nil) string)
  :set (sp-globals--set 'user-full-name t)
  :group 'spcustom)

(defcustom sp-user-mail-address nil
  "My mail address, as in `user-mail-address', or nil to leave Emacs's own value."
  :type '(choice (const :tag "Emacs's own value" nil) string)
  :set (sp-globals--set 'user-mail-address t)
  :group 'spcustom)

;; Moved here from sp-academic.el.
(defcustom sp-bib-notes nil "User citation notes directory."
  :group 'spcustom
  :tag "Lambda-Emacs Citation Notes Directory")
(defcustom sp-citar-note nil "Template for use with citar notes."
  :group 'spcustom
  :tag "Lambda-Emacs Citar Notes Template")

;; Moved here from sp-dashboard.el.
(defcustom sp-dashboard-private-tags '("private")
  "Entries with one of these tags (inherited) are private."
  :type '(repeat string)
  :group 'spcustom)

(defcustom sp-dashboard-private-files nil
  "Regexps of files whose entries are all private."
  :type '(repeat regexp)
  :group 'spcustom)

(defcustom sp-dashboard-trusted-networks nil
  "Wi-Fi names that count as private, for `sp-dashboard-condition-untrusted-network'."
  :type '(repeat string)
  :group 'spcustom)

(defcustom sp-dashboard-screen-share-processes nil
  "Process names that mean the screen is shared, such as a call app's helper.
Used by `sp-dashboard-condition-screen-share'."
  :type '(repeat string)
  :group 'spcustom)

(defcustom sp-ispell-program "aspell"
  "Spelling program `sp-spelling' uses when it is found on the PATH."
  :type 'string
  :group 'spcustom)

;; Moved here from sp-spelling.el.
;; taken from EWS
(defcustom sia-hunspell-dictionaries "en_US"
  "Comma-separated list of Hunspell dictionaries."
  :group 'spcustom
  :type 'list)

(defcustom sp-confirm-kill-emacs nil
  "Non-nil asks before closing Emacs, as `confirm-kill-emacs'."
  :type 'boolean
  :set (sp-globals--set 'confirm-kill-emacs)
  :group 'spcustom)

(defcustom sp-confirm-kill-processes nil
  "Non-nil asks before closing Emacs with running processes, as `confirm-kill-processes'."
  :type 'boolean
  :set (sp-globals--set 'confirm-kill-processes)
  :group 'spcustom)

(defcustom sp-ring-bell-function 'ignore
  "What to do instead of ringing the bell, as `ring-bell-function'."
  :type 'function
  :set (sp-globals--set 'ring-bell-function)
  :group 'spcustom)

(defcustom sp-visible-bell t
  "Non-nil flashes the screen instead of ringing the bell, as `visible-bell'."
  :type 'boolean
  :set (sp-globals--set 'visible-bell)
  :group 'spcustom)

(defcustom sp-use-dialog-box nil
  "Non-nil asks with dialog boxes, as `use-dialog-box'."
  :type 'boolean
  :set (sp-globals--set 'use-dialog-box)
  :group 'spcustom)

(defcustom sp-use-file-dialog nil
  "Non-nil opens files with the system file dialog, as `use-file-dialog'."
  :type 'boolean
  :set (sp-globals--set 'use-file-dialog)
  :group 'spcustom)

(defcustom sp-backup-directory (expand-file-name "backups/" sp-var-dir)
  "Folder for the backup files of every file, as in `backup-directory-alist'."
  :type 'directory
  :set (lambda (symbol value)
         (set-default symbol value)
         (set-default 'backup-directory-alist
                      `(("." . ,(expand-file-name value)))))
  :group 'spcustom)

(defcustom sp-create-lockfiles nil
  "Non-nil makes lock files (.#file) next to edited files, as `create-lockfiles'."
  :type 'boolean
  :set (sp-globals--set 'create-lockfiles)
  :group 'spcustom)

(defcustom sp-calendar-week-start-day 1
  "First day of the week, 0 for Sunday, as `calendar-week-start-day'."
  :type 'integer
  :set (sp-globals--set 'calendar-week-start-day)
  :group 'spcustom)

;; Moved here from sp-scratch.el.
(defcustom sp-persistent-scratch t
  "If t, make scratch buffer persist across sessions.
Default is to persist."
  :group 'spcustom
  :type 'boolean)

(defcustom sp-scratch-default-dir (expand-file-name "~/")
  "Default directory for scratch buffer.
User may prefer to set this to `sp-scratch-save-dir'."
  :group 'spcustom
  :type 'string)

;; The former sp-paths module, still provided so that an old (require 'sp-paths)
;; keeps working.
(provide 'sp-paths)
(provide 'sp-globals)
;; sp-globals.el ends here.
