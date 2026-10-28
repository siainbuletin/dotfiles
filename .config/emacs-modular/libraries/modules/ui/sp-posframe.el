;;; sp-posframe.el --- Centered minibuffer in a posframe -*- lexical-binding: t; -*-

;;; Commentary:

;; The minibuffer (the prompt and Vertico's candidates) is shown in a child frame in the
;; centre of the screen, at a fixed share of the frame width, with some padding. Nothing
;; else: no prompt styling and no dimming.

;;; Code:

(defcustom sp-posframe-width-fraction 0.75
  "Fraction of the parent frame's width that the posframe always occupies."
  :type 'float
  :group 'minibuffer)

(defun sp-posframe-get-size (buffer)
  "Return the size of the posframe for BUFFER: a fixed share of the frame width.
Width and minimum width are both `sp-posframe-width-fraction' of the frame, so
the posframe does not follow the length of the prompt or the candidates. The
height is left to `vertico-posframe-get-size'."
  (let* ((width (round (* sp-posframe-width-fraction (frame-width))))
         (size (copy-sequence (vertico-posframe-get-size buffer))))
    (plist-put size :width width)
    (plist-put size :min-width width)
    (plist-put size :max-width width)
    size))

(defvar vertico-posframe-font)

(defun sp-posframe-update-font ()
  "Set `vertico-posframe-font' to the size of `sp-minibuffer-face'.
The face height is a multiple of the `default' height; the font is the
`default' family at that size in points.  Run once at load and again on every
fontaine preset, never per prompt."
  (let ((height (face-attribute 'sp-minibuffer-face :height nil t)))
    (when (floatp height)
      (setq vertico-posframe-font
            (font-spec :family (face-attribute 'default :family)
                       :size (/ (* height (face-attribute 'default :height)) 10.0))))))

(use-package vertico-posframe
  :ensure t
  :after vertico

  :custom
  (vertico-posframe-poshandler #'posframe-poshandler-frame-center) ; centered both ways
  (vertico-posframe-size-function #'sp-posframe-get-size) ; fixed width
  (vertico-posframe-border-width 4)  ; padding around the text
  (vertico-posframe-fallback-mode 'vertico-buffer-mode) ; terminals have no child frames

  :config
  (vertico-posframe-mode 1))

(sp-posframe-update-font)
(add-hook 'fontaine-set-preset-hook #'sp-posframe-update-font)

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
