;;; sp-posframe.el --- Centered minibuffer in a posframe -*- lexical-binding: t; -*-

;;; Commentary:

;; The minibuffer (the prompt and Vertico's candidates) is shown in a child frame in the
;; centre of the screen, with some padding. Nothing else: no prompt styling, no dimming
;; and no text size of its own.

;;; Code:

(use-package vertico-posframe
  :ensure t
  :after vertico

  :custom
  (vertico-posframe-poshandler #'posframe-poshandler-frame-center) ; centered both ways
  (vertico-posframe-border-width 4)  ; padding around the text
  (vertico-posframe-fallback-mode 'vertico-buffer-mode) ; terminals have no child frames

  :config
  (vertico-posframe-mode 1))

(defun sp-posframe--match-border ()
  "Give the posframe border the background colour of the posframe itself.
The border then reads as padding. It is run again on every theme change."
  (when (facep 'vertico-posframe-border)
    (let ((bg (or (face-background 'vertico-posframe nil t)
                  (face-background 'default nil t))))
      (when (stringp bg)
        (set-face-attribute 'vertico-posframe-border nil :background bg)))))

(with-eval-after-load 'vertico-posframe
  (sp-posframe--match-border))
(add-hook 'enable-theme-functions (lambda (_theme) (sp-posframe--match-border)))

(provide 'sp-posframe)
;; sp-posframe.el ends here.
