;;; sp-faces.el --- Faces, highlighting and visual feedback -*- lexical-binding: t; -*-

;;; Commentary:

;; This module gathers settings that change how text and the cursor look:
;; outline heading faces in Lisp files, SVG tags in code, TODO and number
;; highlighting, a TODO navigation transient, pulsing the current line after
;; jumps, and highlighting of edited regions with Goggles. It also defines a
;; small `what-face' helper for inspecting faces.

;;; Code:

;;;; Outline Faces
;; Make outline faces look better
(use-package outline-minor-faces
  :ensure t
  :after outline
  :hook ((emacs-lisp-mode lisp-interaction-mode lisp-mode) . outline-minor-faces-mode))

;;;; What Face?
;; https://stackoverflow.com/a/66287459/6277148
(defun what-face (pos)
  "State the face at point POS in the minibuffer."
  (interactive "d")
  (let ((face (or (get-char-property (point) 'read-face-name)
                  (get-char-property (point) 'face))))
    (if face (message "Face: %s" face) (message "No face at %d" pos))))

;;;; Underline
(customize-set-variable 'x-underline-at-descent-line t)

;;;; Reveal Mode
;; Toggle uncloaking of invisible text near point, including folded org headlines (Reveal mode).
(use-package reveal
  :ensure nil
  :defer 1
  :config
  (setq reveal-auto-hide nil)
  (global-reveal-mode))

;;;; SVG Library (For Tags/Labels/etc.)
;;;;; SVG Tag Mode
(use-package svg-tag-mode
  :ensure t
  :when (image-type-available-p 'svg)
  :hook (prog-mode . svg-tag-mode)
  :config
  (setq svg-tag-tags
        '(;; Replaces any occurence of :XXX: with a dynamic SVG tag displaying XXX
          ("\\(:[A-Z]+:\\)" . ((lambda (tag)
                                 (svg-tag-make tag :face 'success :inverse t :beg 1 :end -1))))
          ;; other tags
          ("DONE:"  . ((lambda (tag) (svg-tag-make "DONE:"  :face 'fringe  :inverse t ))))
          ("FIXME:" . ((lambda (tag) (svg-tag-make "FIXME:" :face 'error   :inverse t))))
          ("HACK:"  . ((lambda (tag) (svg-tag-make "HACK:"  :face 'warning :inverse t))))
          ("NOTE:"  . ((lambda (tag) (svg-tag-make "NOTE:"  :face 'warning :inverse t))))
          ("TODO:"  . ((lambda (tag) (svg-tag-make "TODO:"  :face 'warning :inverse t)))))))

;;;; Widgets
(use-package wid-edit
  :ensure nil
  :defer 1
  :custom
  ;; No ugly button for checkboxes
  (widget-image-enable nil))

;;;; Highlight

;;;;; Highlight Numbers & TODOS
(use-package highlight-numbers
  :ensure t
  :defer t
  :commands highlight-numbers-mode
  :init
  (add-hook 'prog-mode-hook #'highlight-numbers-mode))

(use-package hl-todo
  :ensure t
  :defer t
  :commands hl-todo-mode
  :init
  ;; (add-hook 'org-mode-hook #'hl-todo-mode)
  (add-hook 'prog-mode-hook #'hl-todo-mode)
  (add-hook 'markdown-mode-hook #'hl-todo-mode))

;; TODO navigation transient. Bound to <leader> s t in
;; sp-keybindings.el. Suffixes stay on press; "q" exits.
;;
;; Setup/teardown: the prefix's BODY runs at invocation, enables
;; `hl-todo-mode', and registers a one-shot `transient-exit-hook'
;; that disables it on every exit path (q, C-g, prefix re-invocation,
;; focus loss). The hook removes itself so subsequent exits do not
;; double-toggle. See git history for the prior macro-based dispatch
;; implementation this replaced.
(require 'transient)

(transient-define-prefix sp-todo-transient ()
  "TODO navigation."
  ["TODO"
   ("n" "Next"     hl-todo-next     :transient t)
   ("p" "Previous" hl-todo-previous :transient t)
   ("o" "Occur"    hl-todo-occur    :transient t)
   ("q" "Quit"     transient-quit-one)]
  (interactive)
  (hl-todo-mode 1)
  (let (cleanup)
    (setq cleanup
          (lambda ()
            (hl-todo-mode -1)
            (remove-hook 'transient-exit-hook cleanup)))
    (add-hook 'transient-exit-hook cleanup))
  (transient-setup 'sp-todo-transient))

;; ;;https://github.com/erickgnavar/dotfiles/tree/master/.emacs.d#highlight-todo-fixme-etc
;; (defun lem-highlight-todo-like-words ()
;;   (font-lock-add-keywords
;;    nil `(("\\<\\(FIXME\\|TODO\\|NOTE\\)"
;;           1 font-lock-warning-face t))))

;; (add-hook 'prog-mode-hook 'my/highlight-todo-like-words)

;;;; Cursor
;; don't show cursor in inactive windows
(customize-set-variable 'cursor-in-non-selected-windows nil)

;;;;; Highlight Cursor Line with Pulse
;; From https://karthinks.com/software/batteries-included-with-emacs/
;; Replace external package with internal command

(use-package pulse
  :bind
  ("C-<return>" . pulse-line)
  :commands (pulse-line pulse-momentary-highlight-one-line)
  :config
  (setq pulse-delay 0.08)
  (defun pulse-line (&rest _)
    "Pulse the current line."
    (interactive)
    (pulse-momentary-highlight-one-line (point)))
  ;; pulse on window change
  (push 'pulse-line window-selection-change-functions))

;;;; Goggles (Highlight Changes)
(use-package goggles
  :ensure t
  :hook ((prog-mode text-mode) . goggles-mode)
  :config
  (setq-default goggles-pulse t)) ;; set to nil to disable pulsing

;;;; Empty Lines
;; Don't show empty lines.
;; .. Allows you to tell if there are blank lines at the end of the file.
(setq-default indicate-empty-lines nil)

(provide 'sp-faces)
;;; sp-faces.el ends here
