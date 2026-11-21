;;; thesis-desk-journal.el --- Reading sessions: why you opened it, why you left -*- lexical-binding: t; -*-

;;; Commentary:

;; One session per stretch of reading, in a date tree of `journal.org':
;;
;;   READING  started, not left yet (at most one at a time)
;;   PAUSED   left with something still to do: has :NEXT:
;;   DONE     found what it was opened for
;;   DROPPED  not relevant: has :WHY_NOT:, and the record gets one star
;;   RESUMED  a paused session that a later session took over
;;
;; `thesis-desk-start' asks which claims the reading is for (any number, or
;; none) and what you want from it.  `thesis-desk-switch' asks why you left,
;; what the text did for each claim, and where to resume.  The functions with
;; two dashes do the writing without asking, so they can be tested.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)
(require 'org-datetree)
(require 'org-clock)
(require 'thesis-desk-dt)
(require 'thesis-desk-map)

(declare-function thesis-desk-file "thesis-desk")
(defvar thesis-desk-journal-file)

(defcustom thesis-desk-leave-reasons
  '((?f found "found what I needed" "DONE")
    (?c citation "followed a citation" "PAUSED")
    (?d dense "too dense, need background first" "PAUSED")
    (?l later "relevant later (another section)" "PAUSED")
    (?i interrupted "interrupted" "PAUSED")
    (?n not-relevant "not relevant (say why)" "DROPPED"))
  "Why a reading was left: (KEY SYMBOL DESCRIPTION STATE).
STATE is the TODO state the session takes.  A DROPPED reason asks why and
rates the record `thesis-desk-not-relevant-rating'."
  :type '(repeat (list character symbol string string)) :group 'thesis-desk)

(defcustom thesis-desk-verdicts
  '((?s supports "supports") (?o opposes "opposes") (?b background "background")
    (?x irrelevant "irrelevant here") (?? unsure "unsure"))
  "What a text did for one claim: (KEY SYMBOL DESCRIPTION)."
  :type '(repeat (list character symbol string)) :group 'thesis-desk)

(defcustom thesis-desk-not-relevant-rating 1
  "Rating given in DEVONthink to a record left as not relevant; nil sets none."
  :type '(choice (const nil) integer) :group 'thesis-desk)

(defcustom thesis-desk-clock t
  "Non-nil clocks into a session while it is READING."
  :type 'boolean :group 'thesis-desk)

(defconst thesis-desk-journal--header
  "#+title: Reading journal
#+todo: READING PAUSED | DONE DROPPED RESUMED
#+startup: overview

"
  "Contents of a new journal file.")

(defvar thesis-desk--came-from nil
  "ID of the session left by following a citation, for the next start.")

;;;; The file

(defun thesis-desk-journal-path ()
  "The journal file."
  (thesis-desk-file thesis-desk-journal-file))

