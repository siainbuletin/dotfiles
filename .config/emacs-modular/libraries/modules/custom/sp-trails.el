;;; sp-trails.el --- Branching browsing trails tied to org questions -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Browser --org-protocol--> a tree of pages under a "trail" heading in
;; `sp-trails-file'.  Each trail belongs to a QUESTION declared somewhere
;; in your notes.  A page opened by following a link from another page
;; becomes that page's child, so the outline is the branching history.
;;
;; org-edna enforces the workflow:
;;   - a trail can only become ARCHIVED once every page in it is READ or
;;     PRUNED (BLOCKER: descendants);
;;   - archiving a trail sets its question to REVIEW, scheduled today
;;     (TRIGGER: ids(...) todo!(REVIEW) scheduled!("."));
;;   - a question can only become ANSWERED once none of its trails are
;;     still open (BLOCKER: match("QUESTION={id}" agenda)).
;;
;; Keywords expected (in `org-todo-keywords', or #+todo lines per file):
;;   QUESTION(q) REVIEW(v) | ANSWERED(n) DROPPED(x)
;;   ACTIVE(a) PARKED(k) | ARCHIVED(A)
;;   TOREAD(r) | READ(d) PRUNED(p)
;;
;; `sp-trails-file' must be in `org-agenda-files' for the question
;; blocker to see the trails, and `org-edna-mode' must be on.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-parse)
(require 'org)
(require 'org-id)
(require 'org-attach)
(require 'org-protocol)
(require 'org-ql)

(defgroup sp-trails nil
  "Branching browsing trails tied to org questions."
  :group 'org)

(defcustom sp-trails-file (expand-file-name "trails.org" org-directory)
  "Org file holding the trails."
  :type 'file
  :group 'spcustom)

(defcustom sp-trails-question-files nil
  "Files searched for QUESTION headings.  nil means `org-agenda-files'."
  :type '(repeat file)
  :group 'spcustom)

