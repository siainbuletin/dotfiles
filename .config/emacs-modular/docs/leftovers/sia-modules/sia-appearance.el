;; This is supposed to improve org-mode visually
      (require 'nano-writer)
      (add-to-list 'major-mode-remap-alist '(org-mode . writer-mode))

      ;; Define different themes for light and dark mode
      ;; (require 'nano-theme-light)
      ;; (require 'nano-theme-dark)
