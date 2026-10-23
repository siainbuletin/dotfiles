;;; sp-vulpea-table-exc.el --- Vulpea tables as exc grids -*- lexical-binding: t; -*-

;;; Commentary:

;; Shows a Vulpea table in exc (https://github.com/yibie/exc), the
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
(require 'sp-vulpea-table-core)

(declare-function exc--show-grid "exc")
(declare-function exc--show-grid-in-current-buffer "exc")
(declare-function make-exc-default-data-source "exc-data-source")
(declare-function exc-set-style-at "exc")
(declare-function exc-set-frozen "exc")
(declare-function exc-set-column-width "exc")
(declare-function exc-get-cell-at-point "exc")
(declare-function exc-etaf-goto "exc-etaf")
(declare-function sp-vulpea-table-menu "sp-vulpea-table-menu")
(defvar exc--data-source)
(defvar sp-vulpea-table-menu--spec)
(defvar sp-vulpea-table-menu--target)

(defcustom sp-vulpea-table-exc-column-widths
  '((:title . 42) (:tags . 24) (:id . 38) (:path . 50) (t . 20))
  "Width in characters of each column in an exc table.
A column not listed uses the entry for t."
  :type '(alist :key-type (choice symbol string) :value-type integer)
  :group 'sp-vulpea-table)

(defvar-local sp-vulpea-table-exc--spec nil
  "The resolved spec the current exc table shows.")
(defvar-local sp-vulpea-table-exc--notes nil
  "Vector of the notes in the current exc table, one per data row.")
(defvar-local sp-vulpea-table-exc--refresher nil
  "The function this buffer subscribed to `sp-vulpea-table-refresh-functions'.")
(dolist (var '(sp-vulpea-table-exc--spec sp-vulpea-table-exc--notes
               sp-vulpea-table-exc--refresher))
  (put var 'permanent-local t))

(defun sp-vulpea-table-exc-available-p ()
  "Non-nil if exc and ETAF can be loaded."
  (and (require 'exc nil t) (locate-library "exc-etaf")
       (require 'etaf nil t)))

(defun sp-vulpea-table-exc--require ()
  "Load exc, or say what is missing."
  (unless (sp-vulpea-table-exc-available-p)
    (user-error "exc is not available: it needs Emacs 29.1 and the ecss, ebox, etaf and exc checkouts on `load-path' (see `sp-vulpea-table-renderer')")))

(defun sp-vulpea-table-exc--width (column)
  "Return the width for COLUMN."
  (or (alist-get column sp-vulpea-table-exc-column-widths nil nil #'equal)
      (alist-get t sp-vulpea-table-exc-column-widths)
      20))

;;;; Building the grid

(defun sp-vulpea-table-exc--guard (source columns notes)
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
                             (sp-vulpea-table-header-label (nth col columns))))
                (t (sp-vulpea-table-write-meta (aref notes (1- row)) (nth col columns) value)
                   (funcall original s row col value))))
             source)))

(defun sp-vulpea-table-exc--source (spec notes)
  "Return an exc data source for SPEC and the list NOTES."
  (let* ((columns (plist-get spec :columns))
         (labels (mapcar #'sp-vulpea-table-header-label columns))
         (source (make-exc-default-data-source
                  labels
                  (cons labels (sp-vulpea-table-rows notes columns))
                  (sp-vulpea-table-spec-summary spec))))
    (cl-loop for column in columns
             for i from 0
             do (exc-set-style-at source 0 i '(:bold t))
             do (exc-set-column-width source i (sp-vulpea-table-exc--width column)))
    (exc-set-frozen source 1 0)
    (sp-vulpea-table-exc--guard source columns (vconcat notes))
    source))

;;;; The buffer

(defvar sp-vulpea-table-exc-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c o") #'sp-vulpea-table-exc-open-note)
    (define-key map (kbd "C-c q") #'sp-vulpea-table-exc-edit-query)
    (define-key map (kbd "C-c C-u") #'sp-vulpea-table-exc-refresh)
    map)
  "Keymap of `sp-vulpea-table-exc-mode'.")

(define-minor-mode sp-vulpea-table-exc-mode
  "Keys for an exc grid that shows a Vulpea table.
\\{sp-vulpea-table-exc-mode-map}"
  :lighter " VTable"
  :keymap sp-vulpea-table-exc-mode-map)

(defun sp-vulpea-table-exc--draw (spec)
  "Run SPEC and draw the result in the current buffer."
  (let* ((notes (sp-vulpea-table-query spec))
         (source (sp-vulpea-table-exc--source spec notes)))
    (exc--show-grid-in-current-buffer source (sp-vulpea-table-spec-summary spec))
    (setq sp-vulpea-table-exc--spec spec
          sp-vulpea-table-exc--notes (vconcat notes))
    (sp-vulpea-table-exc-mode 1)
    (sp-vulpea-table-exc--subscribe)
    (length notes)))

(defun sp-vulpea-table-exc--subscribe ()
  "Refresh this buffer when `sp-vulpea-table-refresh-functions' run."
  (unless sp-vulpea-table-exc--refresher
    (let ((buffer (current-buffer)))
      (setq sp-vulpea-table-exc--refresher
            (lambda ()
              (if (buffer-live-p buffer)
                  (with-current-buffer buffer (sp-vulpea-table-exc-refresh))
                (remove-hook 'sp-vulpea-table-refresh-functions
                             sp-vulpea-table-exc--refresher))))
      (add-hook 'sp-vulpea-table-refresh-functions sp-vulpea-table-exc--refresher)
      (add-hook 'kill-buffer-hook
                (lambda ()
                  (remove-hook 'sp-vulpea-table-refresh-functions
                               sp-vulpea-table-exc--refresher))
                nil t))))

(defun sp-vulpea-table-exc-open (spec buffer-name)
  "Show SPEC, already resolved, in an exc grid called BUFFER-NAME."
  (sp-vulpea-table-exc--require)
  (let ((buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (sp-vulpea-table-exc--draw spec))
    (switch-to-buffer buffer)))

(defun sp-vulpea-table-exc-refresh ()
  "Run the table's query again and redraw the grid."
  (interactive)
  (unless sp-vulpea-table-exc--spec
    (user-error "Not a Vulpea table"))
  (let ((cell (ignore-errors (exc-get-cell-at-point))))
    (sp-vulpea-table-exc--draw sp-vulpea-table-exc--spec)
    (when cell
      (ignore-errors
        (exc-etaf-goto (plist-get cell :slice-row) (1- (plist-get cell :slice-col)))))))

(defun sp-vulpea-table-exc--note-at-point ()
  "Return the note in the row at point, or nil on the header row."
  (let* ((cell (exc-get-cell-at-point))
         (row (plist-get cell :slice-row)))
    (when (and row (>= row 1) (<= row (length sp-vulpea-table-exc--notes)))
      (aref sp-vulpea-table-exc--notes (1- row)))))

(defun sp-vulpea-table-exc-open-note ()
  "Visit the note in the row at point."
  (interactive)
  (if-let* ((note (sp-vulpea-table-exc--note-at-point)))
      (progn (find-file (vulpea-note-path note))
             (when (> (or (vulpea-note-level note) 0) 0)
               (goto-char (vulpea-note-pos note))))
    (user-error "No note on this row")))

(defun sp-vulpea-table-exc-edit-query ()
  "Change this table's query in the menu; running it redraws this buffer."
  (interactive)
  (require 'sp-vulpea-table-menu)
  (setq sp-vulpea-table-menu--spec (copy-tree sp-vulpea-table-exc--spec)
        sp-vulpea-table-menu--target (current-buffer))
  (sp-vulpea-table-menu))

(provide 'sp-vulpea-table-exc)
;;; sp-vulpea-table-exc.el ends here
