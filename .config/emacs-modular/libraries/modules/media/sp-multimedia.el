;;; sp-multimedia.el --- Music and media playback -*- lexical-binding: t; -*-

;;; Commentary:

;; This module installs several media packages: `emms', `vuiet', `lastfm',
;; `ready-player' and `listen'. Only `ready-player' gets real configuration.

;;; Code:

(use-package emms
  :ensure t)

(use-package vuiet
  :ensure t)

(use-package lastfm
  :ensure t)

(use-package ready-player
  :ensure t
  :init
  (ready-player-mode 1)
  :custom
  (ready-player-thumbnail-max-pixel-height 200)
  (ready-player-autoplay nil)
  (ready-player-repeat t)
  (ready-player-shuffle t)
  (ready-player-open-playback-commands
   '(
      ("mpv" "--audio-display=no")
      ("mplayer")
      ("ffplay")
      ("vlc")
     )))

(use-package listen
  :ensure t)

(use-package supersonic
  :ensure t
  :commands supersonic
  :bind (("C-c m" . supersonic))
  :custom
  (supersonic-host "http://192.168.88.10:4355") ;; see "Connecting to a Subsonic server"
  (supersonic-enable-scrobbling t))

(provide 'sp-multimedia)
;; sp-multimedia.el ends here.
