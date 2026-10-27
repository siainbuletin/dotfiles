;;; sp-modeline-parts.el --- Boxed segments for the bottom mode line -*- lexical-binding: t; -*-

;;; Commentary:

;; The segments of the bottom mode line shared by `sp-lambda-modeline' and
;; `sp-prot-modeline': window number, major mode box, word count or
;; line:column, keycast with a fixed slot, clocked task, branch.  The left and
;; right parts are aligned by `mode-line-maker'.
;; Layout after doom-modeline.  Nothing happens until
;; `sp-modeline-parts-install' is called.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar sp-after-load-theme-hook)
(declare-function sp-theme-color "sp-theme-engine")
(declare-function nerd-icons-icon-for-mode "nerd-icons")
(declare-function mode-line-maker--make "mode-line-maker")
(declare-function org-clocking-p "org-clock")
(declare-function org-clock-get-clocked-time "org-clock")
(declare-function org-duration-from-minutes "org-duration")
(declare-function org-get-todo-state "org")
(declare-function org-back-to-heading "org")
(declare-function org-clock-goto "org-clock")
(defvar org-clock-heading)
(defvar org-clock-marker)
(defvar org-clock-history)
(defvar org-clock-in-switch-to-state)
(defvar org-clock-in-hook)
(defvar org-clock-out-hook)
(defvar org-todo-keywords-1)
(defvar org-done-keywords)
(defvar mode-line-maker-padding-face)
(declare-function sp-org-tag-groups-modeline-string "sp-org-tag-groups" ())
(declare-function keycast-format "keycast")
(declare-function keycast-mode-line-mode "keycast")
(declare-function keycast-header-line-mode "keycast")
(defvar keycast-mode-line-mode)
(defvar keycast-header-line-mode)
(defvar keycast-mode-line-insert-after)
(defvar keycast-mode-line-window-predicate)
(defvar keycast-mode-line-remove-tail-elements)
(defvar keycast-substitute-alist)

(use-package mode-line-maker
  :ensure (:host github :repo "rougier/mode-line-maker"))

(defgroup sp-modeline-parts nil
  "Boxed segments for the bottom mode line."
  :group 'mode-line)

(defcustom sp-modeline-parts-left
  '(window-number mode position keycast)
  "The segments at the left of the line, in order.
Each is one of `bar' (a thin accent bar, as in doom-modeline),
`window-number', `mode', `position', `keycast', `clock', `tags'
and `vc'."
  :type '(repeat (choice (const bar) (const window-number) (const mode)
                         (const position) (const keycast)
                         (const clock) (const tags) (const vc)))
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-right '(clock tags vc)
  "The segments at the right of the line, in order.  See `sp-modeline-parts-left'."
  :type '(repeat (choice (const bar) (const window-number) (const mode)
                         (const position) (const keycast)
                         (const clock) (const tags) (const vc)))
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-boxed '(window-number mode keycast clock)
  "The segments that are drawn in a coloured box (the others are plain text).
Any of `window-number', `mode', `keycast' (the key, not the command) and
`clock' (the todo keyword)."
  :type '(set (const window-number) (const mode) (const keycast) (const clock))
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-narrow-width 80
  "Windows narrower than this many columns leave out keycast."
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

(defcustom sp-modeline-parts-clock-keyword "PROG"
  "Todo keyword that the clocked-in entry is switched to, or nil to keep its state."
  :type '(choice string (const :tag "Keep the state" nil))
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-clock-width 28
  "Width in columns of the heading of the clocked task."
  :type 'natnum
  :group 'sp-modeline-parts)

(defcustom sp-modeline-parts-clock-arrow t
  "When non-nil, flag the clocked-in heading with an arrow in the fringe."
  :type 'boolean
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

(defface sp-modeline-parts-accent-4
  '((t :inherit (bold font-lock-warning-face) :inverse-video t))
  "Fourth box colour: the todo keyword of the clocked task.")

(defface sp-modeline-parts-bar
  '((t :inherit sp-modeline-parts-accent-1))
  "Face of the thin bar at the left, when the `bar' segment is used.")

