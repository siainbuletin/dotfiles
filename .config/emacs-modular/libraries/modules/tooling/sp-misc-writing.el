;; -*- lexical-binding: t; -*-

;;;; Dictionaries
;; this is useful for looking up more information

(use-package define-word
  :when (and lem-load-extras (locate-library "define-word"))
  :commands (define-word define-word-at-point))

(use-package osx-dictionary
  :when (and lem-load-extras (locate-library "osx-dictionary"))
  :commands (osx-dictionary-search-word-at-point osx-dictionary-search-input))

(use-package lexic
  :ensure t)

(provide 'sp-misc-writing)

;; Abbreviation

(use-package abbrev
  :ensure nil
  :defer 2
  :config
  ;; (add-hook 'text-mode-hook #'abbrev-mode)
  (setq abbrev-file-name (concat lem-var-dir "abbrev/.abbrev_defs")
        save-abbrevs 'nil)
  (if (file-exists-p abbrev-file-name)
      (quietly-read-abbrev-file)))

;;;; Capitalization
;; From https://karthinks.com/software/batteries-included-with-emacs/
(keymap-global-set "M-u" 'upcase-dwim)
(keymap-global-set "M-l" 'downcase-dwim)
(keymap-global-set "M-c" 'capitalize-dwim)

(provide 'sp-misc-writing)