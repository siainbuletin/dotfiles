(use-package mini-frame)

;; Is this the command that you want to use if you're on a tiling window manager like Hyprland?
;; (setq mini-frame-detach-on-hide nil)
(setq mini-frame-standalone 't)
(setq mini-frame-resize-min-height 10)
;; (setq mini-frame-ignore-commands
;;      (append mini-frame-ignore-commands '(evil-window-split evil-window-vsplit evil-ex))
;;      )

;; Custom position for the mini frame

;; Making the miniframe scale better in the middle of the page
;; this has to use resize-mini-frames
