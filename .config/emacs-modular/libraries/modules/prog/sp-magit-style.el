;; -*- lexical-binding: t; -*-
;; sp-magit-style.el

;;; Commentary:

;; Visual polish for Magit buffers: larger section headings with an
;; overline, chevron indicators for folded/expanded sections, and
;; nerd-icons next to files and directories.  Depends only on `magit'
;; and (optionally) `nerd-icons'; without icons it still styles headings.

;;; Code:

(defgroup sp-magit-style nil
  "Prettier Magit buffers."
  :group 'magit)

(defcustom sp-magit-style-icons t
  "Show nerd-icons next to files and directories in Magit buffers."
  :type 'boolean)

(defcustom sp-magit-style-heading-height 1.15
  "Relative height of Magit section headings."
  :type 'number)

(defun sp-magit-style--icon (kind file)
  "Return an icon string for FILE (a path) in a Magit buffer of KIND, or nil."
  (when (and sp-magit-style-icons (fboundp 'nerd-icons-icon-for-file))
    (let ((dirp (string-suffix-p "/" file)))
      (ignore-errors
        (if dirp
            (nerd-icons-icon-for-dir file)
          (nerd-icons-icon-for-file (file-name-nondirectory file)))))))

(defun sp-magit-style-format-file (kind file face &optional status orig)
  "Format FILE like `magit-format-file-default', prefixed by an icon.
KIND, FACE, STATUS and ORIG are as for `magit-format-file-function'."
  (let ((text (magit-format-file-default kind file face status orig))
        (icon (sp-magit-style--icon kind file)))
    (if icon (concat icon " " text) text)))

(defun sp-magit-style--set-faces ()
  "Enlarge and underline Magit section headings."
  (dolist (face '(magit-section-heading magit-diff-file-heading))
    (when (facep face)
      (set-face-attribute face nil
                          :height (if (eq face 'magit-section-heading)
                                      sp-magit-style-heading-height
                                    1.05)
                          :weight 'bold)))
  (when (facep 'magit-section-heading)
    (set-face-attribute 'magit-section-heading nil
                        :overline t :extend t))
  (when (facep 'magit-branch-local)
    (set-face-attribute 'magit-branch-local nil :box nil)))

(with-eval-after-load 'magit-section
  ;; Chevrons instead of the default fringe bitmaps (also work in a TTY).
  (setq magit-section-visibility-indicators
        (list (cons (string #xf054) (string #xf078))))
  (sp-magit-style--set-faces)
  ;; Re-apply after a theme change, which resets face attributes.
  (add-hook 'enable-theme-functions
            (lambda (&rest _) (sp-magit-style--set-faces))))

(with-eval-after-load 'magit
  (setq magit-format-file-function #'sp-magit-style-format-file))

(provide 'sp-magit-style)
;; sp-magit-style.el ends here
