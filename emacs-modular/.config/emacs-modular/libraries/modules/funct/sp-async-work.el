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

(cl-defstruct (sp-async-work-job (:constructor sp-async-work--make) (:copier nil))
  name          ; string, also the key of `sp-async-work-find'
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
          'help-echo "M-x sp-async-work-cancel stops the job"
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
  (when (eq (sp-async-work-job-status job) 'running)
    (if (> (minibuffer-depth) 0)
        (sp-async-work--schedule job 0.5)
      (condition-case err
          (sp-async-work--work job nil)
        (error (sp-async-work--fail job err)))
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
    (user-error "%s is still running; M-x sp-async-work-cancel stops it" name))
  (let ((job (sp-async-work--make :name name :stages stages :finish done
                                  :error-function on-error)))
    (sp-async-work--show-in-mode-line)
    (push job sp-async-work--jobs)
    (if sp-async-work-synchronous
        (condition-case err
            (sp-async-work--work job t)
          (error (sp-async-work--end job 'failed)
                 (signal (car err) (cdr err))))
      (sp-async-work--schedule job 0))
    job))

(defun sp-async-work-cancel-job (job)
  "Stop JOB.  What it already did stays done."
  (when (eq (sp-async-work-job-status job) 'running)
    (sp-async-work--end job 'cancelled)
    (message "%s cancelled after %d of %d" (sp-async-work-job-name job)
             (sp-async-work-job-done job) (sp-async-work-job-total job))))

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
