;;; sp-vulpea-vui-table.el --- Live Vulpea property tables with vui -*- lexical-binding: t; -*-

;;; Commentary:

;; This module builds an interactive table of Vulpea notes in its own buffer,
;; using the declarative component library `vui'. Note titles are buttons that
;; open the note, columns can be sorted by clicking, and meta properties (the
;; description-list lines of the form KEY :: value that Vulpea reads as
;; metadata) are editable fields that write straight back into the note file.

;;; Code:

(require 'vui)
(require 'vulpea)
(require 'sp-vulpea-dblock) ; for sia-vulpea--resolve-parent-of / sia-vulpea--note-matches-p

;;; Cross-buffer refresh broadcasting ----------------------------------

(defvar sp-vulpea-table-refresh-functions nil
  "Abnormal hook: functions called with no arguments to signal that
open live Vulpea tables should refresh. Each mounted
`sp-vulpea-table' instance subscribes to this while it's alive
(via `vui-use-effect') and unsubscribes on unmount.")

(defun sia-vulpea-refresh-all-tables ()
  "Signal every open live Vulpea table to refresh itself."
  (interactive)
  (run-hook-with-args 'sp-vulpea-table-refresh-functions))

(defvar sia-vulpea--refresh-after-save-timer nil)

(defun sia-vulpea--schedule-refresh-after-save ()
  "Debounced trigger for `sia-vulpea-refresh-all-tables' after a note is saved.
There's no confirmed public \"Vulpea db sync completed\" hook to
key off of directly, so this waits half a second after any Org
save -- on the assumption your existing `vulpea-db-autosync'
setup updates the db synchronously (or near enough) on save --
before broadcasting the refresh. If tables sometimes reload with
stale data, this delay is the first thing to lengthen."
  (when (and buffer-file-name (derived-mode-p 'org-mode))
    (when (timerp sia-vulpea--refresh-after-save-timer)
      (cancel-timer sia-vulpea--refresh-after-save-timer))
    (setq sia-vulpea--refresh-after-save-timer
          (run-with-timer 0.5 nil #'sia-vulpea-refresh-all-tables))))

(add-hook 'after-save-hook #'sia-vulpea--schedule-refresh-after-save)

;;; Writing a meta property back to its note ----------------------------

(defun sia-vulpea--write-meta (note key value)
  "Set NOTE's meta property KEY to VALUE, in NOTE's own file.
Rewrites the existing \"- KEY :: ...\" description-list line if
one exists; otherwise inserts a new one just before the first
heading (or at the end of the file, if there is no heading).

I could not confirm a public Vulpea function for writing this
description-list metadata format -- only the older #+KEYWORD:
file-property system (`vulpea-buffer-prop-set') is documented --
so this edits the line directly, in the same format
`vulpea-note-meta-get-list' reads. Saves the buffer; relies on
your existing autosync to pick the change up (which, via
`sia-vulpea--schedule-refresh-after-save' above, also refreshes
every open live table -- including this one)."
  (with-current-buffer (find-file-noselect (vulpea-note-path note))
    (save-excursion
      (goto-char (point-min))
      (let* ((case-fold-search t)
             (re (format "^\\(-[ \t]+%s[ \t]+::[ \t]*\\).*$" (regexp-quote key)))
             (escaped (replace-regexp-in-string "\\\\" "\\\\\\\\" value)))
        (if (re-search-forward re nil t)
            (replace-match (concat "\\1" escaped) t)
          (goto-char (point-min))
          (if (re-search-forward "^\\*" nil t)
              (progn (beginning-of-line) (insert (format "- %s :: %s\n" key value)))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert (format "- %s :: %s\n" key value))))))
    (save-buffer)))

