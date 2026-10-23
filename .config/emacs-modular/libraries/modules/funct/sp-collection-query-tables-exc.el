;;; sp-collection-query-tables-exc.el --- Query tables as exc grids -*- lexical-binding: t; -*-

;;; Commentary:

;; Shows a query table in exc (https://github.com/yibie/exc), the
;; spreadsheet drawn with ETAF (https://github.com/emacs-taf).  exc needs
;; Emacs 29.1 and the ecss, ebox and etaf checkouts on `load-path'.
;;
;; The first row of the grid holds the column names and is frozen.  Meta
;; columns can be edited in place: the new text is written to the note's
;; file before the cell changes.  Titles, tags and the other built-in
;; columns are read-only.  Undo (C-/) only undoes the grid, not the note.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'sp-collection-query-tables-core)

(declare-function exc--show-grid "exc")
(declare-function exc--show-grid-in-current-buffer "exc")
(declare-function make-exc-default-data-source "exc-data-source")
(declare-function exc-set-style-at "exc")
(declare-function exc-set-frozen "exc")
(declare-function exc-set-column-width "exc")
(declare-function exc-get-cell-at-point "exc")
(declare-function exc-etaf-goto "exc-etaf")
(declare-function sp-collection-query-tables-menu "sp-collection-query-tables-menu")
(defvar exc--data-source)
(defvar sp-collection-query-tables-menu--spec)
(defvar sp-collection-query-tables-menu--target)

(defcustom sp-collection-query-tables-exc-column-widths
  '((:title . 42) (:tags . 24) (:id . 38) (:path . 50) (t . 20))
  "Width in characters of each column in an exc table.
A column not listed uses the entry for t."
  :type '(alist :key-type (choice symbol string) :value-type integer)
  :group 'sp-collection-query-tables)

(defvar-local sp-collection-query-tables-exc--spec nil
  "The resolved spec the current exc table shows.")
(defvar-local sp-collection-query-tables-exc--notes nil
  "Vector of the notes in the current exc table, one per data row.")
(defvar-local sp-collection-query-tables-exc--refresher nil
  "The function this buffer subscribed to `sp-collection-query-tables-refresh-functions'.")
(dolist (var '(sp-collection-query-tables-exc--spec sp-collection-query-tables-exc--notes
               sp-collection-query-tables-exc--refresher))
  (put var 'permanent-local t))

(defun sp-collection-query-tables-exc-available-p ()
  "Non-nil if exc and ETAF can be loaded."
  (and (require 'exc nil t) (locate-library "exc-etaf")
       (require 'etaf nil t)))

(defun sp-collection-query-tables-exc--require ()
  "Load exc, or say what is missing."
  (unless (sp-collection-query-tables-exc-available-p)
    (user-error "exc is not available: it needs Emacs 29.1 and the ecss, ebox, etaf and exc checkouts on `load-path' (see `sp-collection-query-tables-renderer')")))

(defun sp-collection-query-tables-exc--width (column)
  "Return the width for COLUMN."
  (or (alist-get column sp-collection-query-tables-exc-column-widths nil nil #'equal)
      (alist-get t sp-collection-query-tables-exc-column-widths)
      20))

;;;; Building the grid

(defun sp-collection-query-tables-exc--guard (source columns notes)
  "Make SOURCE write meta cells to their notes and refuse other edits.
COLUMNS are the table's columns and NOTES a vector of its notes."
  (let ((original (gethash :set-raw-value-at source))
        (ncols (length columns)))
    (puthash :set-raw-value-at
             (lambda (s row col value)
               (cond
                ((= row 0) (user-error "The header row is not editable"))
                ((or (>= col ncols) (> row (length notes)))
                 (user-error "Outside the table"))
                ((not (stringp (nth col columns)))
                 (user-error "The %s column is read-only"
                             (sp-collection-query-tables-header-label (nth col columns))))
                (t (sp-collection-query-tables-write-meta (aref notes (1- row)) (nth col columns) value)
                   (funcall original s row col value))))
             source)))

(defun sp-collection-query-tables-exc--source (spec notes)
  "Return an exc data source for SPEC and the list NOTES."
  (let* ((columns (plist-get spec :columns))
         (labels (mapcar #'sp-collection-query-tables-header-label columns))
         (source (make-exc-default-data-source
                  labels
                  (cons labels (sp-collection-query-tables-rows notes columns))
                  (sp-collection-query-tables-spec-summary spec))))
    (cl-loop for column in columns
             for i from 0
             do (exc-set-style-at source 0 i '(:bold t))
             do (exc-set-column-width source i (sp-collection-query-tables-exc--width column)))
    (exc-set-frozen source 1 0)
    (sp-collection-query-tables-exc--guard source columns (vconcat notes))
    source))

;;;; The buffer

(defvar sp-collection-query-tables-exc-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c o") #'sp-collection-query-tables-exc-open-note)
    (define-key map (kbd "C-c q") #'sp-collection-query-tables-exc-edit-query)
    (define-key map (kbd "C-c C-u") #'sp-collection-query-tables-exc-refresh)
    map)
  "Keymap of `sp-collection-query-tables-exc-mode'.")

(define-minor-mode sp-collection-query-tables-exc-mode
  "Keys for an exc grid that shows a query table.
\\{sp-collection-query-tables-exc-mode-map}"
  :lighter " VTable"
  :keymap sp-collection-query-tables-exc-mode-map)

(defun sp-collection-query-tables-exc--draw (spec)
  "Run SPEC and draw the result in the current buffer."
  (let* ((notes (sp-collection-query-tables-query spec))
         (source (sp-collection-query-tables-exc--source spec notes)))
    (exc--show-grid-in-current-buffer source (sp-collection-query-tables-spec-summary spec))
    (setq sp-collection-query-tables-exc--spec spec
          sp-collection-query-tables-exc--notes (vconcat notes))
    (sp-collection-query-tables-exc-mode 1)
    (sp-collection-query-tables-exc--subscribe)
    (length notes)))

(defun sp-collection-query-tables-exc--subscribe ()
  "Refresh this buffer when `sp-collection-query-tables-refresh-functions' run."
  (unless sp-collection-query-tables-exc--refresher
    (let ((buffer (current-buffer)))
      (setq sp-collection-query-tables-exc--refresher
            (lambda ()
              (if (buffer-live-p buffer)
                  (with-current-buffer buffer (sp-collection-query-tables-exc-refresh))
                (remove-hook 'sp-collection-query-tables-refresh-functions
                             sp-collection-query-tables-exc--refresher))))
      (add-hook 'sp-collection-query-tables-refresh-functions sp-collection-query-tables-exc--refresher)
      (add-hook 'kill-buffer-hook
                (lambda ()
                  (remove-hook 'sp-collection-query-tables-refresh-functions
                               sp-collection-query-tables-exc--refresher))
                nil t))))

(defun sp-collection-query-tables-exc-open (spec buffer-name)
  "Show SPEC, already resolved, in an exc grid called BUFFER-NAME."
  (sp-collection-query-tables-exc--require)
  (let ((buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (sp-collection-query-tables-exc--draw spec))
    (switch-to-buffer buffer)))

(defun sp-collection-query-tables-exc-refresh ()
  "Run the table's query again and redraw the grid."
  (interactive)
  (unless sp-collection-query-tables-exc--spec
    (user-error "Not a query table"))
  (let ((cell (ignore-errors (exc-get-cell-at-point))))
    (sp-collection-query-tables-exc--draw sp-collection-query-tables-exc--spec)
    (when cell
      (ignore-errors
        (exc-etaf-goto (plist-get cell :slice-row) (1- (plist-get cell :slice-col)))))))

(defun sp-collection-query-tables-exc--note-at-point ()
  "Return the note in the row at point, or nil on the header row."
  (let* ((cell (exc-get-cell-at-point))
         (row (plist-get cell :slice-row)))
    (when (and row (>= row 1) (<= row (length sp-collection-query-tables-exc--notes)))
      (aref sp-collection-query-tables-exc--notes (1- row)))))

(defun sp-collection-query-tables-exc-open-note ()
  "Visit the note in the row at point."
  (interactive)
  (if-let* ((note (sp-collection-query-tables-exc--note-at-point)))
      (progn (find-file (vulpea-note-path note))
             (when (> (or (vulpea-note-level note) 0) 0)
               (goto-char (vulpea-note-pos note))))
    (user-error "No note on this row")))

(defun sp-collection-query-tables-exc-edit-query ()
  "Change this table's query in the menu; running it redraws this buffer."
  (interactive)
  (require 'sp-collection-query-tables-menu)
  (setq sp-collection-query-tables-menu--spec (copy-tree sp-collection-query-tables-exc--spec)
        sp-collection-query-tables-menu--target (current-buffer))
  (sp-collection-query-tables-menu))

(provide 'sp-collection-query-tables-exc)
;;; sp-collection-query-tables-exc.el ends here