(defun thesis-desk-journal--buffer ()
  "The journal buffer, creating the file when missing."
  (let ((file (thesis-desk-journal-path)))
    (unless (file-exists-p file)
      (make-directory (file-name-directory file) t)
      (with-temp-file file (insert thesis-desk-journal--header)))
    (let ((buffer (find-file-noselect file)))
      (with-current-buffer buffer
        (unless (derived-mode-p 'org-mode) (org-mode)))
      buffer)))

;;;###autoload
(defun thesis-desk-journal-visit ()
  "Open the reading journal."
  (interactive)
  (pop-to-buffer-same-window (thesis-desk-journal--buffer)))

;;;; Reading sessions back

(defun thesis-desk--verdicts-parse (string)
  "Parse \"ID=verdict ID=verdict\" into an alist of (ID . SYMBOL)."
  (delq nil (mapcar (lambda (pair)
                      (when (string-match "\\`\\(.+\\)=\\([^=]+\\)\\'" pair)
                        (cons (match-string 1 pair) (intern (match-string 2 pair)))))
                    (split-string (or string "") "[ \t]+" t))))

(defun thesis-desk--verdicts-format (alist)
  "ALIST of (ID . SYMBOL) as the :VERDICTS: string."
  (mapconcat (lambda (cell) (format "%s=%s" (car cell) (cdr cell))) alist " "))

(defun thesis-desk--number (string)
  "STRING as a number, or nil."
  (and string (string-match-p "\\`[0-9]+\\'" string) (string-to-number string)))

(defun thesis-desk-journal--session-at-point ()
  "The session at point as a plist, or nil when the heading is not one."
  (let ((uuid (org-entry-get (point) "DT_UUID"))
        (key (org-entry-get (point) "CITEKEY")))
    (when (or uuid key)
      (list :id (org-entry-get (point) "ID")
            :state (org-get-todo-state)
            :title (org-get-heading t t t t)
            :key key
            :uuid uuid
            :claims (org-entry-get-multivalued-property (point) "CLAIMS")
            :purpose (org-entry-get (point) "PURPOSE")
            :start-page (thesis-desk--number (org-entry-get (point) "START_PAGE"))
            :end-page (thesis-desk--number (org-entry-get (point) "END_PAGE"))
            :left (let ((v (org-entry-get (point) "LEFT"))) (and v (intern v)))
            :verdicts (thesis-desk--verdicts-parse (org-entry-get (point) "VERDICTS"))
            :why (org-entry-get (point) "WHY_NOT")
            :next (org-entry-get (point) "NEXT")
            :came-from (org-entry-get (point) "CAME_FROM")
            :started (org-entry-get (point) "STARTED")
            :file (buffer-file-name)
            :pos (point)
            :line (line-number-at-pos (point) t)))))

(defun thesis-desk-journal-sessions (&optional states)
  "Every session of the journal, oldest first; only STATES (strings) when given."
  (with-current-buffer (thesis-desk-journal--buffer)
    (let (sessions)
      (org-with-wide-buffer
       (goto-char (point-min))
       (while (re-search-forward org-heading-regexp nil t)
         (save-excursion
           (beginning-of-line)
           (when-let* ((s (thesis-desk-journal--session-at-point)))
             (when (or (null states) (member (plist-get s :state) states))
               (push s sessions))))))
      (nreverse sessions))))

(defun thesis-desk-journal-active ()
  "The session now READING, or nil."
  (car (last (thesis-desk-journal-sessions '("READING")))))

(defun thesis-desk-journal--goto (id)
  "Move point in the journal buffer to session ID; error when missing."
  (goto-char (point-min))
  (unless (re-search-forward
           (format "^[ \t]*:ID:[ \t]+%s[ \t]*$" (regexp-quote id)) nil t)
    (error "No session %s in the journal" id))
  (org-back-to-heading t))

(defun thesis-desk--session-title (key purpose)
  "Heading text for a session on KEY with PURPOSE."
  (let ((purpose (string-trim (or purpose ""))))
    (if (string-empty-p purpose)
        key
      (format "%s: %s" key (truncate-string-to-width purpose 70 nil nil "…")))))

;;;; Writing sessions

(cl-defun thesis-desk-journal--create (record claims purpose
                                              &key came-from resumes time)
  "Write a READING session for RECORD (a front-record plist).
CLAIMS is a list of IDs, PURPOSE a string.  CAME-FROM and RESUMES are
session IDs.  TIME (a Lisp time) defaults to now.  Return the new ID."
  (let ((time (or time (current-time)))
        (key (or (plist-get record :key) (plist-get record :name) "?")))
    (with-current-buffer (thesis-desk-journal--buffer)
      (org-with-wide-buffer
       (let ((date (decode-time time)))
         (org-datetree-find-date-create
          (list (decoded-time-month date) (decoded-time-day date)
                (decoded-time-year date))))
       (let ((level (1+ (org-current-level))))
         (org-end-of-subtree t t)
         (unless (bolp) (insert "\n"))
         (insert (make-string level ?*) " READING "
                 (thesis-desk--session-title key purpose) "\n")
         (forward-line -1)
         (let ((id (org-id-get-create)))
           (org-entry-put (point) "STARTED"
                          (format-time-string (org-time-stamp-format t t) time))
           (when (plist-get record :key) (org-entry-put (point) "CITEKEY" (plist-get record :key)))
           (when (plist-get record :uuid) (org-entry-put (point) "DT_UUID" (plist-get record :uuid)))
           (when claims (apply #'org-entry-put-multivalued-property (point) "CLAIMS" claims))
           (unless (string-empty-p (string-trim (or purpose "")))
             (org-entry-put (point) "PURPOSE" (string-trim purpose)))
           (when (plist-get record :page)
             (org-entry-put (point) "START_PAGE" (number-to-string (plist-get record :page))))
           (when came-from
             (org-entry-put (point) "CAME_FROM" (org-link-make-string (concat "id:" came-from) "came from")))
           (when resumes
             (org-entry-put (point) "RESUMES" (org-link-make-string (concat "id:" resumes) "resumes"))
             (save-excursion
               (thesis-desk-journal--goto resumes)
               (org-todo "RESUMED")))
           (when thesis-desk-clock
             (save-excursion (org-clock-in)))
           (save-buffer)
           id))))))

(cl-defun thesis-desk-journal--close (id &key reason page verdicts why next note)
  "Leave session ID for REASON (a symbol of `thesis-desk-leave-reasons').
PAGE is where you stopped, VERDICTS an alist (CLAIM-ID . SYMBOL), WHY the
reason a text was not relevant, NEXT what to do on return, NOTE free text.
Return the new state."
  (let* ((entry (or (seq-find (lambda (r) (eq (nth 1 r) reason)) thesis-desk-leave-reasons)
                    (error "Unknown reason %s" reason)))
         (state (nth 3 entry)))
    (when (and (equal state "DROPPED") (string-empty-p (string-trim (or why ""))))
      (user-error "Say why it is not relevant: the reason is kept with the record"))
    (with-current-buffer (thesis-desk-journal--buffer)
      (org-with-wide-buffer
       (thesis-desk-journal--goto id)
       (when (and (org-clocking-p)
                  (equal (marker-buffer org-clock-marker) (current-buffer))
                  (save-excursion
                    (goto-char org-clock-marker)
                    (org-back-to-heading t)
                    (equal (org-entry-get (point) "ID") id)))
         (org-clock-out nil t))
       (org-entry-put (point) "LEFT" (symbol-name reason))
       (org-entry-put (point) "LEFT_AT"
                      (format-time-string (org-time-stamp-format t t)))
       (when page (org-entry-put (point) "END_PAGE" (number-to-string page)))
       (when verdicts (org-entry-put (point) "VERDICTS" (thesis-desk--verdicts-format verdicts)))
       (unless (string-empty-p (string-trim (or why "")))
         (org-entry-put (point) "WHY_NOT" (string-trim why)))
       (unless (string-empty-p (string-trim (or next "")))
         (org-entry-put (point) "NEXT" (string-trim next)))
       (let ((org-log-done nil) (org-todo-log-states nil))
         (org-todo state))
       (unless (string-empty-p (string-trim (or note "")))
         (save-excursion
           (org-end-of-subtree t t)
           (unless (bolp) (insert "\n"))
           (insert (format-time-string (org-time-stamp-format t t)) " " (string-trim note) "\n")))
       (save-buffer)))
    state))

;;;; Commands

(defun thesis-desk--record-or-ask ()
  "The record DEVONthink shows, or one typed by hand."
  (or (thesis-desk-front-record)
      (let ((key (read-string "DEVONthink did not answer; citekey or name: ")))
        (when (string-empty-p key) (user-error "No record"))
        (list :key key :name key))))

(defun thesis-desk--latest-paused (uuid key)
  "The most recent PAUSED session of the record UUID (or KEY), or nil."
  (car (last (seq-filter (lambda (s)
                           (if uuid
                               (equal (plist-get s :uuid) uuid)
                             (equal (plist-get s :key) key)))
                         (thesis-desk-journal-sessions '("PAUSED"))))))

;;;###autoload
(defun thesis-desk-start (&optional record)
  "Start a reading session on RECORD, by default what DEVONthink shows.
A session still READING on another record is left first (you are asked
why).  A paused session of the same record is offered for resuming."
  (interactive)
  (let* ((record (or record (thesis-desk--record-or-ask)))
         (active (thesis-desk-journal-active)))
    (when active
      (if (and (plist-get record :uuid)
               (equal (plist-get active :uuid) (plist-get record :uuid)))
          (user-error "Already reading %s" (plist-get active :title))
        (message "Leaving %s first" (plist-get active :title))
        (thesis-desk-switch t)))
    (let* ((paused (thesis-desk--latest-paused (plist-get record :uuid) (plist-get record :key)))
           (resume (and paused
                        (y-or-n-p (format "Resume \"%s\" (next: %s)? "
                                          (or (plist-get paused :purpose) (plist-get paused :title))
                                          (or (plist-get paused :next) "-")))))
           (claims (thesis-desk-read-claims
                    (format "Claims %s is for (empty for none): "
                            (or (plist-get record :key) (plist-get record :name)))
                    (and resume (plist-get paused :claims))))
           (purpose (read-string "What are you looking for? "
                                 (and resume (plist-get paused :purpose))))
           (id (thesis-desk-journal--create
                record claims purpose
                :came-from (prog1 thesis-desk--came-from (setq thesis-desk--came-from nil))
                :resumes (and resume (plist-get paused :id)))))
      (message "Reading %s%s" (or (plist-get record :key) (plist-get record :name))
               (if resume (format ", resume at: %s" (plist-get paused :next)) ""))
      id)))

(defun thesis-desk--read-choice (prompt choices)
  "Ask PROMPT with CHOICES of (KEY SYMBOL DESCRIPTION ...); return the SYMBOL."
  (let ((answer (read-multiple-choice
                 prompt (mapcar (lambda (c) (list (nth 0 c) (nth 2 c))) choices))))
    (nth 1 (assq (car answer) choices))))

;;;###autoload
(defun thesis-desk-switch (&optional no-follow)
  "Leave the session now READING: why, what it did for each claim, what next.
With NO-FOLLOW (as when `thesis-desk-start' leaves a session for you), do
not offer to start the next session after a followed citation."
  (interactive)
  (let* ((session (or (thesis-desk-journal-active)
                      (user-error "No reading session is open")))
         (front (thesis-desk-front-record))
         (page (or (and front (equal (plist-get front :uuid) (plist-get session :uuid))
                        (plist-get front :page))
                   (thesis-desk--number (read-string "Stopped at page (empty if unknown): ")))))
    (let* ((reason (thesis-desk--read-choice
                    (format "Leaving %s, why? " (plist-get session :title))
                    thesis-desk-leave-reasons))
           (dropped (equal (nth 3 (seq-find (lambda (r) (eq (nth 1 r) reason))
                                            thesis-desk-leave-reasons))
                           "DROPPED"))
           (why (when dropped
                  (let ((answer ""))
                    (while (string-empty-p (string-trim answer))
                      (setq answer (read-string "Why is it not relevant? ")))
                    answer)))
           (claims (plist-get session :claims))
           (titles (and claims (thesis-desk-claims)))
           (verdicts
            (if dropped
                (mapcar (lambda (id) (cons id 'irrelevant)) claims)
              (mapcar (lambda (id)
                        (cons id (thesis-desk--read-choice
                                  (format "For \"%s\": " (thesis-desk-claim-title id titles))
                                  thesis-desk-verdicts)))
                      claims)))
           (next (when (and (not dropped) (not (eq reason 'found)))
                   (read-string "Next time: " (and page (format "resume at p. %d" page)))))
           (note (read-string "A note (optional): ")))
      (thesis-desk-journal--close (plist-get session :id)
                                  :reason reason :page page :verdicts verdicts
                                  :why why :next next :note note)
      (when (and dropped thesis-desk-not-relevant-rating (plist-get session :uuid))
        (condition-case err
            (funcall thesis-desk-set-rating-function
                     (plist-get session :uuid) thesis-desk-not-relevant-rating)
          (error (message "[thesis-desk] rating not set: %s" (error-message-string err)))))
      (when (eq reason 'citation)
        (setq thesis-desk--came-from (plist-get session :id))
        (unless no-follow
          (when (y-or-n-p "Open the cited text in DEVONthink, then start it now? ")
            (thesis-desk-start))))
      reason)))

(provide 'thesis-desk-journal)
;;; thesis-desk-journal.el ends here
