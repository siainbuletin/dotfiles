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
  "Non-nil to write note titles as id: links in Org tables."
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
