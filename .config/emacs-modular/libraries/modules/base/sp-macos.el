;;; sp-macos.el --- macOS integration -*- lexical-binding: t; -*-

;;; Commentary:

;; MacOS is my main operating system (my most capable and portable computer),
;; for this reason, it's important to have it be integrated with the rest of
;; the system, including running DEVONthink well enough (although DT support
;; is configured elsewhere in this config).

;;; Code:

;; This is so that I can actually use the CMD key as my Meta key.
(setq mac-command-modifier 'meta)
(setq mac-option-modifier 'none)
(setq ns-right-command-modifier 'super)

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

;;;; macOS system appearance
(defun sp-macos-appearance ()
  "Return the macOS appearance, `light' or `dark', or nil if unknown."
  (cond
   ((and (boundp 'ns-system-appearance) ns-system-appearance)
    ns-system-appearance)
   ((executable-find "defaults")
    (with-temp-buffer
      (let ((exit (call-process "defaults" nil t nil
                                "read" "-g" "AppleInterfaceStyle")))
        (if (and (zerop exit) (string-match-p "Dark" (buffer-string)))
            'dark
          'light))))))

(defun sp-macos-watch-appearance (callback)
  "Call CALLBACK with `light' or `dark' when macOS flips.
Return the function that stops watching."
  (when (boundp 'ns-system-appearance-change-functions)
    (add-hook 'ns-system-appearance-change-functions callback)
    (lambda ()
      (remove-hook 'ns-system-appearance-change-functions callback))))

;;;; macOS ambient light
(defcustom sp-macos-light-sensor-command nil
  "Shell command that prints the light level of the room in lux, or nil."
  :group 'spcustom
  :type '(choice (const :tag "No sensor" nil) string))

(defcustom sp-macos-ambient-levels
  '((hard-light . 150)
    (faded-light  . 60)
    (faded-dark  . 15)
    (hard-dark   . 0))
  "The families by light level, an alist of (FAMILY . LUX), brightest first.
A family applies from LUX up to the LUX of the family before it."
  :group 'spcustom
  :type '(alist :key-type symbol :value-type number))

(defcustom sp-macos-ambient-margin 0.25
  "Fraction by which the light must pass a boundary to leave a family."
  :group 'spcustom
  :type 'number)

(defvar sp-macos--ambient-family nil
  "The family `sp-macos-ambient-family' answered last.")

(defun sp-macos-ambient-lux ()
  "Return the light level in lux from `sp-macos-light-sensor-command', or nil."
  (when (and sp-macos-light-sensor-command
             (not (string-empty-p sp-macos-light-sensor-command)))
    (let ((out (string-trim (shell-command-to-string sp-macos-light-sensor-command))))
      (when (string-match-p "\\`[0-9]+\\(?:\\.[0-9]*\\)?\\'" out)
        (string-to-number out)))))

(defun sp-macos--level-for (lux)
  "Return the family for LUX, holding on to the current one near a boundary."
  (let* ((levels sp-macos-ambient-levels)
         (fresh (car (seq-find (lambda (l) (>= lux (cdr l))) levels)))
         (pos (seq-position levels sp-macos--ambient-family
                            (lambda (l family) (eq (car l) family)))))
    (if (null pos)
        fresh
      (let* ((upper (and (> pos 0) (cdr (nth (1- pos) levels))))
             (lower (cdr (nth pos levels)))
             (m sp-macos-ambient-margin))
        (if (and (>= lux (* lower (- 1 m)))
                 (or (null upper) (< lux (* upper (+ 1 m)))))
            sp-macos--ambient-family
          fresh)))))

(defun sp-macos-ambient-family ()
  "Return the family for the light of the room, or nil without a reading."
  (let ((lux (sp-macos-ambient-lux)))
    (when lux
      (setq sp-macos--ambient-family (sp-macos--level-for lux)))))

;;;; macOS system-appearance dispatch
(when (bound-and-true-p sys-mac)
  (sp-theme-auto-mode 1))

;; taken from Lambda emacs
;;;; Org Mac Link
(use-package org-mac-link
    :ensure t
    :after org
    :hook (org-mode . (lambda ()
                        (define-key org-mode-map (kbd "C-c g")
                          'org-mac-link-get-link))))

(provide 'sp-macos)
;; sp-macos.el ends here.
