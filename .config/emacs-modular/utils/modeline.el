;; -*- lexical-binding: t; -*-
(defcustom siapip/modeline 'doom-modeline
  "The modeline to use.
Options are 'doom-modeline or 'smart-mode-line."
  :type '(choice
          (const :tag "Doom modeline" doom-modeline)
          (const :tag "Smart mode line" smart-mode-line))
  :group 'siapip)
(cond
 ((eq siapip/modeline 'doom-modeline)
  (use-package doom-modeline
    :ensure t
    :init
    (doom-modeline-mode t)))
 ((eq siapip/modeline 'smart-mode-line)
  (use-package smart-mode-line
    :ensure t
    :config
    (sml/setup))))
