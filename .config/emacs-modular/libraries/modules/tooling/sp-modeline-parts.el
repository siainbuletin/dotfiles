;;; sp-modeline-parts.el --- Boxed segments for the bottom mode line -*- lexical-binding: t; -*-

;;; Commentary:

;; The segments of the bottom mode line shared by `sp-lambda-modeline' and
;; `sp-prot-modeline': window number, major mode box, word count or
;; line:column, keycast with a fixed slot, minor modes count, branch.
;; Layout after doom-modeline.  Nothing happens until
;; `sp-modeline-parts-install' is called.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar sp-after-load-theme-hook)
(declare-function sp-theme-color "sp-theme-engine")
(declare-function nerd-icons-icon-for-mode "nerd-icons")
(declare-function nerd-icons-mdicon "nerd-icons")
(declare-function sp-tag-emoji-modeline-string "sp-tag-emoji" ())
(declare-function keycast-format "keycast")
(declare-function keycast-mode-line-mode "keycast")
(declare-function keycast-header-line-mode "keycast")
(defvar keycast-mode-line-mode)
(defvar keycast-header-line-mode)
(defvar keycast-mode-line-insert-after)
(defvar keycast-mode-line-window-predicate)
(defvar keycast-mode-line-remove-tail-elements)
(defvar keycast-substitute-alist)

(defgroup sp-modeline-parts nil
  "Boxed segments for the bottom mode line."
  :group 'mode-line)

(defcustom sp-modeline-parts-left
  '(window-number mode position keycast minor-modes)
  "The segments at the left of the line, in order.
Each is one of `bar' (a thin accent bar, as in doom-modeline),
`window-number', `mode', `position', `keycast', `minor-modes', `tags'
and `vc'."
  :type '(repeat (choice (const bar) (const window-number) (const mode)
                         (const position) (const keycast)
                         (const minor-modes) (const tags) (const vc)))
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-right '(tags vc)
  "The segments at the right of the line, in order.  See `sp-modeline-parts-left'."
  :type '(repeat (choice (const bar) (const window-number) (const mode)
                         (const position) (const keycast)
                         (const minor-modes) (const tags) (const vc)))
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-boxed '(window-number mode keycast)
  "The segments that are drawn in a coloured box (the others are plain text).
Any of `window-number', `mode' and `keycast' (the key, not the command)."
  :type '(set (const window-number) (const mode) (const keycast))
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-narrow-width 80
  "Windows narrower than this many columns leave out keycast and the minor modes."
  :type 'natnum
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-keycast t
  "When non-nil, the keycast slot is shown and keycast follows the commands."
  :type 'boolean
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-keycast-width 32
  "Width in columns of the keycast slot, key and command together."
  :type 'natnum
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-mode-icon t
  "When non-nil, show the major mode as a nerd-icons icon, not as text."
  :type 'boolean
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-word-count-modes
  '(text-mode org-mode markdown-mode latex-mode LaTeX-mode tex-mode
    typst-ts-mode typst-mode)
  "Modes whose buffers show the word count instead of line and column."
  :type '(repeat symbol)
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-word-count-limit 300000
  "Buffers longer than this many characters show `~' instead of a word count."
  :type 'natnum
  :group 'sp-modeline-parts)

(defface sp-modeline-parts-accent-1
  '((t :inherit (bold font-lock-keyword-face) :inverse-video t))
  "First box colour: the window number.")

(defface sp-modeline-parts-accent-2
  '((t :inherit (bold font-lock-function-name-face) :inverse-video t))
  "Second box colour: the major mode.")

(defface sp-modeline-parts-accent-3
  '((t :inherit (bold font-lock-string-face) :inverse-video t))
  "Third box colour: the key of keycast.")

(defface sp-modeline-parts-bar
  '((t :inherit sp-modeline-parts-accent-1))
  "Face of the thin bar at the left, when the `bar' segment is used.")

