;;; sp-async-work.el --- Run long jobs in slices so Emacs stays usable -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-async-work-run' runs a job made of stages.  A stage is a list of items
;; and a function that handles one item.  Items are handled in slices of
;; `sp-async-work-slice' seconds, between your keystrokes, so Emacs stays
;; usable.  The progress is shown in the mode line; `sp-async-work-cancel'
;; stops a job.  See docs/tangles/funct/sp-async-work.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup sp-async-work nil
  "Run long jobs in slices so Emacs stays usable."
  :group 'convenience
  :prefix "sp-async-work-")

(defcustom sp-async-work-slice 0.05
  "Seconds a job works before it gives control back to Emacs."
  :type 'number
  :group 'sp-async-work)

(defcustom sp-async-work-pause 0.01
  "Seconds Emacs gets between two slices of a job."
  :type 'number
  :group 'sp-async-work)

(defvar sp-async-work-synchronous nil
  "When non-nil, `sp-async-work-run' runs the whole job before it returns.
The tests bind this; the commands behave as usual otherwise.")

(defvar sp-var-dir)

(defcustom sp-async-work-registry-directory nil
  "Folder where a running job keeps its status file, or nil for the default.
The default is batch-jobs/ in `sp-var-dir'.  The folder is shared by every
Emacs of the same configuration, so one Emacs can list and stop the jobs of
another, and so can the script tools/sp-batch-jobs."
  :type '(choice (const :tag "batch-jobs/ in the var folder" nil) directory)
  :group 'sp-async-work)

(defcustom sp-async-work-registry-interval 1.0
  "Seconds between two updates of the status file of a job.
The job looks for a cancel request at the same moment."
  :type 'number
  :group 'sp-async-work)

(defcustom sp-async-work-quit-cancels t
  "Whether two C-g in a row, outside the minibuffer, stop the running jobs.
A C-g that arrives while a slice runs always stops the job."
  :type 'boolean
  :group 'sp-async-work)

(cl-defstruct (sp-async-work-job (:constructor sp-async-work--make) (:copier nil))
  name          ; string, also the key of `sp-async-work-find'
  id            ; PID-NAME, names the status file of the job
  command       ; the command that started the job
  (started 0) (synced 0) ; float times: the start, the last status file write
  stages        ; stages not started yet
  current       ; (LABEL ITEMS-FUNCTION STEP-FUNCTION) of the running stage
  queue         ; items of the running stage still to handle
  (total 0) (done 0)
  timer
  (status 'running) ; running, finished, cancelled or failed
  finish error-function cleanup)

(defvar sp-async-work--jobs nil
  "The jobs that are running, newest first.")

(defun sp-async-work-find (name)
  "Return the running job called NAME, or nil."
  (seq-find (lambda (job) (equal (sp-async-work-job-name job) name))
            sp-async-work--jobs))

(defun sp-async-work-push (job item)
  "Add ITEM to the front of the items of the running stage of JOB.
A step uses this to handle a big item in several slices: handle a part of
it, then push the rest."
  (push item (sp-async-work-job-queue job))
  (cl-incf (sp-async-work-job-total job)))

(defun sp-async-work-on-cleanup (job function)
  "Call FUNCTION when JOB ends, however it ends."
  (push function (sp-async-work-job-cleanup job)))

(defun sp-async-work-registry-directory ()
  "The folder of the status files, see `sp-async-work-registry-directory'."
  (file-name-as-directory
   (or sp-async-work-registry-directory
       (expand-file-name "batch-jobs"
                         (if (boundp 'sp-var-dir) sp-var-dir user-emacs-directory)))))

(defun sp-async-work--file (id extension)
  "The file with EXTENSION that belongs to the job ID."
  (expand-file-name (concat id extension) (sp-async-work-registry-directory)))

(defun sp-async-work--slug (name)
  "NAME as lower-case words joined by dashes."
  (string-trim (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase name)) "-" "-"))

(defun sp-async-work--registry-write (job)
  "Write the status file of JOB.  An error is ignored: a job must not fail for it."
  (setf (sp-async-work-job-synced job) (float-time))
  (condition-case nil
      (let* ((file (sp-async-work--file (sp-async-work-job-id job) ".job"))
             (temp (concat file ".tmp"))
             (label (car (sp-async-work-job-current job))))
        (make-directory (file-name-directory file) t)
        (with-temp-file temp
          (dolist (pair `(("id" . ,(sp-async-work-job-id job))
                          ("pid" . ,(emacs-pid))
                          ("name" . ,(sp-async-work-job-name job))
                          ("command" . ,(or (sp-async-work-job-command job) ""))
                          ("stage" . ,(or label ""))
                          ("done" . ,(sp-async-work-job-done job))
                          ("total" . ,(sp-async-work-job-total job))
                          ("started" . ,(floor (sp-async-work-job-started job)))
                          ("updated" . ,(floor (float-time)))))
            (insert (car pair) "=" (replace-regexp-in-string "[\n\r]+" " " (format "%s" (cdr pair))) "\n")))
        (rename-file temp file t))
    (error nil)))

(defun sp-async-work--registry-remove (job)
  "Delete the status file and the cancel request of JOB."
  (dolist (extension '(".job" ".job.tmp" ".cancel"))
    (ignore-errors (delete-file (sp-async-work--file (sp-async-work-job-id job) extension)))))

(defun sp-async-work--sync (job)
  "Update the status file of JOB, and stop JOB when a cancel request is there.
Only once per `sp-async-work-registry-interval'."
  (when (and (not sp-async-work-synchronous)
             (>= (- (float-time) (sp-async-work-job-synced job))
                 sp-async-work-registry-interval))
    (if (ignore-errors (file-exists-p (sp-async-work--file (sp-async-work-job-id job) ".cancel")))
        (sp-async-work-cancel-job job "cancel request from outside")
      (sp-async-work--registry-write job))))

(defun sp-async-work--mode-line ()
  "The progress of the running jobs, for the mode line."
  (when sp-async-work--jobs
    (mapconcat
     (lambda (job)
       (let ((label (car (sp-async-work-job-current job))))
         (propertize
          (format " [%s%s %d/%d]" (sp-async-work-job-name job)
                  (if label (concat " " label) "")
                  (sp-async-work-job-done job) (sp-async-work-job-total job))
          'help-echo "C-g C-g or M-x sp-batch-cancel stops the job"
          'face 'mode-line-emphasis)))
     (reverse sp-async-work--jobs) "")))

(defvar sp-async-work--mode-line-entry '(:eval (sp-async-work--mode-line))
  "What `global-mode-string' holds for this library.")

(defun sp-async-work--show-in-mode-line ()
  "Make sure the progress of the jobs is in the mode line."
  (unless (listp global-mode-string)
    (setq global-mode-string (list global-mode-string)))
  (add-to-list 'global-mode-string 'sp-async-work--mode-line-entry t))

(defun sp-async-work--end (job status)
  "End JOB with STATUS: stop its timer, run its cleanups and forget it."
  (setf (sp-async-work-job-status job) status)
  (when (timerp (sp-async-work-job-timer job))
    (cancel-timer (sp-async-work-job-timer job)))
  (setf (sp-async-work-job-timer job) nil)
  (setq sp-async-work--jobs (delq job sp-async-work--jobs))
  (sp-async-work--registry-remove job)
  (dolist (function (sp-async-work-job-cleanup job))
    (ignore-errors (funcall function)))
  (setf (sp-async-work-job-cleanup job) nil)
  (force-mode-line-update t))

(defun sp-async-work--begin-stage (job)
  "Start the next stage of JOB."
  (let ((stage (pop (sp-async-work-job-stages job))))
    (setf (sp-async-work-job-current job) stage
          (sp-async-work-job-done job) 0
          (sp-async-work-job-queue job) (funcall (nth 1 stage)))
    (setf (sp-async-work-job-total job) (length (sp-async-work-job-queue job)))))

(defun sp-async-work--work (job synchronous)
  "Handle items of JOB: all of them when SYNCHRONOUS, else for one slice."
  (let ((deadline (+ (float-time) sp-async-work-slice))
        (first t))
    (while (and (eq (sp-async-work-job-status job) 'running)
                (or synchronous first
                    (and (< (float-time) deadline) (not (input-pending-p)))))
      (setq first nil)
      (cond ((sp-async-work-job-queue job)
             (let ((item (pop (sp-async-work-job-queue job))))
               (funcall (nth 2 (sp-async-work-job-current job)) item job)
               (cl-incf (sp-async-work-job-done job))))
            ((sp-async-work-job-stages job)
             (sp-async-work--begin-stage job))
            (t
             (sp-async-work--end job 'finished)
             (when (sp-async-work-job-finish job)
               (funcall (sp-async-work-job-finish job) job)))))))

(defun sp-async-work--fail (job err)
  "End JOB because of the error ERR."
  (sp-async-work--end job 'failed)
  (if (sp-async-work-job-error-function job)
      (funcall (sp-async-work-job-error-function job) err job)
    (message "%s stopped: %s" (sp-async-work-job-name job) (error-message-string err))))

(defun sp-async-work--schedule (job delay)
  "Run the next slice of JOB after DELAY seconds."
  (when (eq (sp-async-work-job-status job) 'running)
    (setf (sp-async-work-job-timer job)
          (run-with-timer delay nil #'sp-async-work--slice job))))

(defun sp-async-work--slice (job)
  "One slice of JOB, run by its timer."
  (setf (sp-async-work-job-timer job) nil)
  (sp-async-work--sync job)
  (when (eq (sp-async-work-job-status job) 'running)
    (if (> (minibuffer-depth) 0)
        (sp-async-work--schedule job 0.5)
      ;; Emacs runs timers with `inhibit-quit' set, so a C-g would wait until the
      ;; slice is over and then do nothing: let it through, and stop the job.
      (let ((inhibit-quit nil))
        (condition-case err
            (sp-async-work--work job nil)
          (quit (let ((inhibit-quit t)) (sp-async-work-cancel-job job "C-g")))
          (error (sp-async-work--fail job err))))
      (force-mode-line-update t)
      (sp-async-work--schedule job sp-async-work-pause))))

;;;###autoload
(cl-defun sp-async-work-run (name stages &key done on-error)
  "Run the job NAME made of STAGES, in slices; return the job.
Each stage is a list (LABEL ITEMS-FUNCTION STEP-FUNCTION).  When the stage
starts, ITEMS-FUNCTION is called with no arguments and returns the list of
items.  STEP-FUNCTION is called with an item and the job for every item,
and may add more with `sp-async-work-push'.  DONE is called with the job
after the last item of the last stage; ON-ERROR with the error and the job
when a step signals one.  A job of the same NAME that runs already is an
error.  With `sp-async-work-synchronous' the job is finished when this
returns."
  (when (sp-async-work-find name)
    (user-error "%s is still running; M-x sp-batch-cancel stops it" name))
  (let ((job (sp-async-work--make :name name :stages stages :finish done
                                  :error-function on-error
                                  :id (format "%d-%s" (emacs-pid) (sp-async-work--slug name))
                                  :command (and (symbolp this-command) this-command)
                                  :started (float-time))))
    (sp-async-work--show-in-mode-line)
    (push job sp-async-work--jobs)
    (unless sp-async-work-synchronous (sp-async-work--registry-write job))
    (if sp-async-work-synchronous
        (condition-case err
            (sp-async-work--work job t)
          (error (sp-async-work--end job 'failed)
                 (signal (car err) (cdr err))))
      (sp-async-work--schedule job 0))
    job))

(defun sp-async-work-registry-read (file)
  "The alist (KEY . VALUE) of the status file FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let (alist)
      (dolist (line (split-string (buffer-string) "\n" t))
        (when (string-match "\\`\\([a-z]+\\)=\\(.*\\)\\'" line)
          (push (cons (match-string 1 line) (match-string 2 line)) alist)))
      alist)))

(defun sp-async-work-registry-jobs ()
  "The status alists of the running jobs of all Emacs instances, oldest first.
The files of an Emacs that no longer exists are deleted."
  (let ((dir (sp-async-work-registry-directory)) jobs)
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\.job\\'"))
        (let* ((record (ignore-errors (sp-async-work-registry-read file)))
               (pid (string-to-number (or (cdr (assoc "pid" record)) "0"))))
          (if (and record (> pid 0)
                   (or (= pid (emacs-pid)) (process-attributes pid)))
              (push record jobs)
            (ignore-errors
              (delete-file file)
              (delete-file (concat (file-name-sans-extension file) ".cancel")))))))
    (sort jobs (lambda (a b)
                 (< (string-to-number (or (cdr (assoc "started" a)) "0"))
                    (string-to-number (or (cdr (assoc "started" b)) "0")))))))

(defun sp-async-work-request-cancel (id)
  "Stop the job ID, of this Emacs at once or of another by a cancel request."
  (if-let* ((job (seq-find (lambda (job) (equal (sp-async-work-job-id job) id))
                           sp-async-work--jobs)))
      (sp-async-work-cancel-job job "stopped from the job list")
    (let ((file (sp-async-work--file id ".cancel")))
      (make-directory (file-name-directory file) t)
      (write-region "" nil file nil 'silent)
      (message "Asked %s to stop; it looks within %s s" id sp-async-work-registry-interval))))

(defun sp-async-work--duration (seconds)
  "SECONDS as a short text such as 3m12s."
  (let ((seconds (max 0 (floor seconds))))
    (cond ((< seconds 60) (format "%ds" seconds))
          ((< seconds 3600) (format "%dm%02ds" (/ seconds 60) (% seconds 60)))
          (t (format "%dh%02dm" (/ seconds 3600) (/ (% seconds 3600) 60))))))

(defun sp-async-work--list-entries ()
  "The `tabulated-list-entries' of the jobs."
  (mapcar
   (lambda (record)
     (let ((field (lambda (key) (or (cdr (assoc key record)) ""))))
       (list (funcall field "id")
             (vector (funcall field "name")
                     (funcall field "command")
                     (funcall field "stage")
                     (format "%s/%s" (funcall field "done") (funcall field "total"))
                     (sp-async-work--duration
                      (- (float-time) (string-to-number (funcall field "started"))))
                     (concat (funcall field "pid")
                             (if (equal (funcall field "pid") (number-to-string (emacs-pid)))
                                 " this" ""))))))
   (sp-async-work-registry-jobs)))

(defun sp-async-work-jobs-cancel ()
  "Stop the job at point."
  (interactive)
  (let ((id (or (tabulated-list-get-id) (user-error "No job here"))))
    (sp-async-work-request-cancel id)
    (revert-buffer)))

(defvar-keymap sp-async-work-jobs-mode-map
  :doc "Keys of `sp-async-work-jobs-mode'."
  "k" #'sp-async-work-jobs-cancel)

(define-derived-mode sp-async-work-jobs-mode tabulated-list-mode "Batch-jobs"
  "List of the running batch jobs of all Emacs instances.
\\<sp-async-work-jobs-mode-map>\\[sp-async-work-jobs-cancel] stops the job at point, \\[revert-buffer] refreshes."
  (setq tabulated-list-format [("Job" 26 t) ("Command" 26 t) ("Stage" 14 t)
                               ("Progress" 10 nil) ("Running" 9 nil) ("Emacs" 10 t)]
        tabulated-list-padding 1)
  (add-hook 'tabulated-list-revert-hook
            (lambda () (setq tabulated-list-entries (sp-async-work--list-entries)))
            nil t)
  (tabulated-list-init-header))

;;;###autoload
(defun sp-async-work-list-jobs ()
  "List the running batch jobs of all Emacs instances; k stops one."
  (interactive)
  (with-current-buffer (get-buffer-create "*Batch jobs*")
    (sp-async-work-jobs-mode)
    (setq tabulated-list-entries (sp-async-work--list-entries))
    (tabulated-list-print)
    (pop-to-buffer (current-buffer))))

;;;###autoload
(defalias 'sp-batch-list-jobs #'sp-async-work-list-jobs
  "List the running batch jobs of all Emacs instances.")

(defun sp-async-work-cancel-job (job &optional reason)
  "Stop JOB.  What it already did stays done.  REASON is added to the message."
  (when (eq (sp-async-work-job-status job) 'running)
    (sp-async-work--end job 'cancelled)
    (message "%s cancelled after %d of %d%s" (sp-async-work-job-name job)
             (sp-async-work-job-done job) (sp-async-work-job-total job)
             (if reason (format " (%s)" reason) ""))))

;;;###autoload
(defun sp-async-work-cancel ()
  "Stop a running job, asking which when there are several."
  (interactive)
  (let ((jobs sp-async-work--jobs))
    (cond ((null jobs) (message "No job is running"))
          ((null (cdr jobs)) (sp-async-work-cancel-job (car jobs)))
          (t (sp-async-work-cancel-job
              (sp-async-work-find
               (completing-read "Stop: " (mapcar #'sp-async-work-job-name jobs) nil t)))))))

(defun sp-async-work-cancel-all ()
  "Stop every running job of this Emacs."
  (interactive)
  (if sp-async-work--jobs
      (dolist (job (copy-sequence sp-async-work--jobs))
        (sp-async-work-cancel-job job))
    (message "No job is running")))

(defun sp-async-work--keyboard-quit ()
  "Stop the jobs on the second of two C-g in a row, see `sp-async-work-quit-cancels'.
Runs before `keyboard-quit'."
  (when (and sp-async-work-quit-cancels sp-async-work--jobs
             (eq last-command 'keyboard-quit)
             (zerop (minibuffer-depth)))
    (sp-async-work-cancel-all)))

(advice-add 'keyboard-quit :before #'sp-async-work--keyboard-quit)

;;;###autoload
(defalias 'sp-batch-cancel #'sp-async-work-cancel
  "Stop a running batch job of this Emacs.")

(defun sp-async-work-wait (job &optional timeout)
  "Wait until JOB has ended, for at most TIMEOUT seconds (default 30).
Meant for scripts and tests that start a job without
`sp-async-work-synchronous'.  Return the status of the job."
  (let ((limit (+ (float-time) (or timeout 30))))
    (while (and (eq (sp-async-work-job-status job) 'running)
                (< (float-time) limit))
      (sit-for 0.02))
    (sp-async-work-job-status job)))

(provide 'sp-async-work)
;;; sp-async-work.el ends here