(defun sp-modeline-parts--accent (n)
  "Return the colour of accent N (1 to 3) of the theme in use."
  (or (and (fboundp 'sp-theme-color)
           (seq-some (lambda (theme) (get theme 'sp-theme-flavor))
                     custom-enabled-themes)
           (ignore-errors
             (sp-theme-color (pcase n (1 'accent-1) (2 'accent-2) (3 'cyan) (_ 'accent-3)))))
      (face-foreground (pcase n
                         (1 'font-lock-keyword-face)
                         (2 'font-lock-function-name-face)
                         (3 'font-lock-string-face)
                         (_ 'font-lock-warning-face))
                       nil t)))

(defun sp-modeline-parts-update-accents (&rest _)
  "Set the box faces from the accents of the current theme."
  (let ((bg (face-background 'default nil t)))
    (dolist (n '(1 2 3 4))
      (let ((color (sp-modeline-parts--accent n))
            (face (intern (format "sp-modeline-parts-accent-%d" n))))
        (when (and (stringp color) (stringp bg))
          (set-face-attribute face nil
                              :inverse-video nil :weight 'bold
                              :foreground bg :background color))))
    (when (facep 'mode-line-maker-padding-face)
      (set-face-attribute 'mode-line-maker-padding-face nil
                          :foreground (face-foreground 'default nil t)
                          :background bg))
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

(defvar sp-modeline-parts-clock-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'org-clock-goto)
    (define-key map [mode-line mouse-3] #'org-agenda)
    map)
  "Keymap of the clocked task: mouse-1 goes to the entry, mouse-3 opens the agenda.")

(defun sp-modeline-parts--clock-state ()
  "Return the todo keyword of the clocked entry, or nil."
  (when (and (markerp org-clock-marker) (marker-buffer org-clock-marker))
    (ignore-errors
      (with-current-buffer (marker-buffer org-clock-marker)
        (save-excursion
          (goto-char org-clock-marker)
          (org-back-to-heading t)
          (org-get-todo-state))))))

(defun sp-modeline-parts-clock ()
  "Return the clocked task: keyword in a box, heading and time, or nil."
  (when (and (featurep 'org-clock) (org-clocking-p))
    (let* ((selected (mode-line-window-selected-p))
           (state (or (sp-modeline-parts--clock-state) "CLOCK"))
           (heading (truncate-string-to-width
                     (substring-no-properties (or org-clock-heading ""))
                     sp-modeline-parts-clock-width nil nil "…"))
           (time (org-duration-from-minutes (org-clock-get-clocked-time))))
      (propertize
       (concat (sp-modeline-parts--box 'clock state 'sp-modeline-parts-accent-4)
               (propertize (format " %s %s " heading time)
                           'face (if selected nil 'shadow)))
       'mouse-face 'mode-line-highlight
       'help-echo (format "Clocked: %s (%s)\nmouse-1: go to the entry\nmouse-3: org-agenda"
                          heading time)
       'local-map sp-modeline-parts-clock-map))))

(defun sp-modeline-parts-clock-switch-state (&optional state)
  "Return the keyword to switch the entry being clocked in to, or nil.
For `org-clock-in-switch-to-state', which Org calls with one argument,
the current todo keyword STATE of the entry (nil when it has none)."
  (when (and state
             sp-modeline-parts-clock-keyword
             (member sp-modeline-parts-clock-keyword org-todo-keywords-1)
             (not (member state org-done-keywords)))
    sp-modeline-parts-clock-keyword))

(defun sp-modeline-parts-clock-flag ()
  "Flag the clocked-in heading with a fringe arrow."
  (when (and sp-modeline-parts-clock-arrow
             (markerp org-clock-marker) (marker-buffer org-clock-marker))
    (with-current-buffer (marker-buffer org-clock-marker)
      (save-excursion
        (goto-char org-clock-marker)
        (org-back-to-heading t)
        (setq-local overlay-arrow-position (copy-marker (point)))))))

(defun sp-modeline-parts-clock-unflag ()
  "Remove the fringe arrow from the buffers of the clocked entries."
  (dolist (marker (list org-clock-marker (car org-clock-history)))
    (when (and (markerp marker) (marker-buffer marker))
      (with-current-buffer (marker-buffer marker)
        (kill-local-variable 'overlay-arrow-position)))))

(defun sp-modeline-parts--clock-install ()
  "Wire the keyword switch and the arrow to Org's clock."
  (unless org-clock-in-switch-to-state
    (setq org-clock-in-switch-to-state #'sp-modeline-parts-clock-switch-state))
  (add-hook 'org-clock-in-hook #'sp-modeline-parts-clock-flag)
  (add-hook 'org-clock-out-hook #'sp-modeline-parts-clock-unflag))

(defun sp-modeline-parts--clock-uninstall ()
  "Undo `sp-modeline-parts--clock-install'."
  (when (eq org-clock-in-switch-to-state #'sp-modeline-parts-clock-switch-state)
    (setq org-clock-in-switch-to-state nil))
  (remove-hook 'org-clock-in-hook #'sp-modeline-parts-clock-flag)
  (remove-hook 'org-clock-out-hook #'sp-modeline-parts-clock-unflag))

(defun sp-modeline-parts-tags ()
  "Return the tag emoji of `sp-org-tag-groups' at point, or nil."
  (when (fboundp 'sp-org-tag-groups-modeline-string)
    (let ((tags (ignore-errors (sp-org-tag-groups-modeline-string))))
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
  (if (and (require 'mode-line-maker nil t) (fboundp 'mode-line-maker--make))
      (apply #'concat
             (mode-line-maker--make
              '((:eval (sp-modeline-parts--join sp-modeline-parts-left)))
              '((:eval (sp-modeline-parts--join sp-modeline-parts-right)))))
    (let ((left (sp-modeline-parts--join sp-modeline-parts-left))
          (right (concat (sp-modeline-parts--join sp-modeline-parts-right) " ")))
      (concat left
              (propertize " " 'display
                          `(space :align-to (- right ,(string-width right))))
              right))))

(dolist (name '(bar window-number mode position keycast clock tags vc))
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
  (with-eval-after-load 'org-clock (sp-modeline-parts--clock-install))
  (force-mode-line-update t))

(defun sp-modeline-parts-uninstall ()
  "Stop updating the box colours, and stop keycast in the mode line."
  (interactive)
  (remove-hook 'sp-after-load-theme-hook #'sp-modeline-parts-update-accents)
  (when (featurep 'org-clock) (sp-modeline-parts--clock-uninstall))
  (when (bound-and-true-p keycast-mode-line-mode)
    (keycast-mode-line-mode -1)))

(provide 'sp-modeline-parts)
