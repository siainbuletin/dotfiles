;; -*- lexical-binding: t; -*-
;; sp-multimedia.el --- dedicated specifically to music playback from Emacs --- as far as it can go in the multi-threaded direction

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

(provide 'sp-multimedia)
;; sp-multimedia.el ends here.