;; -*- lexical-binding: t; -*-
;; sp-prog-misc.el --- miscellaneous utilities for programming

(use-package emr
  :defer t)

(use-package rainbow-delimiters
  :ensure t
  :hook ((prog-mode . rainbow-delimiters-mode)
         (salt-mode . rainbow-delimiters-mode)))

(use-package x509-mode
  :defer t)

(use-package yaml-mode
  :defer t)

(use-package dot-mode
  :defer t)

(use-package dockerfile-mode
  :defer t)

(use-package docker-compose-mode
  :defer t)

(use-package json-mode
  :defer t)

(use-package elf-mode
  :defer t)

(use-package demangle-mode
  :defer t)

(use-package systemd
  :defer t)

(use-package easy-hugo
  :defer t)

(use-package gh-md
  :defer t)

(use-package ein
  :defer t)

(global-unset-key (kbd "C-z")) ; stop me from freezing emacs

(global-set-key (kbd "<M-up>") 'move-text-up)
(global-set-key (kbd "<M-down>") 'move-text-down)
;(global-set-key (kbd "<home>") 'smart-beginning-of-line)

;; avoid help-for-help via f1
(global-unset-key [(f1)])

;; Yes or no short
(defalias 'yes-or-no-p 'y-or-n-p)

;; Selection/Clipboard improvements
(delete-selection-mode t)
;; (transient-mark-mode t)
;;focus follow mouse
(defcustom siapip/focus-follows-mouse t
  "When non-nil, focus follows the mouse pointer."
  :type 'boolean
  :group 'siapip)
;; Negative delay: debounces auto-selection (brushing past a split won't grab
;; it) and, crucially, suppresses minibuffer auto-selection so mouse nudges
;; don't yank focus out of an active vertico/consult session.
(setq mouse-autoselect-window -0.2
      focus-follows-mouse siapip/focus-follows-mouse)
;;(setq interprogram-paste-function 'x-cut-buffer-or-selection-value)

;;;; Diffing
;;Diff adjustements
(setq ediff-window-setup-function 'ediff-setup-windows-plain
      ediff-split-window-function 'split-window-horizontally
      ediff-diff-options "-w")
;;/etc/etc-update.conf
;;diff_command="emacs-diff %file1 %file2"
;;using_editor=1
;;merge_command="emacs-merge %orig %new %merged"

;;;;; Diffing against the clipboard (for code generated with AI)
(defun my/ediff-with-clipboard ()
  "Ediff the current buffer (or active region) against the latest kill/clipboard."
  (interactive)
  (let* ((mode major-mode)
         (clip (generate-new-buffer "*clipboard*"))
         (orig (if (use-region-p)
                   (let ((b (generate-new-buffer "*region*"))
                         (s (buffer-substring (region-beginning) (region-end))))
                     (with-current-buffer b (insert s) (funcall mode))
                     b)
                 (current-buffer))))
    (with-current-buffer clip
      (insert (current-kill 0))
      (funcall mode))
    (ediff-buffers orig clip)))

;;;; Other misc settings
(global-font-lock-mode t)
(delete-selection-mode t)
(auto-compression-mode t)
(line-number-mode t)
(column-number-mode t)
;;Show matching parentheses
(show-paren-mode t)
(setq show-paren-delay 0)
(transient-mark-mode t)
(global-hl-line-mode t)
;(setq cursor-type 'bar)
(setq redisplay-dont-pause t)
;(setq ring-bell-function 'ignore)

(require 'recentf)
(setq recentf-auto-cleanup 'never
      recentf-max-menu-items 25
      recentf-max-saved-items 50)
(recentf-mode 1)
(global-set-key (kbd "C-x C-r") 'recentf-open-files)

;;Mouse scroll
(defcustom siapip/scroll-amount 5
  "Scolling up/down will jump by this amount."
  :type 'integer
  :group 'siapip)
(defun up-slightly () (interactive) (scroll-up siapip/scroll-amount))
(defun down-slightly () (interactive) (scroll-down siapip/scroll-amount))
(global-set-key [mouse-4] 'down-slightly)
(global-set-key [mouse-5] 'up-slightly)

;;Term or GUI mode mouse changes
(unless (display-graphic-p)
  (require 'mouse)
  ;;http://stackoverflow.com/questions/3466643/emacs-unicode-xterm-mouse-escape-sequences-and-wide-terminals
  (xterm-mouse-mode t)
  (defun track-mouse (e))
  (setq mouse-sel-mode t))

(add-hook 'dired-mode-hook 'dired-hide-details-mode)
(put 'downcase-region 'disabled nil)
(put 'upcase-region 'disabled nil)

(use-package git-gutter
  :ensure t
  
  :config
  (global-git-gutter-mode t)
  (setq git-gutter:update-interval 0.2)
  
  :hook
  (prog-mode . git-gutter-mode)
)

;; this will ensure that there's a git gutter in dired
(use-package git-gutter-fringe
  :ensure t)
         
(global-set-key
 (kbd "C-c b")
 (lambda ()
   (interactive)
   (let ((url (thing-at-point 'url))
         (filename (thing-at-point 'filename)))
     (cond
      (url (browse-url url))
      (filename (find-file filename))
      (t (message "No URL or file found"))))))

(use-package origami
  :ensure t
  :after s
  :defer t
  :config
  (global-origami-mode t))

(use-package envrc
  :ensure t
  :hook (after-init . envrc-global-mode))

(add-hook 'compilation-filter-hook
          (lambda ()
            (ansi-color-apply-on-region compilation-filter-start (point))))

(defun sp-camelcase-separate-words ()
  "Treat CamelCaseSubWords as separate words in every programming
mode."
  (add-hook 'prog-mode-hook 'subword-mode))

;;;; Working with scripts
;; When saving a file that starts with `#!', make it executable."
(add-hook 'after-save-hook
            'executable-make-buffer-file-executable-if-script-p)

;;;; Linting code well enough
;; If you save a file that doesn't end with a newline, automatically append one.
(setq require-final-newline t)

;;; Provide:

(provide 'sp-prog-misc)
;; sp-prog-misc.el ends here.