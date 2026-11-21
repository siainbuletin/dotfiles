;;; thesis-desk-remind.el --- DEVONthink reminders for paused readings -*- lexical-binding: t; -*-

;;; Commentary:

;; Leaving a reading with a reason in `thesis-desk-remind-days' asks for a
;; date (with a default), schedules the session on it in Org, and sets a
;; DEVONthink reminder on the record, so DEVONthink brings it up even when
;; Emacs is closed.  The Org date is the truth; the reminder is the alarm.
;;
;; `thesis-desk-reminders' compares the two for every paused session: missing
;; or different reminders are listed, and A sets them.  Starting a session on
;; a record clears its reminder.
;;
;; Untested on the Mac: the reminder AppleScript is written from memory of the
;; DEVONthink dictionary.  The scripts are options, so a fix needs no new code.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'thesis-desk-dt)
(require 'thesis-desk-journal)
(require 'thesis-desk-views)

(defcustom thesis-desk-remind-days '((later . 5) (dense . 3) (interrupted . 1) (citation . 2))
  "Reasons for leaving that set a reminder, and the default days until it."
  :type '(alist :key-type symbol :value-type integer) :group 'thesis-desk)

(defcustom thesis-desk-remind-alarm "notification"
  "The DEVONthink alarm of a reminder, as AppleScript names it."
  :type 'string :group 'thesis-desk)

(defcustom thesis-desk-remind-set-script
  "set theRecord to get record with uuid %UUID%
if theRecord is missing value then error \"No record \" & %UUID%
set d to current date
set year of d to %Y%
set month of d to %M%
set day of d to %D%
set time of d to %SECONDS%
try
  make new reminder with properties {schedule:once, alarm:%ALARM%, due date:d} at theRecord
on error
  set reminder of theRecord to {schedule:once, alarm:%ALARM%, due date:d}
end try"
  "AppleScript (inside a tell to DEVONthink) that sets a reminder.
%UUID% is a quoted string; %Y% %M% %D% %SECONDS% numbers; %ALARM% the alarm."
  :type 'string :group 'thesis-desk)

(defcustom thesis-desk-remind-clear-script
  "set theRecord to get record with uuid %UUID%
if theRecord is not missing value then
  try
    delete reminder of theRecord
  end try
end if"
  "AppleScript (inside a tell to DEVONthink) that removes a record's reminder."
  :type 'string :group 'thesis-desk)

(defcustom thesis-desk-remind-read-script
  "set out to \"\"
repeat with u in {%UUIDS%}
  set theDate to \"-\"
  try
    set theRecord to get record with uuid u
    set r to reminder of theRecord
    if r is not missing value then
      set d to due date of r
      set theDate to ((year of d) as text) & \"-\" & ((month of d as integer) as text) & \"-\" & ((day of d) as text)
    end if
  end try
  set out to out & u & tab & theDate & linefeed
end repeat
return out"
  "AppleScript (inside a tell to DEVONthink) printing UUID and due date per line."
  :type 'string :group 'thesis-desk)

(defcustom thesis-desk-remind-hour 9
  "Hour of the day a reminder is due."
  :type 'integer :group 'thesis-desk)

;;;; The scripts

(defun thesis-desk-remind--fill (template alist)
  "TEMPLATE with each %KEY% of ALIST replaced, inside a tell to DEVONthink."
  (let ((text template))
    (dolist (cell alist)
      (setq text (string-replace (format "%%%s%%" (car cell)) (cdr cell) text)))
    (concat "tell application id \"DNtp\"\n" text "\nend tell")))

(defun thesis-desk-remind-set-script-for (uuid time)
  "The script that sets a reminder on UUID for TIME."
  (let ((d (decode-time time)))
    (thesis-desk-remind--fill
     thesis-desk-remind-set-script
     `(("UUID" . ,(thesis-desk-dt--quote uuid))
       ("Y" . ,(number-to-string (decoded-time-year d)))
       ("M" . ,(number-to-string (decoded-time-month d)))
       ("D" . ,(number-to-string (decoded-time-day d)))
       ("SECONDS" . ,(number-to-string (* 3600 thesis-desk-remind-hour)))
       ("ALARM" . ,thesis-desk-remind-alarm)))))

(defun thesis-desk-remind-set (uuid time)
  "Set a DEVONthink reminder on UUID for the day of TIME."
  (thesis-desk-dt--osascript (thesis-desk-remind-set-script-for uuid time)))

(defun thesis-desk-remind-clear (uuid)
  "Remove the reminder of UUID, if any."
  (thesis-desk-dt--osascript
   (thesis-desk-remind--fill thesis-desk-remind-clear-script
                             `(("UUID" . ,(thesis-desk-dt--quote uuid))))))

(defun thesis-desk-remind-parse-dates (output)
  "Parse OUTPUT of the read script into an alist (UUID . \"YYYY-MM-DD\" or nil)."
  (delq nil (mapcar (lambda (line)
                      (let ((parts (split-string line "\t")))
                        (when (= (length parts) 2)
                          (cons (car parts)
                                (and (string-match "\\`\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)\\'" (cadr parts))
                                     (format "%04d-%02d-%02d"
                                             (string-to-number (match-string 1 (cadr parts)))
                                             (string-to-number (match-string 2 (cadr parts)))
                                             (string-to-number (match-string 3 (cadr parts)))))))))
                    (split-string (or output "") "\n" t))))

(defun thesis-desk-remind-read (uuids)
  "The due dates of the reminders of UUIDS, as `thesis-desk-remind-parse-dates'."
  (when uuids
    (thesis-desk-remind-parse-dates
     (thesis-desk-dt--osascript
      (thesis-desk-remind--fill thesis-desk-remind-read-script
                                `(("UUIDS" . ,(mapconcat #'thesis-desk-dt--quote uuids ", "))))))))

;;;; Org side

(defun thesis-desk-session-scheduled (id)
  "The SCHEDULED date of session ID as \"YYYY-MM-DD\", or nil."
  (with-current-buffer (thesis-desk-journal--buffer)
    (org-with-wide-buffer
     (thesis-desk-journal--goto id)
     (when-let* ((ts (org-entry-get (point) "SCHEDULED")))
       (and (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" ts) (match-string 0 ts))))))

(defun thesis-desk-session-schedule (id time)
  "Schedule session ID on the day of TIME."
  (with-current-buffer (thesis-desk-journal--buffer)
    (org-with-wide-buffer
     (thesis-desk-journal--goto id)
     (org-schedule nil (format-time-string "%Y-%m-%d" time))
     (save-buffer))))

;;;; Hooks into the journal

(defun thesis-desk-remind-after-switch (session reason state)
  "Ask for a date and set the reminder when SESSION was left for REASON.
Nothing happens unless STATE is PAUSED and REASON is in
`thesis-desk-remind-days'."
  (when-let* (((equal state "PAUSED"))
              (days (alist-get reason thesis-desk-remind-days)))
    (let ((time (org-read-date nil t nil "Come back on: " nil (format "+%dd" days))))
      (thesis-desk-session-schedule (plist-get session :id) time)
      (when (plist-get session :uuid)
        (condition-case err
            (thesis-desk-remind-set (plist-get session :uuid) time)
          (error (message "[thesis-desk] reminder not set in DEVONthink: %s"
                          (error-message-string err))))))))

(defun thesis-desk-remind-after-start (_id record)
  "Clear the DEVONthink reminder of RECORD: you came back to it."
  (when-let* ((uuid (plist-get record :uuid)))
    (ignore-errors (thesis-desk-remind-clear uuid))))

(add-hook 'thesis-desk-after-switch-functions #'thesis-desk-remind-after-switch)
(add-hook 'thesis-desk-after-start-functions #'thesis-desk-remind-after-start)

;;;; Comparing the two

(defun thesis-desk-reminder-sections (sessions scheduled dates)
  "Report sections comparing paused SESSIONS with DEVONthink.
SCHEDULED maps session ID to its Org date, DATES maps UUID to the reminder date."
  (let (missing different fine)
    (dolist (s sessions)
      (let* ((org (cdr (assoc (plist-get s :id) scheduled)))
             (dt (cdr (assoc (plist-get s :uuid) dates)))
             (item (list :key (plist-get s :id) :file (plist-get s :file) :line (plist-get s :line)
                         :label (or (plist-get s :key) (plist-get s :title))
                         :text (format "Org %s, DEVONthink %s" (or org "none") (or dt "none")))))
        (cond ((null org))
              ((null dt) (push item missing))
              ((not (equal org dt)) (push item different))
              (t (push item fine)))))
    (list (list :title "No reminder in DEVONthink (A sets it)" :items (nreverse missing) :empty "none")
          (list :title "Different date in DEVONthink (A sets the Org date)" :items (nreverse different) :empty "none")
          (list :title "In step" :items (nreverse fine) :empty "none"))))

(defvar thesis-desk--reminder-plan nil "(SESSION . DATE) pairs `A' would set.")

;;;###autoload
(defun thesis-desk-reminders ()
  "Compare the dates of paused sessions with their DEVONthink reminders."
  (interactive)
  (let* ((sessions (seq-filter (lambda (s) (plist-get s :uuid))
                               (thesis-desk-journal-sessions '("PAUSED"))))
         (scheduled (mapcar (lambda (s) (cons (plist-get s :id) (thesis-desk-session-scheduled (plist-get s :id))))
                            sessions))
         (dates (thesis-desk-remind-read (delete-dups (mapcar (lambda (s) (plist-get s :uuid)) sessions)))))
    (setq thesis-desk--reminder-plan
          (delq nil (mapcar (lambda (s)
                              (let ((org (cdr (assoc (plist-get s :id) scheduled))))
                                (when (and org (not (equal org (cdr (assoc (plist-get s :uuid) dates)))))
                                  (cons s org))))
                            sessions)))
    (thesis-desk-report
     "*thesis-desk: reminders*" "Reminders of paused readings"
     (thesis-desk-reminder-sections sessions scheduled dates)
     :intro (format "%d paused sessions with a record; %d to set." (length sessions)
                    (length thesis-desk--reminder-plan))
     :refresh #'thesis-desk-reminders
     :apply #'thesis-desk-reminders-apply)))

(defun thesis-desk-reminders-apply (&optional excluded)
  "Set the DEVONthink reminders listed, except the sessions in EXCLUDED."
  (let ((n 0))
    (dolist (pair thesis-desk--reminder-plan)
      (unless (member (plist-get (car pair) :id) excluded)
        (condition-case err
            (progn (thesis-desk-remind-set (plist-get (car pair) :uuid)
                                           (org-time-string-to-time (cdr pair)))
                   (setq n (1+ n)))
          (error (message "[thesis-desk] %s: %s" (plist-get (car pair) :key) (error-message-string err))))))
    (message "%d reminders set" n)
    (thesis-desk-reminders)))

(provide 'thesis-desk-remind)
;;; thesis-desk-remind.el ends here
