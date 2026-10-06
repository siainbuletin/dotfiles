;; -*- lexical-binding: t; -*-
;; sp-backups.el

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

(setq auto-save-default nil)
(setq create-lockfiles nil)

;;;; Backups / Auto-Save
(use-package files
  :ensure nil
  :defer 1
  :init
  
  ;; backups
  (let ((backup-dir (concat sp-cache-dir "backup")))
    ;; Move backup file to `~/.emacs.d/temp/cache/backup'
    (setq backup-directory-alist `(("." . ,backup-dir)))
    ;; Makesure backup directory exist
    (when (not (file-exists-p backup-dir))
      (make-directory backup-dir t)))
  
  ;; auto save
  (setq auto-save-list-file-prefix
        (concat sp-cache-dir "auto-save-list/.saves-"))
  (let ((auto-save-files-dir (concat sp-cache-dir "auto-save-files/")))
    (setq auto-save-file-name-transforms
          `((".*" ,auto-save-files-dir t)))
    (when (not (file-exists-p auto-save-files-dir))
      (make-directory auto-save-files-dir t)))
  
  ;; auto-save every file visiting buffer
  ;; see https://emacs.stackexchange.com/q/7729/11934
  (setq-default auto-save-default t)
  (setq-default
   auto-save-timeout 30              ; number of seconds idle time before auto-save (default: 30)
   auto-save-interval 300            ; number of keystrokes between auto-saves (default: 300)
   delete-auto-save-files t
   create-lockfiles nil)
  (auto-save-visited-mode 1)
  :config
  (setq  make-backup-files t               ; backup of a file the first time it is saved.
         backup-by-copying t               ; don't clobber symlinks
         version-control t                 ; version numbers for backup files
         delete-old-versions t             ; delete excess backup files silently
         kept-old-versions 0               ; oldest versions to keep when a new numbered backup is made
         kept-new-versions 10              ; newest versions to keep when a new numbered backup is made
         vc-make-backup-files t            ; backup versioned files, which Emacs does not do by default
         )

  (defun lem-full-auto-save ()
    (interactive)
    (save-excursion
      (dolist (buf (buffer-list))
        (when (buffer-live-p buf)  ; Check if buffer is still valid
          (with-current-buffer buf  ; Use with-current-buffer instead of set-buffer
            (when (and (buffer-file-name) (buffer-modified-p))
              (condition-case nil  ; Catch any errors during save
                  (basic-save-buffer)
                (error nil))))))))

  (add-hook 'auto-save-hook 'lem-full-auto-save)

  ;; Save all buffers after idle time
  (run-with-idle-timer 5 t (lambda () (lem-full-auto-save))))

;; What to do with the backups?
(setq delete-old-versions t)
(setq kept-new-versions 6)
(setq kept-old-versions 2)
(setq version-control t)

(use-package vc-backup
  :ensure (:wait t))

(setq-default backup-directory-alist
    `(("." . ,(expand-file-name "backups/" user-emacs-directory)))
      make-backup-files t
      vc-make-backup-files t ; Won't create backup of files that are already under version control
      backup-by-copying t ; Avoid symlinks
      delete-old-versions t
      delete-by-moving-to-trash t ; This makes sure that the files aren't permanently deleted
      kept-new-versions 6
      kept-old-versions 3
      version-control t)

;;; Lockfiles unfortunately cause more pain than benefit
(setq create-lockfiles nil)

;; What do you do with the saved history?
(use-package savehist
  :ensure nil
  :init
  (savehist-mode t)
  :config
  (setq savehist-file (expand-file-name "savehist" user-emacs-directory)))