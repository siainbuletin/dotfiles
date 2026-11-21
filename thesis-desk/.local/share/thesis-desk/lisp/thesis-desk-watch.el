;;; thesis-desk-watch.el --- Notice what you open in DEVONthink -*- lexical-binding: t; -*-

;;; Commentary:

;; A DEVONthink smart rule ("On Opening", script
;; thesis-desk/devonthink/thesis-desk-log-open.applescript) appends one line
;; per opened record to `thesis-desk-opens-file': time, UUID and name, by
;; tabs.  `thesis-desk-watch-mode' watches that file with `file-notify', so
;; nothing polls: Emacs reads only the lines added since it last looked.
;;
;; On a new open, while another record is being READ:
;;   ask    raise Emacs and ask why you left the old one, then start the new
;;          one (`thesis-desk-start');
;;   queue  only say so; the open waits in `thesis-desk-today'.
;; With no session open, an open is only logged; `thesis-desk-today' lists the
;; opens of the day that have no session, and RET on one starts it.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'filenotify)
(require 'thesis-desk-journal)
(require 'thesis-desk-views)

(defcustom thesis-desk-opens-file "~/.local/state/thesis-desk/opens.tsv"
  "File the smart rule appends opened records to."
  :type 'file :group 'thesis-desk)

(defcustom thesis-desk-watch-on-switch 'ask
  "What a new open does while another record is being read: `ask' or `queue'."
  :type '(choice (const ask) (const queue)) :group 'thesis-desk)

(defcustom thesis-desk-watch-name-regexp "\\.pdf\\'"
  "Only opens whose record name matches this count; nil counts all."
  :type '(choice (const nil) regexp) :group 'thesis-desk)

(defcustom thesis-desk-watch-delay 1.0
  "Idle seconds after the last open before Emacs reacts; a burst counts once."
  :type 'number :group 'thesis-desk)

(defcustom thesis-desk-smart-rule-script-directory
  "~/Library/Application Scripts/com.devon-technologies.think/Smart Rules/"
  "Where DEVONthink looks for the scripts of smart rules (DEVONthink 4)."
  :type 'directory :group 'thesis-desk)

(defvar thesis-desk--watch nil "The `file-notify' descriptor, or nil.")
(defvar thesis-desk--watch-offset 0 "Bytes of the opens file already read.")
(defvar thesis-desk--watch-timer nil "Idle timer of the pending reaction.")
(defvar thesis-desk--watch-pending nil "The newest open not reacted to yet.")

;;;; Reading the log

(defun thesis-desk-parse-open (line)
  "Parse LINE of the opens file into (:time :uuid :name :key), or nil."
  (let ((parts (split-string line "\t")))
    (when (and (>= (length parts) 3)
               (string-match-p "\\`[0-9A-Fa-f-]\\{20,\\}\\'" (nth 1 parts)))
      (let ((name (string-join (nthcdr 2 parts) " ")))
        (list :time (nth 0 parts) :uuid (nth 1 parts) :name name
              :key (replace-regexp-in-string "\\.pdf\\'" "" name t t))))))

(defun thesis-desk-read-opens (&optional from)
  "The opens in the file from byte FROM (default 0), and the new end offset.
Return (OPENS . OFFSET); a line not yet ended by a newline is left for later."
  (let ((file (expand-file-name thesis-desk-opens-file)))
    (if (not (file-readable-p file))
        (cons nil 0)
      (with-temp-buffer
        (let* ((size (file-attribute-size (file-attributes file)))
               (from (if (and from (<= from size)) from 0)))
          (insert-file-contents file nil from size)
          (goto-char (point-max))
          (let ((complete (if (re-search-backward "\n" nil t) (1+ (point)) (point-min))))
            (cons (delq nil (mapcar #'thesis-desk-parse-open
                                    (split-string (buffer-substring (point-min) complete) "\n" t)))
                  (+ from (string-bytes (buffer-substring (point-min) complete))))))))))

