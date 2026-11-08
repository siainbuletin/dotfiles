;;; sp-vulpea-grouped-backlinks.el --- Vulpea backlinks grouped by meta property -*- lexical-binding: t; -*-

;;; Commentary:

;; What this does: for a given note, finds every other note linking
;; to it, and sorts each link into either "Mentions" (a plain inline
;; or body-text [[id:...]] link) or a group named after the meta
;; property it was found in -- e.g. a note with
;;   - pub-author :: [[id:...][Christopher Arthur]]
;; contributes to a "pub-author" group when you look at Christopher
;; Arthur's backlinks, distinct from any note that just mentions him
;; in passing prose.
;;
;; NOT YET a real vulpea-ui sidebar widget -- see the top-level
;; docstrings below for why, and `sp-vulpea-grouped-backlinks-classify' for
;; the one point of Vulpea API I couldn't fully confirm.

;;; Code:

(require 'vulpea)
(require 'org)
(require 'sp-collection-query-tables-core) ; for sp-collec-query-select-note

(declare-function vulpea-ui-visit-note "vulpea-ui")
(declare-function vulpea-ui--get-main-window "vulpea-ui")
(declare-function vulpea-ui--get-note-from-buffer "vulpea-ui")

(defun sp-vulpea-grouped-backlinks--meta-key-at (file pos)
  "If POS in FILE sits on a \"- KEY :: ...\" meta line, return KEY.
Otherwise return nil, meaning this link sits in plain prose (a
heading, a paragraph, anywhere that isn't a meta description-list
entry) rather than a structured meta property."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char pos)
      (beginning-of-line)
      (if (looking-at "^[ \t]*-[ \t]+\\([A-Za-z0-9_-]+\\)[ \t]+::[ \t]")
          (match-string 1)
        nil))))

(defun sp-vulpea-grouped-backlinks-classify (id)
  "Return an alist of (GROUP . NOTES) for every note linking to ID.
GROUP is \"Mentions\" for a plain inline/body link, or the
meta-property key name (e.g. \"pub-author\") for a link found on
a \"- KEY :: [[id:...]]\" line -- see `sp-vulpea-grouped-backlinks--meta-key-at'.
NOTES is a deduplicated list of `vulpea-note' structs: the source
of each such link.

This relies on `vulpea-db-query-links-to' returning link plists
with at least :source (a note ID) and :pos (a buffer position in
the source file). I've seen this shape referenced in Vulpea's own
db/changelog material, but haven't been able to confirm it
against a live Emacs session -- if this errors for you, `C-h f
vulpea-db-query-links-to' will show the real return shape, and
the two `plist-get' calls below are the only things that would
need adjusting."
  (let ((groups (make-hash-table :test #'equal)))
    (dolist (link (vulpea-db-query-links-to id))
      (let* ((source-id (plist-get link :source))
             (pos (plist-get link :pos))
             (source-note (and source-id (vulpea-db-get-by-id source-id))))
        (when (and source-note pos)
          (let* ((key (sp-vulpea-grouped-backlinks--meta-key-at (vulpea-note-path source-note) pos))
                 (group (or key "Mentions")))
            (puthash group (cons source-note (gethash group groups)) groups)))))
    (let (result)
      (maphash
       (lambda (group notes)
         (push (cons group
                     (seq-uniq notes (lambda (a b)
                                       (equal (vulpea-note-id a) (vulpea-note-id b)))))
               result))
       groups)
      result)))

(defun sp-vulpea-grouped-backlinks-sorted (id)
  "Return the groups of notes linking to ID, sorted by group name.
See `sp-vulpea-grouped-backlinks-classify' for the shape."
  (sort (sp-vulpea-grouped-backlinks-classify id)
        (lambda (a b) (string< (car a) (car b)))))

(defun sp-vulpea-grouped-backlinks-org-detached (&optional note)
  "Show backlinks to NOTE, grouped into \"Mentions\" plus one section
per meta-property key they were found under (see
`sp-vulpea-grouped-backlinks-sorted'). Prompts for NOTE, via
`sp-collec-query-select-note' (tag-annotated completion), if not given.

Each entry is a real, clickable [[id:...][Title]] link back to
the note that made the reference -- opened in `org-mode' so
`org-open-at-point' works on them, same pattern as the property-
conversion report."
  (interactive)
  (let* ((note (or note (sp-collec-query-select-note "Show backlinks for: ")))
         (groups (sp-vulpea-grouped-backlinks-sorted (vulpea-note-id note))))
    (with-current-buffer (get-buffer-create
                           (format "*vulpea backlinks: %s*" (vulpea-note-title note)))
      (erase-buffer)
      (org-mode)
      (insert (format "* Backlinks to %s\n\n" (vulpea-note-title note)))
      (if (null groups)
          (insert "No backlinks found.\n")
        (dolist (group groups)
          (insert (format "** %s (%d)\n" (car group) (length (cdr group))))
          (dolist (n (cdr group))
            (insert (format "- %s\n"
                            (org-link-make-string (concat "id:" (vulpea-note-id n))
                                                   (vulpea-note-title n)))))
          (insert "\n")))
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

(defgroup sp-vulpea-grouped-backlinks nil
  "Vulpea backlinks grouped by meta property."
  :group 'vulpea)

(defcustom sp-vulpea-grouped-backlinks-sidebar-follow t
  "Non-nil means the sidebar follows the note in the main window.
Nil keeps the note it shows (pinned) until it is toggled back or the
sidebar is reopened.  Only the sidebar reads this; the `vulpea-ui'
widget always follows."
  :type 'boolean
  :group 'sp-vulpea-grouped-backlinks)

(defcustom sp-vulpea-grouped-backlinks-sidebar-side 'right
  "Side of the frame for the grouped backlinks sidebar."
  :type '(choice (const left) (const right) (const top) (const bottom))
  :group 'sp-vulpea-grouped-backlinks)

(defcustom sp-vulpea-grouped-backlinks-sidebar-slot 1
  "Slot of the sidebar on its side; the `vulpea-ui' sidebar uses 0."
  :type 'integer
  :group 'sp-vulpea-grouped-backlinks)

(defcustom sp-vulpea-grouped-backlinks-sidebar-size 0.33
  "Size of the sidebar as a fraction of the frame."
  :type 'number
  :group 'sp-vulpea-grouped-backlinks)

(defconst sp-vulpea-grouped-backlinks-sidebar-buffer-name
  "*vulpea grouped backlinks*"
  "Name of the grouped backlinks sidebar buffer.")

(defvar-local sp-vulpea-grouped-backlinks-sidebar--note nil
  "The `vulpea-note' the sidebar buffer shows.")

(defvar sp-vulpea-grouped-backlinks-sidebar--timer nil
  "Pending sync timer, or nil.")

(defun sp-vulpea-grouped-backlinks-sidebar--main-note ()
  "Return the note shown in the main window, or nil."
  (require 'vulpea-ui)
  (when-let* ((win (vulpea-ui--get-main-window)))
    (vulpea-ui--get-note-from-buffer (window-buffer win))))

(defun sp-vulpea-grouped-backlinks-sidebar--visit (button)
  "Open the note of BUTTON in the main window."
  (require 'vulpea-ui)
  (vulpea-ui-visit-note (button-get button 'sp-note)))

(defun sp-vulpea-grouped-backlinks-sidebar--render (note)
  "Draw the grouped backlinks of NOTE in the current buffer."
  (let ((inhibit-read-only t)
        (groups (sp-vulpea-grouped-backlinks-sorted (vulpea-note-id note))))
    (erase-buffer)
    (setq sp-vulpea-grouped-backlinks-sidebar--note note)
    (insert (propertize (format "Backlinks to %s" (vulpea-note-title note))
                        'face 'bold)
            "\n"
            (propertize (if sp-vulpea-grouped-backlinks-sidebar-follow
                            "following the main note (f: pin)"
                          "pinned (f: follow)")
                        'face 'shadow)
            "\n\n")
    (if (null groups)
        (insert "No backlinks found.\n")
      (dolist (group groups)
        (insert (propertize (format "%s (%d)" (car group) (length (cdr group)))
                            'face 'font-lock-keyword-face)
                "\n")
        (dolist (n (cdr group))
          (insert "  ")
          (insert-text-button
           (or (vulpea-note-title n) "(untitled)")
           'action #'sp-vulpea-grouped-backlinks-sidebar--visit
           'follow-link t
           'sp-note n)
          (insert "\n"))
        (insert "\n")))
    (goto-char (point-min))))

(defun sp-vulpea-grouped-backlinks-sidebar--sync ()
  "Redraw the sidebar if the main window shows another note."
  (setq sp-vulpea-grouped-backlinks-sidebar--timer nil)
  (when-let* ((buf (get-buffer sp-vulpea-grouped-backlinks-sidebar-buffer-name))
              ((and sp-vulpea-grouped-backlinks-sidebar-follow
                    (get-buffer-window buf t)))
              (note (sp-vulpea-grouped-backlinks-sidebar--main-note))
              (shown (buffer-local-value
                      'sp-vulpea-grouped-backlinks-sidebar--note buf))
              ((not (equal (vulpea-note-id note) (vulpea-note-id shown)))))
    (with-current-buffer buf
      (sp-vulpea-grouped-backlinks-sidebar--render note))))

(defun sp-vulpea-grouped-backlinks-sidebar--on-window-change (&optional _frame)
  "Arm a sync after a window or buffer change."
  (unless (or (minibufferp) sp-vulpea-grouped-backlinks-sidebar--timer)
    (setq sp-vulpea-grouped-backlinks-sidebar--timer
          (run-with-timer 0 nil #'sp-vulpea-grouped-backlinks-sidebar--sync))))

(defun sp-vulpea-grouped-backlinks-sidebar--add-hooks ()
  "Track the main window while the sidebar exists."
  (add-hook 'window-buffer-change-functions
            #'sp-vulpea-grouped-backlinks-sidebar--on-window-change)
  (add-hook 'window-selection-change-functions
            #'sp-vulpea-grouped-backlinks-sidebar--on-window-change))

(defun sp-vulpea-grouped-backlinks-sidebar--remove-hooks ()
  "Stop tracking and cancel a pending sync."
  (remove-hook 'window-buffer-change-functions
               #'sp-vulpea-grouped-backlinks-sidebar--on-window-change)
  (remove-hook 'window-selection-change-functions
               #'sp-vulpea-grouped-backlinks-sidebar--on-window-change)
  (when (timerp sp-vulpea-grouped-backlinks-sidebar--timer)
    (cancel-timer sp-vulpea-grouped-backlinks-sidebar--timer))
  (setq sp-vulpea-grouped-backlinks-sidebar--timer nil))

(defvar-keymap sp-vulpea-grouped-backlinks-sidebar-mode-map
  :doc "Keys of the grouped backlinks sidebar."
  :parent special-mode-map
  "f" #'sp-vulpea-grouped-backlinks-sidebar-toggle-follow
  "q" #'sp-vulpea-grouped-backlinks-sidebar-close
  "RET" #'push-button)

(define-derived-mode sp-vulpea-grouped-backlinks-sidebar-mode special-mode
  "Backlinks"
  "Major mode of the grouped backlinks sidebar."
  (setq-local revert-buffer-function
              (lambda (&rest _)
                (when sp-vulpea-grouped-backlinks-sidebar--note
                  (sp-vulpea-grouped-backlinks-sidebar--render
                   sp-vulpea-grouped-backlinks-sidebar--note))))
  (add-hook 'kill-buffer-hook
            #'sp-vulpea-grouped-backlinks-sidebar--remove-hooks nil t))

(defun sp-vulpea-grouped-backlinks-sidebar--display (buffer)
  "Show BUFFER in a side window and return the window."
  (let ((window-sides-slots (list nil nil nil nil))
        (side sp-vulpea-grouped-backlinks-sidebar-side)
        (size sp-vulpea-grouped-backlinks-sidebar-size))
    (display-buffer-in-side-window
     buffer
     `((side . ,side)
       (slot . ,sp-vulpea-grouped-backlinks-sidebar-slot)
       (window-width . ,(if (memq side '(left right)) size nil))
       (window-height . ,(if (memq side '(top bottom)) size nil))
       (window-parameters . ((no-delete-other-windows . t)))))))

;;;###autoload
(defun sp-vulpea-grouped-backlinks-sidebar-close ()
  "Close the grouped backlinks sidebar."
  (interactive)
  (when-let* ((buf (get-buffer sp-vulpea-grouped-backlinks-sidebar-buffer-name)))
    (dolist (win (get-buffer-window-list buf nil t))
      (when (window-parameter win 'window-side)
        (delete-window win)))
    (kill-buffer buf)))

;;;###autoload
(defun sp-vulpea-grouped-backlinks-sidebar ()
  "Toggle a side window with the grouped backlinks of the main note.
The window follows the note in the main window while
`sp-vulpea-grouped-backlinks-sidebar-follow' is non-nil.  Ask for a note
when the main window shows none."
  (interactive)
  (if (get-buffer-window sp-vulpea-grouped-backlinks-sidebar-buffer-name)
      (sp-vulpea-grouped-backlinks-sidebar-close)
    (let ((note (or (sp-vulpea-grouped-backlinks-sidebar--main-note)
                    (sp-collec-query-select-note "Show backlinks for: ")))
          (buf (get-buffer-create
                sp-vulpea-grouped-backlinks-sidebar-buffer-name)))
      (with-current-buffer buf
        (unless (derived-mode-p 'sp-vulpea-grouped-backlinks-sidebar-mode)
          (sp-vulpea-grouped-backlinks-sidebar-mode))
        (sp-vulpea-grouped-backlinks-sidebar--render note))
      (sp-vulpea-grouped-backlinks-sidebar--add-hooks)
      (sp-vulpea-grouped-backlinks-sidebar--display buf))))

;;;###autoload
(defun sp-vulpea-grouped-backlinks-sidebar-toggle-follow ()
  "Toggle whether the grouped backlinks sidebar follows the main note."
  (interactive)
  (setq sp-vulpea-grouped-backlinks-sidebar-follow
        (not sp-vulpea-grouped-backlinks-sidebar-follow))
  (when-let* ((buf (get-buffer sp-vulpea-grouped-backlinks-sidebar-buffer-name)))
    (with-current-buffer buf
      (when sp-vulpea-grouped-backlinks-sidebar--note
        (sp-vulpea-grouped-backlinks-sidebar--render
         sp-vulpea-grouped-backlinks-sidebar--note)))
    (when sp-vulpea-grouped-backlinks-sidebar-follow
      (sp-vulpea-grouped-backlinks-sidebar--sync)))
  (message "Grouped backlinks sidebar: %s"
           (if sp-vulpea-grouped-backlinks-sidebar-follow
               "following the main note"
             "pinned")))

(provide 'sp-vulpea-grouped-backlinks)
;;; sp-vulpea-grouped-backlinks.el ends here
