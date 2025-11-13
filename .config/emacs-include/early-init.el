;; Most of this configuration is taken from the Lambda Emacs repository.
;; This is published to GitHub solely for my own usage and for ease of
;; synchronisation between different machines.

;; This file has been generated from an org-mode file (=../org-modules/bootstrap.org=)
;; DO NOT EDIT DIRECTLY, IT WILL BE OVERWRITTEN

(setq package-enable-at-startup nil)

(defconst sys-linux   (eq system-type 'gnu/linux))
(defconst sys-mac     (eq system-type 'darwin))
(defconst sys-bsd     (or sys-mac (eq system-type 'berkeley-unix)))
(defconst sys-win     (memq system-type '(cygwin windows-nt ms-dos)))

(setq frame-resize-pixelwise t
    frame-inhibit-implied-resize 'force)

;; Fundamental mode at startup.
;; This helps with load-time since no extra libraries are loaded.
(setopt initial-major-mode 'fundamental-mode)
