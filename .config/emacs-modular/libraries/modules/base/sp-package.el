;; -*- lexical-binding: t; -*-


;; Settings from Lambda Emacs for use-package
;; Use-Package Settings
(use-package use-package
  :custom
  (use-package-always-defer nil)        ;; Don't automatically defer
  (use-package-verbose t)               ;; Report loading details
  (use-package-minimum-reported-time 0) ;; This is really helpful for profiling
  (use-package-expand-minimally nil)    ;; Expand normally
  
  ;; Unconditional: lambda-emacs handles installation via
  ;; `sp-install-extras' driven by `sp-packages-alist', not via
  ;; use-package's :ensure machinery. Setting this to nil lets
  ;; modules omit :ensure entirely without accidentally triggering
  ;; an install on any form that says nothing about :ensure.
  ;; (use-package-always-ensure nil)
  ;; I don't know what to do with this setting

  ;; Navigate use-package declarations w/imenu
  (use-package-enable-imenu-support t))
  