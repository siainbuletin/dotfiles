;; -*- lexical-binding: t; -*-

(defun sia-execute-all-buffers ()
  (interactive)
  (let ((org-confirm-babel-evaluate nil))
    (org-babel-execute-buffer))
)

(global-set-key (kbd "C-c o o") 'org-org-export-to-org)
(global-set-key (kbd "C-c e c") 'sia-execute-all-buffers)

(setq initial-major-mode 'org-mode)

(org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (org . t)
     (R . t))
)

(setq-default cursor-type 'bar) ;; this will make the cursor similar to other text editors

;; WINDOW FUNCTIONS
(setq-default frame-title-format '("␥ %b ␥")) ;; Make the window title to be the buffer name

;; Redrawing the display when there's graphical errors
(global-set-key (kbd "<f6>") 'redraw-display)


(use-package undo-tree
  :ensure (:wait t)
  :config
  (add-to-list 'undo-tree-incompatible-major-modes #'nxml-mode)
  (global-undo-tree-mode)

  :custom
  (undo-tree-history-directory-alist '(("." . "~/.emacs.d/undo"))))

(use-package vundo
  :ensure (:wait t))

(keymap-global-set "C-c j j" #'join-line)

(electric-pair-mode 1)

(defun sia-clean-whitespace (&optional Begin End)
  "Delete trailing whitespace, and replace repeated blank lines to just 1.
Only space and tab is considered whitespace here.
Works on whole buffer or selection, respects `narrow-to-region'."
  (interactive)
  (let (xbeg xend)
    (seq-setq (xbeg xend)
              (if (and Begin End)
                  (list Begin End)
                (if (region-active-p)
                    (list (region-beginning) (region-end))
                  (list (point-min) (point-max)))))
    (save-excursion
      (save-restriction
        (narrow-to-region xbeg xend)
        (progn
          (goto-char (point-min))
          (while (re-search-forward "[ \t]+\n" nil t) (replace-match "\n")))
        (progn
          (goto-char (point-min))
          (while (re-search-forward "\n\n\n+" nil t) (replace-match "\n\n")))
        (progn
          (goto-char (point-max))
          (while (eq (char-before) 32) (delete-char -1))))))
  (message "done sia-clean-whitespace"))

(add-hook 'before-save-hook 'sia-clean-whitespace)

(use-package load-dir
  :ensure (:wait t))

(use-package cond-let
  :ensure (:wait t))

(use-package keycast
  :ensure (:wait t))

(use-package dwim-shell-command
  :ensure t
  :bind (([remap shell-command] . dwim-shell-command)
         :map dired-mode-map
         ([remap dired-do-async-shell-command] . dwim-shell-command)
         ([remap dired-do-shell-command] . dwim-shell-command)
         ([remap dired-smart-shell-command] . dwim-shell-command)))

(use-package try
  :ensure (:wait t))

;; SOUNDS
(setq ring-bell-function 'ignore) ;; Disable the bell sound

;; BUFFER FUNCTIONS
(global-auto-revert-mode t) ;; If the file has changed on the disk, then update the buffer as well

;; Suppress unnecessary warnings

;; You can set minimum severity level for displaying the warning buffer to :error or :emergency:
;; https://emacs.stackexchange.com/questions/78800/how-to-disable-automatic-appearance-of-warnings-buffer-in-emacs

(setq warning-minimum-level :error)

(use-package transient
  :ensure t)

(use-package p-search
  :ensure (:host github :repo "zkry/p-search"))

(use-package websocket
  :ensure (:wait t)
)

(use-package helm
    :ensure (:wait t))

(use-package ess
  :ensure t)

(use-package taxy
  :ensure t)
