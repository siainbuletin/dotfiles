;; -*- lexical-binding: t; -*-

(use-package which-key
    :ensure t

    :config
    (which-key-mode)

    :custom
    (which-key-max-description-length 40)
    (which-key-lighter nil)
    (which-key-sort-order 'which-key-description-order)
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

(global-set-key (kbd "C-x t b") 'transpose-buffers)

;; Main keybindings
(global-set-key (kbd "C-c sl") 'easysession-switch-to)  ; Load
(global-set-key (kbd "C-c ss") 'easysession-save-as)  ; Save

;; Other keybindings
(global-set-key (kbd "C-c sL") 'easysession-switch-to-and-restore-geometry)
(global-set-key (kbd "C-c sd") 'easysession-delete)
(global-set-key (kbd "C-c sr") 'easysession-rename)
(global-set-key (kbd "C-c sR") 'easysession-reset)

(global-set-key (kbd "C-c e b b") 'eval-buffer)

(use-package hydra
  :ensure (:wait t))

(use-package use-package-hydra
  :ensure (:wait t))