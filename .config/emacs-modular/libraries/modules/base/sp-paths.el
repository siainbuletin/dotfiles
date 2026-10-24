;;; sp-paths.el --- Where my files live -*- lexical-binding: t; -*-

;;; Commentary:

;; Every place outside the Emacs directory that the modules read or write
;; (notes, bibliography, literature, source checkouts) is named here once, so
;; that the modules never spell out "~/notes" and the like themselves.  Load it
;; before any module that uses one of these variables.
;;
;; Each location can be overridden from the environment before Emacs starts,
;; e.g. SP_NOTES_DIR=/tmp/notes emacs, which is how a test run is kept away from
;; the real notes.  The defaults sit under the home folder and are built with
;; `expand-file-name', so they are right on macOS, Linux and Windows alike.
;;
;; All of them are directories with a trailing slash.  Use `sp-path' to build a
;; path below one of them.

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

(defcustom sp-notes-dir (sp-paths--dir "SP_NOTES_DIR" "~/notes")
  "Root of the notes (the Zettelkasten, inbox, areas)."
  :type 'directory :group 'spcustom)

(defcustom sp-documents-dir (sp-paths--dir "SP_DOCUMENTS_DIR" "~/Documents")
  "The documents folder (calibre library, writing, elfeed.org)."
  :type 'directory :group 'spcustom)

(defcustom sp-literature-dir (sp-path sp-documents-dir "literature/")
  "Folder with the PDFs and attachments of the bibliography."
  :type 'directory :group 'spcustom)

(defcustom sp-bibliography-dir (sp-paths--dir "SP_BIBLIOGRAPHY_DIR" "~/bibliography")
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

(provide 'sp-paths)
;; sp-paths.el ends here.
