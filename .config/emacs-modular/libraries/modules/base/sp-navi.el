;;; sp-navi.el --- Navigation: files, places and outlines -*- lexical-binding: t; -*-

;;; Commentary:

;; Contains the general configuration for navigation within Emacs. The relevant
;; submodules are recursed within the file

;;; Code:

;;;; Require sub-libraries for navigation (organised alphabetically)
(require 'sp-consult-snapfile)
(require 'sp-dired)
(require 'sp-goto)
(require 'sp-search)

;;;; Defining utility functions
(defun sp-open-from-home-dir ()
  "When opening a file, start searching at the user's home
directory."
  (setq default-directory "~/"))

(defun sp-auto-follow-symlinks ()
  "When opening a file, always follow symlinks."
  (setq vc-follow-symlinks t))

;;;; Imenu list outline
;; Make a useful outline buffer
;; Binding set to toggle "o"
(use-package imenu-list
  :ensure t
  :commands (imenu-list-smart-toggle imenu-list-minor-mode)

  :config
  (setq imenu-list-focus-after-activation t
        imenu-list-auto-resize t
        imenu-list-position 'right))

;;;; Save place
;; Everyone remember where we parked.
(use-package saveplace
  :ensure nil
  :hook (emacs-startup . save-place-mode)
  :config
  (setq save-place-file (concat sp-cache-dir "saved-places"))
  (setq save-place-forget-unreadable-files nil))

;;;; Recent files
;; List recent files
(use-package recentf
  :ensure nil
  :defer 2
  :custom
  (recentf-save-file (concat sp-cache-dir "recentf"))
  (recentf-max-saved-items 500)
  (recentf-max-menu-items 10)
  :config
  (recentf-mode 1))

;;;; Jump in Buffer
(defun lem-jump-in-buffer ()
  "Jump between headlines in buffer using consult"
  (interactive)
  (cond
   ((eq major-mode 'org-mode)
    (call-interactively 'consult-org-heading))
   (t
    (call-interactively 'consult-outline))))

;;;; Better find-file
(defvar sp-find-file-options '(("find -type f -printf \"$PWD/%p\\0\"" . :string)
                               ("fd --absolute-path --type f -0" . :string)
                               ("rg --follow --files --null" . :string)
                               ("find-name-dired" . :command))
  "Ways `sp-find-file' can list files, each with how to run it.
A `:string' method is a shell command printing NUL-separated files;
a `:command' method is an interactive command.")

(defun sp-find-file--read (method &optional regexp)
  "Complete on the files that the shell command METHOD lists in `default-directory'.
When REGEXP is non-nil, only offer files whose name matches it.
Return the chosen file as an absolute name, or nil if none is chosen."
  (let* ((metadata '((category . file)))
         (file-list (split-string (shell-command-to-string method) "\0" t))
         (file-list (if regexp
                        (seq-filter (lambda (f) (string-match-p regexp f)) file-list)
                      file-list))
         (file (completing-read (format "Find file in %s: " (abbreviate-file-name default-directory))
                                (lambda (str pred action)
                                  (if (eq action 'metadata)
                                      `(metadata . ,metadata)
                                    (complete-with-action action file-list str pred)))
                                nil t nil 'file-name-history)))
    (when (and file (not (string-empty-p file)))
      (expand-file-name file))))

(defun sp-find-file ()
  "Find file from current directory in many different ways."
  (interactive)
  (let* ((selection (completing-read "Select : " sp-find-file-options)))
    (pcase (alist-get selection sp-find-file-options nil nil #'string=)
      (:command
       (call-interactively (intern selection)))
      (:string
       (when-let* ((file (sp-find-file--read selection)))
         (find-file file))))))

(defun sp-find-file-pick (dir &optional regexp)
  "Return a file under DIR chosen with the same fuzzy search as `sp-find-file'.
Ask for the method among the shell ones, run it in DIR, and offer only
the files whose name matches REGEXP, if given.  Visit nothing; return
the absolute file name, or nil if none is chosen."
  (let* ((default-directory (file-name-as-directory (expand-file-name dir)))
         (methods (seq-filter (lambda (option) (eq (cdr option) :string))
                              sp-find-file-options))
         (selection (completing-read "Select : " methods)))
    (sp-find-file--read selection regexp)))

(global-unset-key (kbd "C-x C-f")) ; Rebinding the find-file command.
(keymap-global-set "C-x C-f" #'sp-find-file)

(provide 'sp-navi)
;; sp-navi.el ends here.
