;; -*- lexical-binding: t -*-
;; sp-goto.el 

;;; Commentary:

;; This package allows you to click or hit a key sequence while on a
;; URL or e-mail address, and either load the URL into a browser of
;; your choice using the browse-url package, or if it's an e-mail
;; address, to send an e-mail to that address.

;;; Code:

(use-package goto-addr
  :ensure nil
  :hook ((compilation-mode . goto-address-mode)
         (prog-mode . goto-address-prog-mode)
         (eshell-mode . goto-address-mode)
         (text-mode . goto-address-mode)
         (shell-mode . goto-address-mode))
  :bind (:map goto-address-highlight-keymap
         ("<RET>"  . goto-address-at-point)
         ("M-<RET>" . newline))
  :commands (goto-address-prog-mode
             goto-address-mode))

;;;; Goto Functions
(defun sp-goto-private ()
  (interactive)
  (find-file (concat sp-user-dir "private.el")))

(defun sp-goto-journal ()
  (interactive)
  (find-file (concat org-directory "journal.org")))

(defun sp-goto-early-init.el ()
  "Open early-init.el file"
  (interactive)
  (find-file (expand-file-name "early-init.el" user-emacs-directory)))

(defun sp-goto-init.el ()
  "Open init.el file"
  (interactive)
  (find-file user-init-file))

(defun sp-goto-custom.el ()
  "Open custom.el file"
  (interactive)
  (find-file custom-file))

(defun sp-goto-emacs-dir ()
  "Open 𝛌-Emacs directory"
  (interactive)
  (find-file user-emacs-directory))
(defun sp-goto-projects ()
  "Open projects dir"
  (interactive)
  (find-file sp-project-dir))
(defun sp-goto-elisp-library ()
  "Open user elisp library."
  (interactive)
  (find-file sp-user-elisp-dir))

;;;; Go To Change
;; Easily go to last change
(use-package goto-last-change
  :when (and sp-load-extras (locate-library "goto-last-change"))
  :bind (("C-\"" . #'goto-last-change)))

;;; Provide:

(provide 'sp-goto)
;; sp-goto.el ends here.