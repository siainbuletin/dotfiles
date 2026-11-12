;;; sp-vulpea-grouped-backlinks.el --- Vulpea backlinks grouped by meta property -*- lexical-binding: t; -*-

;;; Commentary:

;; What this does: for a given note, finds every other note linking
;; to it, and sorts each link into either "Mentions" (a plain inline
;; or body-text [[id:...]] link, split by the kind of note it sits in:
;; regular notes, litnotes, writing projects) or a group named after the meta
;; property it was found in -- e.g. a note with
;;   - pub-author :: [[id:...][Christopher Arthur]]
;; contributes to a "pub-author" group when you look at Christopher
;; Arthur's backlinks, distinct from any note that just mentions him
;; in passing prose.
;;
;; The vulpea-ui widget is in sp-vulpea-grouped-backlinks-widget.el.
;; `sp-vulpea-grouped-backlinks-classify' holds the one point of Vulpea
;; API I couldn't fully confirm.

;;; Code:

(require 'vulpea)
(require 'org)
(require 'sp-collection-query-core) ; for sp-collec-query-select-note

(declare-function vulpea-ui-visit-note "vulpea-ui")
(declare-function vulpea-ui--get-main-window "vulpea-ui")
(declare-function vulpea-ui--get-note-from-buffer "vulpea-ui")

(defvar sp-writing-projects)

(defgroup sp-vulpea-grouped-backlinks nil
  "Vulpea backlinks grouped by meta property."
  :group 'vulpea)

(defcustom sp-vulpea-grouped-backlinks-block-padding 2
  "Number of blank lines between two blocks of grouped backlinks.
A block is a section (\"Mentions\", a meta key) or one of the
subsections of \"Mentions\".  Every view reads this."
  :type 'natnum
  :group 'sp-vulpea-grouped-backlinks)

(defconst sp-vulpea-grouped-backlinks--mentions-prefix "Mentions / "
  "Prefix of the group names of plain mentions, before the kind of source.")

(defconst sp-vulpea-grouped-backlinks-mention-kinds
  '("Notes" "Litnotes" "Writing projects")
  "Kinds of source note a mention can come from, in display order.")

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

(defun sp-vulpea-grouped-backlinks--writing-p (path)
  "Non-nil when the file PATH is below `sp-writing-projects'."
  (and path
       (bound-and-true-p sp-writing-projects)
       (string-prefix-p (file-name-as-directory
                         (expand-file-name sp-writing-projects))
                        (expand-file-name path))))

(defun sp-vulpea-grouped-backlinks--mention-kind (note)
  "Return the kind of source NOTE is, one of `sp-vulpea-grouped-backlinks-mention-kinds'.
- \"Writing projects\": its file is below `sp-writing-projects'.
- \"Litnotes\": it is tagged `litnote'.
- \"Notes\": anything else, i.e. the regular notes (tagged `concept' or
  `zettel', or not tagged at all)."
  (cond ((sp-vulpea-grouped-backlinks--writing-p (vulpea-note-path note))
         "Writing projects")
        ((member "litnote" (vulpea-note-tags note)) "Litnotes")
        (t "Notes")))

(defun sp-vulpea-grouped-backlinks-classify (id)
  "Return an alist of (GROUP . NOTES) for every note linking to ID.
GROUP is \"Mentions / KIND\" for a plain inline/body link (KIND from
`sp-vulpea-grouped-backlinks--mention-kind'), or the
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
                 (group (or key
                            (concat sp-vulpea-grouped-backlinks--mentions-prefix
                                    (sp-vulpea-grouped-backlinks--mention-kind
                                     source-note)))))
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

(defun sp-vulpea-grouped-backlinks--rank (group)
  "Return the sort rank of the group name GROUP.
Mention groups come first, in `sp-vulpea-grouped-backlinks-mention-kinds'
order; the meta-key groups follow."
  (if (string-prefix-p sp-vulpea-grouped-backlinks--mentions-prefix group)
      (or (seq-position sp-vulpea-grouped-backlinks-mention-kinds
                        (string-remove-prefix
                         sp-vulpea-grouped-backlinks--mentions-prefix group))
          0)
    (length sp-vulpea-grouped-backlinks-mention-kinds)))

(defun sp-vulpea-grouped-backlinks-sorted (id)
  "Return the groups of notes linking to ID, in display order.
Mention groups come first (see `sp-vulpea-grouped-backlinks--rank'), the
meta-key groups after them sorted by name.  See
`sp-vulpea-grouped-backlinks-classify' for the shape."
  (sort (sp-vulpea-grouped-backlinks-classify id)
        (lambda (a b)
          (let ((ra (sp-vulpea-grouped-backlinks--rank (car a)))
                (rb (sp-vulpea-grouped-backlinks--rank (car b))))
            (if (= ra rb)
                (string< (car a) (car b))
              (< ra rb))))))

(defun sp-vulpea-grouped-backlinks--fold-sections (groups)
  "Fold the sorted GROUPS into sections, a list of (TITLE . SUBGROUPS).
SUBGROUPS is an alist of (LABEL . NOTES).  The mention groups become one
\"Mentions\" section with a subgroup per kind of source note; each
meta-key group is a section with one subgroup whose LABEL is nil."
  (let (mentions sections)
    (dolist (group groups)
      (if (string-prefix-p sp-vulpea-grouped-backlinks--mentions-prefix
                           (car group))
          (push (cons (string-remove-prefix
                       sp-vulpea-grouped-backlinks--mentions-prefix (car group))
                      (cdr group))
                mentions)
        (push (list (car group) (cons nil (cdr group))) sections)))
    (append (when mentions (list (cons "Mentions" (nreverse mentions))))
            (nreverse sections))))

(defun sp-vulpea-grouped-backlinks-sections (id)
  "Return the backlinks of ID as sections, the shape every view draws.
See `sp-vulpea-grouped-backlinks--fold-sections'."
  (sp-vulpea-grouped-backlinks--fold-sections
   (sp-vulpea-grouped-backlinks-sorted id)))

