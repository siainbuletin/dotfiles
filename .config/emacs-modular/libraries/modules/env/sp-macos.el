;; -*- lexical-binding: t; -*-
;; sp-macos.el --- settings specific to the MacOS environment.

;;; Commentary:

;; MacOS is my main operating system (my most capable and portable computer),
;; for this reason, it's important to have it be integrated with the rest of
;; the system, including running DEVONthink well enough (although DT support
;; is configured elsewhere in this config).

;;; Code:

;; This is so that I can actually use the CMD key as my Meta key.
(setq mac-command-modifier 'meta)
(setq mac-option-modifier 'none)

;; Open with a specific MacOS app

(defun dwim-shell-commands-macos-open-with ()
  "Convert all marked images to jpg(s)."
  (interactive)
  (let* ((apps (seq-sort
                #'string-lessp
                (seq-mapcat (lambda (paths)
                              (directory-files-recursively
                               paths "\\.app$" t (lambda (path)
                                                  (not (string-suffix-p ".app" path)))))
                            '("/Applications" "~/Applications" "/System/Applications"))))
         (selection (progn
                      (cl-assert apps nil "No apps found")
                      (completing-read "Open with: "
                                       (mapcar (lambda (path)
                                                 (propertize (file-name-base path) 'path path))
                                               apps)))))
    (dwim-shell-command-on-marked-files
     "Open with"
     (format "open -a '%s' '<<*>>'" (get-text-property 0 'path selection))
     :silent-success t
     :no-progress t
     :utils "open")))

;; kill macos processes right from emacs

(require 'dwim-shell-command)
(require 'map)
(require 'proced)
(require 'seq)

(defun dwim-shell-commands-kill-process ()
  "Select and kill process."
  (interactive)
  (let* ((pid-width 5)
         (comm-width 25)
         (user-width 10)
         (processes (proced-process-attributes))
         (candidates
          (mapcar (lambda (attributes)
                    (let* ((process (cdr attributes))
                           (pid (format (format "%%%ds" pid-width) (map-elt process 'pid)))
                           (user (format (format "%%-%ds" user-width)
                                         (truncate-string-to-width
                                          (map-elt process 'user) user-width nil nil t)))
                           (comm (format (format "%%-%ds" comm-width)
                                         (truncate-string-to-width
                                          (map-elt process 'comm) comm-width nil nil t)))
                           (args-width (- (window-width) (+ pid-width user-width comm-width 3)))
                           (args (map-elt process 'args)))
                      (cons (if args
                                (format "%s %s %s %s" pid user comm (truncate-string-to-width args args-width nil nil t))
                              (format "%s %s %s" pid user comm))
                            process)))
                  processes))
         (selection (map-elt candidates
                             (completing-read "kill process: "
                                              (seq-sort
                                               (lambda (p1 p2)
                                                 (string-lessp (nth 2 (split-string (string-trim (car p1))))
                                                               (nth 2 (split-string (string-trim (car p2))))))
                                               candidates) nil t)))
         (prompt-title (format "%s %s %s"
                               (map-elt selection 'pid)
                               (map-elt selection 'user)
                               (map-elt selection 'comm))))
    (when (y-or-n-p (format "Kill? %s" prompt-title))
      (dwim-shell-command-on-marked-files
       (format "Kill %s" prompt-title)
       (format "kill -9 %d" (map-elt selection 'pid))
       :utils "kill"
       :error-autofocus t
       :silent-success t))))

; Source - https://stackoverflow.com/a/4083987
; Posted by hatmatrix
; Retrieved 2026-03-29, License - CC BY-SA 2.5

(when (eq system-type 'darwin)
  (require 'ls-lisp)
  (setq ls-lisp-use-insert-directory-program nil))

;;;;; macOS system-appearance dispatch
;; Delegate Light/Dark choice to macOS. The system already does
;; sunrise/sunset when set to Auto, and reflects manual flips
;; instantly -- following it removes every source of drift between
;; Emacs and the rest of the desktop.
;;
;; `ns-system-appearance' (symbol `light' or `dark') is set when an NS
;; frame initializes; `ns-system-appearance-change-functions' fires
;; when the system flips. The change hook does NOT fire at startup --
;; the prior version of this code only registered the hook, which is
;; why initial theme often disagreed with macOS. We apply once at file
;; load to fix that, falling back to `defaults read' so a frameless
;; daemon (which has not bound `ns-system-appearance' yet) still picks
;; the right theme at boot.

(defun lem--system-apply-theme (appearance)
  "Load the lambda variant matching system APPEARANCE.
APPEARANCE is `light' or `dark' from
`ns-system-appearance-change-functions' or `ns-system-appearance'.
No-op when the target is already at the head of
`custom-enabled-themes'."
  (let ((target (pcase appearance
                  ('dark 'lambda-dark)
                  (_     'lambda-light))))
    (unless (eq target (car custom-enabled-themes))
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme target t))))

(defun lem--macos-current-appearance ()
  "Return current macOS system appearance as `light' or `dark'.
Prefers `ns-system-appearance' (set once an NS frame exists); falls
back to `defaults read -g AppleInterfaceStyle' for frameless daemons.
`defaults' returns \"Dark\" when dark mode is on and exits non-zero
when light, so any non-zero exit (or output not containing \"Dark\")
is treated as light."
  (cond
   ((and (boundp 'ns-system-appearance) ns-system-appearance)
    ns-system-appearance)
   ((and (bound-and-true-p sys-mac)
         (executable-find "defaults"))
    (with-temp-buffer
      (let ((exit (call-process "defaults" nil t nil
                                "read" "-g" "AppleInterfaceStyle")))
        (if (and (zerop exit)
                 (string-match-p "Dark" (buffer-string)))
            'dark
          'light))))
   (t 'light)))

(when (bound-and-true-p sys-mac)
  (when (boundp 'ns-system-appearance-change-functions)
    (add-hook 'ns-system-appearance-change-functions
              #'lem--system-apply-theme))
  (lem--system-apply-theme (lem--macos-current-appearance)))

;;;;; Daemon client-frame sync

;; A frameless launchd/NS daemon never binds `ns-system-appearance' and
;; never receives NS appearance-change events, so the hook above never
;; fires for it -- the daemon freezes on whatever appearance it read at
;; startup, which is usually stale by the time a client connects (and
;; leaves `emacsclient -t' frames on the wrong variant). Re-read the
;; system appearance whenever a client frame is created so every frame
;; matches the current macOS Light/Dark state. `lem--system-apply-theme'
;; no-ops when the target theme is already active, so this is cheap.

(defun lem--sync-theme-on-new-frame (&rest _)
  "Sync the lambda theme to the current macOS appearance.
For `server-after-make-frame-hook': daemon client frames pick up the
live system appearance instead of the daemon's stale startup value."
  (lem--system-apply-theme (lem--macos-current-appearance)))

(when (and (bound-and-true-p sys-mac) (daemonp))
  (add-hook 'server-after-make-frame-hook #'lem--sync-theme-on-new-frame))

;; taken from Lambda emacs
;;; Org Mac Link
(use-package org-mac-link
    :ensure t
    :after org
    :hook (org-mode . (lambda ()
                        (define-key org-mode-map (kbd "C-c g")
                          'org-mac-link-get-link))))

;;; Provide:

(provide 'sp-macos)
;; sp-macos.el ends here.
