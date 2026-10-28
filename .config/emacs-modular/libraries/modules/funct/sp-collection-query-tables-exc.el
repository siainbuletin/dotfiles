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
(declare-function sp-collec-query-menu "sp-collection-query-tables-menu")
(defvar exc--data-source)
(defvar exc-calc-sheet-limit)
(defvar sp-collec-query-menu--spec)
(defvar sp-collec-query-menu--target)

(defcustom sp-collec-query-exc-column-widths
  '((:title . 42) (:tags . 24) (:id . 38) (:path . 50) (t . 20))
  "Width in characters of each column in an exc table.
A column not listed uses the entry for t.  The :column-widths of a
table's spec, saved with a view, override these."
  :type '(alist :key-type (choice symbol string) :value-type integer)
  :group 'spcustom)

(defcustom sp-collec-query-exc-wrap 'wrap
  "How an exc table treats text longer than its column.
`wrap' keeps the widths of `sp-collec-query-exc-column-widths' and wraps
long text onto more lines.  `fit' sizes each column to its longest text,
up to `sp-collec-query-exc-max-width'; text beyond that still wraps.  The
:wrap of a table's spec overrides this."
  :type '(choice (const :tag "Wrap inside the column width" wrap)
                 (const :tag "Fit the column to its text" fit))
  :group 'sp-collec-query)

(defcustom sp-collec-query-exc-max-width 80
  "Widest a column may grow in characters when the table fits its columns."
  :type 'integer
  :group 'sp-collec-query)

(defvar-local sp-collec-query-exc--spec nil
  "The resolved spec the current exc table shows.")
(defvar-local sp-collec-query-exc--notes nil
  "Vector of the notes in the current exc table, one per data row.")
(defvar-local sp-collec-query-exc--refresher nil
  "The function this buffer subscribed to `sp-collec-query-refresh-functions'.")
(dolist (var '(sp-collec-query-exc--spec sp-collec-query-exc--notes
               sp-collec-query-exc--refresher))
  (put var 'permanent-local t))
(put 'exc-calc-sheet-limit 'permanent-local t)

(defun sp-collec-query-exc-available-p ()
  "Non-nil if exc and ETAF can be loaded."
  (and (require 'exc nil t) (locate-library "exc-etaf")
       (require 'etaf nil t)))

(defun sp-collec-query-exc--require ()
  "Load exc, or say what is missing."
  (unless (sp-collec-query-exc-available-p)
    (user-error "exc is not available: it needs Emacs 29.1 and the ecss, ebox, etaf and exc checkouts on `load-path' (see `sp-collec-query-renderer')")))

(defun sp-collec-query-exc--width (column spec &optional texts)
  "Return the width for COLUMN of SPEC, whose cell and header text is TEXTS.
A width in the spec's :column-widths wins; then, if the table fits its
columns, the longest line in TEXTS up to `sp-collec-query-exc-max-width';
then `sp-collec-query-exc-column-widths'."
  (let ((own (plist-get spec :column-widths)))
    (or (alist-get column own nil nil #'equal)
        (and (eq (or (plist-get spec :wrap) sp-collec-query-exc-wrap) 'fit)
             (min sp-collec-query-exc-max-width
                  (apply #'max 1
                         (mapcar (lambda (text)
                                   (apply #'max 0
                                          (mapcar #'string-width
                                                  (split-string text "\n"))))
                                 texts))))
        (alist-get t own)
        (alist-get column sp-collec-query-exc-column-widths nil nil #'equal)
        (alist-get t sp-collec-query-exc-column-widths)
        20)))

;;;; Building the grid

(defun sp-collec-query-exc--guard (source columns notes)
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
                             (sp-collec-query-header-label (nth col columns))))
                ((sp-org-link-has-link-p
                  (sp-collec-query-cell (aref notes (1- row)) (nth col columns)))
                 (user-error "This cell holds a link; edit it in the note"))
                (t (sp-collec-query-write-meta (aref notes (1- row)) (nth col columns) value)
                   (funcall original s row col value))))
             source)))

(defun sp-collec-query-exc--source (spec notes)
  "Return an exc data source for SPEC and the list NOTES."
  (let* ((columns (plist-get spec :columns))
         (labels (mapcar #'sp-collec-query-header-label columns))
         (rows (sp-collec-query-rows notes columns))
         (source (make-exc-default-data-source
                  labels
                  (cons labels rows)
                  (sp-collec-query-spec-summary spec))))
    (cl-loop for column in columns
             for i from 0
             do (exc-set-style-at source 0 i '(:bold t))
             do (exc-set-column-width
                 source i
                 (sp-collec-query-exc--width
                  column spec
                  (cons (nth i labels)
                        (mapcar (lambda (row) (format "%s" (or (nth i row) "")))
                                rows)))))
    (exc-set-frozen source 1 0)
    (sp-collec-query-exc--guard source columns (vconcat notes))
    source))

;;;; The buffer

(defvar sp-collec-query-exc-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c o") #'sp-collec-query-exc-open-note)
    (define-key map (kbd "C-c q") #'sp-collec-query-exc-edit-query)
    (define-key map (kbd "C-c C-u") #'sp-collec-query-exc-refresh)
    map)
  "Keymap of `sp-collec-query-exc-mode'.")

(define-minor-mode sp-collec-query-exc-mode
  "Keys for an exc grid that shows a query table.
\\{sp-collec-query-exc-mode-map}"
  :lighter " VTable"
  :keymap sp-collec-query-exc-mode-map)

(defun sp-collec-query-exc--draw (spec)
  "Run SPEC and draw the result in the current buffer."
  (let* ((notes (sp-collec-query-query spec))
         (source (sp-collec-query-exc--source spec notes)))
    ;; exc draws empty rows below the data down to the end of the window;
    ;; end the sheet one row after the last note, to add an entry there.
    (setq-local exc-calc-sheet-limit
                (cons (+ (length notes) 2) (cdr exc-calc-sheet-limit)))
    (exc--show-grid-in-current-buffer source (sp-collec-query-spec-summary spec))
    (setq sp-collec-query-exc--spec spec
          sp-collec-query-exc--notes (vconcat notes))
    (sp-collec-query-exc-mode 1)
    (sp-collec-query-exc--subscribe)
    (length notes)))

(defun sp-collec-query-exc--subscribe ()
  "Refresh this buffer when `sp-collec-query-refresh-functions' run."
  (unless sp-collec-query-exc--refresher
    (let ((buffer (current-buffer)))
      (setq sp-collec-query-exc--refresher
            (lambda ()
              (if (buffer-live-p buffer)
                  (with-current-buffer buffer (sp-collec-query-exc-refresh))
                (remove-hook 'sp-collec-query-refresh-functions
                             sp-collec-query-exc--refresher))))
      (add-hook 'sp-collec-query-refresh-functions sp-collec-query-exc--refresher)
      (add-hook 'kill-buffer-hook
                (lambda ()
                  (remove-hook 'sp-collec-query-refresh-functions
                               sp-collec-query-exc--refresher))
                nil t))))

(defun sp-collec-query-exc-open (spec buffer-name)
  "Show SPEC, already resolved, in an exc grid called BUFFER-NAME."
  (sp-collec-query-exc--require)
  (let ((buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (sp-collec-query-exc--draw spec))
    (switch-to-buffer buffer)))

(defun sp-collec-query-exc-refresh ()
  "Run the table's query again and redraw the grid."
  (interactive)
  (unless sp-collec-query-exc--spec
    (user-error "Not a query table"))
  (let ((cell (ignore-errors (exc-get-cell-at-point))))
    (sp-collec-query-exc--draw sp-collec-query-exc--spec)
    (when cell
      (ignore-errors
        (exc-etaf-goto (plist-get cell :slice-row) (1- (plist-get cell :slice-col)))))))

(defun sp-collec-query-exc--note-at-point ()
  "Return the note in the row at point, or nil on the header row."
  (let* ((cell (exc-get-cell-at-point))
         (row (plist-get cell :slice-row)))
    (when (and row (>= row 1) (<= row (length sp-collec-query-exc--notes)))
      (aref sp-collec-query-exc--notes (1- row)))))

(defun sp-collec-query-exc-open-note ()
  "Visit the note in the row at point."
  (interactive)
  (if-let* ((note (sp-collec-query-exc--note-at-point)))
      (progn (find-file (vulpea-note-path note))
             (when (> (or (vulpea-note-level note) 0) 0)
               (goto-char (vulpea-note-pos note))))
    (user-error "No note on this row")))

(defun sp-collec-query-exc-edit-query ()
  "Change this table's query in the menu; running it redraws this buffer."
  (interactive)
  (require 'sp-collection-query-tables-menu)
  (setq sp-collec-query-menu--spec (copy-tree sp-collec-query-exc--spec)
        sp-collec-query-menu--target (current-buffer))
  (sp-collec-query-menu))

(provide 'sp-collection-query-tables-exc)
;;; sp-collection-query-tables-exc.el ends here
