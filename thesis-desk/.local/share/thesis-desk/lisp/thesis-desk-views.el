;;; thesis-desk-views.el --- Lists to come back from: where was I, what was rejected -*- lexical-binding: t; -*-

;;; Commentary:

;; Every list of thesis-desk is a report of sections of items, the data shape
;; of `sp-batch-report' (sections with :title and :items; items with :file,
;; :line, :label, :text, :key, :children).  When `sp-batch-report' is loaded
;; the lists open in its view, with its keys (RET, d, u, A, g, q); otherwise
;; they open as a read-only Org buffer with the same text.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'thesis-desk-dt)
(require 'thesis-desk-map)
(require 'thesis-desk-journal)

(declare-function sp-batch-report-open "sp-batch-report")
(declare-function sp-batch-report-text "sp-batch-report")

(defcustom thesis-desk-use-batch-report t
  "Non-nil shows the lists in `sp-batch-report' when it can be loaded."
  :type 'boolean :group 'thesis-desk)

;;;; Showing a report

(defun thesis-desk--item-org (item)
  "The Org list item of ITEM, for the fallback view."
  (concat "- "
          (if (plist-get item :file)
              (org-link-make-string
               (concat "file:" (plist-get item :file)
                       (and (plist-get item :line) (format "::%d" (plist-get item :line))))
               (or (plist-get item :label) (file-name-nondirectory (plist-get item :file))))
            (or (plist-get item :label) ""))
          (and (plist-get item :text) (concat "  " (plist-get item :text)))
          "\n"
          (mapconcat (lambda (c) (concat "  - " c "\n")) (plist-get item :children) "")))

(defun thesis-desk-report-org-text (title sections &optional intro)
  "The Org text of a report TITLE of SECTIONS with INTRO, for the fallback view."
  (concat "#+title: " title "\n\n"
          (and intro (concat intro "\n\n"))
          (mapconcat (lambda (section)
                       (let ((items (plist-get section :items)))
                         (concat "* " (plist-get section :title)
                                 (format " (%d)\n" (length items))
                                 (if items
                                     (mapconcat #'thesis-desk--item-org items "")
                                   (concat (or (plist-get section :empty) "none") "\n"))
                                 "\n")))
                     sections "")))

(cl-defun thesis-desk-report (name title sections &key intro refresh apply)
  "Show SECTIONS as the report NAME called TITLE, with INTRO.
REFRESH is what \\`g' runs; APPLY what \\`A' runs, with the dropped keys."
  (if (and thesis-desk-use-batch-report (require 'sp-batch-report nil t))
      (sp-batch-report-open name (sp-batch-report-text title sections :intro intro)
                            :refresh refresh :apply apply)
    (with-current-buffer (get-buffer-create name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (thesis-desk-report-org-text title sections intro))
        (org-mode)
        (goto-char (point-min)))
      (setq buffer-read-only t)
      (local-set-key "q" #'quit-window)
      (when refresh (local-set-key "g" (lambda () (interactive) (funcall refresh))))
      (pop-to-buffer (current-buffer))
      (current-buffer))))

;;;; Grouping sessions by claim

(defun thesis-desk-group-by-claim (sessions claims)
  "SESSIONS grouped by claim, in the order of CLAIMS, as (TITLE . SESSIONS).
A session with several claims is listed under each; one with none goes to
\"No claim\", which comes last."
  (let ((groups (make-hash-table :test #'equal))
        none)
    (dolist (s sessions)
      (if (plist-get s :claims)
          (dolist (id (plist-get s :claims))
            (puthash id (append (gethash id groups) (list s)) groups))
        (setq none (append none (list s)))))
    (let (result)
      (dolist (claim claims)
        (when-let* ((found (gethash (plist-get claim :id) groups)))
          (push (cons (plist-get claim :title) found) result)
          (remhash (plist-get claim :id) groups)))
      ;; Claims that no longer exist in any source keep their ID as title.
      (maphash (lambda (id found) (push (cons id found) result)) groups)
      (when none (push (cons "No claim" none) result))
      (nreverse result))))

(defun thesis-desk--session-link (s page)
  "An Org link that opens session S's record at PAGE, or nil without a UUID."
  (when (plist-get s :uuid)
    (funcall thesis-desk-record-link-function (plist-get s :uuid) page
             (if page (format "open at p. %d" page) "open"))))

;;;; Where was I

(defun thesis-desk-where-sections (sessions claims)
  "Report sections of the PAUSED SESSIONS, by claim of CLAIMS."
  (mapcar
   (lambda (group)
     (list :title (car group)
           :items (mapcar
                   (lambda (s)
                     (list :file (plist-get s :file) :line (plist-get s :line)
                           :label (or (plist-get s :key) (plist-get s :title))
                           :key (plist-get s :id)
                           :text (concat (or (plist-get s :next) "no next step")
                                         (and (plist-get s :purpose)
                                              (concat ". For: " (plist-get s :purpose))))
                           :children (delq nil
                                           (list (thesis-desk--session-link s (plist-get s :end-page))
                                                 (and (plist-get s :left)
                                                      (format "left: %s" (plist-get s :left)))))))
                   (cdr group))))
   (thesis-desk-group-by-claim sessions claims)))

;;;###autoload
(defun thesis-desk-where ()
  "List paused readings by claim, with where to resume and a link to the page."
  (interactive)
  (let ((sessions (thesis-desk-journal-sessions '("PAUSED")))
        (active (thesis-desk-journal-active)))
    (thesis-desk-report
     "*thesis-desk: where was I*" "Where was I"
     (thesis-desk-where-sections sessions (thesis-desk-claims))
     :intro (format "%d paused readings.%s" (length sessions)
                    (if active (format " Reading now: %s." (plist-get active :title)) ""))
     :refresh #'thesis-desk-where)))

;;;; What was rejected, and why

(defun thesis-desk-rejected-sections (sessions claims)
  "Report sections of the DROPPED SESSIONS, by claim of CLAIMS."
  (mapcar
   (lambda (group)
     (list :title (car group)
           :items (mapcar
                   (lambda (s)
                     (list :file (plist-get s :file) :line (plist-get s :line)
                           :label (or (plist-get s :key) (plist-get s :title))
                           :key (plist-get s :id)
                           :text (or (plist-get s :why) "no reason given")
                           :children (delq nil
                                           (list (and (plist-get s :purpose)
                                                      (concat "was looking for: " (plist-get s :purpose)))
                                                 (thesis-desk--session-link s (plist-get s :end-page))))))
                   (cdr group))))
   (thesis-desk-group-by-claim sessions claims)))

;;;###autoload
(defun thesis-desk-rejected ()
  "List the readings left as not relevant, with the reason, by claim."
  (interactive)
  (let ((sessions (thesis-desk-journal-sessions '("DROPPED"))))
    (thesis-desk-report
     "*thesis-desk: rejected*" "Rejected readings"
     (thesis-desk-rejected-sections sessions (thesis-desk-claims))
     :intro (format "%d readings left as not relevant." (length sessions))
     :refresh #'thesis-desk-rejected)))

(provide 'thesis-desk-views)
;;; thesis-desk-views.el ends here
