;;; sp-prot-modeline.el --- A native mode line adapted from Prot's -*- lexical-binding: t; -*-

;;; Commentary:

;; A mode line made of constructs, adapted from `prot-modeline.el' in
;; Protesilaos Stavrou's dotfiles (GPLv3).  Unlike his, it uses the boxed
;; segments of `sp-modeline-parts', mode-line-maker for the left and right
;; parts, and takes its colours from the theme.  Alternative to `sp-lambda-modeline'; load only one of the two.

;;; Code:

(require 'vc)
(require 'subr-x)
(require 'sp-nano-style)
(require 'sp-modeline-parts)

(defgroup sp-prot-modeline nil
  "A mode line adapted from Prot's."
  :group 'mode-line)

(defcustom sp-prot-modeline-string-truncate-length 9
  "String length after which truncation is done in small windows."
  :type 'natnum
  :group 'sp-prot-modeline)

(defface sp-prot-modeline-indicator-button nil
  "Face inherited by the indicators that have a background.
Add a :box attribute to it to give all of them a border.")

(defface sp-prot-modeline-indicator-gray
  '((t :inherit (bold shadow)))
  "Face for muted indicators.")

(defface sp-prot-modeline-indicator-red
  '((t :inherit (bold error)))
  "Face for indicators that need attention.")

(defface sp-prot-modeline-indicator-red-bg
  '((t :inherit (bold error sp-prot-modeline-indicator-button) :inverse-video t))
  "Face for indicators that need attention, with a background.")

(defface sp-prot-modeline-indicator-green-bg
  '((t :inherit (bold success sp-prot-modeline-indicator-button) :inverse-video t))
  "Face for informative indicators, with a background.")

(defface sp-prot-modeline-indicator-blue-bg
  '((t :inherit (bold font-lock-keyword-face sp-prot-modeline-indicator-button)
       :inverse-video t))
  "Face for the keyboard macro indicator, with a background.")

(defface sp-prot-modeline-indicator-cyan-bg
  '((t :inherit (bold font-lock-type-face sp-prot-modeline-indicator-button)
       :inverse-video t))
  "Face for the narrowing indicator, with a background.")

(defface sp-prot-modeline-indicator-gray-bg
  '((t :inherit (bold shadow sp-prot-modeline-indicator-button) :inverse-video t))
  "Face for the dedicated window indicator, with a background.")

(defun sp-prot-modeline--window-narrow-p ()
  "Return non-nil if the window is narrower than `split-width-threshold'."
  (and (numberp split-width-threshold)
       (< (window-total-width) split-width-threshold)))

(defun sp-prot-modeline--truncate-p (str)
  "Return non-nil if the non-blank string STR should be truncated."
  (and (stringp str)
       (not (string-blank-p str))
       (sp-prot-modeline--window-narrow-p)
       (> (length str) sp-prot-modeline-string-truncate-length)
       (not (one-window-p :no-minibuffer))))

(defun sp-prot-modeline-string-cut-end (str)
  "Return STR cut at `sp-prot-modeline-string-truncate-length' when appropriate."
  (if (sp-prot-modeline--truncate-p str)
      (concat (substring str 0 sp-prot-modeline-string-truncate-length) "...")
    str))

(defun sp-prot-modeline-string-cut-middle (str)
  "Return STR with its middle cut out when appropriate."
  (let ((half (floor sp-prot-modeline-string-truncate-length 2)))
    (if (sp-prot-modeline--truncate-p str)
        (concat (substring str 0 half) "..." (substring str (- half)))
      str)))

(defvar-local sp-prot-modeline-kbd-macro
    '(:eval
      (when (and (mode-line-window-selected-p) defining-kbd-macro)
        (propertize " KMacro " 'face 'sp-prot-modeline-indicator-blue-bg)))
  "Mode line construct for a keyboard macro being defined.")

(defvar-local sp-prot-modeline-narrow
    '(:eval
      (when (and (mode-line-window-selected-p)
                 (buffer-narrowed-p)
                 (not (derived-mode-p 'Info-mode 'help-mode 'message-mode 'special-mode)))
        (propertize " Narrow " 'face 'sp-prot-modeline-indicator-cyan-bg)))
  "Mode line construct for a narrowed buffer.")

