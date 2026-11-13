;;; sp-vulpea-backlink-check.el --- Is this heading backlinked? -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-vulpea-backlink-check' reports in the echo area whether the heading
;; at point (it needs an ID) is linked to from anywhere in the vault.  The
;; result is an Embark target: `embark-act' on it lists the backlinks in a
;; temporary buffer, where RET jumps to each one.

;;; Code:

(require 'org)
(require 'seq)
(require 'subr-x)

(declare-function vulpea-db-query-links-to "vulpea-db-query")
(declare-function vulpea-db-get-by-id "vulpea-db")
(declare-function vulpea-note-id "vulpea-note")
(declare-function vulpea-note-title "vulpea-note")
(declare-function vulpea-note-path "vulpea-note")
(declare-function org-fold-show-context "org-fold")

(defvar embark-target-finders)
(defvar embark-keymap-alist)
(defvar embark-default-action-overrides)
(defvar embark-general-map)

(defgroup sp-vulpea-backlink-check nil
  "Check whether a heading is backlinked."
  :group 'vulpea)

(defcustom sp-vulpea-backlink-check-timeout 10
  "Seconds the last result stays an Embark target after the echo area changes."
  :type 'natnum
  :group 'sp-vulpea-backlink-check)

(defcustom sp-vulpea-backlink-check-context-width 100
  "Columns of the line of context shown for each backlink."
  :type 'natnum
  :group 'sp-vulpea-backlink-check)

(defvar sp-vulpea-backlink-check--last nil
  "Cons of the ID and the time (`float-time') of the last check, or nil.")

(defun sp-vulpea-backlink-check--links (id)
  "Return the links to the note ID, without the ones from ID itself."
  (seq-remove (lambda (link) (equal (plist-get link :source) id))
              (vulpea-db-query-links-to id)))

(defvar sp-vulpea-backlink-check--history nil
  "Alist of (TEXT . ID) of the latest results, newest first.")

(defcustom sp-vulpea-backlink-check-history-size 20
  "Number of results kept to make them Embark targets again.
See `sp-vulpea-backlink-check-restore'."
  :type 'natnum
  :group 'sp-vulpea-backlink-check)

(defun sp-vulpea-backlink-check--propertize (text id)
  "Return TEXT as a result string for the heading ID."
  (propertize text
              'sp-vulpea-backlink-check id
              'face (if (equal text "not backlinked") 'shadow 'success)
              'help-echo "embark-act: list the backlinks"))

(defun sp-vulpea-backlink-check-restore (text)
  "Return TEXT as a result string again, if it is a recent result, else nil.
For `sp-copy-last-message-functions': the text copied out of *Messages*
has lost its properties.  This also makes the heading the target for
`sp-vulpea-backlink-check-timeout' seconds."
  (when-let* ((cell (assoc (string-remove-prefix "Copied: " text)
                           sp-vulpea-backlink-check--history)))
    (setq sp-vulpea-backlink-check--last (cons (cdr cell) (float-time)))
    (sp-vulpea-backlink-check--propertize (car cell) (cdr cell))))

(defun sp-vulpea-backlink-check--format (id links)
  "Return the echo-area result for ID with LINKS, a propertized string."
  (let* ((n (length links))
         (sources (length (seq-uniq (mapcar (lambda (l) (plist-get l :source))
                                            links))))
         (text (if (zerop n)
                   "not backlinked"
                 (format "%d backlink%s from %d note%s"
                         n (if (= n 1) "" "s")
                         sources (if (= sources 1) "" "s")))))
    (sp-vulpea-backlink-check--propertize text id)))

(defun sp-vulpea-backlink-check--id-at-point ()
  "Return the ID of the heading at point, or signal a `user-error'."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an Org buffer"))
  (or (org-entry-get nil "ID")
      (user-error "This heading has no ID")))

;;;###autoload
(defun sp-vulpea-backlink-check (&optional id)
  "Say in the echo area whether the heading at point is backlinked.
ID defaults to the ID property of the heading at point.  The result,
for example \"3 backlinks from 2 notes\", is an Embark target: `embark-act'
on it lists the backlinks.  Return the result string."
  (interactive)
  (let* ((id (or id (sp-vulpea-backlink-check--id-at-point)))
         (result (sp-vulpea-backlink-check--format
                  id (sp-vulpea-backlink-check--links id))))
    (setq sp-vulpea-backlink-check--last (cons id (float-time)))
    (setq sp-vulpea-backlink-check--history
          (seq-take (cons (cons (substring-no-properties result) id)
                          (assoc-delete-all (substring-no-properties result)
                                            sp-vulpea-backlink-check--history))
                    sp-vulpea-backlink-check-history-size))
    (message "%s" result)
    result))

