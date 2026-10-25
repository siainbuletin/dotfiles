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
