;;; sp-quick-capture.el --- Things-style quick entry into inbox.org -*- lexical-binding: t; -*-

;;; Commentary:

;; A global hotkey (set up outside Emacs, see tools/quick-capture) pops a
;; small frame with one prompt.  "Buy milk #errands !fri" becomes a TODO
;; under "Tasks" in inbox.org, tagged @errands, due next Friday.
;;
;; Also reachable as org-protocol://sp-quick-capture[?text=...].
;;
;; tools/quick-capture-native does not wait for Emacs: it writes the line
;; to a spool folder, and `sp-quick-capture-drain' files the lines in
;; inbox.org when Emacs is next free (see "The queue" in the doc).
;;
;; Documented in docs/tangles/text/sp-quick-capture.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)
(require 'org-protocol)

;;;; Options

(defgroup sp-quick-capture nil
  "Things-style quick entry into inbox.org."
  :group 'org)

(defcustom sp-quick-capture-file nil
  "File that receives the tasks, or nil for `org-default-notes-file'."
  :type '(choice (const :tag "org-default-notes-file" nil) file)
  :group 'sp-quick-capture)

(defcustom sp-quick-capture-heading "Tasks"
  "Top-level heading of `sp-quick-capture-file' that receives the tasks.
It is created at the end of the file when it is missing.  This is the
heading the \"t\" template in `sp-org-capture' uses."
  :type 'string
  :group 'sp-quick-capture)

(defcustom sp-quick-capture-keyword "TODO"
  "Keyword of a captured task."
  :type 'string
  :group 'sp-quick-capture)

(defcustom sp-quick-capture-width 72
  "Width of the quick entry frame, in characters."
  :type 'integer
  :group 'sp-quick-capture)

(defcustom sp-quick-capture-hide-emacs t
  "When non-nil, hide Emacs after capturing so the previous app is in front.
Uses `ns-do-hide-emacs' on macOS, and only when no other visible frame
of Emacs is left to hide, so a capture started from your Emacs window
does not hide it."
  :type 'boolean
  :group 'sp-quick-capture)

(defcustom sp-quick-capture-spool-dir
  (or (getenv "QUICK_CAPTURE_SPOOL")
      (expand-file-name "quick-capture"
                        (or (getenv "XDG_STATE_HOME") "~/.local/state")))
  "Folder where `tools/quick-capture-native' leaves lines to capture.
The script uses the same default, so change both or neither."
  :type 'directory
  :group 'sp-quick-capture)

(defcustom sp-quick-capture-drain-interval 30
  "Seconds of idle time after which queued lines are filed, or nil for never.
The queue is also emptied once shortly after this module loads, and by
the script each time it queues a line."
  :type '(choice (const :tag "Never" nil) natnum)
  :group 'sp-quick-capture)

;;;; Dates

(defconst sp-quick-capture--weekdays
  '(("sunday" . 0) ("monday" . 1) ("tuesday" . 2) ("wednesday" . 3)
    ("thursday" . 4) ("friday" . 5) ("saturday" . 6))
  "Weekday names, numbered as in `decode-time'.")

(defconst sp-quick-capture--months
  '("jan" "feb" "mar" "apr" "may" "jun" "jul" "aug" "sep" "oct" "nov" "dec")
  "Month names by their first three letters.")

(defun sp-quick-capture--day-shift (time days)
  "Return TIME moved by DAYS days, at noon so daylight saving cannot move the day."
  (let* ((d (decode-time time))
         (day (+ (decoded-time-day d) days)))
    (encode-time (list 0 0 12 day (decoded-time-month d) (decoded-time-year d)
                       nil -1 nil))))

(defun sp-quick-capture--month-day (month day now)
  "Return the next MONTH/DAY on or after the day of NOW, or nil if it is no date."
  (when (and (<= 1 month 12) (<= 1 day 31))
    (let* ((d (decode-time now))
           (year (decoded-time-year d))
           (this (encode-time (list 0 0 12 day month year nil -1 nil)))
           (check (decode-time this)))
      ;; 31 Feb overflows into March: not a date.
      (when (and (= (decoded-time-month check) month)
                 (= (decoded-time-day check) day))
        (if (time-less-p this (sp-quick-capture--day-shift now 0))
            (encode-time (list 0 0 12 day month (1+ year) nil -1 nil))
          this)))))

(defun sp-quick-capture-parse-date (word &optional now)
  "Return the time (at noon) that WORD names, relative to NOW, or nil."
  (let* ((now (or now (current-time)))
         (w (downcase word))
         (today (sp-quick-capture--day-shift now 0)))
    (cond
     ((string= w "today") today)
     ((member w '("tom" "tomorrow")) (sp-quick-capture--day-shift now 1))
     ((string-match "\\`\\+?\\([0-9]+\\)\\([dwmy]\\)\\'" w)
      (let ((n (string-to-number (match-string 1 w)))
            (unit (match-string 2 w)))
        (pcase unit
          ("d" (sp-quick-capture--day-shift now n))
          ("w" (sp-quick-capture--day-shift now (* 7 n)))
          (_ (let* ((d (decode-time today))
                    (months (if (string= unit "m") n (* 12 n))))
               ;; Clamp the day so +1m from 31 Jan gives 28/29 Feb, not March.
               (let* ((total (+ (1- (decoded-time-month d)) months))
                      (year (+ (decoded-time-year d) (/ total 12)))
                      (month (1+ (% total 12)))
                      (last (calendar-last-day-of-month month year)))
                 (encode-time (list 0 0 12 (min (decoded-time-day d) last)
                                    month year nil -1 nil))))))))
     ((string-match "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{1,2\\}\\)-\\([0-9]\\{1,2\\}\\)\\'" w)
      (let ((y (string-to-number (match-string 1 w)))
            (m (string-to-number (match-string 2 w)))
            (dd (string-to-number (match-string 3 w))))
        (when (and (<= 1 m 12) (<= 1 dd (calendar-last-day-of-month m y)))
          (encode-time (list 0 0 12 dd m y nil -1 nil)))))
     ((string-match "\\`\\([0-9]\\{1,2\\}\\)-\\([0-9]\\{1,2\\}\\)\\'" w)
      (sp-quick-capture--month-day (string-to-number (match-string 1 w))
                                   (string-to-number (match-string 2 w)) now))
     ((string-match "\\`\\([0-9]\\{1,2\\}\\)\\([a-z]\\{3,\\}\\)\\'" w)
      (let ((m (cl-position (substring (match-string 2 w) 0 3)
                            sp-quick-capture--months :test #'string=)))
        (and m (sp-quick-capture--month-day
                (1+ m) (string-to-number (match-string 1 w)) now))))
     ((string-match "\\`\\([a-z]\\{3,\\}\\)\\([0-9]\\{1,2\\}\\)\\'" w)
      (let ((m (cl-position (substring (match-string 1 w) 0 3)
                            sp-quick-capture--months :test #'string=)))
        (and m (sp-quick-capture--month-day
                (1+ m) (string-to-number (match-string 2 w)) now))))
     ((and (>= (length w) 3)
           (cl-find-if (lambda (d) (string-prefix-p w (car d)))
                       sp-quick-capture--weekdays))
      (let* ((target (cdr (cl-find-if (lambda (d) (string-prefix-p w (car d)))
                                      sp-quick-capture--weekdays)))
             (ahead (mod (- target (decoded-time-weekday (decode-time today))) 7)))
        (sp-quick-capture--day-shift now (if (zerop ahead) 7 ahead)))))))

(defun sp-quick-capture--timestamp (time)
  "Return the active Org timestamp for TIME."
  (format-time-string "<%Y-%m-%d %a>" time))

;;;; Tags

(defun sp-quick-capture-tag-names ()
  "Return every tag the task and note tag lists know, as strings."
  (let (names)
    (dolist (entry (append org-tag-alist org-tag-persistent-alist))
      (let ((name (cond ((stringp entry) entry)
                        ((and (consp entry) (stringp (car entry))) (car entry)))))
        (when name (push name names))))
    (delete-dups (nreverse names))))

(defun sp-quick-capture--bare (tag)
  "Return TAG without a leading @."
  (string-remove-prefix "@" tag))

(defun sp-quick-capture--resolve-tag (word)
  "Resolve WORD to (TAG) , (:ambiguous NAMES), or (:unknown WORD)."
  (let* ((names (sp-quick-capture-tag-names))
         (w (downcase (sp-quick-capture--bare word)))
         (exact (cl-remove-if-not
                 (lambda (n) (string= (downcase (sp-quick-capture--bare n)) w))
                 names)))
    (if exact
        ;; The bare and the @ form may both exist; prefer the one typed.
        (list (or (cl-find (downcase word) exact :test #'string= :key #'downcase)
                  (car exact)))
      (let ((prefix (cl-remove-if-not
                     (lambda (n)
                       (string-prefix-p w (downcase (sp-quick-capture--bare n))))
                     names)))
        (cond ((= (length prefix) 1) (list (car prefix)))
              (prefix (list :ambiguous prefix))
              (t (list :unknown word)))))))

;;;; Parser

(defun sp-quick-capture-parse (line &optional now)
  "Parse LINE into a plist with :title :tags :deadline :scheduled :warnings.
The dates are Org timestamp strings.  NOW is the time that relative
dates count from (default: now).  :warnings is a list of strings."
  (let (title tags deadline scheduled warnings)
    (dolist (word (split-string line "[ \t\n]+" t))
      (let ((sigil (aref word 0))
            (rest (substring word 1)))
        (cond
         ((and (memq sigil '(?! ?^)) (not (string-empty-p rest)))
          (let ((time (sp-quick-capture-parse-date rest now)))
            (cond ((null time)
                   (push word title)
                   (push (format "%s is not a date" word) warnings))
                  ((eq sigil ?!) (setq deadline (sp-quick-capture--timestamp time)))
                  (t (setq scheduled (sp-quick-capture--timestamp time))))))
         ((and (eq sigil ?#) (not (string-empty-p rest)))
          (let ((hit (sp-quick-capture--resolve-tag rest)))
            (pcase (car hit)
              (:ambiguous
               (push word title)
               (push (format "%s is ambiguous: %s" word
                             (string-join (cadr hit) ", "))
                     warnings))
              (:unknown
               (push (replace-regexp-in-string "[^[:alnum:]_@#%]" "_" rest) tags)
               (push (format "%s is not a registered tag" word) warnings))
              (tag (push tag tags)))))
         (t (push word title)))))
    (list :title (string-join (nreverse title) " ")
          :tags (delete-dups (nreverse tags))
          :deadline deadline
          :scheduled scheduled
          :warnings (nreverse warnings))))

(defun sp-quick-capture-preview (parsed)
  "Return a one-line description of PARSED, for the box."
  (let ((tags (plist-get parsed :tags))
        (deadline (plist-get parsed :deadline))
        (scheduled (plist-get parsed :scheduled))
        (warnings (plist-get parsed :warnings)))
    (string-join
     (delq nil
           (list (format "→ %s" (let ((title (plist-get parsed :title)))
                                  (if (string-empty-p title) "…" title)))
                 (and tags (format ":%s:" (string-join tags ":")))
                 (and deadline (format "due %s" (substring deadline 1 -1)))
                 (and scheduled (format "sched %s" (substring scheduled 1 -1)))
                 (and warnings (format "(%s)" (string-join warnings "; ")))))
     "  ")))

;;;; Writing

(defun sp-quick-capture--file ()
  "Return the absolute file name that receives the tasks."
  (expand-file-name (or sp-quick-capture-file org-default-notes-file)))

(defun sp-quick-capture-insert (parsed &optional time)
  "Write the task PARSED (from `sp-quick-capture-parse') into the inbox.
TIME is when it was captured (default: now); it sets :CREATED:.
Return the title."
  (let ((title (plist-get parsed :title)))
    (when (string-empty-p (string-trim title))
      (user-error "Nothing to capture: the line has no title"))
    (with-current-buffer (find-file-noselect (sp-quick-capture--file))
      (unless (derived-mode-p 'org-mode) (org-mode))
      (org-with-wide-buffer
       (goto-char (point-min))
       (let ((level 1))
         (if (re-search-forward
              (format "^\\* +%s\\(?:[ \t]+:[^ \t]*:\\)?[ \t]*$"
                      (regexp-quote sp-quick-capture-heading))
              nil t)
             (progn (org-back-to-heading t)
                    (setq level (1+ (org-current-level)))
                    (org-end-of-subtree t t))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert "* " sp-quick-capture-heading "\n")
           (setq level 2))
         (unless (bolp) (insert "\n"))
         (let ((start (point)))
           (insert (make-string level ?*) " " sp-quick-capture-keyword " " title "\n")
           (let ((planning (string-join
                            (delq nil
                                  (list (and (plist-get parsed :scheduled)
                                             (concat "SCHEDULED: " (plist-get parsed :scheduled)))
                                        (and (plist-get parsed :deadline)
                                             (concat "DEADLINE: " (plist-get parsed :deadline)))))
                            " ")))
             (unless (string-empty-p planning) (insert planning "\n")))
           (insert ":PROPERTIES:\n"
                   ":ID:       " (org-id-new) "\n"
                   ":CREATED:  " (format-time-string "[%Y-%m-%d %H:%M]" time) "\n"
                   ":END:\n")
           (goto-char start)
           (when (plist-get parsed :tags)
             (org-set-tags (plist-get parsed :tags))))))
      (save-buffer))
    title))

;;;; Prompt

(defun sp-quick-capture--capf ()
  "Complete the tag after a # in the minibuffer."
  (let ((end (point)))
    (save-excursion
      (skip-chars-backward "[:alnum:]_@%")
      (when (eq (char-before) ?#)
        (list (point) end
              (mapcar #'sp-quick-capture--bare (sp-quick-capture-tag-names))
              :exclusive 'no)))))

(defvar-local sp-quick-capture--overlay nil
  "Overlay showing the preview in the minibuffer.")

(defun sp-quick-capture--update-preview ()
  "Show the preview of the minibuffer contents after them."
  (unless (overlayp sp-quick-capture--overlay)
    (setq sp-quick-capture--overlay (make-overlay (point-max) (point-max) nil t t)))
  (move-overlay sp-quick-capture--overlay (point-max) (point-max))
  (overlay-put sp-quick-capture--overlay 'after-string
               (propertize (concat "\n" (sp-quick-capture-preview
                                         (sp-quick-capture-parse
                                          (minibuffer-contents-no-properties))))
                           'face 'shadow)))

(defun sp-quick-capture--minibuffer-setup ()
  "Set up the quick entry minibuffer."
  (add-hook 'completion-at-point-functions #'sp-quick-capture--capf nil t)
  (local-set-key (kbd "TAB") #'completion-at-point)
  (add-hook 'post-command-hook #'sp-quick-capture--update-preview nil t))

(defun sp-quick-capture-read ()
  "Read a task line in the minibuffer."
  ;; `this-command' makes `mini-frame' leave this prompt in its own frame.
  (let ((this-command 'sp-quick-capture)
        (enable-recursive-minibuffers t))
    (minibuffer-with-setup-hook #'sp-quick-capture--minibuffer-setup
      (read-string "Task: "))))

(with-eval-after-load 'mini-frame
  (defvar mini-frame-ignore-commands)
  (add-to-list 'mini-frame-ignore-commands 'sp-quick-capture))

;;;###autoload
(defun sp-quick-capture (line)
  "Capture LINE as a task in the inbox and return its preview text.
Called interactively, it prompts for LINE.  The return value is what
`tools/quick-capture-native' shows in its notification."
  (interactive (list (sp-quick-capture-read)))
  (let ((parsed (sp-quick-capture-parse line)))
    (sp-quick-capture-insert parsed)
    (message "Captured: %s" (sp-quick-capture-preview parsed))
    (sp-quick-capture-preview parsed)))

;;;; Frame

(defvar sp-quick-capture-frame-name "quick-capture"
  "Name of the quick entry frame; window manager rules can match on it.")

(defun sp-quick-capture--frame-parameters ()
  "Return the parameters of the quick entry frame."
  (let* ((cw (frame-char-width))
         (width (* cw sp-quick-capture-width))
         (left (max 0 (/ (- (display-pixel-width) width) 2)))
         (top (/ (display-pixel-height) 4)))
    `((name . ,sp-quick-capture-frame-name)
      (minibuffer . only)
      (width . ,sp-quick-capture-width)
      (height . 2)
      (left . ,left)
      (top . ,top)
      (undecorated . t)
      (internal-border-width . 12)
      (vertical-scroll-bars . nil)
      (menu-bar-lines . 0)
      (tool-bar-lines . 0)
      (unsplittable . t)
      (window-system . ,(or window-system
                            (and (eq system-type 'darwin) 'ns))))))

(defun sp-quick-capture--maybe-hide ()
  "Hide Emacs when the quick entry was the only visible frame."
  (when (and sp-quick-capture-hide-emacs
             (fboundp 'ns-do-hide-emacs)
             (not (cl-some (lambda (f) (and (frame-visible-p f)
                                            (not (equal (frame-parameter f 'name)
                                                        sp-quick-capture-frame-name))))
                           (frame-list))))
    (ns-do-hide-emacs)))

;;;###autoload
(defun sp-quick-capture-popup (&optional line)
  "Capture a task from a small frame.  With LINE, capture it without asking."
  (interactive)
  (cond
   (line (sp-quick-capture line))
   ((not (or (display-graphic-p) (eq system-type 'darwin)))
    (call-interactively #'sp-quick-capture))
   (t
    (let ((frame (make-frame (sp-quick-capture--frame-parameters))))
      (unwind-protect
          (with-selected-frame frame
            (select-frame-set-input-focus frame)
            (condition-case err
                (call-interactively #'sp-quick-capture)
              (quit (message "Quick capture cancelled"))
              (user-error (message "%s" (error-message-string err)))))
        (when (frame-live-p frame) (delete-frame frame t))
        (sp-quick-capture--maybe-hide))))))

;;;; The queue

(defvar sp-quick-capture--draining nil
  "Non-nil while `sp-quick-capture-drain' runs, so it does not nest.")

(defun sp-quick-capture-pending ()
  "Return the queued capture files, oldest first."
  (when (file-directory-p sp-quick-capture-spool-dir)
    (directory-files sp-quick-capture-spool-dir t "\\`[0-9]+-.*\\.txt\\'")))

(defun sp-quick-capture--file-one (file)
  "File the line in FILE into the inbox and delete FILE.  Return the preview."
  (let* ((line (with-temp-buffer
                 (insert-file-contents file)
                 (string-trim (buffer-string))))
         (time (file-attribute-modification-time (file-attributes file)))
         (parsed (sp-quick-capture-parse line time)))
    (sp-quick-capture-insert parsed time)
    (delete-file file)
    (sp-quick-capture-preview parsed)))

(defun sp-quick-capture--park (file)
  "Move FILE to the failed/ folder of the spool."
  (let ((dir (expand-file-name "failed" sp-quick-capture-spool-dir)))
    (make-directory dir t)
    (rename-file file (expand-file-name (file-name-nondirectory file) dir) t)))

;;;###autoload
(defun sp-quick-capture-drain ()
  "File every queued line in the inbox.  Return how many were filed."
  (interactive)
  (let ((done 0) (failed 0))
    (unless sp-quick-capture--draining
      (let ((sp-quick-capture--draining t))
        (dolist (file (sp-quick-capture-pending))
          (condition-case err
              (let ((preview (sp-quick-capture--file-one file)))
                (cl-incf done)
                (message "Captured: %s" preview))
            (error
             (cl-incf failed)
             (message "Quick capture: %s moved to failed/ (%s)"
                      (file-name-nondirectory file) (error-message-string err))
             (sp-quick-capture--park file))))))
    (when (and (called-interactively-p 'interactive) (zerop (+ done failed)))
      (message "Quick capture: the queue is empty"))
    done))

(defvar sp-quick-capture--drain-timer nil
  "Idle timer that runs `sp-quick-capture-drain'.")

(defun sp-quick-capture--schedule ()
  "(Re)start the idle timer according to `sp-quick-capture-drain-interval'."
  (when (timerp sp-quick-capture--drain-timer)
    (cancel-timer sp-quick-capture--drain-timer))
  (setq sp-quick-capture--drain-timer
        (and sp-quick-capture-drain-interval
             (run-with-idle-timer sp-quick-capture-drain-interval t
                                  #'sp-quick-capture-drain))))

(unless noninteractive
  (sp-quick-capture--schedule)
  ;; Lines captured while Emacs was not running.
  (run-with-idle-timer 2 nil #'sp-quick-capture-drain))

;;;; org-protocol

(defun sp-quick-capture-protocol (info)
  "Handle org-protocol://sp-quick-capture[?text=…]."
  (let ((text (plist-get info :text)))
    (if (and text (not (string-blank-p text)))
        (sp-quick-capture-popup text)
      (sp-quick-capture-popup)))
  nil)

(add-to-list 'org-protocol-protocol-alist
             '("sp-quick-capture" :protocol "sp-quick-capture"
               :function sp-quick-capture-protocol :kill-client t))

(provide 'sp-quick-capture)
