;;; sp-spelling.el --- Spell checking -*- lexical-binding: t; -*-

;;; Commentary:

;; This module configures spell checking with the built-in `ispell' and
;; `flyspell' libraries, preferring the external `aspell' program when it is
;; installed. Flyspell is deliberately not switched on automatically: a stalled
;; speller process once froze the Emacs daemon, so spell checking is used on
;; demand.

;;; Code:

;;;; Spelling
(use-package ispell
  :ensure nil
  :commands (ispell-word ispell-region ispell-buffer)
  :config
  ;; The program, `sp-ispell-program', is set in `sp-globals'.
  (when (executable-find sp-ispell-program)
    (setq ispell-program-name sp-ispell-program)
    ;; Please note ispell-extra-args contains ACTUAL parameters passed to aspell
    (setq ispell-extra-args '("--sug-mode=ultra" "--lang=en_US"))))

;; Configure flyspell only when a speller exists, but deliberately do
;; NOT auto-enable it via :hook.  flyspell drives ispell/aspell with a
;; synchronous read in the command loop, so a stalled aspell freezes the
;; whole Emacs (it froze the daemon and cost a journal entry once).  Use
;; it on demand: M-x flyspell-mode, flyspell-buffer, or ispell-buffer.
(use-package flyspell
  :ensure nil

  :if (or (executable-find "aspell")
            (executable-find "hunspell")
            (executable-find "ispell"))
  :config
  (setq flyspell-abbrev-p t
        flyspell-use-global-abbrev-table-p t
        flyspell-issue-message-flag nil
        flyspell-issue-welcome-flag nil))

;; completion of spellings
(use-package flyspell-correct
  :ensure t
  :after flyspell
  :bind (:map flyspell-mode-map
         ("C-;" . flyspell-correct-previous)
         ("C-:" . flyspell-correct-at-point))
  :custom
  (flyspell-correct-interface #'flyspell-correct-completing-read))

;; Spelling transient. Bound to <leader> b S and <leader> S h in
;; sp-setup-keybindings.el. The three navigation keys (<, >, f) stay
;; on press; the rest exit. See git history for the prior macro-based
;; dispatch implementation that this replaced.
(require 'transient)
(transient-define-prefix lem-spelling-transient ()
  "Spelling commands."
  ["Spelling"
   ["Errors"
    ("<" "Previous" flyspell-correct-previous :transient t)
    (">" "Next"     flyspell-correct-next     :transient t)
    ("f" "Check"    flyspell-buffer           :transient t)]
   ["Checker"
    ("c" "Correction" ispell)
    ("d" "Dictionary" ispell-change-dictionary)
    ("m" "Mode"       flyspell-mode)]
   [""
    ("q" "Quit" transient-quit-one)]])

;; Completion of misspelled words in buffer
(use-package consult-flyspell
  :ensure t
  :after flyspell
  :config
  (setq consult-flyspell-set-point-after-word t
        consult-flyspell-always-check-buffer nil
        ;; Apply flyspell-correct-at-point directly after selecting candidate
        ;; and jump back to consult-flyspell.
        consult-flyspell-select-function
        (lambda () (flyspell-correct-at-point) (consult-flyspell))))

;;;;; Spelling Goto Next Error
(defun lem-flyspell-ispell-goto-next-error ()
  "Custom function to spell check next highlighted word"
  (interactive)
  (flyspell-goto-next-error)
  (ispell-word))

;; Moved to `sp-globals': `sia-hunspell-dictionaries' (taken from EWS).

(provide 'sp-spelling)
;; sp-spelling.el ends here.