(defun sia-vulpea-vui--cell (note column)
  "Return a display string for COLUMN of NOTE.
Same COLUMN shapes as the dblock version: a keyword for a
built-in field (:tags, :id, :file), or a string naming a Vulpea
meta key. :title is handled separately by the caller, since it
becomes a button rather than plain text."
  (pcase column
    (:tags (mapconcat #'identity (vulpea-note-tags note) ", "))
    (:id (vulpea-note-id note))
    (:file (file-name-nondirectory (vulpea-note-path note)))
    ((pred stringp)
     (mapconcat #'identity (or (vulpea-note-meta-get-list note column) '(""))
                ", "))
    (_ "")))

(defun sia-vulpea-vui--header-label (column)
  "Return a display label for COLUMN."
  (if (keywordp column) (capitalize (substring (symbol-name column) 1)) column))

(vui-defcomponent sp-vulpea-table (tags columns sort-by parent-of parent-prop parent-title)
  "A live, clickable, editable table of Vulpea notes.
TAGS filters notes (must have all of them). COLUMNS is the
ordered list of fields to show -- :title is always a button that
opens the note; :tags/:id/:file are read-only; a string (a meta
key) is rendered as an editable field that writes straight back
to the note on submit (see `sia-vulpea--write-meta'). SORT-BY is
the initial sort column; click any column's button in the \"Sort
by:\" row to change it live, or click it again to reverse
direction -- this overrides SORT-BY once clicked (mirrors what
you called \"overwriting the :sort property\"). PARENT-OF/
PARENT-PROP/PARENT-TITLE are as in `sia-vulpea--note-matches-p'
and the parent-display line.

The table also refreshes automatically: it subscribes to
`sp-vulpea-table-refresh-functions' while mounted, which fires
after any note is saved (see `sia-vulpea--schedule-refresh-after-save')."
  :state ((refresh-tick 0)
          (sort-override nil)
          (sort-desc nil))
  :render
  (progn
    (vui-use-effect ()
      (let ((fn (lambda () (vui-set-state :refresh-tick #'1+))))
        (add-hook 'sp-vulpea-table-refresh-functions fn)
        (lambda () (remove-hook 'sp-vulpea-table-refresh-functions fn))))
    (let* ((effective-sort (or sort-override sort-by))
           (notes (vulpea-db-query
                   (lambda (note)
                     (sia-vulpea--note-matches-p note tags parent-of parent-prop))))
           (notes (if effective-sort
                      (let ((sorted (seq-sort-by
                                     (lambda (n) (sia-vulpea-vui--cell n effective-sort))
                                     #'string< notes)))
                        (if sort-desc (reverse sorted) sorted))
                    notes))
           (vui-columns (mapcar (lambda (c)
                                   (list :header (sia-vulpea-vui--header-label c) :width 24))
                                 columns))
           (rows (mapcar
                  (lambda (note)
                    (mapcar
                     (lambda (c)
                       (cond
                        ((eq c :title)
                         (vui-button (vulpea-note-title note)
                                     :on-click (lambda () (find-file (vulpea-note-path note)))))
                        ((keywordp c) (sia-vulpea-vui--cell note c))
                        (t
                         ;; A meta key: editable. NOTE: I'm not fully
                         ;; certain `vui-field' uses :on-change for its
                         ;; commit callback -- check `describe-function
                         ;; vui-field' if edits don't seem to take.
                         (vui-field
                          :value (car (or (vulpea-note-meta-get-list note c) '("")))
                          :on-change (lambda (val)
                                       (sia-vulpea--write-meta note c val)
                                       (vui-set-state :refresh-tick #'1+))))))
                     columns))
                  notes)))
      (vui-vstack
       (when parent-title
         (vui-text (format "Parent: %s" parent-title) :face 'bold))
       (vui-text (format "%d note%s" (length notes) (if (= (length notes) 1) "" "s"))
                  :face 'shadow)
       (vui-newline)
       (apply #'vui-hstack
              (vui-text "Sort by: " :face 'shadow)
              (mapcar
               (lambda (c)
                 (vui-button
                  (concat (sia-vulpea-vui--header-label c)
                          (cond ((not (equal effective-sort c)) "")
                                (sort-desc " \u2193") (t " \u2191")))
                  :on-click (lambda ()
                              (if (equal sort-override c)
                                  (vui-set-state :sort-desc (not sort-desc))
                                (progn (vui-set-state :sort-override c)
                                       (vui-set-state :sort-desc nil))))))
               columns))
       (vui-newline)
       (vui-table :columns vui-columns :rows rows :border :ascii)))))

(defun sia-vulpea--table-buffer-name (view-name parent-of)
  "Return a buffer name for a live Vulpea table.
VIEW-NAME, if given, names it directly (so each saved view gets
its own persistent buffer instead of all views sharing one).
Otherwise, if PARENT-OF is set, name it after that note's title
so ad-hoc \"children of X\" queries are still distinguishable.
Falls back to a generic name."
  (cond
   (view-name (format "*vulpea: %s*" view-name))
   (parent-of
    (let ((note (ignore-errors (vulpea-db-get-by-id parent-of))))
      (format "*vulpea: children of %s*" (if note (vulpea-note-title note) parent-of))))
   (t "*vulpea table*")))

(defun sia-vulpea-open-table (&optional tags columns sort-by parent-of parent-prop view-name)
  "Open a live, clickable table of Vulpea notes in its own buffer.
Prompts for TAGS/COLUMNS/SORT-BY/PARENT-OF/PARENT-PROP when
called interactively (same shapes as the vulpea-table dblock --
see `org-dblock-write:vulpea-table'). PARENT-OF is chosen via
`sia-vulpea-read-parent' (pick \"self\", or any note through
`sia-vulpea-select-note', tag-annotated); if it comes back as
\"self\", it's resolved against the buffer you called this from
-- i.e. whichever note you were visiting -- *before* the new
table buffer takes over, so \"self\" means what you'd expect even
though the table itself opens somewhere else.

VIEW-NAME (only meaningful when called non-interactively, e.g.
from `sia-vulpea-open-saved-table') gives the resulting buffer
its own name, so different saved views stay in separate,
independently reusable buffers rather than overwriting each
other. The buffer also displays which parent note it's scoped
to, when PARENT-OF is set.

Click a title to open that note; press `g' in the resulting
buffer to refresh against the current state of the Vulpea db."
  (interactive
   (let* ((tags (split-string (read-string "Filter by tags (space-separated, blank for all): ") nil t))
          (columns-raw (split-string
                        (read-string "Columns (space-separated; :title/:tags/:id/:file or meta keys): "
                                     ":title")
                        nil t))
          (columns (mapcar (lambda (c) (if (string-prefix-p ":" c) (intern c) c)) columns-raw))
          (sort-by (let ((s (read-string "Sort by column (blank for none): ")))
                     (unless (string-empty-p s)
                       (if (string-prefix-p ":" s) (intern s) s))))
          (parent-of (sia-vulpea-read-parent t))
          (parent-prop (let ((s (read-string "Parent meta property (blank for \"parents\"): ")))
                          (unless (string-empty-p s) s))))
     ;; Resolve "self" now, in the buffer this command was called
     ;; from -- by the time vui-mount switches buffers below, we'd
     ;; have lost that context.
     (list tags columns sort-by (sia-vulpea--resolve-parent-of parent-of) parent-prop)))
  (let ((parent-title (and parent-of
                            (let ((note (ignore-errors (vulpea-db-get-by-id parent-of))))
                              (and note (vulpea-note-title note))))))
    (vui-mount (vui-component 'sp-vulpea-table
                 :tags tags :columns columns :sort-by sort-by
                 :parent-of parent-of :parent-prop parent-prop :parent-title parent-title)
               (sia-vulpea--table-buffer-name view-name parent-of))))

(provide 'sp-vulpea-vui-table)
;;; sp-vulpea-vui-table.el ends here
