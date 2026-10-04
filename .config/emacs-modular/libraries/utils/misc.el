;; -*- lexical-binding: t; -*-
(use-package savehist
  :ensure nil
  :init
  (savehist-mode t)
  :config
  (setq savehist-file (expand-file-name "savehist" user-emacs-directory)))

(global-unset-key (kbd "C-z")) ; stop me from freezing emacs
;; Always group items in buffer menu
(setq mouse-buffer-menu-mode-mult 0)
;; Use ibuffer instead of temporary buffer popup
(global-set-key (kbd "C-x C-b") 'ibuffer)
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
(setq x-select-enable-clipboard t)
(setq mouse-yank-at-point t)
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

;;Diff adjustements
(setq ediff-window-setup-function 'ediff-setup-windows-plain
      ediff-split-window-function 'split-window-horizontally
      ediff-diff-options "-w")
;;/etc/etc-update.conf
;;diff_command="emacs-diff %file1 %file2"
;;using_editor=1
;;merge_command="emacs-merge %orig %new %merged"

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

;; Git diff fix
(setq vc-handled-backends ())

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
  (setq git-gutter:update-interval 0.2))

(use-package avy
  :ensure t
  :demand t
  :bind (("C-:" . avy-goto-char)
         ("C-M-:" . avy-goto-char-timer)))
         
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
