;; -*- lexical-binding: t; -*-

;; dired-x is necessary for making counsel-fd work

(use-package counsel
  :ensure (:wait t)
)

(use-package s
  :ensure (:wait t)
  )

(use-package consult
  :ensure (:wait t)
  )

(keymap-global-set "C-c s l" #'consult-line)
(keymap-global-set "C-c s r" #'consult-ripgrep)

(use-package deadgrep
  :ensure (:wait t)
  )

(use-package rg
  :ensure (:wait t)
  )