;;; sp-colors.el --- summary -*- lexical-binding: t -*-

;; Setup how emacs handles colors

;;;; Color
(setq-default ns-use-srgb-colorspace t)

;;;; Show Colors
;; https://github.com/emacsmirror/rainbow-mode
;; Colorize color names in buffers
(use-package rainbow-mode
  :if (and sp-load-extras (locate-library "rainbow-mode"))
  ;; :commands rainbow-mode
  :config
  (progn (setq rainbow-x-colors nil)
         (add-hook 'prog-mode-hook 'rainbow-mode))
  )

(provide 'sp-colors)
;;; sp-colors.el ends here
