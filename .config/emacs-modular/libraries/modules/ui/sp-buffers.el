;; -*- lexical-binding: t; -*-
;; sp-buffers.el --- Buffer setup

;;; Commentary:

;;; Code:

(use-package ibuffer
  :ensure nil
  :config
  (setq ibuffer-expert t)
  (setq ibuffer-display-summary nil)
  (setq ibuffer-use-other-window nil)
  (setq ibuffer-show-empty-filter-groups nil)
  (setq ibuffer-default-sorting-mode 'filename/process)
  (setq ibuffer-title-face 'font-lock-doc-face)
  (setq ibuffer-use-header-line t)
  (setq ibuffer-default-shrink-to-minimum-size nil)
  (setq ibuffer-formats
        '((mark modified read-only locked " "
                (name 30 30 :left :elide)
                " "
                (size 9 -1 :right)
                " "
                (mode 16 16 :left :elide)
                " " filename-and-process)
          (mark " "
                (name 16 -1)
                " " filename))))

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
                   (name . "^\\*Messages\\*$")))))
         )

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
  ;; :if (and sp-load-extras (locate-library "popper"))
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

;;; Provide:

(provide 'sp-buffers)
;; sp-buffers.el ends here.
