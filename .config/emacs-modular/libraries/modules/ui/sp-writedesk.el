;;; sp-writedesk.el --- Writing desk: Olivetti and Writeroom -*- lexical-binding: t; -*-

;;; Commentary:

;; This sub-library is called 'writedesk' because it's supposed to set up the space specifically
;; for longform writing within org-mode.

;;; Code:

;; Olivetti makes sure that every org buffer is being wrapped properly.
(use-package olivetti
  :ensure t
  
  :custom
  (olivetti-minimum-body 100)
  (olivetti-body-width 0.8)
  
  :bind
  (("C-c w o" . sp-olivetti))
  
  :hook
  (org-mode . olivetti-mode))

;; Distraction-free writing
(defvar sp-olivetti-point nil
  "Stores the point position before enabling Olivetti mode.")

;;;###autoload
(defun sp-olivetti ()
  "Distraction-free writing environment enhancing Olivetti mode.

Stores the window configuration when enabling Olivetti mode.
Restores the previous configuration when existing Olivetti mode
and moves point to the last location."
  (interactive)
  (if olivetti-mode
      (progn
        (if (eq (length (window-list)) 1)
            (progn
              (jump-to-register 1)
              (goto-char sp-olivetti-point)))
        (olivetti-mode 0)
        (text-scale-set 0))
    (progn
      (setq sp-olivetti-point (point))
      (window-configuration-to-register 1)
      (delete-other-windows)
      (text-scale-set 1)
      (olivetti-mode t))))

;;; org-view-mode
(use-package org-view-mode
  :ensure t)

