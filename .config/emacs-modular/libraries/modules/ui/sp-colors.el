;;; sp-colors.el --- Colour space and rainbow-mode -*- lexical-binding: t; -*-

;;; Commentary:

;; Setup how emacs handles colors

;;; Code:

(setq-default ns-use-srgb-colorspace t)

;;;; Show Colors
;; https://github.com/emacsmirror/rainbow-mode
;; Colorize color names in buffers
(use-package rainbow-mode
  :if (locate-library "rainbow-mode")
  ;; :commands rainbow-mode
  :config
  (progn (setq rainbow-x-colors nil)
         (add-hook 'prog-mode-hook 'rainbow-mode))
  )

(provide 'sp-colors)
;;; sp-colors.el ends here
