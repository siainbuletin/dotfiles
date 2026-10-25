;;; sp-modeline.el --- A native mode line adapted from Prot's -*- lexical-binding: t; -*-

;;; Commentary:

;; A mode line made of constructs, adapted from `prot-modeline.el' in
;; Protesilaos Stavrou's dotfiles (GPLv3).  Unlike his, it shows the lighters
;; of the minor modes, needs no other library, and takes its colours from the
;; theme.  Alternative to `sp-lambda-line'; load only one of the two.

;;; Code:

(require 'vc)
(require 'subr-x)

(defgroup sp-modeline nil
  "A mode line adapted from Prot's."
  :group 'mode-line)

(defcustom sp-modeline-string-truncate-length 9
  "String length after which truncation is done in small windows."
  :type 'natnum
  :group 'sp-modeline)

(defcustom sp-modeline-minor-modes-style 'lighters
  "How to show the enabled minor modes.
`lighters' shows the text each mode puts in the mode line, `count'
shows how many are enabled, nil shows nothing."
  :type '(choice (const :tag "Lighters" lighters)
                 (const :tag "Count" count)
                 (const :tag "None" nil))
  :group 'sp-modeline)

(defface sp-modeline-indicator-button nil
  "Face inherited by the indicators that have a background.
Add a :box attribute to it to give all of them a border.")

(defface sp-modeline-indicator-gray
  '((t :inherit (bold shadow)))
  "Face for muted indicators.")

(defface sp-modeline-indicator-red
  '((t :inherit (bold error)))
  "Face for indicators that need attention.")

(defface sp-modeline-indicator-red-bg
  '((t :inherit (bold error sp-modeline-indicator-button) :inverse-video t))
  "Face for indicators that need attention, with a background.")

(defface sp-modeline-indicator-green-bg
  '((t :inherit (bold success sp-modeline-indicator-button) :inverse-video t))
  "Face for informative indicators, with a background.")

(defface sp-modeline-indicator-blue-bg
  '((t :inherit (bold font-lock-keyword-face sp-modeline-indicator-button)
       :inverse-video t))
  "Face for the keyboard macro indicator, with a background.")

(defface sp-modeline-indicator-cyan-bg
  '((t :inherit (bold font-lock-type-face sp-modeline-indicator-button)
       :inverse-video t))
  "Face for the narrowing indicator, with a background.")

(defface sp-modeline-indicator-gray-bg
  '((t :inherit (bold shadow sp-modeline-indicator-button) :inverse-video t))
  "Face for the dedicated window indicator, with a background.")

(defun sp-modeline--window-narrow-p ()
  "Return non-nil if the window is narrower than `split-width-threshold'."
  (and (numberp split-width-threshold)
       (< (window-total-width) split-width-threshold)))

(defun sp-modeline--truncate-p (str)
  "Return non-nil if the non-blank string STR should be truncated."
  (and (stringp str)
       (not (string-blank-p str))
       (sp-modeline--window-narrow-p)
       (> (length str) sp-modeline-string-truncate-length)
       (not (one-window-p :no-minibuffer))))

(defun sp-modeline-string-cut-end (str)
  "Return STR cut at `sp-modeline-string-truncate-length' when appropriate."
  (if (sp-modeline--truncate-p str)
      (concat (substring str 0 sp-modeline-string-truncate-length) "...")
    str))

(defun sp-modeline-string-cut-middle (str)
  "Return STR with its middle cut out when appropriate."
  (let ((half (floor sp-modeline-string-truncate-length 2)))
    (if (sp-modeline--truncate-p str)
        (concat (substring str 0 half) "..." (substring str (- half)))
      str)))

(defvar-local sp-modeline-kbd-macro
    '(:eval
      (when (and (mode-line-window-selected-p) defining-kbd-macro)
        (propertize " KMacro " 'face 'sp-modeline-indicator-blue-bg)))
  "Mode line construct for a keyboard macro being defined.")

(defvar-local sp-modeline-narrow
    '(:eval
      (when (and (mode-line-window-selected-p)
                 (buffer-narrowed-p)
                 (not (derived-mode-p 'Info-mode 'help-mode 'message-mode 'special-mode)))
        (propertize " Narrow " 'face 'sp-modeline-indicator-cyan-bg)))
  "Mode line construct for a narrowed buffer.")

(defvar-local sp-modeline-input-method
    '(:eval
      (when (and (mode-line-window-selected-p) current-input-method-title)
        (propertize (format " %s " current-input-method-title)
                    'face 'sp-modeline-indicator-green-bg
                    'mouse-face 'mode-line-highlight)))
  "Mode line construct for the input method.")

(defvar-local sp-modeline-buffer-status
    '(:eval
      (when (file-remote-p default-directory)
        (propertize " @ "
                    'face 'sp-modeline-indicator-red-bg
                    'mouse-face 'mode-line-highlight)))
  "Mode line construct for a remote buffer.")

