;;; sp-backups.el --- Backups, auto-saving and history -*- lexical-binding: t; -*-

;;; Commentary:

;; Emacs leaves a bunch of backup files behind, that I don't actually want
;; to have to see.
;;
;; There should also be a better way to deal with all of these files.

;;; Code:

;;;; Backups / Auto-Save
(use-package files
  :ensure nil
  :defer 1
  :init

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
   delete-auto-save-files t)
  (auto-save-visited-mode 1)
  :config
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

(use-package vc-backup
  :ensure (:wait t))

;; The backup folder (`backup-directory-alist') moved to `sp-globals', as
;; `sp-backup-directory'.
(setq-default make-backup-files t
              vc-make-backup-files t ; Won't create backup of files that are already under version control
              backup-by-copying t ; Avoid symlinks
              delete-old-versions t
              delete-by-moving-to-trash t ; This makes sure that the files aren't permanently deleted
              kept-new-versions 6
              kept-old-versions 3
              version-control t)

;;;; Lockfiles unfortunately cause more pain than benefit
;; Moved to `sp-globals': `sp-create-lockfiles' (nil: no lock files).

;; What do you do with the saved history?
(use-package savehist
  :ensure nil
  :init
  (setq savehist-file (expand-file-name "savehist" sp-var-dir))
  (savehist-mode t))

(provide 'sp-backups)
;; sp-backups.el ends here.
