;; -*- lexical-binding: t -*-
;; -*-no-byte-compile: t; -*-

;; IMPORTANT: This will actually enable this configuration
(load "~/.config/emacs-modular/sia-emacs")

;; INFO: Your custom config can be either here or inside /path/to/siapip-emacs-config/custom.el

;; Essential configurations - essential.el

;; snippet management - snippet.el

;; Search packages - search.el

;; minibuffer - minibuffer-packs.el

;; packages

;; embark.el

;; counsel-recoll.el

;; essential-packs.el

;; consult-snapfile.el

;; keys.el

;; dired-conf.el

;; bookmarks.el

;; org-config.el

;; sia-dashboard.el

;; denote.el

;; dgraphs.el

;; org-node-mem.el

;; academic.el

;; reading.el

;; projects.el

;; latex.el

;; help.el

;; browsing.el

;; vc.el

;; icons.el

;; utils/modeline.el

;; rss.el

;; init/gui.el

;; fonts.el

;; taskman.el

;; themes.el

;; utils/minibuffer.el

;; windows.el

;; buffer-man.el

;; multimedia.el

;; terminal.el

;; macos.el

;; http.el

;; ai.el

;; vulpea-eco.el

;; ENVIRONMENT VARIABLES - see env.el

;; the rest of the functions can be found in the /functions/ folder

;; textui.el
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(bibtex-aux-opt-alist
   '(("keywords" "Keywords to describe the entry" "")
     ("file" "Relative or absolute path to attachments" "")) nil nil "Customized with use-package bibtex")
 '(custom-safe-themes
   '("acd363510d3e4b638db178783bde3d4492574c0f5c889f845251949f43567d16"
     "f2f42f0b7c53736840fc3ff5751235e3b87cc535b04ddaf3423e2926548bfbb4"
     default))
 '(sia/modeline 'lambda-line))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-default ((t (:background "#F0B609" :inherit default))))
 '(org-extra-emphasis ((t (:background "#F0B609" :height 1.0 :inherit default :weight bold :width normal))) t)
 '(org-extra-emphasis-01 ((t (:foreground "#003F66" :inherit org-extra-emphasis :underline t))))
 '(org-extra-emphasis-02 ((t (:foreground "#003F66" :inherit org-extra-emphasis :underline t)))))
