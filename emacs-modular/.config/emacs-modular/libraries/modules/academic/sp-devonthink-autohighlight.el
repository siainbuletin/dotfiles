;;; sp-devonthink-autohighlight.el --- Highlight a DEVONthink selection without the shortcut -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-devonthink-highlight-selection' presses DEVONthink's Highlight menu item;
;; `sp-devonthink-auto-highlight-mode' does it for every selection that settles.
;; macOS only.  Literate source: docs/tangles/academic/sp-devonthink-autohighlight.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'sp-reading)
(require 'sp-devonthink)

(defgroup sp-devonthink-autohighlight nil
  "Highlight a DEVONthink selection without the shortcut."
  :group 'sp-devonthink)

(defcustom sp-devonthink-highlight-menu-item "Highlight"
  "Name of DEVONthink's menu item that highlights the selected text."
  :type 'string)

(defcustom sp-devonthink-auto-highlight-interval 1
  "Seconds between two looks at DEVONthink's selection."
  :type 'number)

(defcustom sp-devonthink-auto-highlight-settle 2
  "Looks in a row that must show the same selection before it is highlighted."
  :type 'integer)

(defconst sp-devonthink-autohighlight--selection-script
  "tell application \"System Events\"
  if not (frontmost of process \"DEVONthink\") then return \"\"
end tell
tell application id \"DNtp\"
  try
    return (selected text of think window 1) as text
  end try
end tell
return \"\""
  "AppleScript printing DEVONthink's front-window selection, or nothing.")

(defun sp-devonthink-autohighlight--selection ()
  "The text selected in DEVONthink's front window, trimmed, or nil."
  (let ((text (string-trim (sp-reading--osascript
                            sp-devonthink-autohighlight--selection-script))))
    (and (not (string-empty-p text)) text)))

(defun sp-devonthink-autohighlight--quote (string)
  "STRING as the body of an AppleScript string literal."
  (replace-regexp-in-string "[\"\\\\]" "\\\\\\&" string))

(defun sp-devonthink-autohighlight--click-script (item)
  "AppleScript that clicks the enabled menu item named ITEM in DEVONthink."
  (format "tell application \"System Events\"
  tell process \"DEVONthink\"
    repeat with bar in (menu bar items of menu bar 1)
      try
        repeat with entry in (menu items of menu 1 of bar)
          if (name of entry) is \"%1$s\" and (enabled of entry) then
            click entry
            return \"ok\"
          end if
          try
            repeat with sub in (menu items of menu 1 of entry)
              if (name of sub) is \"%1$s\" and (enabled of sub) then
                click sub
                return \"ok\"
              end if
            end repeat
          end try
        end repeat
      end try
    end repeat
  end tell
end tell
return \"none\""
          (sp-devonthink-autohighlight--quote item)))

(defun sp-devonthink-autohighlight--press ()
  "Click DEVONthink's Highlight menu item; return non-nil if it was clicked."
  (let ((out (condition-case err
                 (sp-reading--osascript
                  (sp-devonthink-autohighlight--click-script
                   sp-devonthink-highlight-menu-item))
               (error
                (if (string-match-p "assistive access\\|not allowed" (error-message-string err))
                    (user-error "Give Emacs the Accessibility permission (System Settings > Privacy & Security > Accessibility)")
                  (signal (car err) (cdr err)))))))
    (equal out "ok")))

;;;###autoload
(defun sp-devonthink-highlight-selection ()
  "Highlight the text selected in DEVONthink, as if its Highlight item was chosen."
  (interactive)
  (if (sp-devonthink-autohighlight--press)
      (message "Highlighted in DEVONthink")
    (user-error "DEVONthink has no enabled \"%s\" item (select text in a PDF first)"
                sp-devonthink-highlight-menu-item)))

(defvar sp-devonthink-autohighlight--timer nil
  "The repeating timer of `sp-devonthink-auto-highlight-mode', or nil.")

(defvar sp-devonthink-autohighlight--seen nil
  "The selection of the last look at DEVONthink.")

(defvar sp-devonthink-autohighlight--count 0
  "How many looks in a row showed `sp-devonthink-autohighlight--seen'.")

(defvar sp-devonthink-autohighlight--done nil
  "The selection that was just highlighted, so it is not highlighted again.")

(defun sp-devonthink-autohighlight--reset ()
  "Forget what was seen and highlighted."
  (setq sp-devonthink-autohighlight--seen nil
        sp-devonthink-autohighlight--count 0
        sp-devonthink-autohighlight--done nil))

(defun sp-devonthink-autohighlight--step (text)
  "Take the reading TEXT of the selection; return `highlight' when it is time to."
  (cond
   ((null text)
    (sp-devonthink-autohighlight--reset)
    nil)
   ((equal text sp-devonthink-autohighlight--done) nil)
   ((equal text sp-devonthink-autohighlight--seen)
    (cl-incf sp-devonthink-autohighlight--count)
    (when (>= sp-devonthink-autohighlight--count sp-devonthink-auto-highlight-settle)
      (setq sp-devonthink-autohighlight--done text)
      'highlight))
   (t
    (setq sp-devonthink-autohighlight--seen text
          sp-devonthink-autohighlight--count 1)
    (when (>= 1 sp-devonthink-auto-highlight-settle)
      (setq sp-devonthink-autohighlight--done text)
      'highlight))))

(defun sp-devonthink-autohighlight--emacs-focused-p ()
  "Non-nil if an Emacs frame has the keyboard focus."
  (seq-some (lambda (frame) (eq (frame-focus-state frame) t)) (frame-list)))

(defun sp-devonthink-autohighlight--tick ()
  "Look at DEVONthink's selection and highlight it when it has settled."
  (unless (sp-devonthink-autohighlight--emacs-focused-p)
    (condition-case err
        (when (eq (sp-devonthink-autohighlight--step
                   (sp-devonthink-autohighlight--selection))
                  'highlight)
          (sp-devonthink-autohighlight--press))
      (error
       (sp-devonthink-auto-highlight-mode -1)
       (message "sp-devonthink-auto-highlight-mode stopped: %s" (error-message-string err))))))

;;;###autoload
(define-minor-mode sp-devonthink-auto-highlight-mode
  "Highlight whatever gets selected in DEVONthink, without pressing a shortcut.
Looks at the selection every `sp-devonthink-auto-highlight-interval' seconds,
only while Emacs is not the focused app."
  :global t
  :lighter " DTh"
  (when (timerp sp-devonthink-autohighlight--timer)
    (cancel-timer sp-devonthink-autohighlight--timer))
  (setq sp-devonthink-autohighlight--timer nil)
  (sp-devonthink-autohighlight--reset)
  (when sp-devonthink-auto-highlight-mode
    (setq sp-devonthink-autohighlight--timer
          (run-with-timer sp-devonthink-auto-highlight-interval
                          sp-devonthink-auto-highlight-interval
                          #'sp-devonthink-autohighlight--tick))))

(keymap-set sp-devonthink-map "h" #'sp-devonthink-highlight-selection)
(keymap-set sp-devonthink-map "H" #'sp-devonthink-auto-highlight-mode)

;;; Provide

(provide 'sp-devonthink-autohighlight)
;;; sp-devonthink-autohighlight.el ends here
