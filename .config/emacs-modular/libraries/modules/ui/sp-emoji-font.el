;; -*- lexical-binding: t; -*-
;; sp-emoji-font.el --- Colour emoji on macOS and Linux

;;; Commentary:

;; Picks the first installed colour emoji family from
;; `sp-emoji-font-families' and prepends it to the `emoji' script of the
;; default fontset.  On Linux an Apple Color Emoji .ttf given in
;; `sp-emoji-font-file' is installed into the user's font directory.
;; Load it after sp-fonts.

;;; Code:

(require 'url-handlers)

;;;; Settings
(defgroup sp-emoji-font nil
  "Colour emoji font selection."
  :group 'faces
  :prefix "sp-emoji-font-")

(defcustom sp-emoji-font-families
  '("Apple Color Emoji" "Noto Color Emoji" "Segoe UI Emoji" "Twemoji Mozilla")
  "Emoji font families, best first.  The first installed one is used."
  :type '(repeat string))

(defcustom sp-emoji-font-file nil
  "Apple Color Emoji font file (.ttf) to install on Linux, or nil.
It is only installed when the \"Apple Color Emoji\" family is not
available yet.  See `sp-emoji-font-install'."
  :type '(choice (const :tag "None" nil) file))

(defcustom sp-emoji-font-install-dir
  (expand-file-name "fonts/sp-emoji/"
                    (or (getenv "XDG_DATA_HOME") "~/.local/share"))
  "Directory the emoji font is installed into on Linux."
  :type 'directory)

;;;; Selecting the font
(defvar sp-emoji-font--applied nil
  "The family last prepended to the emoji fontset, or nil.")

(defun sp-emoji-font--available-p (family)
  "Non-nil when FAMILY is an installed font family."
  (and (member family (font-family-list)) t))

(defun sp-emoji-font--pick ()
  "The first installed family of `sp-emoji-font-families', or nil."
  (seq-find #'sp-emoji-font--available-p sp-emoji-font-families))

(defun sp-emoji-font-apply (&optional frame)
  "Prepend the best installed emoji family to the default fontset.
Does nothing when FRAME (default: the selected frame) is not graphical.
Return the family used, or nil."
  (when (display-graphic-p frame)
    (when-let* ((family (sp-emoji-font--pick)))
      (if (>= emacs-major-version 28)
          (set-fontset-font t 'emoji (font-spec :family family) nil 'prepend)
        (set-fontset-font t '(#x1f000 . #x1faff)
                          (font-spec :family family) nil 'prepend))
      (setq sp-emoji-font--applied family))))

;;;; Installing a font
(defun sp-emoji-font-install (source)
  "Install the emoji font file or https URL SOURCE for the current user.
The file goes into `sp-emoji-font-install-dir', then fontconfig is
refreshed and the emoji font is applied again.  Linux only: macOS
already has Apple Color Emoji."
  (interactive
   (list (read-string "Emoji font file or URL: " sp-emoji-font-file)))
  (when (eq system-type 'darwin)
    (user-error "macOS has Apple Color Emoji built in"))
  (let* ((name (file-name-nondirectory
                (replace-regexp-in-string "[?#].*\\'" "" source)))
         (dest (expand-file-name name sp-emoji-font-install-dir)))
    (make-directory sp-emoji-font-install-dir t)
    (if (string-match-p "\\`https?://" source)
        (url-copy-file source dest t)
      (copy-file (expand-file-name source) dest t))
    (if (executable-find "fc-cache")
        (call-process "fc-cache" nil nil nil "-f" sp-emoji-font-install-dir)
      (message "fc-cache not found: restart Emacs after refreshing fontconfig"))
    (clear-font-cache)
    (message "Installed %s; emoji font: %s" dest (sp-emoji-font-apply))
    dest))

;;;; Start-up
(defun sp-emoji-font--setup (&optional frame)
  "Install `sp-emoji-font-file' if needed, then apply the font to FRAME."
  (when (display-graphic-p frame)
    (when (and (eq system-type 'gnu/linux)
               sp-emoji-font-file
               (file-exists-p sp-emoji-font-file)
               (not (sp-emoji-font--available-p "Apple Color Emoji")))
      (condition-case err
          (sp-emoji-font-install sp-emoji-font-file)
        (error (message "sp-emoji-font: install failed: %s"
                        (error-message-string err)))))
    (sp-emoji-font-apply frame)))

(sp-emoji-font--setup)
(add-hook 'after-make-frame-functions #'sp-emoji-font--setup)

;;; Provide:

(provide 'sp-emoji-font)
;; sp-emoji-font.el ends here.
