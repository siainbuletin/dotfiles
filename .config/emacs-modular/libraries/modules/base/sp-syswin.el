;;; sp-syswin.el --- Windows-specific settings -*- lexical-binding: t; -*-

;;; Commentary:

;; This is the specialized module for dealing with launching Emacs on Windows. Because of issues
;; with the way that Windows accesses the native binaries for Emacs, it might be a better idea to
;; run Emacs within WSL.

;; Lambda-Emacs is developed on macOS and Linux; Windows works but needs a little more care. Put
;; git (and ideally ripgrep) on your Windows PATH, expect the first-run compilation to take
;; noticeably longer, and prefer a recent official Emacs build with native compilation. Restarting
;; Emacs to resume installation usually clears transient build failures.
;; https://codeberg.org/Lambda-Emacs/lambda-emacs#headline-10

;; It also reads the Windows light or dark appearance for `sp-theme-auto-mode'.

;;; Code:

(require 'subr-x)

(when (memq system-type '(windows-nt cygwin ms-dos))
  (setq w32-pipe-read-delay 0                 ; Faster IPC
        w32-get-true-file-attributes nil      ; Decrease file IO workload
        w32-pipe-buffer-size (* 128 1024)))   ; Read more at a time

;;;; Windows appearance
(defconst sp-syswin--personalize-key
  "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
  "The registry key that holds the app mode.")

(defun sp-syswin--parse-registry (output)
  "Return `light', `dark' or nil from the `reg query' OUTPUT."
  (when (string-match "AppsUseLightTheme[ \t]+REG_DWORD[ \t]+0x\\([0-9a-fA-F]+\\)" output)
    (if (zerop (string-to-number (match-string 1 output) 16)) 'dark 'light)))

(defun sp-syswin-appearance ()
  "Return the Windows app mode, `light' or `dark', or nil if unknown."
  (when (and (memq system-type '(windows-nt cygwin ms-dos))
             (executable-find "reg"))
    (with-temp-buffer
      (when (zerop (call-process "reg" nil (list (current-buffer) nil) nil
                                 "query" sp-syswin--personalize-key
                                 "/v" "AppsUseLightTheme"))
        (sp-syswin--parse-registry (buffer-string))))))

;; Follow the app mode on Windows.
(when (and (memq system-type '(windows-nt cygwin ms-dos))
           (fboundp 'sp-theme-auto-mode))
  (sp-theme-auto-mode 1))

(provide 'sp-syswin)
;; sp-syswin.el ends here
