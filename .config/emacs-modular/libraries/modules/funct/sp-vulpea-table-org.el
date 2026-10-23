;;; sp-vulpea-table-org.el --- Org table output for Vulpea tables -*- lexical-binding: t; -*-

;;; Commentary:

;; The plain-text side of Vulpea tables: the `vulpea-table' dynamic block,
;; a command that inserts one from a spec, and `org' as a renderer, a
;; read-only Org buffer with the same table.  No extra packages are needed,
;; so this is also the fallback when neither exc nor vui can be loaded.

;;; Code:

(require 'org)
(require 'org-table)
(require 'subr-x)
(require 'sp-vulpea-table-core)

(declare-function sp-vulpea-table-views-get "sp-vulpea-table-views")
(declare-function sp-vulpea-table-views-read-name "sp-vulpea-table-views")

(defcustom sp-vulpea-table-link-titles t
  "Non-nil to write note titles as id: links in Org tables."
  :type 'boolean
  :group 'sp-vulpea-table)

(defun sp-vulpea-table--org-escape (text)
  "Return TEXT safe inside an Org table cell: no bars, no line breaks."
  (replace-regexp-in-string
   "|" "\\\\vert{}"
   (replace-regexp-in-string "[\n\r]+" " " text)))

(defun sp-vulpea-table--org-cell (note column)
  "Return the Org text of COLUMN for NOTE."
  (let ((text (sp-vulpea-table--org-escape (sp-vulpea-table-cell note column))))
    (if (and sp-vulpea-table-link-titles (eq column :title)
             (vulpea-note-id note) (not (string-empty-p text)))
        (format "[[id:%s][%s]]" (vulpea-note-id note)
                (replace-regexp-in-string "[][]" "" text))
      text)))

(defun sp-vulpea-table-org-text (spec)
  "Return an aligned Org table for SPEC, as a string without final newline.
SPEC's :parent-of must be resolved already."
  (let* ((spec (sp-vulpea-table-spec-normalize spec))
         (columns (plist-get spec :columns))
         (notes (sp-vulpea-table-query spec)))
    (with-temp-buffer
      (delay-mode-hooks (org-mode))
      (insert "| " (mapconcat #'sp-vulpea-table-header-label columns " | ") " |\n|-\n")
      (dolist (note notes)
        (insert "| "
                (mapconcat (lambda (c) (sp-vulpea-table--org-cell note c)) columns " | ")
                " |\n"))
      (when notes (delete-char -1))
      (org-table-align)
      (string-trim-right (buffer-string)))))

(defun org-dblock-write:vulpea-table (params)
  "Write a table of Vulpea notes into the current dynamic block.
PARAMS is a spec, see `sp-vulpea-table-spec-keys'; :parent-of may be
the string \"self\", resolved on every update to the note the block is in.

  #+BEGIN: vulpea-table :tags (\"book\") :columns (:title \"author\" \"rating\") :sort-by \"rating\"
  #+END:

  #+BEGIN: vulpea-table :todo (\"TODO\" \"NEXT\") :columns (:title :todo :tags)
  #+END:"
  (insert (sp-vulpea-table-org-text (sp-vulpea-table-resolve-spec params))))

(defun sp-vulpea-table-insert-dblock (spec)
  "Insert a `vulpea-table' dynamic block for SPEC at point and fill it.
SPEC is kept as written, so a \"self\" :parent-of keeps meaning the note
the block is in.  Interactively, SPEC is a saved view picked with
completion; the menu (`sp-vulpea-table-menu') inserts its own draft."
  (interactive
   (progn (require 'sp-vulpea-table-views)
          (list (sp-vulpea-table-views-get
                 (sp-vulpea-table-views-read-name "Insert view: ")))))
  (org-create-dblock (append (list :name "vulpea-table")
                             (sp-vulpea-table-spec-normalize spec)))
  (org-update-dblock))

;;;; Org buffer renderer

(defvar-local sp-vulpea-table-org--spec nil
  "The (resolved) spec the current Org table buffer shows.")

(defvar sp-vulpea-table-org-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'sp-vulpea-table-org-refresh)
    map)
  "Keymap of `sp-vulpea-table-org-mode'.")

(define-derived-mode sp-vulpea-table-org-mode org-mode "Vulpea-Table"
  "Read-only Org buffer showing a table of Vulpea notes; `g' refreshes.")

(defun sp-vulpea-table-org-refresh ()
  "Run the query again and redraw the table."
  (interactive)
  (let ((inhibit-read-only t) (pos (point)))
    (erase-buffer)
    (insert (format "#+title: %s\n\n" (sp-vulpea-table-spec-summary sp-vulpea-table-org--spec))
            (sp-vulpea-table-org-text sp-vulpea-table-org--spec) "\n")
    (goto-char (min pos (point-max)))
    (set-buffer-modified-p nil)
    (setq buffer-read-only t)))

(defun sp-vulpea-table-org-open (spec buffer-name)
  "Show SPEC (resolved) in a read-only Org buffer called BUFFER-NAME."
  (with-current-buffer (get-buffer-create buffer-name)
    (sp-vulpea-table-org-mode)
    (setq sp-vulpea-table-org--spec spec)
    (sp-vulpea-table-org-refresh)
    (pop-to-buffer (current-buffer))))

(define-obsolete-function-alias 'sia-insert-vulpea-table
  #'sp-vulpea-table-insert-dblock "2026-10-21")

(provide 'sp-vulpea-table-org)
;;; sp-vulpea-table-org.el ends here