(defun sp-vulpea-backlink-check--location (link)
  "Return the location plist of the LINK plist, or nil without a source file."
  (when-let* ((note (vulpea-db-get-by-id (plist-get link :source)))
              (path (vulpea-note-path note))
              (pos (plist-get link :pos)))
    (let ((buf (find-buffer-visiting path)))
      (with-temp-buffer
        (if buf
            (insert (with-current-buffer buf
                      (save-restriction (widen) (buffer-string))))
          (insert-file-contents path))
        (goto-char (min pos (point-max)))
        (list :note note :path path :pos pos
              :line (line-number-at-pos)
              :heading (save-excursion
                         (and (re-search-backward "^\\*+[ \t]+\\(.*\\)$" nil t)
                              (string-trim (match-string 1))))
              :context (truncate-string-to-width
                        (string-trim (buffer-substring
                                      (line-beginning-position)
                                      (line-end-position)))
                        sp-vulpea-backlink-check-context-width nil nil "…"))))))

(defun sp-vulpea-backlink-check--locations (id)
  "Return the locations of the links to ID, grouped by source note.
The value is an alist of (NOTE . LOCATIONS), in file order."
  (let (groups)
    (dolist (link (sp-vulpea-backlink-check--links id))
      (when-let* ((loc (sp-vulpea-backlink-check--location link)))
        (let* ((key (plist-get loc :path))
               (cell (assoc key groups)))
          (if cell
              (setcdr cell (cons loc (cdr cell)))
            (push (list key loc) groups)))))
    (mapcar (lambda (g)
              (cons (plist-get (cadr g) :note)
                    (sort (cdr g) (lambda (a b)
                                    (< (plist-get a :pos) (plist-get b :pos))))))
            (nreverse groups))))

(defvar-local sp-vulpea-backlink-check--buffer-id nil
  "The heading ID the locations buffer lists.")

