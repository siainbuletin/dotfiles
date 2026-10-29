;;; sp-collection-query-tables-org.el --- Org table output for query tables -*- lexical-binding: t; -*-

;;; Commentary:

;; The plain-text side of query tables: the `collection-query-table' dynamic block,
;; a command that inserts one from a spec, and `org' as a renderer, a
;; read-only Org buffer with the same table.  No extra packages are needed,
;; so this is also the fallback when neither exc nor vui can be loaded.

;;; Code:

(require 'org)
(require 'org-table)
(require 'subr-x)
(require 'sp-collection-query-tables-core)

(declare-function sp-collec-query-views-get "sp-collection-query-tables-views")
(declare-function sp-collec-query-views-read-name "sp-collection-query-tables-views")

(defcustom sp-collec-query-link-titles t
  "Non-nil to write note titles as id: links in Org tables.
Only the title column is affected, and only in the dynamic block and the
Org buffer.  Links already in the text of a cell are kept as they are;
the other renderers show them by their description."
  :type 'boolean
  :group 'sp-collec-query)

(defun sp-collec-query--org-escape (text)
  "Return TEXT safe inside an Org table cell: no bars, no line breaks."
  (replace-regexp-in-string
   "|" "\\\\vert{}"
   (replace-regexp-in-string "[\n\r]+" " " text)))

(defun sp-collec-query--org-cell (note column)
  "Return the Org text of COLUMN for NOTE."
  (let ((text (sp-collec-query--org-escape (sp-collec-query-cell note column))))
    (if (and sp-collec-query-link-titles (eq column :title)
             (vulpea-note-id note) (not (string-empty-p text)))
        (format "[[id:%s][%s]]" (vulpea-note-id note)
                (replace-regexp-in-string "[][]" "" text))
      text)))

(defun sp-collec-query-org-text (spec)
  "Return an aligned Org table for SPEC, as a string without final newline.
SPEC's :parent-of must be resolved already."
  (let* ((spec (sp-collec-query-spec-normalize spec))
         (columns (plist-get spec :columns))
         (notes (sp-collec-query-query spec)))
    (with-temp-buffer
      (delay-mode-hooks (org-mode))
      (insert "| " (mapconcat #'sp-collec-query-header-label columns " | ") " |\n|-\n")
      (dolist (note notes)
        (insert "| "
                (mapconcat (lambda (c) (sp-collec-query--org-cell note c)) columns " | ")
                " |\n"))
      (when notes (delete-char -1))
      (org-table-align)
      (string-trim-right (buffer-string)))))

(defun org-dblock-write:collection-query-table (params)
  "Write a table of Vulpea notes into the current dynamic block.
PARAMS is a spec, see `sp-collec-query-spec-keys'; :parent-of may be
the string \"self\", resolved on every update to the note the block is in.

  #+BEGIN: collection-query-table :tags (\"book\") :columns (:title \"author\" \"rating\") :sort-by \"rating\"
  #+END:

  #+BEGIN: collection-query-table :todo (\"TODO\" \"NEXT\") :columns (:title :todo :tags)
  #+END:"
  (insert (sp-collec-query-org-text (sp-collec-query-resolve-spec params))))

(defalias 'org-dblock-write:vulpea-table #'org-dblock-write:collection-query-table
  "Old name of the `collection-query-table' dynamic block, read from existing notes.")

(defun sp-collec-query-insert-dblock (spec)
  "Insert a `collection-query-table' dynamic block for SPEC at point and fill it.
SPEC is kept as written, so a \"self\" :parent-of keeps meaning the note
the block is in.  Interactively, SPEC is a saved view picked with
completion; the menu (`sp-collec-query-menu') inserts its own draft."
  (interactive
   (progn (require 'sp-collection-query-tables-views)
          (list (sp-collec-query-views-get
                 (sp-collec-query-views-read-name "Insert view: ")))))
  (org-create-dblock (append (list :name "collection-query-table")
                             (sp-collec-query-spec-normalize spec)))
  (org-update-dblock))

;;;; Keeping dynamic blocks up to date

(defgroup sp-collec-query-dblock nil
  "Updating query table dynamic blocks without asking."
  :group 'sp-collec-query)

(defcustom sp-collec-query-dblock-update-on '(open save)
  "When `sp-collec-query-dblock-auto-mode' updates dynamic blocks.
`open' updates a note's blocks when its file is visited; `save' updates
the blocks in all open notes some seconds after any Org note is saved."
  :type '(set (const :tag "When a file is opened" open)
              (const :tag "After any Org note is saved" save))
  :group 'sp-collec-query-dblock)

(defcustom sp-collec-query-dblock-names '("collection-query-table" "vulpea-table")
  "Names of the dynamic blocks `sp-collec-query-dblock-auto-mode' updates.
Other dynamic blocks, such as clock tables, are never touched."
  :type '(repeat string)
  :group 'sp-collec-query-dblock)

(defcustom sp-collec-query-dblock-delay 2.0
  "Seconds after a save before open notes have their blocks updated.
The Vulpea database is updated by its own autosync; if blocks show the
state from before the save, lengthen this."
  :type 'number
  :group 'sp-collec-query-dblock)

(defcustom sp-collec-query-dblock-save nil
  "Non-nil to save a note after its blocks changed.
Only a note that had no unsaved edits before the update is saved."
  :type 'boolean
  :group 'sp-collec-query-dblock)

(defvar sp-collec-query-dblock--saving nil
  "Non-nil while the mode itself saves a buffer, so that save starts no new round.")

(defvar sp-collec-query-dblock--timer nil)

(defun sp-collec-query-dblock--regexp ()
  "Return the regexp matching the begin line of a block to update."
  (format "^[ \t]*#\\+BEGIN:[ \t]+%s\\_>"
          (regexp-opt sp-collec-query-dblock-names t)))

(defun sp-collec-query-dblock-has-block-p ()
  "Non-nil if the current buffer contains a block to update."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (re-search-forward (sp-collec-query-dblock--regexp) nil t)))))

(defun sp-collec-query-dblock-update-buffer ()
  "Update every query table dynamic block in the current buffer.
Return non-nil if the text of the buffer changed.  A buffer that was
unmodified and whose blocks came out the same is left unmodified.  With
`sp-collec-query-dblock-save', a buffer that was unmodified and changed
is saved."
  (interactive)
  (when (and (derived-mode-p 'org-mode)
             (fboundp 'vulpea-db-query)
             (not buffer-read-only)
             (sp-collec-query-dblock-has-block-p))
    (let ((was-modified (buffer-modified-p))
          (before (buffer-hash))
          (regexp (sp-collec-query-dblock--regexp))
          (case-fold-search t))
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (while (re-search-forward regexp nil t)
            (beginning-of-line)
            (condition-case err
                (org-update-dblock)
              (error (message "Query table block in %s: %s"
                              (buffer-name) (error-message-string err))))
            (unless (re-search-forward "^[ \t]*#\\+END" nil t)
              (goto-char (point-max))))))
      (let ((changed (not (equal before (buffer-hash)))))
        (cond ((not changed)
               (unless was-modified (set-buffer-modified-p nil)))
              ((and sp-collec-query-dblock-save buffer-file-name (not was-modified))
               (let ((sp-collec-query-dblock--saving t))
                 (save-buffer))))
        changed))))

(defun sp-collec-query-dblock-update-all ()
  "Update the query table blocks in every open Org file buffer."
  (interactive)
  (let ((count 0))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and buffer-file-name
                   (sp-collec-query-dblock-update-buffer))
          (setq count (1+ count)))))
    (when (called-interactively-p 'any)
      (message "Query table blocks changed in %d buffer%s" count (if (= count 1) "" "s")))
    count))

(defun sp-collec-query-dblock--on-open ()
  "Update the blocks of the file just visited, once Emacs is idle."
  (when (and (memq 'open sp-collec-query-dblock-update-on)
             buffer-file-name
             (derived-mode-p 'org-mode))
    (let ((buffer (current-buffer)))
      (run-with-idle-timer
       0.5 nil
       (lambda ()
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (sp-collec-query-dblock-update-buffer))))))))

(defun sp-collec-query-dblock--after-save ()
  "Schedule an update of all open blocks after an Org note is saved."
  (when (and (memq 'save sp-collec-query-dblock-update-on)
             (not sp-collec-query-dblock--saving)
             buffer-file-name
             (derived-mode-p 'org-mode))
    (when (timerp sp-collec-query-dblock--timer)
      (cancel-timer sp-collec-query-dblock--timer))
    (setq sp-collec-query-dblock--timer
          (run-with-timer sp-collec-query-dblock-delay nil
                          #'sp-collec-query-dblock-update-all))))

(define-minor-mode sp-collec-query-dblock-auto-mode
  "Update query table dynamic blocks without running `org-dblock-update'.
See `sp-collec-query-dblock-update-on' for when."
  :global t
  :group 'sp-collec-query-dblock
  (if sp-collec-query-dblock-auto-mode
      (progn (add-hook 'find-file-hook #'sp-collec-query-dblock--on-open)
             (add-hook 'after-save-hook #'sp-collec-query-dblock--after-save))
    (remove-hook 'find-file-hook #'sp-collec-query-dblock--on-open)
    (remove-hook 'after-save-hook #'sp-collec-query-dblock--after-save)
    (when (timerp sp-collec-query-dblock--timer)
      (cancel-timer sp-collec-query-dblock--timer)
      (setq sp-collec-query-dblock--timer nil))))

;;;; Org buffer renderer

(defvar-local sp-collec-query-org--spec nil
  "The (resolved) spec the current Org table buffer shows.")

(defvar sp-collec-query-org-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'sp-collec-query-org-refresh)
    map)
  "Keymap of `sp-collec-query-org-mode'.")

(define-derived-mode sp-collec-query-org-mode org-mode "Query-Table"
  "Read-only Org buffer showing a table of Vulpea notes; `g' refreshes.")

(defun sp-collec-query-org-refresh ()
  "Run the query again and redraw the table."
  (interactive)
  (let ((inhibit-read-only t) (pos (point)))
    (erase-buffer)
    (insert (format "#+title: %s\n\n" (sp-collec-query-spec-summary sp-collec-query-org--spec))
            (sp-collec-query-org-text sp-collec-query-org--spec) "\n")
    (goto-char (min pos (point-max)))
    (set-buffer-modified-p nil)
    (setq buffer-read-only t)))

(defun sp-collec-query-org-open (spec buffer-name)
  "Show SPEC (resolved) in a read-only Org buffer called BUFFER-NAME."
  (with-current-buffer (get-buffer-create buffer-name)
    (sp-collec-query-org-mode)
    (setq sp-collec-query-org--spec spec)
    (sp-collec-query-org-refresh)
    (pop-to-buffer (current-buffer))))

(define-obsolete-function-alias 'sia-insert-vulpea-table
  #'sp-collec-query-insert-dblock "2026-10-21")

(provide 'sp-collection-query-tables-org)
;;; sp-collection-query-tables-org.el ends here
