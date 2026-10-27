;; Loading NANO theme with better font file
      ;; (require 'nano-theme)
      ;; (setq nano-font-size 13) ;; font size has to be set BEFORE loading the NANO theme
      ;; (nano-toggle-theme)

;; Face settings
(set-face-attribute 'nano-face-strong nil
                    :foreground (face-foreground 'nano-face-default)
                    :weight 'bold)

;; By default, nano seems to disable a lot of bolding that is used,
;; so this function is supposed to fix it
(set-face-attribute 'bold nil :weight 'bold) ;; isn't this setting already redundant?
