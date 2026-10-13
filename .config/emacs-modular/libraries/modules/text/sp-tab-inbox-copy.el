;;; sp-tab-inbox.el --- Link inbox widget for vulpea-ui -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (vulpea "2") (vulpea-ui "0") (vui "0"))

;;; Commentary:

;; A `vulpea-ui' sidebar widget that searches a directory of plain files
;; (the "link inbox") for mentions of the current note's title and aliases,
;; without adding those files to the vulpea database.
;;
;; - Each hit is shown on its own lines, with the body text word-wrapped.
;; - Hits whose only match sits inside an id: link into the current note's
;;   file (the note itself or any heading with an :ID:) are filtered out.
;; - `collect' moves a hit under a heading of the current note using
;;   `sp-move-region-to-heading', keeping the list bullet in both places and
;;   leaving a link behind.  `collect all' does this for every hit, asking for
;;   the heading once.
;; - Inbox files that were not already open are saved and killed afterwards.
;;
;; Load it after vulpea-ui, e.g.:
;;
;;   (with-eval-after-load 'vulpea-ui
;;     (require 'sp-tab-inbox))
;;
;; and set `sp-tab-inbox-dir' to your inbox directory.  Press `g' in the
;; sidebar to refresh.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vulpea)
(require 'vulpea-ui)
(require 'vui)
(require 'sp-move-region-to-heading)

;;;; Configuration

(defcustom sp-tab-inbox-dir "~/notes/inbox/tabs/"
  "Directory of plain files with unsorted links."
  :type 'directory
  :group 'vulpea)

(defcustom sp-tab-inbox-fill-column 40
  "Wrap width for link inbox results.
Tune to your sidebar width."
  :type 'integer
  :group 'vulpea)

(defvar sp-tab-inbox-generation 0
  "Bumped after collecting, so the widget's memo recomputes.")

(defconst sp-tab-inbox-bullet-re
  "\\(?:[ \t]*[-+]\\|[ \t]*[0-9]+[.)]\\|[ \t]+\\*\\)[ \t]+\\(?:\\[[ xX-]\\][ \t]+\\)?"
  "Matches a list bullet (and optional checkbox) at the start of a line.
A column-0 `*' is an Org heading, so it is not treated as a bullet.")

;;;; Searching

(defun sp-tab-inbox--note-ids (note)
  "Return the ID of NOTE plus every :ID: property in NOTE's file."
  (let ((path (vulpea-note-path note))
        (ids (list (vulpea-note-id note))))
    (when (and path (file-readable-p path))
      (with-temp-buffer
        (if-let ((buf (find-buffer-visiting path)))
            (insert (with-current-buffer buf
                      (save-restriction
                        (widen)
                        (buffer-substring-no-properties (point-min) (point-max)))))
          (insert-file-contents path))
        (goto-char (point-min))
        (while (re-search-forward "^[ \t]*:ID:[ \t]+\\([^ \t\n]+\\)" nil t)
          (push (match-string 1) ids))))
    (delete-dups ids)))

(defun sp-tab-inbox--unlinked-p (text terms ids)
  "Non-nil if some term in TERMS occurs in TEXT outside links to any of IDS."
  (let* ((case-fold-search t)
         (link-re (concat "\\[\\[id:" (regexp-opt ids)
                          "\\]\\(?:\\[[^]]*\\]\\)?\\]"))
         (stripped (replace-regexp-in-string link-re "" text t t)))
    (seq-some (lambda (term) (string-match-p (regexp-quote term) stripped))
              terms)))

(defun sp-tab-inbox-search (note)
  "Return list of (FILE LINE TEXT) mentioning NOTE's title or aliases.
Matches that only sit inside id: links into NOTE's file are dropped."
  (when-let* ((rg (executable-find "rg"))
              (terms (seq-filter
                      (lambda (s) (>= (length s) 3))
                      (cons (vulpea-note-title note)
                            (vulpea-note-aliases note)))))
    (with-temp-buffer
      (apply #'call-process rg nil t nil
             "--line-number" "--no-heading" "--with-filename"
             "--ignore-case" "--fixed-strings" "--word-regexp"
             (append (mapcan (lambda (term) (list "-e" term)) terms)
                     (list (expand-file-name sp-tab-inbox-dir))))
      (goto-char (point-min))
      (let ((ids (sp-tab-inbox--note-ids note))
            result)
        (while (re-search-forward "^\\(.+?\\):\\([0-9]+\\):\\(.*\\)$" nil t)
          (let ((text (string-trim (match-string 3))))
            (when (sp-tab-inbox--unlinked-p text terms ids)
              (push (list (match-string 1)
                          (string-to-number (match-string 2))
                          text)
                    result))))
        (nreverse result)))))

;;;; Display helpers

(defun sp-tab-inbox-wrap (text)
  "Fill TEXT to `sp-tab-inbox-fill-column' and indent it by two spaces."
  (with-temp-buffer
    (insert text)
    (let ((fill-column sp-tab-inbox-fill-column))
      (fill-region (point-min) (point-max)))
    (goto-char (point-min))
    (while (not (eobp))
      (insert "  ")
      (forward-line 1))
    (buffer-string)))

(defun sp-tab-inbox-visit (file line)
  "Visit LINE of FILE in another window."
  (find-file-other-window file)
  (goto-char (point-min))
  (forward-line (1- line)))

;;;; Collecting

(defun sp-tab-inbox-collect (file line text note &optional target)
  "Move LINE of FILE under a heading of NOTE with `sp-move-region-to-heading'.
The list bullet, if any, is moved with the text and also kept in FILE in
front of the link left behind.
TEXT is the hit text, checked against the file to catch stale line numbers.
TARGET is an optional (MARKER . PATH) to skip the heading prompt.
Return the target used."
  (let* ((target (or target (sp--read-org-heading (vulpea-note-path note))))
         (existing (find-buffer-visiting file))
         (buf (or existing (find-file-noselect file))))
    (unwind-protect
        (with-current-buffer buf
          (save-excursion
            (goto-char (point-min))
            (forward-line (1- line))
            (let ((bol (line-beginning-position))
                  (end (line-end-position)))
              (unless (equal (string-trim (buffer-substring-no-properties bol end))
                             text)
                (user-error "Line %d of %s changed; refresh the sidebar"
                            line (file-name-nondirectory file)))
              (goto-char bol)
              (let* ((bullet-end (and (looking-at sp-tab-inbox-bullet-re)
                                      (match-end 0)))
                     ;; with a bullet, start at the bullet (skip indentation)
                     (beg (if bullet-end
                              (progn (skip-chars-forward " \t") (point))
                            bol))
                     (bullet (and bullet-end
                                  (buffer-substring-no-properties beg bullet-end))))
                (goto-char beg)
                (sp-move-region-to-heading beg end (car target) (cdr target))
                ;; the link now sits at BEG; put the bullet back before it
                (when bullet
                  (goto-char beg)
                  (insert bullet)))))
          (save-buffer))
      ;; only kill buffers this command opened
      (when (and (not existing) (buffer-live-p buf))
        (kill-buffer buf)))
    target))

(defun sp-tab-inbox-collect-one (file line text note)
  "Collect a single hit (FILE, LINE, TEXT) into NOTE and refresh the sidebar."
  (sp-tab-inbox-collect file line text note)
  (cl-incf sp-tab-inbox-generation)
  (vulpea-ui-sidebar-refresh))

(defun sp-tab-inbox-collect-all (hits note)
  "Collect every hit in HITS under one heading of NOTE."
  (when hits
    (let ((target (sp--read-org-heading (vulpea-note-path note))))
      ;; Each moved line is replaced by a one-line link, so line numbers
      ;; in the inbox files stay valid between hits.
      (dolist (hit hits)
        (pcase-let ((`(,file ,line ,text) hit))
          (sp-tab-inbox-collect file line text note target)))
      (cl-incf sp-tab-inbox-generation)
      (message "Collected %d link inbox lines" (length hits))
      (vulpea-ui-sidebar-refresh))))

;;;; Widget

(vui-defcomponent sp-tab-inbox-widget ()
  "Plain-text mentions of the current note in the link inbox."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (let ((hits (vui-use-memo (note sp-tab-inbox-generation)
                    (sp-tab-inbox-search note))))
        (vui-component 'vulpea-ui-widget
          :title "Link inbox"
          :count (length hits)
          :children
          (lambda ()
            (if (null hits)
                (vui-text "No mentions")
              (apply #'vui-vstack
                     (vui-button "collect all"
                                 :on-click (lambda ()
                                             (sp-tab-inbox-collect-all hits note)))
                     (mapcar
                      (lambda (hit)
                        (pcase-let ((`(,file ,line ,text) hit))
                          (vui-vstack
                           (vui-hstack
                            (vui-button
                             (format "%s:%d" (file-name-nondirectory file) line)
                             :on-click (lambda () (sp-tab-inbox-visit file line)))
                            (vui-text " ")
                            (vui-button
                             "collect"
                             :on-click (lambda ()
                                         (sp-tab-inbox-collect-one
                                          file line text note))))
                           (vui-text
                            (propertize (sp-tab-inbox-wrap text)
                                        'face 'vulpea-ui-mention-context-face)))))
                      hits)))))))))

(vulpea-ui-register-widget 'link-inbox
  :component 'sp-tab-inbox-widget
  :order 360) ; right after unlinked-mentions (350)

(provide 'sp-tab-inbox)
;;; sp-tab-inbox.el ends here
