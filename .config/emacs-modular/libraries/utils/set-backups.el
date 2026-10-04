;; -*- lexical-binding: t; -*-
;; sia-set-backups.el

(defcustom siapip/backup-file-location "~/.emacs.d/backups"
  "Directory where backup files will be stored.
This specifies the path where Emacs will save backup files when
editing. The default location is in the .emacs.d directory."
  :type 'directory
  :group 'siapip)
(condition-case nil
    (make-directory siapip/backup-file-location t)
  (error (message "Warning: Could not create backup directory")))
(setq backup-directory-alist (list (cons "." siapip/backup-file-location)))
(setq backup-by-copying t)
(setq delete-old-versions t
      kept-new-versions 6
      kept-old-versions 2
      version-control t)
(setq auto-save-default nil)
(setq create-lockfiles nil)