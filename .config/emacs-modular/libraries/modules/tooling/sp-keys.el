;; -*- lexical-binding: t; -*-

(use-package hydra
  :ensure (:wait t))

(use-package use-package-hydra
  :ensure (:wait t))

(use-package which-key
    :ensure t
    :demand t

    :config
    (which-key-mode 1)

    :custom
    (which-key-max-description-length 40)
    (which-key-lighter nil)
    (setq which-key-idle-delay 0.3)
    (which-key-sort-order 'which-key-order-alpha)
    (which-key-mode +1)
    :init
    (which-key-add-key-based-replacements
"C-c w"   "Emacs Writing Studio"
    "C-c w b" "Bibliographic"
    "C-c w d" "Denote"
    "C-c w m" "Multimedia"
    "C-c w s" "Spelling and Grammar"
    "C-c w t" "Themes"
    "C-c w x" "Explore"))

(use-package helm-descbinds
  :ensure (:type git :host github :repo "emacs-helm/helm-descbinds"))

(global-unset-key (kbd "C-z"))

(keymap-global-set "C->" #'indent-rigidly-right-to-tab-stop) ; Indent selection by one tab length
(keymap-global-set "C-<" #'indent-rigidly-left-to-tab-stop)  ; De-indent selection by one tab length

(keymap-global-set "C-x t b" 'transpose-buffers)

;; Main keybindings
(keymap-global-set "C-c s l" 'easysession-switch-to)  ; Load
(keymap-global-set "C-c s s" 'easysession-save-as)  ; Save

;; Other keybindings
(keymap-global-set "C-c s L" 'easysession-switch-to-and-restore-geometry)
(keymap-global-set "C-c s d" 'easysession-delete)
(keymap-global-set "C-c s r" 'easysession-rename)
(keymap-global-set "C-c s R" 'easysession-reset)

(keymap-global-set "C-c e b b" 'eval-buffer)

(keymap-global-set "C-M-<up>") (lambda () (interactive)
                                   (set-face-attribute 'default nil :height (+ (face-attribute 'default :height) 5))))
(keymap-global-set "C-M-<down>") (lambda () (interactive)
                                     (set-face-attribute 'default nil :height (- (face-attribute 'default :height) 5))))
(keymap-global-set "C-+" 'text-scale-increase)
(keymap-global-set "C--" 'text-scale-decrease)
(keymap-global-set "C-M-S-u" 'rename-uniquely)
(keymap-global-set "C-M-z C-e" 'eval-region)
(keymap-global-set "C-M-z C-M-e" 'eval-buffer)
(keymap-global-set "C-M-S-c" 'find-emacs-config)
(keymap-global-set "C-M-S-z" 'cmake-ide-compile)
(defun find-emacs-config ()
  "Open the emacs configuration file"
  (interactive)
  (find-file "~/.emacs.d/siapip/siapip-emacs.el"))