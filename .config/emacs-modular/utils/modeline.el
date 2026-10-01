;; -*- lexical-binding: t; -*-

;(defcustom siapip/modeline 'doom-modeline
;  "The modeline to use.
;Options are 'doom-modeline or 'smart-mode-line."
;  :type '(choice
;          (const :tag "Doom modeline" doom-modeline)
;          (const :tag "Smart mode line" smart-mode-line))
;  :group 'siapip)
;(cond
; ((eq siapip/modeline 'doom-modeline)
;  (use-package doom-modeline
;    :ensure t
;    :init
;    (doom-modeline-mode t)))
; ((eq siapip/modeline 'smart-mode-line)
;  (use-package smart-mode-line
;    :ensure t
;    :config
;    (sml/setup))))

;; this would be cool to try out for different situations

(use-package doom-modeline
  :ensure (:wait t)
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
)