(defun sp-vulpea-backlink-check-visit ()
  "Jump to the backlink at point."
  (interactive)
  (let ((loc (get-text-property (point) 'sp-vulpea-backlink-check-loc)))
    (unless loc (user-error "No backlink on this line"))
    (find-file-other-window (plist-get loc :path))
    (goto-char (plist-get loc :pos))
    (when (derived-mode-p 'org-mode)
      (org-fold-show-context 'link-search))))

(defun sp-vulpea-backlink-check--next (n)
  "Move N backlink entries forward; backward when N is negative.
An entry spans two lines with the same location, so a step skips the
lines of the entry point is on.  Point stays put when there is none."
  (let ((step (if (> n 0) 1 -1)))
    (dotimes (_ (abs n))
      (let* ((start (point))
             (here (get-text-property start 'sp-vulpea-backlink-check-loc)))
        (while (and (not (if (> step 0) (eobp) (bobp)))
                    (progn (forward-line step)
                           (let ((loc (get-text-property
                                       (point) 'sp-vulpea-backlink-check-loc)))
                             (or (null loc) (eq loc here))))))
        (let ((loc (get-text-property (point) 'sp-vulpea-backlink-check-loc)))
          (when (or (null loc) (eq loc here))
            (goto-char start)))
        (when (< step 0)
          ;; Backward lands on the second line of the entry: go to its first.
          (let ((loc (get-text-property (point) 'sp-vulpea-backlink-check-loc)))
            (while (and loc (not (bobp))
                        (eq loc (get-text-property
                                 (1- (line-beginning-position))
                                 'sp-vulpea-backlink-check-loc)))
              (forward-line -1))))))))

(defun sp-vulpea-backlink-check-next-entry (&optional n)
  "Move to the next backlink entry, N times."
  (interactive "p")
  (sp-vulpea-backlink-check--next (or n 1)))

(defun sp-vulpea-backlink-check-previous-entry (&optional n)
  "Move to the previous backlink entry, N times."
  (interactive "p")
  (sp-vulpea-backlink-check--next (- (or n 1))))

(defvar-keymap sp-vulpea-backlink-check-mode-map
  :doc "Keys of the backlink locations buffer."
  :parent special-mode-map
  "RET" #'sp-vulpea-backlink-check-visit
  "<mouse-2>" #'sp-vulpea-backlink-check-visit
  "n" #'sp-vulpea-backlink-check-next-entry
  "p" #'sp-vulpea-backlink-check-previous-entry)

(define-derived-mode sp-vulpea-backlink-check-mode special-mode "Backlinks"
  "Major mode of the buffer that lists the backlinks of a heading."
  (setq-local revert-buffer-function
              (lambda (&rest _)
                (when sp-vulpea-backlink-check--buffer-id
                  (sp-vulpea-backlink-check--render
                   sp-vulpea-backlink-check--buffer-id)))))

(defun sp-vulpea-backlink-check--render (id)
  "Draw the locations of the links to ID in the current buffer."
  (let ((inhibit-read-only t)
        (groups (sp-vulpea-backlink-check--locations id)))
    (erase-buffer)
    (setq sp-vulpea-backlink-check--buffer-id id)
    (insert (propertize (format "Backlinks to %s"
                                (or (when-let* ((note (vulpea-db-get-by-id id)))
                                      (vulpea-note-title note))
                                    id))
                        'face 'bold)
            "\n"
            (propertize "RET: visit  n/p: move  g: refresh  q: quit" 'face 'shadow)
            "\n\n")
    (if (null groups)
        (insert "Not backlinked.\n")
      (dolist (group groups)
        (insert (propertize (vulpea-note-title (car group))
                            'face 'font-lock-keyword-face)
                (propertize (format "  %s"
                                    (abbreviate-file-name
                                     (vulpea-note-path (car group))))
                            'face 'shadow)
                "\n")
        (dolist (loc (cdr group))
          (insert (propertize
                   (format "  %s (line %d)\n    %s\n"
                           (or (plist-get loc :heading) "(before the first heading)")
                           (plist-get loc :line)
                           (plist-get loc :context))
                   'sp-vulpea-backlink-check-loc loc
                   'mouse-face 'highlight
                   'follow-link t)))
        (insert "\n")))
    (goto-char (point-min))
    (sp-vulpea-backlink-check--next 1)))

(defun sp-vulpea-backlink-check--pending-id ()
  "Return the ID of the result in the echo area or just reported, or nil."
  (or (when-let* ((msg (current-message)))
        (get-text-property 0 'sp-vulpea-backlink-check msg))
      (when-let* ((last sp-vulpea-backlink-check--last)
                  ((< (- (float-time) (cdr last))
                      sp-vulpea-backlink-check-timeout)))
        (car last))))

;;;###autoload
(defun sp-vulpea-backlink-check-show (id)
  "List the backlinks of the heading with ID in a temporary buffer.
Interactively, ID is the last result of `sp-vulpea-backlink-check' (Embark
passes the target) or is asked for."
  (interactive
   (list (read-string "Backlinks of ID: " (sp-vulpea-backlink-check--pending-id))))
  (let ((buf (get-buffer-create
              (format "*vulpea backlinks: %s*"
                      (or (when-let* ((note (vulpea-db-get-by-id id)))
                            (vulpea-note-title note))
                          id)))))
    (with-current-buffer buf
      (unless (derived-mode-p 'sp-vulpea-backlink-check-mode)
        (sp-vulpea-backlink-check-mode))
      (sp-vulpea-backlink-check--render id))
    (pop-to-buffer buf)))

(defun sp-vulpea-backlink-check-target ()
  "Embark target finder: the result of `sp-vulpea-backlink-check'.
Found on the line of a result in a buffer such as *Messages*, in the
echo area, or for `sp-vulpea-backlink-check-timeout' seconds after a check."
  (when-let* ((id (or (get-text-property (point) 'sp-vulpea-backlink-check)
                      (sp-vulpea-backlink-check--pending-id))))
    (cons 'sp-vulpea-backlinks id)))

(with-eval-after-load 'embark
  (defvar-keymap sp-vulpea-backlink-check-embark-map
    :doc "Embark actions on the result of `sp-vulpea-backlink-check'."
    :parent embark-general-map
    "RET" #'sp-vulpea-backlink-check-show
    "s" #'sp-vulpea-backlink-check-show)
  (add-to-list 'embark-keymap-alist
               '(sp-vulpea-backlinks . sp-vulpea-backlink-check-embark-map))
  (add-to-list 'embark-default-action-overrides
               '(sp-vulpea-backlinks . sp-vulpea-backlink-check-show))
  (add-to-list 'embark-target-finders #'sp-vulpea-backlink-check-target))

;; `sp-copy-last-message' (sp-helper-funct) calls this hook with the text.
(defvar sp-copy-last-message-functions)
(add-hook 'sp-copy-last-message-functions #'sp-vulpea-backlink-check-restore)

(provide 'sp-vulpea-backlink-check)
;;; sp-vulpea-backlink-check.el ends here
