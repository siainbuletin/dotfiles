;; -*- lexical-binding: t; -*-
;; sp-win.el

;;; Commentary:

;; This is the specialized module for dealing with launching Emacs on Windows. Because of issues
;; with the way that Windows accesses the native binaries for Emacs, it might be a better idea to
;; run Emacs within WSL.

;; Lambda-Emacs is developed on macOS and Linux; Windows works but needs a little more care. Put 
;; git (and ideally ripgrep) on your Windows PATH, expect the first-run compilation to take 
;; noticeably longer, and prefer a recent official Emacs build with native compilation. Restarting 
;; Emacs to resume installation usually clears transient build failures.
;; https://codeberg.org/Lambda-Emacs/lambda-emacs#headline-10

;;; Code:

(when (memq system-type '(windows-nt cygwin ms-dos))
  (setq w32-pipe-read-delay 0                 ; Faster IPC
        w32-get-true-file-attributes nil      ; Decrease file IO workload
        w32-pipe-buffer-size (* 128 1024)))   ; Read more at a time

(provide 'sp-win)