(defun sp-modeline-parts--accent (n)
  "Return the colour of accent N (1 to 3) of the theme in use."
  (or (and (fboundp 'sp-theme-color)
           (seq-some (lambda (theme) (get theme 'sp-theme-flavor))
                     custom-enabled-themes)
           (ignore-errors
             (sp-theme-color (pcase n (1 'accent-1) (2 'accent-2) (_ 'cyan)))))
      (face-foreground (pcase n
                         (1 'font-lock-keyword-face)
                         (2 'font-lock-function-name-face)
                         (_ 'font-lock-string-face))
                       nil t)))

(defun sp-modeline-parts-update-accents (&rest _)
  "Set the box faces from the accents of the current theme."
  (let ((bg (face-background 'default nil t)))
    (dolist (n '(1 2 3))
      (let ((color (sp-modeline-parts--accent n))
            (face (intern (format "sp-modeline-parts-accent-%d" n))))
        (when (and (stringp color) (stringp bg))
          (set-face-attribute face nil
                              :inverse-video nil :weight 'bold
                              :foreground bg :background color))))
    (force-mode-line-update t)))

(defun sp-modeline-parts--narrow-p ()
  "Return non-nil if the window is narrower than `sp-modeline-parts-narrow-width'."
  (< (window-total-width) sp-modeline-parts-narrow-width))

(defun sp-modeline-parts--box (segment text face &rest props)
  "Return TEXT for SEGMENT, in a box of FACE when SEGMENT is boxed and selected.
PROPS are text properties for the result."
  (let* ((selected (mode-line-window-selected-p))
         (boxed (memq segment sp-modeline-parts-boxed))
         (text (concat " " text " ")))
    (add-face-text-property 0 (length text)
                            (cond ((and boxed selected) face)
                                  (selected 'bold)
                                  (t 'shadow))
                            nil text)
    (apply #'propertize text props)))

(defun sp-modeline-parts-window-number ()
  "Return the number of the window being displayed."
  (let* ((window (selected-window))
         (frame (window-frame window))
         (windows (window-list frame 'no-minibuf (frame-first-window frame)))
         (number (1+ (or (cl-position window windows) 0))))
    (sp-modeline-parts--box 'window-number (number-to-string number)
                            'sp-modeline-parts-accent-1
                            'help-echo (format "Window %d" number))))

(defun sp-modeline-parts--mode-icon ()
  "Return the nerd-icons icon of the major mode, or nil."
  (when (and sp-modeline-parts-mode-icon (require 'nerd-icons nil t))
    (let ((icon (nerd-icons-icon-for-mode major-mode)))
      (and (stringp icon) (not (string-empty-p icon)) (copy-sequence icon)))))

(defun sp-modeline-parts-mode ()
  "Return the major mode box."
  (let* ((name (format-mode-line mode-name))
         (icon (sp-modeline-parts--mode-icon)))
    (sp-modeline-parts--box
     'mode (or icon name) 'sp-modeline-parts-accent-2
     'help-echo (format "%s (`%s')\nmouse-1: describe-mode" name major-mode)
     'mouse-face 'mode-line-highlight
     'local-map (let ((map (make-sparse-keymap)))
                  (define-key map [mode-line down-mouse-1] #'describe-mode)
                  map))))

(defvar-local sp-modeline-parts--word-count nil
  "List of the modified tick, the time and the count last computed.")

(defun sp-modeline-parts--words ()
  "Return the number of words in the buffer, cached, or nil if it is too long."
  (let ((tick (buffer-chars-modified-tick))
        (now (float-time)))
    (if (and sp-modeline-parts--word-count
             (or (eq (nth 0 sp-modeline-parts--word-count) tick)
                 (< (- now (nth 1 sp-modeline-parts--word-count)) 0.5)))
        (nth 2 sp-modeline-parts--word-count)
      (let ((count (and (<= (buffer-size) sp-modeline-parts-word-count-limit)
                        (count-words (point-min) (point-max)))))
        (setq sp-modeline-parts--word-count (list tick now count))
        count))))

(defun sp-modeline-parts-position ()
  "Return the word count in text buffers, else line and column."
  (propertize
   (if (apply #'derived-mode-p sp-modeline-parts-word-count-modes)
       (let ((words (sp-modeline-parts--words)))
         (format " %s words " (or words "~")))
     (format " %d:%d " (line-number-at-pos) (current-column)))
   'face (if (mode-line-window-selected-p) nil 'shadow)))

(defvar sp-modeline-parts-keycast-anchor ""
  "Empty element of `mode-line-format' that keycast inserts its segment after.")
(put 'sp-modeline-parts-keycast-anchor 'risky-local-variable t)

(defvar sp-modeline-parts--last-key ""
  "The last key keycast saw.")

(defvar sp-modeline-parts--last-command ""
  "The command of `sp-modeline-parts--last-key'.")

(defun sp-modeline-parts--keycast-remember ()
  "Save the key and command of keycast when the selected window shows a new one."
  (when (and (bound-and-true-p keycast-mode-line-mode)
             (mode-line-window-selected-p))
    (let ((key (ignore-errors (keycast-format "%K")))
          (command (ignore-errors (keycast-format "%C"))))
      (when (and (stringp key) (not (string-blank-p key)))
        (setq sp-modeline-parts--last-key (string-trim (substring-no-properties key))
              sp-modeline-parts--last-command
              (string-trim (substring-no-properties (or command ""))))))))

(defun sp-modeline-parts-keycast ()
  "Return the keycast slot: the last key in a box and its command."
  (when sp-modeline-parts-keycast
    (sp-modeline-parts--keycast-remember)
    (if (sp-modeline-parts--narrow-p)
        ""
      (let* ((selected (mode-line-window-selected-p))
             (key (if (string-empty-p sp-modeline-parts--last-key)
                      ""
                    (sp-modeline-parts--box 'keycast sp-modeline-parts--last-key
                                            'sp-modeline-parts-accent-3)))
             (command (if (string-empty-p sp-modeline-parts--last-command)
                          ""
                        (propertize (concat " " sp-modeline-parts--last-command)
                                    'face (if selected nil 'shadow)))))
        (truncate-string-to-width (concat key command)
                                  sp-modeline-parts-keycast-width 0 ?\s "…")))))

(defun sp-modeline-parts--start-keycast ()
  "Make keycast follow the commands, in the mode line only."
  (when (and sp-modeline-parts-keycast (require 'keycast nil t))
    (when (bound-and-true-p keycast-header-line-mode)
      (keycast-header-line-mode -1))
    (setq keycast-mode-line-insert-after 'sp-modeline-parts-keycast-anchor
          keycast-mode-line-window-predicate #'ignore
          keycast-mode-line-remove-tail-elements nil)
    (dolist (input '(self-insert-command org-self-insert-command))
      (add-to-list 'keycast-substitute-alist `(,input "." "Typing…")))
    (dolist (event '("<mouse-event>" "<mouse-movement>" "<mouse-2>" "<drag-mouse-1>"
                     "<wheel-up>" "<wheel-down>" "<double-wheel-up>" "<double-wheel-down>"
                     "<triple-wheel-up>" "<triple-wheel-down>" "<wheel-left>" "<wheel-right>"
                     handle-select-window mouse-set-point mouse-drag-region))
      (add-to-list 'keycast-substitute-alist `(,event nil nil)))
    (when (listp (default-value 'mode-line-format))
      (unless (memq 'sp-modeline-parts-keycast-anchor
                    (default-value 'mode-line-format))
        (setq-default mode-line-format
                      (append (default-value 'mode-line-format)
                              '(sp-modeline-parts-keycast-anchor)))))
    (unless (bound-and-true-p keycast-mode-line-mode)
      (keycast-mode-line-mode 1))))

(defvar sp-modeline-parts-minor-modes-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line down-mouse-1] #'mouse-minor-mode-menu)
    (define-key map [mode-line down-mouse-3] #'describe-mode)
    map)
  "Keymap of the minor modes button.")

(defun sp-modeline-parts-minor-modes ()
  "Return the minor modes button, with the count."
  (unless (sp-modeline-parts--narrow-p)
    (let* ((modes (delete-dups (append local-minor-modes global-minor-modes)))
           (icon (or (and (require 'nerd-icons nil t)
                          (ignore-errors (nerd-icons-mdicon "nf-md-puzzle")))
                     "≡")))
      (propertize (format " %s %d " (substring-no-properties icon) (length modes))
                  'face (if (mode-line-window-selected-p) nil 'shadow)
                  'mouse-face 'mode-line-highlight
                  'help-echo (format "%d minor modes: %s\nmouse-1: menu\nmouse-3: describe-mode"
                                     (length modes)
                                     (mapconcat #'symbol-name modes ", "))
                  'local-map sp-modeline-parts-minor-modes-map))))

(defun sp-modeline-parts-tags ()
  "Return the tag emoji of `sp-tag-emoji' at point, or nil."
  (when (fboundp 'sp-tag-emoji-modeline-string)
    (let ((tags (ignore-errors (sp-tag-emoji-modeline-string))))
      (and (stringp tags) (not (string-blank-p tags)) tags))))

(defun sp-modeline-parts-vc ()
  "Return the version control branch of the file, or nil."
  (when (and vc-mode buffer-file-name)
    (let ((backend (vc-backend buffer-file-name)))
      (when backend
        (propertize (concat " " (substring-no-properties
                                 vc-mode (+ (if (eq backend 'Hg) 2 3) 2))
                            " ")
                    'face (if (mode-line-window-selected-p) nil 'shadow))))))

(defun sp-modeline-parts-bar ()
  "Return a thin bar in the first accent colour (the selected window only)."
  (propertize " " 'display '(space :width 0.5)
              'face (if (mode-line-window-selected-p)
                        'sp-modeline-parts-bar
                      'mode-line-inactive)))

(defun sp-modeline-parts--join (segments)
  "Return the strings of SEGMENTS (symbols) joined by a space."
  (mapconcat #'identity
             (delq nil
                   (mapcar (lambda (segment)
                             (let ((text (funcall (intern (format "sp-modeline-parts-%s" segment)))))
                               (and (stringp text) (not (string-empty-p text)) text)))
                           segments))
             " "))

(defun sp-modeline-parts-compose ()
  "Return the whole line: the left segments, a gap, and the right ones."
  (let* ((left (sp-modeline-parts--join sp-modeline-parts-left))
         (right (concat (sp-modeline-parts--join sp-modeline-parts-right) " ")))
    (concat left
            (propertize " " 'display
                        `(space :align-to (- right ,(string-width right))))
            right)))

(dolist (name '(bar window-number mode position keycast minor-modes tags vc))
  (let ((construct (intern (format "sp-modeline-parts-%s-construct" name)))
        (function (intern (format "sp-modeline-parts-%s" name))))
    (set construct `(:eval (,function)))
    (put construct 'risky-local-variable t)))

(defun sp-modeline-parts-install ()
  "Set the box colours and start keycast.  Call after setting `mode-line-format'."
  (interactive)
  (sp-modeline-parts-update-accents)
  (add-hook 'sp-after-load-theme-hook #'sp-modeline-parts-update-accents 90)
  (sp-modeline-parts--start-keycast)
  (force-mode-line-update t))

(defun sp-modeline-parts-uninstall ()
  "Stop updating the box colours, and stop keycast in the mode line."
  (interactive)
  (remove-hook 'sp-after-load-theme-hook #'sp-modeline-parts-update-accents)
  (when (bound-and-true-p keycast-mode-line-mode)
    (keycast-mode-line-mode -1)))

(provide 'sp-modeline-parts)
