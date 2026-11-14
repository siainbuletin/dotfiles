;;; sp-buffers.el --- Buffer lists and pop-up buffers -*- lexical-binding: t; -*-

;;; Commentary:

;; This module covers two things: how the buffer list looks and behaves (the
;; built-in `ibuffer', with icons from `nerd-icons-ibuffer'), and how transient
;; pop-up buffers such as help, messages and compilation output are displayed
;; (Karthik Chikmagalur's `popper' package, using settings adapted from Lambda
;; Emacs).

;;; Code:

(use-package ibuffer
  :ensure nil
  
  :custom ;; this is for customizing variables. :config is for functions
  (ibuffer-display-summary nil)
  (ibuffer-use-other-window nil)
  (ibuffer-show-empty-filter-groups nil)
  (ibuffer-default-sorting-mode 'filename/process)
  (ibuffer-title-face 'font-lock-doc-face)
  (ibuffer-use-header-line t)
  (ibuffer-default-shrink-to-minimum-size nil)
  (ibuffer-formats
        '((mark modified read-only locked " "
                (sp-name 36 36 :left :elide)
                " "
                (size 9 -1 :right)
                " "
                (mode 18 18 :left :elide)
                " " filename-and-process)
          (mark " "
                (sp-name 24 24 :left :elide)
                " " filename)))
  ;; Group the list as soon as ibuffer opens, otherwise the saved groups
  ;; below are defined but never applied.
  :hook (ibuffer-mode . sp-buffers-activate-filter-groups))

(defun sp-buffers-activate-filter-groups ()
  "Switch the current ibuffer to the \"Main\" saved filter groups."
  (when (assoc "Main" ibuffer-saved-filter-groups)
    (ibuffer-switch-to-saved-filter-groups "Main")))

;; Show the `#+title' of an Org file in the buffer list instead of its file
;; name.  This is a display column only: the buffers are not renamed, so
;; `switch-to-buffer', Uniquify and the "name" filters keep working.
(defcustom sp-buffers-org-title-in-ibuffer t
  "Non-nil shows the `#+title' of Org buffers in the `sp-name' ibuffer column.
Buffers without a title, and buffers that are not in Org mode, show their
buffer name as usual."
  :type 'boolean
  :group 'ibuffer)

(defconst sp-buffers-org-title-regexp "^[ \t]*#\\+title:[ \t]*\\(.*?\\)[ \t]*$"
  "Match a `#+title' keyword line; group 1 is the title.")

(defconst sp-buffers-org-title-search-limit 4000
  "Look for `#+title' only in the first this many characters of a buffer.")

(defvar-local sp-buffers--title-cache nil
  "Cons of `buffer-chars-modified-tick' and the title found then (or `none').")

(defun sp-buffers-org-title (&optional buffer)
  "Return the `#+title' of the Org BUFFER, or nil when it has none.
BUFFER defaults to the current buffer.  The result is cached in the buffer
and only looked up again after the text changed."
  (with-current-buffer (or buffer (current-buffer))
    (when (derived-mode-p 'org-mode)
      (let ((tick (buffer-chars-modified-tick)))
        (unless (eq (car sp-buffers--title-cache) tick)
          (setq sp-buffers--title-cache
                (cons tick
                      (save-restriction
                        (widen)
                        (save-excursion
                          (goto-char (point-min))
                          (let ((case-fold-search t))
                            (if (re-search-forward
                                 sp-buffers-org-title-regexp
                                 sp-buffers-org-title-search-limit t)
                                (let ((title (match-string-no-properties 1)))
                                  (if (string-empty-p title) 'none title))
                              'none)))))))
        (and-let* ((title (cdr sp-buffers--title-cache))
                   ((stringp title)))
          title)))))

(defun sp-buffers-display-name (&optional buffer)
  "Return the name to list for BUFFER: its Org title, else its buffer name."
  (or (and sp-buffers-org-title-in-ibuffer
           (sp-buffers-org-title buffer))
      (buffer-name buffer)))

(eval-when-compile (require 'ibuf-macs))
(define-ibuffer-column sp-name
  (:name "Name"
   :inline t
   :header-mouse-map ibuffer-name-header-map
   :props
   ('mouse-face 'highlight 'keymap ibuffer-name-map
                'ibuffer-name-column t
                'help-echo "mouse-1: mark buffer   mouse-2: select buffer   mouse-3: operate")
   :summarizer
   (lambda (strings)
     (let ((bufs (length strings)))
       (cond ((zerop bufs) "No buffers")
             ((= 1 bufs) "1 buffer")
             (t (format "%s buffers" bufs))))))
  (let ((string (propertize (sp-buffers-display-name buffer)
                            'font-lock-face
                            (ibuffer-buffer-name-face buffer mark))))
    (string-replace
     "\n" (propertize "^J" 'font-lock-face 'escape-glyph) string)))

;; `nerd-icons-ibuffer-mode' (enabled in sp-icons) replaces `ibuffer-formats'
;; with its own list, so the column widths have to be set here as well.
(with-eval-after-load 'nerd-icons-ibuffer
  (setopt nerd-icons-ibuffer-formats
          '((mark modified read-only locked " "
                  (icon 2 2 :left :elide)
                  " "
                  (sp-name 36 36 :left :elide)
                  " "
                  (size-h 9 -1 :right)
                  " "
                  (mode+ 18 18 :left :elide)
                  " " filename-and-process+)
            (mark " "
                  (icon 2 2 :left :elide)
                  " "
                  (sp-name 24 24 :left :elide)
                  " " filename-and-process+))))

(setq ibuffer-saved-filter-groups
      '(("Main"
         ("Directories" (mode . dired-mode))
         ("Scripts" (or
                     (mode . shell-script-mode)
                     (mode . shell-mode)
                     (mode . sh-mode)
                     (mode . lua-mode)
                     (mode . bat-mode)))
         ("Markup" (or
                    (mode . markdown-mode)
                    (mode . adoc-mode)))
         ("Org" (mode . org-mode))
         ("Emacs Internals" (or
                   (mode . emacs-lisp-mode)
                   (name . "^\\*Help\\*$")
                   (name . "^\\*Custom.*")
                   (name . "^\\*Org Agenda\\*$")
                   (name . "^\\*info\\*$")
                   (name . "^\\*scratch\\*$")
                   (name . "^\\*Backtrace\\*$")
                   (name . "^\\*Messages\\*$"))))))

;; nerd-icons-ibuffer is already called in sp-icons.el

;; Always group items in buffer menu
(setq mouse-buffer-menu-mode-mult 0)
;; Use ibuffer instead of temporary buffer popup
(keymap-global-set "C-x C-b" 'ibuffer)

;; Working with pop-up buffers (Lambda Emacs settings)

;;;; Popper (Pop-up Buffers)
;; this is a package created by Karthik and it makes it possible to bring up windows without
;; messing up the layout
(use-package popper
  :ensure t
  :hook (after-init . popper-mode)
  :bind (("M-`"   . popper-toggle-latest)
         ("C-`"   . popper-cycle)
         ("C-M-`" . popper-toggle-type))

  :custom
  (popper-window-height 20)
  (popper-display-control t)
  (popper-display-function #'popper-select-popup-right)   ;; set display to top -- if user prefers they can set this to `bottom' (i set it to the custom function for sending it right-ward)
  ;; group by project.el project root, with fall back to default-directory
  (popper-group-function #'popper-group-by-directory)
  ;; Set popper buffers
  (popper-reference-buffers
   '("\\*Messages\\*"
     "Output\\*$"
     "\\*Async Shell Command\\*"
     help-mode
     compilation-mode
     vulpea-sidebar-ui-mode))
  
  :init
  ;; For echo area hints
  (popper-echo-mode +1)
  
  :config
  ;; Display functions for popup buffers at top, where they are easy to read.
  ;; This is just a slight modification of the existing functions.
  (defun popper-select-popup-at-top (buffer &optional _alist)
    "Display and switch to popup-buffer BUFFER at the top of the screen."
    (let ((window (popper-display-popup-at-top buffer)))
      (select-window window)))

  (defun popper-display-popup-at-top (buffer &optional _alist)
    "Display popup-buffer BUFFER at the top of the screen."
    (display-buffer-in-side-window
     buffer
     `((window-height . ,popper-window-height)
       (side . top)
       (slot . 1))))
       
  ;; Displaying functions on the side if wanted
  (defun popper-select-popup-right (buffer &optional _alist)
    "Display and switch to popup-buffer BUFFER at the top of the screen."
    (let ((window (popper-display-popup-right buffer)))
      (select-window window)))

  (defun popper-display-popup-right (buffer &optional _alist)
    "Display popup-buffer BUFFER at the top of the screen."
    (display-buffer-in-side-window
     buffer
     `((window-height . ,popper-window-height)
       (side . right)
       (slot . 1))))
       )

(provide 'sp-buffers)
;; sp-buffers.el ends here.
