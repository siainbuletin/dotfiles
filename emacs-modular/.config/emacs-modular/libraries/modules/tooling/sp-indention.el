;;; sp-indention.el --- Tabs, indentation width and indent keys -*- lexical-binding: t; -*-

;;; Commentary:

;; This module sets global indentation defaults: spaces instead of tab
;; characters, a width of 4, and keys for inserting a literal tab and shifting
;; a region by one tab stop. It also registers autoloads for `guess-style', a
;; library that guesses a file's indentation style.

;;; Code:

;; What is this tabbing behavior really for?
(global-set-key (kbd "<backtab>") 'insert-tab-char)
(global-set-key (kbd "<C-tab>") 'company-complete)
(defun insert-tab-char ()
  "insert a tab char. (ASCII 9, \t)"
  (interactive)
  (insert "\t"))

;; Tab width
(setq-default indent-tabs-mode nil)
(setq tab-width 4)
(setq default-tab-width 4)
(defvaralias 'c-basic-offset 'tab-width)
(defvaralias 'cperl-indent-level 'tab-width)

;; Keymap for indentation
(keymap-global-set "C->" #'indent-rigidly-right-to-tab-stop) ; Indent selection by one tab length
(keymap-global-set "C-<" #'indent-rigidly-left-to-tab-stop)  ; De-indent selection by one tab length

;; Auto indentation
(add-to-list 'load-path
             (expand-file-name "guess-style"
                               (file-name-directory (or load-file-name buffer-file-name default-directory))))
(autoload 'guess-style-set-variable "guess-style" nil t)
(autoload 'guess-style-guess-variable "guess-style")
(autoload 'guess-style-guess-all "guess-style" nil t)

(provide 'sp-indention)
;; sp-indention.el ends here.