(defun thesis-desk--open-counts-p (open)
  "Non-nil when OPEN matches `thesis-desk-watch-name-regexp'."
  (or (null thesis-desk-watch-name-regexp)
      (string-match-p thesis-desk-watch-name-regexp (plist-get open :name))))

;;;; Reacting

(defun thesis-desk--watch-react ()
  "React to the newest pending open."
  (setq thesis-desk--watch-timer nil)
  (when-let* ((open (prog1 thesis-desk--watch-pending (setq thesis-desk--watch-pending nil)))
              (active (thesis-desk-journal-active)))
    (unless (equal (plist-get active :uuid) (plist-get open :uuid))
      (pcase thesis-desk-watch-on-switch
        ('ask
         (select-frame-set-input-focus (selected-frame))
         (message "You opened %s while reading %s" (plist-get open :key) (plist-get active :title))
         (thesis-desk-start (list :uuid (plist-get open :uuid) :key (plist-get open :key)
                                  :name (plist-get open :name))))
        (_ (message "[thesis-desk] opened %s; still reading %s (C-; r x to leave it)"
                    (plist-get open :key) (plist-get active :title)))))))

(defun thesis-desk--watch-changed (&optional _event)
  "Read the lines added to the opens file and schedule a reaction."
  (pcase-let ((`(,opens . ,offset) (thesis-desk-read-opens thesis-desk--watch-offset)))
    (setq thesis-desk--watch-offset offset)
    (when-let* ((last (car (last (seq-filter #'thesis-desk--open-counts-p opens)))))
      (setq thesis-desk--watch-pending last)
      (when thesis-desk--watch-timer (cancel-timer thesis-desk--watch-timer))
      (setq thesis-desk--watch-timer
            (run-with-idle-timer thesis-desk-watch-delay nil #'thesis-desk--watch-react)))))

;;;###autoload
(define-minor-mode thesis-desk-watch-mode
  "Watch the opens file the DEVONthink smart rule writes."
  :global t :group 'thesis-desk :lighter nil
  (when thesis-desk--watch
    (file-notify-rm-watch thesis-desk--watch)
    (setq thesis-desk--watch nil))
  (when thesis-desk-watch-mode
    (let* ((file (expand-file-name thesis-desk-opens-file))
           (dir (file-name-directory file)))
      (make-directory dir t)
      ;; Opens from before this Emacs are history, not news.
      (setq thesis-desk--watch-offset (cdr (thesis-desk-read-opens 0)))
      (setq thesis-desk--watch
            (file-notify-add-watch
             dir '(change)
             (lambda (event)
               (when (equal (file-name-nondirectory (nth 2 event))
                            (file-name-nondirectory file))
                 (thesis-desk--watch-changed event))))))))

;;;; The day's opens

(defun thesis-desk-today-sections (opens sessions day)
  "Report sections for the OPENS of DAY (\"YYYY-MM-DD\") against SESSIONS."
  (let* ((today (seq-filter (lambda (o) (string-prefix-p day (plist-get o :time))) opens))
         (uuids (delete-dups (mapcar (lambda (o) (plist-get o :uuid)) today)))
         (with-session (mapcar (lambda (s) (plist-get s :uuid))
                               (seq-filter (lambda (s) (string-prefix-p (concat "[" day)
                                                                        (or (plist-get s :started) "")))
                                           sessions)))
         loose done)
    (dolist (uuid uuids)
      (let* ((mine (seq-filter (lambda (o) (equal (plist-get o :uuid) uuid)) today))
             (open (car mine))
             (item (list :key uuid :label (plist-get open :key)
                         :text (format "opened %d time%s, first at %s"
                                       (length mine) (if (cdr mine) "s" "")
                                       (substring (plist-get open :time) 11 16))
                         :action (lambda ()
                                   (thesis-desk-start (list :uuid uuid :key (plist-get open :key)
                                                            :name (plist-get open :name)))))))
        (if (member uuid with-session) (push item done) (push item loose))))
    (list (list :title "Opened without a session (RET starts one)" :items (nreverse loose)
                :empty "every open has a session")
          (list :title "Opened, with a session" :items (nreverse done) :empty "none"))))

(defun thesis-desk-stalled (opens sessions &optional min)
  "Records opened at least MIN (default 3) times and never left as DONE or DROPPED.
OPENS and SESSIONS as read by `thesis-desk-read-opens' and the journal.
Return plists (:uuid :key :opens :sessions)."
  (let ((counts (make-hash-table :test #'equal))
        (min (or min 3))
        result)
    (dolist (o opens)
      (puthash (plist-get o :uuid) (cons o (gethash (plist-get o :uuid) counts)) counts))
    (maphash (lambda (uuid list)
               (let ((mine (seq-filter (lambda (s) (equal (plist-get s :uuid) uuid)) sessions)))
                 (when (and (>= (length list) min)
                            (not (seq-find (lambda (s) (member (plist-get s :state) '("DONE" "DROPPED")))
                                           mine)))
                   (push (list :uuid uuid :key (plist-get (car list) :key)
                               :opens (length list) :sessions (length mine))
                         result))))
             counts)
    (sort result (lambda (a b) (> (plist-get a :opens) (plist-get b :opens))))))

;;;###autoload
(defun thesis-desk-today ()
  "Today's DEVONthink opens with and without a session, and stalled readings."
  (interactive)
  (let* ((opens (seq-filter #'thesis-desk--open-counts-p (car (thesis-desk-read-opens 0))))
         (sessions (thesis-desk-journal-sessions))
         (day (format-time-string "%Y-%m-%d" nil t))
         (stalled (thesis-desk-stalled opens sessions)))
    (thesis-desk-report
     "*thesis-desk: today*" (format "Today, %s" day)
     (append (thesis-desk-today-sections opens sessions day)
             (list (list :title "Opened 3 times or more, never finished"
                         :items (mapcar (lambda (s)
                                          (list :key (plist-get s :uuid) :label (plist-get s :key)
                                                :text (format "%d opens, %d sessions: finish, drop, or read the background first"
                                                              (plist-get s :opens) (plist-get s :sessions))
                                                :action (lambda ()
                                                          (thesis-desk-start (list :uuid (plist-get s :uuid)
                                                                                   :key (plist-get s :key))))))
                                        stalled)
                         :empty "none")))
     :intro (format "%d opens logged in all.  Days are UTC, as the log writes them." (length opens))
     :refresh #'thesis-desk-today)))

;;;; Installing the smart rule script

(defun thesis-desk--script-source ()
  "The AppleScript source of the smart rule, next to this package in the dotfiles."
  (let ((candidates (list (expand-file-name "../../../../devonthink/thesis-desk-log-open.applescript"
                                            (file-name-directory (file-truename (locate-library "thesis-desk"))))
                          (expand-file-name "~/dotfiles/thesis-desk/devonthink/thesis-desk-log-open.applescript"))))
    (or (seq-find #'file-readable-p candidates)
        (user-error "No thesis-desk-log-open.applescript found"))))

;;;###autoload
(defun thesis-desk-install-smart-rule-script ()
  "Compile the smart rule script into DEVONthink's Smart Rules folder."
  (interactive)
  (let* ((dir (expand-file-name thesis-desk-smart-rule-script-directory))
         (target (expand-file-name "thesis-desk log open.scpt" dir)))
    (make-directory dir t)
    (with-temp-buffer
      (unless (eql 0 (call-process "osacompile" nil t nil "-o" target (thesis-desk--script-source)))
        (error "osacompile failed: %s" (string-trim (buffer-string)))))
    (message "Installed %s; now make the smart rule (README.org, \"Open tracking\")" target)))

(provide 'thesis-desk-watch)
;;; thesis-desk-watch.el ends here
