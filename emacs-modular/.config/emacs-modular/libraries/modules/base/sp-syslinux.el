;;; sp-syslinux.el --- Linux system integration -*- lexical-binding: t; -*-

;;; Commentary:

;; Settings for Emacs running on Linux: the desktop appearance that
;; `sp-theme-auto-mode' follows.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;;;; Desktop appearance
(defun sp-syslinux--parse-portal (output)
  "Return `light', `dark' or nil from the gdbus OUTPUT of the portal."
  (when (string-match "uint32 \\([0-9]+\\)" output)
    (pcase (match-string 1 output)
      ("1" 'dark)
      ("2" 'light))))

(defun sp-syslinux--parse-gsettings (output)
  "Return `light', `dark' or nil from the gsettings color-scheme OUTPUT."
  (cond ((string-match-p "prefer-dark" output) 'dark)
        ((string-match-p "prefer-light\\|default" output) 'light)))

(defun sp-syslinux--parse-kde (output)
  "Return `light', `dark' or nil from the name of a KDE colour scheme."
  (let ((name (string-trim output)))
    (unless (string-empty-p name)
      (if (string-match-p "dark" (downcase name)) 'dark 'light))))

(defun sp-syslinux--run (program &rest args)
  "Return the output of PROGRAM with ARGS, or nil if it fails or is missing."
  (when (executable-find program)
    (with-temp-buffer
      (when (zerop (apply #'call-process program nil (list (current-buffer) nil) nil args))
        (buffer-string)))))

(defun sp-syslinux-appearance ()
  "Return the desktop appearance, `light' or `dark', or nil if unknown."
  (when (eq system-type 'gnu/linux)
    (or (let ((out (sp-syslinux--run
                    "gdbus" "call" "--session"
                    "--dest" "org.freedesktop.portal.Desktop"
                    "--object-path" "/org/freedesktop/portal/desktop"
                    "--method" "org.freedesktop.portal.Settings.Read"
                    "org.freedesktop.appearance" "color-scheme")))
          (and out (sp-syslinux--parse-portal out)))
        (let ((out (sp-syslinux--run "gsettings" "get" "org.gnome.desktop.interface"
                                     "color-scheme")))
          (and out (sp-syslinux--parse-gsettings out)))
        (cl-some (lambda (program)
                   (let ((out (sp-syslinux--run program "--group" "General"
                                                "--key" "ColorScheme")))
                     (and out (sp-syslinux--parse-kde out))))
                 '("kreadconfig6" "kreadconfig5")))))

(defun sp-syslinux--signal-appearance (value)
  "Return `light', `dark' or nil for VALUE, the portal's color-scheme."
  (pcase (if (consp value) (car value) value)
    (1 'dark)
    (2 'light)))

(defun sp-syslinux-watch-appearance (callback)
  "Call CALLBACK with `light' or `dark' when the desktop flips.
Return the function that stops watching, or nil without D-Bus."
  (when (and (eq system-type 'gnu/linux)
             (require 'dbus nil t)
             (fboundp 'dbus-register-signal)
             (getenv "DBUS_SESSION_BUS_ADDRESS"))
    (let ((object
           (ignore-errors
             (dbus-register-signal
              :session "org.freedesktop.portal.Desktop"
              "/org/freedesktop/portal/desktop"
              "org.freedesktop.portal.Settings" "SettingChanged"
              (lambda (namespace key value)
                (when (and (equal namespace "org.freedesktop.appearance")
                           (equal key "color-scheme"))
                  (let ((appearance (sp-syslinux--signal-appearance value)))
                    (when appearance
                      (funcall callback appearance)))))))))
      (when object
        (lambda () (dbus-unregister-object object))))))

;; Follow the desktop appearance on Linux.
(when (and (eq system-type 'gnu/linux) (fboundp 'sp-theme-auto-mode))
  (sp-theme-auto-mode 1))

(provide 'sp-syslinux)
;;; sp-syslinux.el ends here
