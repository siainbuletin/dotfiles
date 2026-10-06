;; -*- lexical-binding: t; -*-

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

;; Working with pop-up buffers (Lambda Emacs settings)

;;;; Popper (Pop-up Buffers)
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
  ;; set display to top -- if user prefers they can set this to `bottom'
  (popper-display-function #'popper-select-popup-at-top)
  ;; group by project.el project root, with fall back to default-directory
  (popper-group-function #'popper-group-by-directory)
  ;; Set popper buffers
  (popper-reference-buffers
   '("\\*Messages\\*"
     "Output\\*$"
     "\\*Async Shell Command\\*"
     help-mode
     compilation-mode))
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
       (slot . 1)))))