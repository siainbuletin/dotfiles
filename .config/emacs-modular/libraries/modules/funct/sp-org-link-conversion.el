;;; -*- lexical-binding: t; -*-
;; sp-org-link-conversion.el --- Create links at point.

;;; Commentary:

;; 
;;
;; Literate configuration is found in ~sp-org-id-link.el~

;;; Code:
;;;; Required libraries:
(require 'org)
(require 'org-id)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vulpea)

;;;; ------------------------------------------------------------------
;;;; Shared helpers
;;;; ------------------------------------------------------------------

(defun sp-org-slugify (title)
  "Turn TITLE into a filesystem-safe slug."
  (let ((slug (string-trim
               (downcase (replace-regexp-in-string "[^[:alnum:]]+" "-" title))
               "-" "-")))
    (if (string-empty-p slug) "note" slug)))

(defun sp-org--write-note (title)
  "Write a new note TITLE into `org-directory' without visiting it.
Register its ID with org and return the ID."
  (let* ((dir  (file-name-as-directory (expand-file-name org-directory)))
         (id   (org-id-new))
         (base (expand-file-name
                (format "%s-%s"
                        (format-time-string "%Y%m%dT%H%M%S")
                        (sp-org-slugify title))
                dir))
         (file (concat base ".org"))
         (n 1)
         (coding-system-for-write 'utf-8))
    (make-directory dir t)
    (while (file-exists-p file)         ; several notes may be created per second
      (setq n (1+ n)
            file (format "%s-%d.org" base n)))
    (with-temp-file file
      (insert (format ":PROPERTIES:\n:ID:       %s\n:END:\n#+title: %s\n\n"
                      id title)))
    (org-id-add-location id file)
    (org-id-locations-save)
    id))

;;;; ------------------------------------------------------------------
;;;; Single-note command (same behavior as before)
;;;; ------------------------------------------------------------------

(defun sp-vulpea-notes-with-title (title)
  "Return all notes in `vulpea-db' whose title equals TITLE, ignoring case."
  (vulpea-db-query
   (lambda (note)
     (let ((existing (vulpea-note-title note)))
       (and (stringp existing)
            (eq t (compare-strings existing nil nil title nil nil t)))))))

(defun sp-org-create-note-and-link (title)
  "Create a new org note TITLE in `org-directory' and insert an ID link to it.
If a note with the same title (case-insensitive) already exists in
`vulpea-db', report the conflict and offer to quit or to call
`vulpea-insert' on the existing match(es) instead.

The new note is written straight to disk: no buffer is visited and no
window is created.  If the region is active, its text is used as the
title and is replaced by the link."
  (interactive
   (list (if (use-region-p)
             (buffer-substring-no-properties (region-beginning) (region-end))
           (read-string "New note title: "))))
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (let ((title (string-trim (replace-regexp-in-string "[\n\r]+" " " title))))
    (when (string-empty-p title)
      (user-error "Empty title"))
    (let ((matches (sp-vulpea-notes-with-title title)))
      (if matches
          (sp-org--handle-title-conflict title matches)
        (sp-org--create-note-and-insert-link title)))))

(defun sp-org--handle-title-conflict (title matches)
  "Report that TITLE conflicts with MATCHES and let the user choose what to do."
  (let* ((n (length matches))
         (msg (format "A note titled \"%s\" already exists (%d match%s)"
                      (vulpea-note-title (car matches))
                      n (if (= n 1) "" "es")))
         (ids (mapcar #'vulpea-note-id matches)))
    (message "%s" msg)
    (pcase (car (read-multiple-choice
                 (concat msg ".")
                 '((?i "insert" "Link to the existing note with `vulpea-insert'")
                   (?q "quit"   "Abort without doing anything"))))
      (?i (vulpea-insert
           (lambda (note) (member (vulpea-note-id note) ids))
           (lambda (&rest _)
             (user-error "Pick one of the existing matches"))))
      (_ (message "Aborted")))))

(defun sp-org--create-note-and-insert-link (title)
  "Write a new note called TITLE to `org-directory' and link to it at point."
  (let ((id (sp-org--write-note title)))
    (when (use-region-p)
      (delete-region (region-beginning) (region-end)))
    (insert (org-link-make-string (concat "id:" id) title))
    (message "Created note \"%s\"" title)))

;;;; ------------------------------------------------------------------
;;;; Wikilink conversion
;;;; ------------------------------------------------------------------

(defface sp-org-wikilink-pending '((t :inherit highlight))
  "Face for wikilinks still waiting to be resolved."
  :group 'org)

(defface sp-org-wikilink-current '((t :inherit isearch))
  "Face for the wikilink currently being resolved."
  :group 'org)

(defvar sp-org--wl-created 0
  "Number of notes created during the current wikilink run.")

(defun sp-org--title-index ()
  "Return a hash table: downcased title or alias -> list of `vulpea-db' notes."
  (let ((idx (make-hash-table :test #'equal)))
    (dolist (note (vulpea-db-query))
      (dolist (name (cons (vulpea-note-title note) (vulpea-note-aliases note)))
        (when (and (stringp name) (not (string-empty-p name)))
          (push note (gethash (downcase name) idx)))))
    idx))

;; Is this hash table actually necessary? Isn't this something that
;; vulpea-db already kind of does?

(defun sp-org--lookup (index key)
  "Return the distinct notes stored under KEY (a downcased name) in INDEX."
  (seq-uniq (gethash key index)
            (lambda (a b) (equal (vulpea-note-id a) (vulpea-note-id b)))))

(defun sp-org--link-type-p (s)
  "Non-nil if S starts with a registered org link type, e.g. \"id:\"."
  (and (string-match "\\`\\([[:alpha:]][[:alnum:]+.-]*\\):" s)
       (member (match-string 1 s) (org-link-types))))

(defun sp-org--wikilink-parts (raw)
  "Parse the inside of a wikilink RAW into (TARGET DESCRIPTION).
Handle the Obsidian forms `Target|Alias', `Target#Heading' and
`Target^block'.  Return nil for things that are not note links:
org links with a type (id:, file:, https:...), file paths, and
same-file references such as `#Heading'."
  (let* ((i (string-match "\\\\?|" raw))
         (j (and i (match-end 0)))
         (target (string-trim (if i (substring raw 0 i) raw)))
         (alias  (and j (string-trim (substring raw j))))
         (base   (string-trim (replace-regexp-in-string "[#^].*\\'" "" target))))
    (when (and (not (string-empty-p base))
               (not (string-match-p "\\`\\(?:\\.\\.?/\\|/\\|~/\\|\\*\\|(\\)" base))
               (not (sp-org--link-type-p base)))
      (list base (if (and alias (not (string-empty-p alias))) alias base)))))

(defun sp-org--collect-wikilinks (beg end)
  "Return wikilinks between BEG and END as plists, in buffer order.
Each plist has :beg and :end markers, the :target to look up and the
:desc to use as link text.  `![[embeds]]' and links inside source,
example, export and comment blocks are ignored."
  (let (entries)
    (save-excursion
      (goto-char beg)
      (while (re-search-forward "\\[\\[\\([^][\n]+\\)\\]\\]" end t)
        (let ((mb (match-beginning 0))
              (me (match-end 0))
              (parts (sp-org--wikilink-parts (match-string-no-properties 1))))
          (when (and parts
                     (not (eq (char-before mb) ?!))
                     (not (save-excursion
                            (goto-char mb)
                            (save-match-data
                              (org-in-block-p '("src" "example" "export" "comment"))))))
            ;; The :beg marker advances on insertion so that adjacent links
            ;; ([[a]][[b]]) survive replacement of the previous one.
            (push (list :beg (copy-marker mb t)
                        :end (copy-marker me)
                        :target (car parts)
                        :desc (cadr parts))
                  entries)))))
    (nreverse entries)))

(defun sp-org--replace-wikilink (entry id)
  "Replace the wikilink ENTRY with an ID link to ID."
  (let ((mb (plist-get entry :beg))
        (me (plist-get entry :end)))
    (save-excursion
      (goto-char mb)
      (delete-region mb me)
      (insert (org-link-make-string (concat "id:" id) (plist-get entry :desc))))
    (set-marker mb nil)
    (set-marker me nil)))

(defun sp-org--highlight (entry)
  "Create and return a highlight overlay over wikilink ENTRY."
  (let ((ov (make-overlay (marker-position (plist-get entry :beg))
                          (marker-position (plist-get entry :end))
                          nil t nil)))
    (overlay-put ov 'face 'sp-org-wikilink-pending)
    (overlay-put ov 'priority 100)
    ov))

(defun sp-org--focus (ov)
  "Move point to overlay OV, reveal it, and mark it as the current link."
  (goto-char (overlay-start ov))
  (if (fboundp 'org-fold-show-context)
      (org-fold-show-context)
    (org-show-context))
  (recenter)
  (overlay-put ov 'face 'sp-org-wikilink-current))

(defun sp-org--offer-create (title index resolved)
  "Step 3: offer to create a note TITLE.  Return an ID, :skip, or quit."
  (pcase (car (read-multiple-choice
               (format "No existing note for \"%s\"" title)
               '((?c "create" "Create a new note in `org-directory'")
                 (?s "skip"   "Leave this wikilink as it is")
                 (?q "quit"   "Stop here; keep what was converted so far"))))
    (?c (let* ((title   (string-trim (read-string "New note title: " title)))
               (matches (sp-org--lookup index (downcase title))))
          (cond ((string-empty-p title) :skip)
                ;; The edited title exists after all: reuse it.
                ((= (length matches) 1) (vulpea-note-id (car matches)))
                (matches :skip)         ; ambiguous: don't add another duplicate
                (t (let ((id (sp-org--write-note title)))
                     (cl-incf sp-org--wl-created)
                     (puthash (downcase title) id resolved)
                     id)))))
    (?s :skip)
    (?q (throw 'sp-org-wikilinks-quit nil))))

(defun sp-org--resolve-interactively (entry index resolved)
  "Steps 2 and 3 for ENTRY: pick an existing note, else offer to create one.
Return an ID or :skip."
  (let* ((target (plist-get entry :target))
         (note (vulpea-select (format "Link target for [[%s]]" target)
                              :initial-prompt target
                              :require-match nil)))
    (or (vulpea-note-id note)           ; an existing note was selected
        (let ((title (string-trim (or (vulpea-note-title note) ""))))
          (if (string-empty-p title)
              :skip
            (sp-org--offer-create title index resolved))))))

(defun sp-org-convert-wikilinks ()
  "Convert Obsidian-style [[wikilinks]] in this org buffer to ID links.
Operates on the active region, or on the whole (accessible) buffer.

1. A wikilink whose target matches exactly one note in `vulpea-db'
   (title or alias, case-insensitive) is converted right away.
2. The remaining wikilinks are highlighted, then visited one by one with
   a `vulpea-select' prompt pre-filled with the text between the brackets.
3. If no existing note is selected, offer to create a new note in
   `org-directory' (the title is editable), skip the link, or quit.

`[[Target|Alias]]' keeps Alias as the link text; `[[Target#Heading]]'
and `[[Target^block]]' link to the note Target."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (entries (sp-org--collect-wikilinks beg end))
         (index (sp-org--title-index))
         (resolved (make-hash-table :test #'equal))
         (sp-org--wl-created 0)
         (auto 0) (manual 0) pending)
    (unless entries
      (user-error "No wikilinks found"))
    (deactivate-mark)

    ;; Step 1: exact, unambiguous matches are converted straight away.
    (dolist (e entries)
      (let* ((matches (sp-org--lookup index (downcase (plist-get e :target))))
             (id (and (= (length matches) 1) (vulpea-note-id (car matches)))))
        (if id
            (progn (sp-org--replace-wikilink e id)
                   (cl-incf auto))
          (push e pending))))
    (setq pending (nreverse pending))

    ;; Steps 2 and 3: highlight what is left and resolve it interactively.
    (when pending
      (setq pending (mapcar (lambda (e) (cons e (sp-org--highlight e))) pending))
      (unwind-protect
          (catch 'sp-org-wikilinks-quit
            (dolist (cell pending)
              (let* ((e   (car cell))
                     (ov  (cdr cell))
                     (key (downcase (plist-get e :target)))
                     (id  (gethash key resolved))) ; same target seen earlier?
                (unless id
                  (sp-org--focus ov)
                  (setq id (sp-org--resolve-interactively e index resolved))
                  (puthash key id resolved))
                (if (stringp id)
                    (progn (delete-overlay ov)
                           (sp-org--replace-wikilink e id)
                           (cl-incf manual))
                  (overlay-put ov 'face 'sp-org-wikilink-pending)))))
        (dolist (cell pending)
          (delete-overlay (cdr cell)))))
    (message "Wikilinks: %d converted automatically, %d resolved by hand (%d new notes), %d left as they were"
             auto manual sp-org--wl-created (- (length pending) manual))))

;;; Provide:

(provide 'sp-org-link-conversion)
;; sp-org-link-conversion.el ends here.
