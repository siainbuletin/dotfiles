;;; sp-interaction.el --- Mouse and scrolling -*- lexical-binding: t; -*-

;;; Commentary:

;; This is set up for the lowest level of interaction
;; with the graphical interface in Emacs. For example,
;; the mouse support.

;;; Code:

;; Scrolling and mouse usage
;; taken from lambda emacs 2026.10.02

;; this is a built-in package
(use-package mwheel
  :ensure nil
  :config
  ;; Optimize mouse wheel scrolling for smooth-scrolling trackpad use.
  ;; Trackpads send a lot more scroll events than regular mouse wheels,
  ;; so the scroll amount and acceleration must be tuned to smooth it out.
  (setq
   ;; If the frame contains multiple windows, scroll the one under the cursor
   ;; instead of the one that currently has keyboard focus.
   mouse-wheel-follow-mouse 't
   ;; Completely disable mouse wheel acceleration to avoid speeding away.
   mouse-wheel-progressive-speed nil
   mwheel-coalesce-scroll-events t
   ;; The most important setting of all! Make each scroll-event move 1 line at a
   ;; time (instead of 5 at default). Simply hold down shift to move twice as
   ;; fast. Perfect for trackpads.
   mouse-wheel-scroll-amount '(1 ((shift) . 2))))

;; Don't use pixel-scroll by default -- it causes janky behavior on MacOS
(use-package pixel-scroll
  :ensure nil
  :disabled)

;;;; Mouse
;; Don't be afraid of the mouse!
;; For ideas see https://ruzkuku.com/texts/emacs-mouse.html
(use-package mouse
  :ensure nil
  :config
  ;; Focus follows mouse
  (setq mouse-autoselect-window t
        focus-follows-mouse t)
  (setq context-menu-functions
        '(context-menu-ffap
          occur-context-menu
          context-menu-region
          context-menu-undo
          context-menu-dictionary)))

;; This should include a link to the window management packages that I use in this case.
;; and exwm should be moved to the window management macro library.

(provide 'sp-interaction)
;; sp-interaction.el ends here.