(defun sp-vulpea-grouped-backlinks-section-count (section)
  "Return the number of notes in SECTION, over all its subgroups."
  (apply #'+ (mapcar (lambda (sub) (length (cdr sub))) (cdr section))))

(defun sp-vulpea-grouped-backlinks--flat-p (section)
  "Non-nil when SECTION has no subsections, only a list of notes."
  (null (car (cadr section))))

(defun sp-vulpea-grouped-backlinks--padding ()
  "Return the blank lines that separate two blocks, as a string."
  (make-string (max 0 sp-vulpea-grouped-backlinks-block-padding) ?\n))

(defun sp-vulpea-grouped-backlinks--insert-org-notes (notes)
  "Insert one Org list item with an `id:' link for each of NOTES."
  (dolist (n notes)
    (insert (format "- %s\n"
                    (org-link-make-string (concat "id:" (vulpea-note-id n))
                                           (vulpea-note-title n))))))

(defun sp-vulpea-grouped-backlinks-org-detached (&optional note)
  "Show backlinks to NOTE, grouped into \"Mentions\" (a subsection per kind
of source note) plus one section per meta-property key they were found
under (see `sp-vulpea-grouped-backlinks-sections'). Prompts for NOTE, via
`sp-collec-query-select-note' (tag-annotated completion), if not given.

Each entry is a real, clickable [[id:...][Title]] link back to
the note that made the reference -- opened in `org-mode' so
`org-open-at-point' works on them, same pattern as the property-
conversion report."
  (interactive)
  (let* ((note (or note (sp-collec-query-select-note "Show backlinks for: ")))
         (sections (sp-vulpea-grouped-backlinks-sections (vulpea-note-id note))))
    (with-current-buffer (get-buffer-create
                           (format "*vulpea backlinks: %s*" (vulpea-note-title note)))
      (erase-buffer)
      (org-mode)
      (insert (format "* Backlinks to %s\n\n" (vulpea-note-title note)))
      (if (null sections)
          (insert "No backlinks found.\n")
        (let ((padding (sp-vulpea-grouped-backlinks--padding))
              (first-section t))
          (dolist (section sections)
            (unless first-section (insert padding))
            (setq first-section nil)
            (insert (format "** %s (%d)\n" (car section)
                            (sp-vulpea-grouped-backlinks-section-count section)))
            (if (sp-vulpea-grouped-backlinks--flat-p section)
                (sp-vulpea-grouped-backlinks--insert-org-notes
                 (cdr (cadr section)))
              (let ((first-sub t))
                (dolist (sub (cdr section))
                  (unless first-sub (insert padding))
                  (setq first-sub nil)
                  (insert (format "*** %s (%d)\n" (car sub) (length (cdr sub))))
                  (sp-vulpea-grouped-backlinks--insert-org-notes
                   (cdr sub))))))))
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

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

(defun sp-vulpea-grouped-backlinks-sidebar--insert-heading (title count indent)
  "Insert the line \"TITLE (COUNT)\", indented by INDENT columns."
  (insert (make-string indent ?\s)
          (propertize (format "%s (%d)" title count)
                      'face 'font-lock-keyword-face)
          "\n"))

(defun sp-vulpea-grouped-backlinks-sidebar--insert-notes (notes indent)
  "Insert one button per note of NOTES, indented by INDENT columns."
  (dolist (n notes)
    (insert (make-string indent ?\s))
    (insert-text-button
     (or (vulpea-note-title n) "(untitled)")
     'action #'sp-vulpea-grouped-backlinks-sidebar--visit
     'follow-link t
     'sp-note n)
    (insert "\n")))

(defun sp-vulpea-grouped-backlinks-sidebar--render (note)
  "Draw the grouped backlinks of NOTE in the current buffer."
  (let ((inhibit-read-only t)
        (sections (sp-vulpea-grouped-backlinks-sections (vulpea-note-id note))))
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
    (if (null sections)
        (insert "No backlinks found.\n")
      (let ((padding (sp-vulpea-grouped-backlinks--padding))
            (first-section t))
        (dolist (section sections)
          (unless first-section (insert padding))
          (setq first-section nil)
          (sp-vulpea-grouped-backlinks-sidebar--insert-heading
           (car section)
           (sp-vulpea-grouped-backlinks-section-count section)
           0)
          (if (sp-vulpea-grouped-backlinks--flat-p section)
              (sp-vulpea-grouped-backlinks-sidebar--insert-notes
               (cdr (cadr section)) 2)
            (let ((first-sub t))
              (dolist (sub (cdr section))
                (unless first-sub (insert padding))
                (setq first-sub nil)
                (sp-vulpea-grouped-backlinks-sidebar--insert-heading
                 (car sub) (length (cdr sub)) 2)
                (sp-vulpea-grouped-backlinks-sidebar--insert-notes
                 (cdr sub) 4)))))))
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
