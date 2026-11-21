;;; thesis-desk.el --- Reading journal and thesis map for a long argument -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (org "9.6"))

;;; Commentary:

;; A thesis map (claims and questions) and a reading journal that ties every
;; article you open to the claims it is meant to help with, and records why
;; you left it.  DEVONthink is reached through `osascript' only.
;;
;; The core files need only Emacs, Org and macOS.  `thesis-desk-sp' plugs in
;; the emacs-modular configuration (vulpea claims, the `C-; t' keys).
;;
;; Documented in thesis-desk/README.org of the dotfiles repository.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)

(defgroup thesis-desk nil
  "Reading journal and thesis map."
  :group 'org
  :prefix "thesis-desk-")

(defcustom thesis-desk-directory "~/Documents/thesis/"
  "Folder that holds the map and the journal."
  :type 'directory)

(defcustom thesis-desk-map-file "map.org"
  "The thesis map, relative to `thesis-desk-directory'."
  :type 'string)

(defcustom thesis-desk-journal-file "journal.org"
  "The reading journal, relative to `thesis-desk-directory'."
  :type 'string)

(defun thesis-desk-file (name)
  "NAME expanded in `thesis-desk-directory'."
  (expand-file-name name thesis-desk-directory))

(require 'thesis-desk-dt)
(require 'thesis-desk-map)
(require 'thesis-desk-journal)
(require 'thesis-desk-views)
(require 'thesis-desk-hotspots)
(require 'thesis-desk-litnotes)

(defvar thesis-desk-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map "s" #'thesis-desk-start)
    (define-key map "x" #'thesis-desk-switch)
    (define-key map "w" #'thesis-desk-where)
    (define-key map "N" #'thesis-desk-rejected)
    (define-key map "j" #'thesis-desk-journal-visit)
    (define-key map "m" #'thesis-desk-map-visit)
    (define-key map "h" #'thesis-desk-hotspots)
    (define-key map "H" #'thesis-desk-synthesis-mark-addressed)
    (define-key map "P" #'thesis-desk-litnotes-propose)
    (define-key map "p" #'thesis-desk-litnotes-review)
    map)
  "Keys of thesis-desk, to be bound under a prefix (`C-; t' in emacs-modular).")

(provide 'thesis-desk)
;;; thesis-desk.el ends here