(defvar-local sp-modeline-window-dedicated-status
    '(:eval
      (when (window-dedicated-p)
        (propertize " = "
                    'face 'sp-modeline-indicator-gray-bg
                    'mouse-face 'mode-line-highlight)))
  "Mode line construct for a dedicated window.")

(defun sp-modeline-buffer-identification-face ()
  "Return the face for `sp-modeline-buffer-identification'."
  (let ((file (buffer-file-name)))
    (cond
     ((and (mode-line-window-selected-p) file (buffer-modified-p))
      '(italic mode-line-buffer-id))
     ((and file (buffer-modified-p)) 'italic)
     ((mode-line-window-selected-p) 'mode-line-buffer-id))))

(defun sp-modeline-buffer-name-help-echo ()
  "Return the `help-echo' text for the buffer name."
  (concat
   (propertize (buffer-name) 'face 'mode-line-buffer-id)
   "\n"
   (propertize
    (or (buffer-file-name)
        (format "No underlying file.\nDirectory is: %s" default-directory))
    'face 'font-lock-doc-face)))

(defvar-local sp-modeline-buffer-identification
    '(:eval
      (let ((name (propertize (sp-modeline-string-cut-middle (buffer-name))
                              'face (sp-modeline-buffer-identification-face)
                              'mouse-face 'mode-line-highlight
                              'help-echo (sp-modeline-buffer-name-help-echo))))
        (if buffer-read-only
            (concat (propertize "RO"
                                'face (if (mode-line-window-selected-p)
                                          'sp-modeline-indicator-red
                                        'sp-modeline-indicator-gray))
                    " " name)
          name)))
  "Mode line construct for the buffer name and its read-only state.")

(defvar sp-modeline-describe-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line down-mouse-1] 'describe-mode)
    map)
  "Keymap for the mode name and minor modes.")

(defun sp-modeline-major-mode-help-echo ()
  "Return the `help-echo' text for the major mode."
  (if-let* ((parent (get major-mode 'derived-mode-parent)))
      (format "Symbol: `%s'.  Derived from: `%s'\nmouse-1: `describe-mode'"
              major-mode parent)
    (format "Symbol: `%s'.\nmouse-1: `describe-mode'" major-mode)))

(defvar-local sp-modeline-major-mode
    (list
     (propertize "%[" 'face 'sp-modeline-indicator-red)
     '(:eval
       (propertize (sp-modeline-string-cut-end (format-mode-line mode-name))
                   'face 'bold
                   'mouse-face 'mode-line-highlight
                   'help-echo (sp-modeline-major-mode-help-echo)
                   'local-map sp-modeline-describe-map))
     (propertize "%]" 'face 'sp-modeline-indicator-red))
  "Mode line construct for the major mode.")

(defun sp-modeline--enabled-minor-modes ()
  "Return the symbols of the minor modes enabled in this buffer."
  (let (modes)
    (dolist (entry minor-mode-alist)
      (let ((mode (car entry)))
        (when (and (boundp mode) (symbol-value mode))
          (push mode modes))))
    (nreverse modes)))

(defun sp-modeline--minor-modes-text ()
  "Return the text for the enabled minor modes, or nil."
  (when-let* ((style sp-modeline-minor-modes-style)
              (modes (sp-modeline--enabled-minor-modes)))
    (pcase style
      ('lighters
       (let ((text (string-trim (format-mode-line minor-mode-alist))))
         (unless (string-empty-p text)
           (propertize (sp-modeline-string-cut-end text)
                       'face 'sp-modeline-indicator-gray
                       'mouse-face 'mode-line-highlight
                       'help-echo (format "Minor modes: %s\nmouse-1: `describe-mode'"
                                          (mapconcat #'symbol-name modes ", "))
                       'local-map sp-modeline-describe-map))))
      ('count
       (propertize (format "(%d)" (length modes))
                   'face 'sp-modeline-indicator-gray
                   'mouse-face 'mode-line-highlight
                   'help-echo (format "Minor modes: %s\nmouse-1: `describe-mode'"
                                      (mapconcat #'symbol-name modes ", "))
                   'local-map sp-modeline-describe-map)))))

(defvar-local sp-modeline-minor-modes
    '(:eval (when (mode-line-window-selected-p)
              (sp-modeline--minor-modes-text)))
  "Mode line construct for the minor modes of the selected window.")

(defvar-local sp-modeline-process
    (list '("" mode-line-process))
  "Mode line construct for the process indicator.")

(declare-function vc-git--symbolic-ref "vc-git" (file))

(defvar sp-modeline-vc-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line down-mouse-1] 'vc-diff)
    (define-key map [mode-line down-mouse-3] 'vc-root-diff)
    map)
  "Keymap for `sp-modeline-vc-branch'.")

(defvar sp-modeline--vc-faces
  '((added . vc-locally-added-state)
    (edited . vc-edited-state)
    (removed . vc-removed-state)
    (missing . vc-missing-state)
    (conflict . vc-conflict-state)
    (locked . vc-locked-state)
    (up-to-date . vc-up-to-date-state))
  "Faces for the states `vc-state' returns.")

(defun sp-modeline--vc-branch-name (file backend)
  "Return the branch name of FILE under BACKEND, or a short revision."
  (when-let* ((rev (vc-working-revision file backend)))
    (or (and (eq backend 'Git) (vc-git--symbolic-ref file))
        (substring rev 0 (min 7 (length rev))))))

(defun sp-modeline--vc-text ()
  "Return the propertized branch text for the current buffer, or nil."
  (when-let* ((file (or buffer-file-name default-directory))
              (backend (vc-backend file))
              (branch (sp-modeline--vc-branch-name file backend))
              (state (vc-state file backend)))
    (propertize (sp-modeline-string-cut-end branch)
                'face (alist-get state sp-modeline--vc-faces 'vc-up-to-date-state)
                'mouse-face 'mode-line-highlight
                'help-echo (format "Revision: %s\nmouse-1: `vc-diff'\nmouse-3: `vc-root-diff'"
                                   (vc-working-revision file backend))
                'local-map sp-modeline-vc-map)))

(defvar-local sp-modeline-vc-branch
    '(:eval (when (mode-line-window-selected-p)
              (sp-modeline--vc-text)))
  "Mode line construct for the version control branch.")

(declare-function flymake--severity "flymake" (type))
(declare-function flymake-diagnostic-type "flymake" (diag))
(declare-function flymake-diagnostics "flymake" (&optional beg end))

(defvar sp-modeline-flymake-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line down-mouse-1] 'flymake-show-buffer-diagnostics)
    (define-key map [mode-line down-mouse-3] 'flymake-show-project-diagnostics)
    map)
  "Keymap for the Flymake counters.")

(defun sp-modeline--flymake-counter (type indicator face)
  "Return INDICATOR and the count of TYPE diagnostics in FACE, or nil."
  (let ((count 0))
    (dolist (d (flymake-diagnostics))
      (when (= (flymake--severity type)
               (flymake--severity (flymake-diagnostic-type d)))
        (setq count (1+ count))))
    (when (> count 0)
      (concat
       (propertize indicator 'face 'sp-modeline-indicator-gray)
       (propertize (number-to-string count)
                   'face face
                   'mouse-face 'mode-line-highlight
                   'local-map sp-modeline-flymake-map
                   'help-echo "mouse-1: buffer diagnostics\nmouse-3: project diagnostics")))))

(defvar-local sp-modeline-flymake
    '(:eval
      (when (and (bound-and-true-p flymake-mode) (mode-line-window-selected-p))
        (concat (sp-modeline--flymake-counter :error "E" 'error)
                (sp-modeline--flymake-counter :warning "!" 'warning)
                (sp-modeline--flymake-counter :note "." 'success))))
  "Mode line construct for the Flymake counters.")

(defvar-local sp-modeline-which-function-indicator
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

(defvar-local sp-modeline-misc-info
    '(:eval (when (mode-line-window-selected-p)
              mode-line-misc-info))
  "Mode line construct for `mode-line-misc-info' (the clock, tag emoji...).")

;; The constructs are variables whose value is a list with :eval forms, so
;; they are not trusted by default.  Without this property they do not render.
(dolist (construct '(sp-modeline-kbd-macro
                     sp-modeline-narrow
                     sp-modeline-input-method
                     sp-modeline-buffer-status
                     sp-modeline-window-dedicated-status
                     sp-modeline-buffer-identification
                     sp-modeline-major-mode
                     sp-modeline-minor-modes
                     sp-modeline-process
                     sp-modeline-vc-branch
                     sp-modeline-flymake
                     sp-modeline-which-function-indicator
                     sp-modeline-misc-info))
  (put construct 'risky-local-variable t))

(defvar sp-modeline--saved-format nil
  "The default `mode-line-format' before `sp-modeline-mode' was enabled.")

(defconst sp-modeline-format
  '("%e"
    sp-modeline-kbd-macro
    sp-modeline-narrow
    sp-modeline-buffer-status
    sp-modeline-window-dedicated-status
    sp-modeline-input-method
    "  "
    sp-modeline-buffer-identification
    "  "
    sp-modeline-major-mode
    " "
    sp-modeline-minor-modes
    sp-modeline-process
    "  "
    sp-modeline-vc-branch
    "  "
    sp-modeline-flymake
    "  "
    mode-line-format-right-align
    sp-modeline-which-function-indicator
    "  "
    sp-modeline-misc-info)
  "The mode line format of `sp-modeline-mode'.")

;;;###autoload
(define-minor-mode sp-modeline-mode
  "Show the mode line adapted from Prot's: buffer name, modes, branch."
  :global t
  :group 'sp-modeline
  (if sp-modeline-mode
      (progn
        (setq sp-modeline--saved-format (default-value 'mode-line-format))
        (setq mode-line-compact nil)
        (setq mode-line-right-align-edge 'right-margin)
        (setq-default mode-line-format sp-modeline-format))
    (setq-default mode-line-format sp-modeline--saved-format))
  (force-mode-line-update t))

(sp-modeline-mode 1)

(provide 'sp-modeline)