(defcustom sp-trails-quote-block "quote"
  "Block type wrapping text selected in the browser."
  :type 'string
  :group 'spcustom)

(defcustom sp-trails-monolith-program "monolith"
  "Program used by `sp-trails-snapshot' to save a page as one HTML file."
  :type 'string
  :group 'spcustom)

;; Moved to `sp-globals': `sp-trails-chrome-history', the Chromium-family
;; History database read by `sp-trails-import-chrome'.

(defvar sp-trails-current nil
  "ID of the trail that receives captured pages.")

;;;; URLs

(defun sp-trails--normalize (url)
  "Return URL without its fragment or trailing slash, or nil if empty."
  (when (and url (not (string-blank-p url)))
    (let ((u (replace-regexp-in-string "#.*\\'" "" (string-trim url))))
      (replace-regexp-in-string "\\([^/]\\)/\\'" "\\1" u))))

(defun sp-trails--origin-only-p (url)
  "Non-nil if URL has no path, as browsers send cross-site referrers."
  (member (url-filename (url-generic-parse-url url)) '("" "/")))

(defun sp-trails--origin (url)
  "Scheme and host of URL."
  (let ((u (url-generic-parse-url url)))
    (format "%s://%s" (url-type u) (url-host u))))

(defun sp-trails--clean-title (title)
  "Make TITLE safe as a link description."
  (replace-regexp-in-string "\\]" ")" (replace-regexp-in-string "\\[" "(" title)))

;;;; Finding things in the current trail

(defun sp-trails--trail-marker ()
  "Marker to the current trail heading."
  (or (and sp-trails-current (org-id-find sp-trails-current 'marker))
      (user-error "No current trail; run `sp-trails-resume-or-start'")))

(defun sp-trails--find-node (pred)
  "Marker to the page in the current trail that PRED likes best.
PRED runs at each heading and returns nil or a string key; the
greatest key wins (keys are VISITED timestamps, so latest wins)."
  (let ((trail (sp-trails--trail-marker)) best best-key)
    (with-current-buffer (marker-buffer trail)
      (org-with-wide-buffer
       (goto-char trail)
       (org-map-entries
        (lambda ()
          (when-let* ((key (funcall pred)))
            (when (or (null best-key) (string> key best-key))
              (setq best (point-marker) best-key key))))
        nil 'tree)))
    best))

(defun sp-trails--find-url (url)
  "Page node in the current trail whose URL is URL."
  (sp-trails--find-node
   (lambda ()
     (and (equal (org-entry-get nil "URL") url)
          (or (org-entry-get nil "VISITED") "")))))

(defun sp-trails--find-origin (origin)
  "Most recently visited page node in the current trail on ORIGIN."
  (sp-trails--find-node
   (lambda ()
     (let ((u (org-entry-get nil "URL")))
       (and u (string-prefix-p origin u)
            (or (org-entry-get nil "VISITED") ""))))))

(defun sp-trails--parent-for (ref)
  "Node a page reached from referrer REF should hang under.
Exact match on REF first; if the browser only sent an origin, the
latest page on that site; otherwise the trail itself (a new branch)."
  (or (and ref (not (string-blank-p ref))
           (if (sp-trails--origin-only-p ref)
               (sp-trails--find-origin (sp-trails--origin ref))
             (sp-trails--find-url (sp-trails--normalize ref))))
      (sp-trails--trail-marker)))

;;;; Writing pages

(defun sp-trails--insert-child (parent text)
  "Insert heading TEXT as the last child of PARENT; return a marker to it."
  (with-current-buffer (marker-buffer parent)
    (org-with-wide-buffer
     (goto-char parent)
     (let ((level (1+ (org-current-level))))
       (org-end-of-subtree t t)
       (unless (bolp) (insert "\n"))
       (insert (make-string level ?*) " " text "\n")
       (forward-line -1)
       (point-marker)))))

(defun sp-trails--add-quote (marker text)
  "Append TEXT in a quote block to the body of the entry at MARKER."
  (org-with-point-at marker
    (org-with-wide-buffer
     (goto-char (org-entry-end-position))
     (unless (bolp) (insert "\n"))
     (insert (format "#+begin_%s\n%s\n#+end_%s\n"
                     sp-trails-quote-block
                     (replace-regexp-in-string "^\\*" " *" (string-trim text))
                     sp-trails-quote-block)))))

(defun sp-trails-add-page (url title &optional ref body)
  "Add URL (TITLE) to the current trail under the page REF linked from.
BODY, if non-blank, is stored as a quote.  Revisiting a page updates
its VISITED time instead of duplicating it.  Returns the node marker."
  (let* ((url (sp-trails--normalize url))
         (title (if (string-blank-p (or title "")) url title))
         (node (or (sp-trails--find-url url)
                   (let ((m (sp-trails--insert-child
                             (sp-trails--parent-for ref)
                             (concat "TOREAD "
                                     (org-link-make-string
                                      url (sp-trails--clean-title title))))))
                     (org-with-point-at m
                       (org-id-get-create)
                       (org-entry-put nil "URL" url)
                       (when (and ref (not (string-blank-p ref)))
                         (org-entry-put nil "REFERRER" ref)))
                     m))))
    (org-with-point-at node
      (org-entry-put nil "VISITED" (format-time-string (org-time-stamp-format t t))))
    (when (and body (not (string-blank-p body)))
      (sp-trails--add-quote node body))
    (with-current-buffer (marker-buffer node) (save-buffer))
    node))

;;;; org-protocol

(defun sp-trails-protocol (info)
  "Handle org-protocol://sp-trail?url=…&title=…&ref=…&body=…"
  (let ((url (plist-get info :url)))
    (unless url (user-error "sp-trail: no url"))
    (unless sp-trails-current
      (raise-frame)
      (call-interactively #'sp-trails-resume-or-start))
    (sp-trails-add-page url (plist-get info :title)
                        (plist-get info :ref) (plist-get info :body))
    (message "Trail ← %s" (or (plist-get info :title) url))
    nil))

(add-to-list 'org-protocol-protocol-alist
             '("sp-trail" :protocol "sp-trail"
               :function sp-trails-protocol :kill-client t))

;;;; Questions

(defun sp-trails--question-files ()
  (or sp-trails-question-files (org-agenda-files)))

(defun sp-trails--questions (&optional states)
  "Questions in STATES (default QUESTION and REVIEW) as plists."
  (org-ql-select (sp-trails--question-files)
    `(todo ,@(or states '("QUESTION" "REVIEW")))
    :action (lambda ()
              (list :id (org-id-get-create)
                    :state (org-get-todo-state)
                    :heading (org-get-heading t t t t)
                    :file (buffer-file-name)))))

(defun sp-trails-read-question ()
  "Pick an open question and return its ID."
  (let ((cands (mapcar (lambda (q)
                         (cons (format "%-8s %s  (%s)"
                                       (plist-get q :state)
                                       (plist-get q :heading)
                                       (file-name-base (plist-get q :file)))
                               (plist-get q :id)))
                       (sp-trails--questions))))
    (unless cands
      (user-error "No open questions; declare one with `sp-trails-declare-question'"))
    (cdr (assoc (completing-read "Question: " cands nil t) cands))))

(defun sp-trails-declare-question ()
  "Make the heading at point a QUESTION that can't be ANSWERED while trails are open."
  (interactive)
  (org-back-to-heading t)
  (let ((id (org-id-get-create)))
    (org-todo "QUESTION")
    (org-entry-put nil "BLOCKER" (format "match(\"QUESTION={%s}\" agenda)" id))
    id))

;;;; Trails

(defun sp-trails-start (question title)
  "Start a trail named TITLE for QUESTION (an ID) and make it current."
  (interactive (list (sp-trails-read-question) (read-string "Trail name: ")))
  (with-current-buffer (find-file-noselect sp-trails-file)
    (org-with-wide-buffer
     (goto-char (point-max))
     (unless (bolp) (insert "\n"))
     (insert "* ACTIVE " title " :trail:\n")
     (forward-line -1)
     (let ((id (org-id-get-create)))
       (org-entry-put nil "QUESTION" question)
       (org-entry-put nil "STARTED" (format-time-string (org-time-stamp-format t t)))
       (org-entry-put nil "BLOCKER" "descendants")
       (org-entry-put nil "TRIGGER"
                      (format "ids(%s) todo!(REVIEW) scheduled!(\".\")" question))
       (save-buffer)
       (setq sp-trails-current id)
       (message "Trail started: %s" title)
       id))))

(defun sp-trails--open-trails ()
  (org-ql-select sp-trails-file
    '(and (tags "trail") (todo "ACTIVE" "PARKED"))
    :action (lambda ()
              (cons (format "%-7s %s" (org-get-todo-state) (org-get-heading t t t t))
                    (org-id-get-create)))))

(defun sp-trails-resume-or-start ()
  "Pick an open trail to make current, or start a new one."
  (interactive)
  (let* ((new "[new trail]")
         (cands (sp-trails--open-trails))
         (choice (completing-read "Trail: " (cons new (mapcar #'car cands)) nil t)))
    (if (equal choice new)
        (call-interactively #'sp-trails-start)
      (let ((id (cdr (assoc choice cands))))
        (org-with-point-at (org-id-find id 'marker)
          (org-todo "ACTIVE")
          (save-buffer))
        (setq sp-trails-current id)))))

(defun sp-trails-park ()
  "Park the current trail; captures will ask for a trail again."
  (interactive)
  (org-with-point-at (sp-trails--trail-marker)
    (org-todo "PARKED")
    (save-buffer))
  (setq sp-trails-current nil))

(defun sp-trails-archive ()
  "Archive the current trail.  org-edna refuses while pages are TOREAD;
on success the trail's question goes to REVIEW."
  (interactive)
  (org-with-point-at (sp-trails--trail-marker)
    (org-todo "ARCHIVED")
    (if (not (equal (org-get-todo-state) "ARCHIVED"))
        (message "Blocked: mark the remaining TOREAD pages READ or PRUNED first")
      (save-buffer)
      (setq sp-trails-current nil))))

(defun sp-trails-goto ()
  "Jump to the current trail."
  (interactive)
  (org-id-goto (or sp-trails-current (user-error "No current trail"))))

(defun sp-trails-prune ()
  "Mark the page at point and every branch under it PRUNED."
  (interactive)
  (org-back-to-heading t)
  (when (member "trail" (org-get-tags nil t))
    (user-error "That's the trail itself; use `sp-trails-archive'"))
  (org-map-entries (lambda () (unless (org-entry-is-done-p) (org-todo "PRUNED")))
                   nil 'tree))

(defun sp-trails-snapshot ()
  "Save the page at point as a single HTML file in its attachment dir."
  (interactive)
  (let* ((url (or (org-entry-get nil "URL") (user-error "No URL on this heading")))
         (dir (org-attach-dir t))
         (file (expand-file-name (format-time-string "%Y%m%dT%H%M%S.html") dir))
         (marker (point-marker)))
    (make-process
     :name "sp-trails-monolith"
     :buffer " *sp-trails-monolith*"
     :command (list sp-trails-monolith-program url "-o" file)
     :sentinel (lambda (proc _event)
                 (when (memq (process-status proc) '(exit signal))
                   (if (zerop (process-exit-status proc))
                       (org-with-point-at marker
                         (org-entry-put nil "SNAPSHOT"
                                        (format "[[attachment:%s]]" (file-name-nondirectory file)))
                         (save-buffer)
                         (message "Snapshot saved"))
                     (message "Snapshot failed; see *sp-trails-monolith*")))))))

;;;; Dashboard

(defun sp-trails--trail-summaries (question-id)
  (org-ql-select sp-trails-file
    `(and (tags "trail") (property "QUESTION" ,question-id))
    :action (lambda ()
              (let ((all 0) (open 0))
                (save-excursion
                  (org-map-entries
                   (lambda ()
                     (when (org-entry-get nil "URL")
                       (cl-incf all)
                       (unless (org-entry-is-done-p) (cl-incf open))))
                   nil 'tree))
                (list :id (org-id-get) :state (org-get-todo-state)
                      :heading (org-get-heading t t t t) :pages all :open open)))))

(defun sp-trails-dashboard ()
  "Show open questions and the trails followed for each."
  (interactive)
  (let ((qs (sp-trails--questions))
        (buf (get-buffer-create "*sp-trails*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (org-mode)
        (insert "#+title: Questions and trails\n\n")
        (dolist (q qs)
          (insert (format "* [%s] [[id:%s][%s]]\n"
                          (plist-get q :state) (plist-get q :id) (plist-get q :heading)))
          (let ((ts (sp-trails--trail-summaries (plist-get q :id))))
            (if (null ts)
                (insert "  /no trails yet/\n")
              (dolist (tr ts)
                (insert (format "  - %s [[id:%s][%s]] — %d pages, %d to read\n"
                                (plist-get tr :state) (plist-get tr :id)
                                (plist-get tr :heading)
                                (plist-get tr :pages) (plist-get tr :open)))))))
        (goto-char (point-min))
        (read-only-mode 1)))
    (pop-to-buffer buf)))

;;;; Rebuilding a trail from Chrome's history

(defun sp-trails--chrome-chain (url)
  "Pages that led to URL in Chrome history, root first, as (URL TITLE)."
  (unless (and (fboundp 'sqlite-available-p) (sqlite-available-p))
    (user-error "This Emacs has no SQLite support (needs Emacs 29+)"))
  (let ((tmp (make-temp-file "sp-trails-history" nil ".db"))
        (wal (concat sp-trails-chrome-history "-wal")))
    ;; Chrome locks the live file, so read a copy.
    (copy-file sp-trails-chrome-history tmp t)
    (when (file-exists-p wal) (copy-file wal (concat tmp "-wal") t))
    (let ((db (sqlite-open tmp)) chain)
      (unwind-protect
          (let ((id (caar (sqlite-select
                           db "SELECT v.id FROM visits v JOIN urls u ON u.id = v.url
                               WHERE u.url = ? ORDER BY v.visit_time DESC LIMIT 1"
                           (list url)))))
            (while (and (integerp id) (> id 0) (< (length chain) 500))
              (pcase-let ((`(,u ,title ,from ,opener)
                           (car (sqlite-select
                                 db "SELECT u.url, u.title, v.from_visit, v.opener_visit
                                     FROM visits v JOIN urls u ON u.id = v.url WHERE v.id = ?"
                                 (list id)))))
                (if (null u)
                    (setq id nil)
                  (unless (equal u (caar chain)) (push (list u title) chain))
                  ;; from_visit = same-tab link; opener_visit = link opened in a new tab
                  (setq id (if (and (integerp from) (> from 0)) from opener)))))
            chain)
        (sqlite-close db)
        (ignore-errors (delete-file (concat tmp "-wal")))
        (delete-file tmp)))))

(defun sp-trails-import-chrome (url)
  "Add the chain of pages that led to URL (from Chrome history) to the current trail."
  (interactive (list (read-string "Leaf URL: " (ignore-errors (current-kill 0 t)))))
  (sp-trails--trail-marker)
  (let ((prev nil) (n 0))
    (dolist (page (sp-trails--chrome-chain url))
      (sp-trails-add-page (car page) (cadr page) prev)
      (setq prev (car page))
      (cl-incf n))
    (message "Imported %d pages" n)))

;;;; Keys

(defvar-keymap sp-trails-map
  :doc "Trail commands."
  "s" #'sp-trails-resume-or-start
  "p" #'sp-trails-park
  "a" #'sp-trails-archive
  "g" #'sp-trails-goto
  "x" #'sp-trails-prune
  "w" #'sp-trails-snapshot
  "q" #'sp-trails-declare-question
  "d" #'sp-trails-dashboard
  "i" #'sp-trails-import-chrome)

(provide 'sp-trails)
;;; sp-trails.el ends here