(defvar-local sp-prot-modeline-input-method
    '(:eval
      (when (and (mode-line-window-selected-p) current-input-method-title)
        (propertize (format " %s " current-input-method-title)
                    'face 'sp-prot-modeline-indicator-green-bg
                    'mouse-face 'mode-line-highlight)))
  "Mode line construct for the input method.")

(defvar-local sp-prot-modeline-buffer-status
    '(:eval
      (when (file-remote-p default-directory)
        (propertize " @ "
                    'face 'sp-prot-modeline-indicator-red-bg
                    'mouse-face 'mode-line-highlight)))
  "Mode line construct for a remote buffer.")

(defvar-local sp-prot-modeline-window-dedicated-status
    '(:eval
      (when (window-dedicated-p)
        (propertize " = "
                    'face 'sp-prot-modeline-indicator-gray-bg
                    'mouse-face 'mode-line-highlight)))
  "Mode line construct for a dedicated window.")

(defvar-local sp-prot-modeline-process
    (list '("" mode-line-process))
  "Mode line construct for the process indicator.")

(declare-function vc-git--symbolic-ref "vc-git" (file))

(defvar sp-prot-modeline-vc-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line down-mouse-1] 'vc-diff)
    (define-key map [mode-line down-mouse-3] 'vc-root-diff)
    map)
  "Keymap for `sp-prot-modeline-vc-branch'.")

(defvar sp-prot-modeline--vc-faces
  '((added . vc-locally-added-state)
    (edited . vc-edited-state)
    (removed . vc-removed-state)
    (missing . vc-missing-state)
    (conflict . vc-conflict-state)
    (locked . vc-locked-state)
    (up-to-date . vc-up-to-date-state))
  "Faces for the states `vc-state' returns.")