;;;; Writeroom
(use-package writeroom-mode
  :ensure t
  :commands (writeroom-mode)

  :config
  (setq writeroom-fullscreen-effect 'maximized)
  (setq writeroom-width 125)
  (setq writeroom-mode-line t)
  (setq writeroom-bottom-divider-width 0)

  ;; better scrolling while writing
  (add-hook 'writeroom-mode-hook #'lem-writing-mode-scroll-settings)
)

;;; Reading mode
;; Inspired by Nicolas Rougier's book-mode (https://github.com/rougier/book-mode,
;; GPL-3.0) and its article example: wide fixed margins and extra line spacing
;; with no fringes.  Only those ideas are used; the code is written for Org here.
(defgroup sp-reading nil
  "Reading mode for long prose buffers."
  :group 'convenience)

(defcustom sp-reading-left-margin 8
  "Left margin of the text, in characters (book-mode: 8)."
  :type 'integer
  :group 'sp-reading)

(defcustom sp-reading-right-margin 6
  "Right margin of the text, in characters (book-mode: 6)."
  :type 'integer
  :group 'sp-reading)

(defcustom sp-reading-line-spacing 1
  "Extra space between lines, as in `line-spacing' (book-mode: 1)."
  :type '(choice integer float)
  :group 'sp-reading)

(defcustom sp-reading-progress 'page
  "How the header line shows the place in the text.
`page' is a fake page count (see `sp-reading-words-per-page'), `percent'
the share of the text before point."
  :type '(choice (const page) (const percent))
  :group 'sp-reading)

(defcustom sp-reading-words-per-page 300
  "Words in one fake page, for the page count of `sp-reading-progress'."
  :type 'integer
  :group 'sp-reading)

(defcustom sp-reading-bar-width 16
  "Width in characters of the progress bar in the mode line."
  :type 'integer
  :group 'sp-reading)

(defcustom sp-reading-bars t
  "Non-nil shows the reading header line and mode line.
Nil leaves both lines as they are and only changes margins and spacing."
  :type 'boolean
  :group 'sp-reading)

(defface sp-reading-marker
  '((t :inverse-video t :weight bold))
  "Face of the state marker (RW, RO or **) at the left of the header line."
  :group 'sp-reading)

(defvar-local sp-reading--remaps nil
  "Face remapping cookies added by `sp-reading-mode'.")

(defvar-local sp-reading--count nil
  "Cache of the word count: (KEY . WORDS), KEY is the buffer state.")

(defvar-local sp-reading--title nil
  "Cache of the title: (TICK . TITLE).")

(defvar-local sp-reading--saved nil
  "Alist of the buffer settings changed by `sp-reading-mode'.")

(defun sp-reading--apply-window (window)
  "Set the margins and fringes of WINDOW for `sp-reading-mode'."
  (set-window-margins window sp-reading-left-margin sp-reading-right-margin)
  (set-window-fringes window 0 0))

(defun sp-reading--refresh ()
  "Apply the margins to every window that shows the current buffer."
  (when sp-reading-mode
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (sp-reading--apply-window window))))

;; Header line and mode line
(defun sp-reading--total-words ()
  "Number of words in the accessible part of the buffer, cached."
  (let ((key (list (buffer-chars-modified-tick) (point-min) (point-max))))
    (unless (equal (car sp-reading--count) key)
      (setq sp-reading--count (cons key (count-words (point-min) (point-max)))))
    (cdr sp-reading--count)))

(defun sp-reading--fraction ()
  "Share of the accessible text that lies before point, from 0.0 to 1.0."
  (let ((span (- (point-max) (point-min))))
    (if (zerop span)
        0.0
      (/ (float (- (point) (point-min))) span))))

(defun sp-reading--progress-string ()
  "The place in the text as a fake page count or a percentage."
  (if (eq sp-reading-progress 'page)
      (let ((pages (max 1 (ceiling (sp-reading--total-words)
                                   sp-reading-words-per-page))))
        (format "page %d/%d"
                (max 1 (ceiling (* (sp-reading--fraction) pages)))
                pages))
    (format "%d%%" (round (* 100 (sp-reading--fraction))))))

(defun sp-reading--title ()
  "The #+title of the buffer, or its name when it has none."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (eq (car sp-reading--title) tick)
      (setq sp-reading--title
            (cons tick
                  (save-excursion
                    (save-restriction
                      (widen)
                      (goto-char (point-min))
                      (when (re-search-forward
                             "^#\\+title:[ \t]*\\(.*?\\)[ \t]*$" nil t)
                        (match-string-no-properties 1)))))))
    (or (cdr sp-reading--title) (buffer-name))))

(defun sp-reading--header ()
  "Header line: state marker and title at the left, words and place at the right."
  (let* ((marker (cond (buffer-read-only " RO ")
                       ((buffer-modified-p) " ** ")
                       (t " RW ")))
         (words (if (use-region-p)
                    (format "%d of %d words"
                            (count-words (region-beginning) (region-end))
                            (sp-reading--total-words))
                  (format "%d words" (sp-reading--total-words))))
         (right (format "%s  ·  %s " words (sp-reading--progress-string))))
    (concat (propertize marker 'face 'sp-reading-marker)
            "  " (sp-reading--title)
            (propertize " " 'display
                        `(space :align-to (- right ,(string-width right))))
            right)))

(defun sp-reading--footer ()
  "Mode line: a progress bar at the left, line and column at the right."
  (let* ((filled (round (* (sp-reading--fraction) sp-reading-bar-width)))
         (bar (concat (make-string filled ?━)
                      (make-string (- sp-reading-bar-width filled) ?─)))
         (right (format-mode-line "%l:%c ")))
    (concat " " bar
            (propertize " " 'display
                        `(space :align-to (- right ,(string-width right))))
            right)))

(defun sp-reading--remap-faces ()
  "Make the header line and mode line plain, in the colours of the text."
  (let ((fg (face-foreground 'default nil t))
        (bg (face-background 'default nil t))
        (height (face-attribute 'default :height nil t)))
    (push (face-remap-add-relative 'header-line :foreground fg :background bg
                                   :underline fg :box nil)
          sp-reading--remaps)
    (dolist (face '(mode-line mode-line-inactive))
      (push (face-remap-add-relative face :foreground fg :background bg
                                     :overline fg :box nil :height height)
            sp-reading--remaps))))

(defun sp-reading--save (var)
  "Remember the local state of VAR so that it can be restored."
  (push (list var (local-variable-p var) (and (boundp var) (symbol-value var)))
        sp-reading--saved))

;;;###autoload
(define-minor-mode sp-reading-mode
  "Toggle a reading layout for long prose in the current buffer.

Sets wide margins, extra line spacing and no fringes, shows a header
line (state, title, word count, fake page or percentage; see
`sp-reading-progress') and a mode line with a progress bar, wraps
lines at the window edge and turns `olivetti-mode' off while it is active
(it would fight for the same margins).  Turning the mode off puts
every setting back as it was."
  :lighter " Read"
  (if sp-reading-mode
      (progn
        (setq sp-reading--saved nil)
        (when (boundp 'olivetti-mode)
          (push (list 'olivetti-mode nil olivetti-mode) sp-reading--saved)
          (when olivetti-mode (olivetti-mode -1)))
        (dolist (var '(line-spacing left-margin-width right-margin-width
                       left-fringe-width right-fringe-width
                       word-wrap truncate-lines
                       header-line-format mode-line-format))
          (sp-reading--save var))
        (push (list 'visual-line-mode nil (bound-and-true-p visual-line-mode))
              sp-reading--saved)
        (setq-local line-spacing sp-reading-line-spacing
                    left-margin-width sp-reading-left-margin
                    right-margin-width sp-reading-right-margin
                    left-fringe-width 0
                    right-fringe-width 0)
        (visual-line-mode 1)
        (when sp-reading-bars
          (sp-reading--remap-faces)
          (setq-local header-line-format '(:eval (sp-reading--header))
                      mode-line-format '(:eval (sp-reading--footer))))
        (add-hook 'window-configuration-change-hook #'sp-reading--refresh nil t)
        (sp-reading--refresh))
    (remove-hook 'window-configuration-change-hook #'sp-reading--refresh t)
    (dolist (entry sp-reading--saved)
      (pcase-let ((`(,var ,local ,value) entry))
        (cond ((eq var 'olivetti-mode)
               (when value (olivetti-mode 1)))
              ((eq var 'visual-line-mode)
               (visual-line-mode (if value 1 -1)))
              (local (set (make-local-variable var) value))
              (t (kill-local-variable var)))))
    (setq sp-reading--saved nil)
    (mapc #'face-remap-remove-relative sp-reading--remaps)
    (setq sp-reading--remaps nil)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (set-window-margins window left-margin-width right-margin-width)
      (set-window-fringes window nil nil))))

(global-set-key (kbd "C-c w r") #'sp-reading-mode)

(provide 'sp-writedesk)
;; sp-writedesk.el ends here.
