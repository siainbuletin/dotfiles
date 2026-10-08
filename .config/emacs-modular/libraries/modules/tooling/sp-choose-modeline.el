;; -*- lexical-binding: t; -*-
;; sp-choose-modeline.el

;;; Commentary:

;; This package allows for choosing between different modelines to use and load in Emacs, 
;; which overall makes the experience a lot easier

;; The ~defcustom~ sia/modeline allows to declare what is the modeline style to use
;; It currently defaults to the doom-modeline
;; Included is also the lambda-emacs modeline

;;; Code:

(defcustom sia/modeline 'lambda-line
  "The modeline to use.
Options are 'doom-modeline or 'lambda-line."
  :type '(choice
          (const :tag "Doom modeline" doom-modeline)
          (const :tag "Lambda Emacs modeline" lambda-line))
  :group 'siapip)

(cond
 ((eq sia/modeline 'doom-modeline)
  (use-package doom-modeline
    :ensure t
     
    :init
    (setq doom-modeline-buffer-encoding nil ; irrelevant for me but shows UTF-8

    ;; identifying the modes we're in
    doom-modeline-major-mode-color-icon t
    doom-modeline-minor-modes nil ; keep identification to the current modes

    ;; this works on the buffer state
    doom-modeline-buffer-state-icon t
    doom-modeline-buffer-modification-icon t
    doom-modeline-file-name-style 'auto

    ;; size and rendering of the modeline
    doom-modeline-height 25
    doom-modeline-bar-width 8
    doom-modeline-window-width-limit 85

    ;; navigating the file
    doom-modeline-percent-position t ; is this for the percentage of the position within the file?
    doom-modeline-support-imenu t
    doom-modeline-percent-position nil

    ;; integrating with project management
    doom-modeline-project-detection 'auto

    ;; other
    doom-modeline-lsp-icon t ; this doesn't currently work as I'm not working with code projects
    doom-modeline-enable-word-count t)
    (doom-modeline-mode 1)
    ))
 
 ((eq sia/modeline 'lambda-line)
  (use-package lambda-line
    :ensure (:type git :repo "https://codeberg.org/Lambda-Emacs/lambda-line")

    :custom
    (lambda-line-icon-time t) ;; requires ClockFace font (see below)
    (lambda-line-clockface-update-fontset "ClockFaceRect") ;; set clock icon
    (lambda-line-position 'bottom) ;; Set position of status-line 
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

    (lambda-line-use-nerd-icon t)

    :config
    (lambda-line-mode)  ;; activate lambda-line 
    
    ;; set divider line in footer
    (when (eq lambda-line-position 'top)
      (setq-default mode-line-format (list "%_"))
      (setq mode-line-format (list "%_")))))
  )

;;; Provide:

(provide 'sp-choose-modeline)
;; sp-choose-modeline.el ends here