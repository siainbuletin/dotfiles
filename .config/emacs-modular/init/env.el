;; -*- lexical-binding: t; -*-

(use-package exec-path-from-shell
  :ensure (:wait t))

(when (memq window-system '(mac ns x pgtk)) (exec-path-from-shell-initialize))

(when (daemonp)
  (exec-path-from-shell-initialize))