(defun sp-prot-modeline--vc-branch-name (file backend)
  "Return the branch name of FILE under BACKEND, or a short revision."
  (when-let* ((rev (vc-working-revision file backend)))
    (or (and (eq backend 'Git) (vc-git--symbolic-ref file))
        (substring rev 0 (min 7 (length rev))))))

(defun sp-prot-modeline--vc-text ()
  "Return the propertized branch text for the current buffer, or nil."
  (when-let* ((file (or buffer-file-name default-directory))
              (backend (vc-backend file))
              (branch (sp-prot-modeline--vc-branch-name file backend))
              (state (vc-state file backend)))
    (propertize (sp-prot-modeline-string-cut-end branch)
                'face (alist-get state sp-prot-modeline--vc-faces 'vc-up-to-date-state)
                'mouse-face 'mode-line-highlight
                'help-echo (format "Revision: %s\nmouse-1: `vc-diff'\nmouse-3: `vc-root-diff'"
                                   (vc-working-revision file backend))
                'local-map sp-prot-modeline-vc-map)))

(defvar-local sp-prot-modeline-vc-branch
    '(:eval (when (mode-line-window-selected-p)
              (sp-prot-modeline--vc-text)))
  "Mode line construct for the version control branch.")

(declare-function flymake--severity "flymake" (type))
(declare-function flymake-diagnostic-type "flymake" (diag))
(declare-function flymake-diagnostics "flymake" (&optional beg end))

(defvar sp-prot-modeline-flymake-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line down-mouse-1] 'flymake-show-buffer-diagnostics)
    (define-key map [mode-line down-mouse-3] 'flymake-show-project-diagnostics)
    map)
  "Keymap for the Flymake counters.")

(defun sp-prot-modeline--flymake-counter (type indicator face)
  "Return INDICATOR and the count of TYPE diagnostics in FACE, or nil."
  (let ((count 0))
    (dolist (d (flymake-diagnostics))
      (when (= (flymake--severity type)
               (flymake--severity (flymake-diagnostic-type d)))
        (setq count (1+ count))))
    (when (> count 0)
      (concat
       (propertize indicator 'face 'sp-prot-modeline-indicator-gray)
       (propertize (number-to-string count)
                   'face face
                   'mouse-face 'mode-line-highlight
                   'local-map sp-prot-modeline-flymake-map
                   'help-echo "mouse-1: buffer diagnostics\nmouse-3: project diagnostics")))))

(defvar-local sp-prot-modeline-flymake
    '(:eval
      (when (and (bound-and-true-p flymake-mode) (mode-line-window-selected-p))
        (concat (sp-prot-modeline--flymake-counter :error "E" 'error)
                (sp-prot-modeline--flymake-counter :warning "!" 'warning)
                (sp-prot-modeline--flymake-counter :note "." 'success))))
  "Mode line construct for the Flymake counters.")

(defvar-local sp-prot-modeline-which-function-indicator
    '(which-function-mode
      (:eval
       (when (and (mode-line-window-selected-p)
                  (derived-mode-p 'text-mode 'prog-mode))
         (let ((string (or (gethash (selected-window) which-func-table)
                           which-func-unknown)))
           (propertize string
                       'face '(:height 0.8 :inherit which-func)
                       'mouse-face 'mode-line-highlight
                       'help-echo (format "Current definition: `%s'" string))))))
  "The equivalent of `which-func-format'.")

(with-eval-after-load 'which-func
  (setq mode-line-misc-info
        (delete (assq 'which-function-mode mode-line-misc-info) mode-line-misc-info)))

(defvar-local sp-prot-modeline-misc-info
    '(:eval (when (mode-line-window-selected-p)
              mode-line-misc-info))
  "Mode line construct for `mode-line-misc-info' (the clock, tag emoji...).")

;; The constructs are variables whose value is a list with :eval forms, so
;; they are not trusted by default.  Without this property they do not render.
(dolist (construct '(sp-prot-modeline-kbd-macro
                     sp-prot-modeline-narrow
                     sp-prot-modeline-input-method
                     sp-prot-modeline-buffer-status
                     sp-prot-modeline-window-dedicated-status
                     sp-prot-modeline-process
                     sp-prot-modeline-vc-branch
                     sp-prot-modeline-flymake
                     sp-prot-modeline-which-function-indicator
                     sp-prot-modeline-misc-info))
  (put construct 'risky-local-variable t))

(defvar sp-prot-modeline--saved-format nil
  "The default `mode-line-format' before `sp-prot-modeline-mode' was enabled.")

(defvar sp-prot-modeline-format
  '("%e"
    sp-modeline-parts-window-number-construct
    " "
    sp-modeline-parts-mode-construct
    " "
    sp-modeline-parts-position-construct
    " "
    sp-modeline-parts-keycast-construct
    "  "
    sp-prot-modeline-kbd-macro
    sp-prot-modeline-narrow
    sp-prot-modeline-buffer-status
    sp-prot-modeline-window-dedicated-status
    sp-prot-modeline-input-method
    sp-prot-modeline-process
    "  "
    sp-prot-modeline-vc-branch
    "  "
    sp-prot-modeline-flymake
    "  "
    mode-line-format-right-align
    sp-modeline-parts-clock-construct
    "  "
    sp-prot-modeline-which-function-indicator
    "  "
    sp-prot-modeline-misc-info)
  "The mode line format of `sp-prot-modeline-mode'.
Change it, then run `sp-prot-modeline-mode' twice (off, on).")

(defun sp-prot-modeline--format ()
  "Return `sp-prot-modeline-format' with its two parts given to mode-line-maker.
The list is cut at `mode-line-format-right-align'.  Without the package the
list is used as it is."
  (if (require 'mode-line-maker nil t)
      (let* ((tail (memq 'mode-line-format-right-align sp-prot-modeline-format))
             (left (remove "%e" (butlast sp-prot-modeline-format (length tail)))))
        (list "%e" (mode-line-maker left (cdr tail))))
    sp-prot-modeline-format))

;;;###autoload
(define-minor-mode sp-prot-modeline-mode
  "Show the mode line adapted from Prot's, with the boxed segments."
  :global t
  :group 'sp-prot-modeline
  (if sp-prot-modeline-mode
      (progn
        (setq sp-prot-modeline--saved-format (default-value 'mode-line-format))
        (setq mode-line-compact nil)
        (setq mode-line-right-align-edge 'right-margin)
        (setq-default mode-line-format (sp-prot-modeline--format))
        (sp-nano-style-install)
        (sp-modeline-parts-install))
    (sp-modeline-parts-uninstall)
    (setq-default mode-line-format sp-prot-modeline--saved-format)
    (sp-nano-style-uninstall))
  (force-mode-line-update t))

(sp-prot-modeline-mode 1)

(provide 'sp-prot-modeline)
