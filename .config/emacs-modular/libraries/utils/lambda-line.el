;; -*- lexical-binding: t; -*-

(use-package lambda-line
    :ensure (:type git :repo "https://codeberg.org/Lambda-Emacs/lambda-line")

    :custom
    (lambda-line-icon-time t) ;; requires ClockFace font (see below)
    (lambda-line-clockface-update-fontset "ClockFaceRect") ;; set clock icon
    (lambda-line-position 'top) ;; Set position of status-line 
    (lambda-line-abbrev t) ;; abbreviate major modes
    (lambda-line-hspace "  ")  ;; add some cushion
    (lambda-line-prefix t) ;; use a prefix symbol
    (lambda-line-prefix-padding nil) ;; no extra space for prefix 
    (lambda-line-status-invert nil)  ;; no invert colors
    (lambda-line-gui-ro-symbol  " ⨂") ;; symbols
    (lambda-line-gui-mod-symbol " ⬤") 
    (lambda-line-gui-rw-symbol  " ◯") 
    (lambda-line-space-top +.50)  ;; padding on top and bottom of line
    (lambda-line-space-bottom -.50)
    (lambda-line-symbol-position 0.1) ;; adjust the vertical placement of symbol

    :config
    (lambda-line-mode)  ;; activate lambda-line 
    ;; set divider line in footer
    (when (eq lambda-line-position 'top)
      (setq-default mode-line-format (list "%_"))
      (setq mode-line-format (list "%_"))))