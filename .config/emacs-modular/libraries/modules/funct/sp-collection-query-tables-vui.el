;;; sp-collection-query-tables-vui.el --- Query tables as vui components -*- lexical-binding: t; -*-

;;; Commentary:

;; The vui renderer: a live table in its own buffer, and tables mounted
;; inline in place of the `collection-query-table' dynamic blocks of a note.  It
;; was the only renderer before exc and stays as the fallback for when exc
;; or ETAF cannot be loaded (see `sp-collection-query-tables-renderer').

;;; Code:

(require 'subr-x)
(require 'vui)
(require 'sp-collection-query-tables-core)
(require 'sp-collection-query-tables-org)

(vui-defcomponent sp-collection-query-tables (spec)
  "A live table of the notes SPEC asks for, with clickable titles.
Meta columns are editable fields that write back to their note.  Click a
column in the \"Sort by\" row to sort by it, and again to reverse."
  :state ((refresh-tick 0)
          (sort-override nil)
          (sort-desc nil))
  :render
  (progn
    (vui-use-effect ()
      (let ((fn (lambda () (vui-set-state :refresh-tick #'1+))))
        (add-hook 'sp-collection-query-tables-refresh-functions fn)
        (lambda () (remove-hook 'sp-collection-query-tables-refresh-functions fn))))
    (let* ((columns (plist-get spec :columns))
           (effective-sort (or sort-override (plist-get spec :sort-by)))
           (descending (if sort-override sort-desc (plist-get spec :sort-desc)))
           (notes (sp-collection-query-tables-sort
                   (sp-collection-query-tables-query (plist-put (copy-sequence spec) :sort-by nil))
                   effective-sort descending))
           (rows (mapcar
                  (lambda (note)
                    (mapcar
                     (lambda (c)
                       (cond
                        ((eq c :title)
                         (vui-button (or (vulpea-note-title note) "")
                                     :on-click (lambda () (find-file (vulpea-note-path note)))))
                        ((keywordp c) (sp-collection-query-tables-cell note c))
                        (t (vui-field
                            :value (or (car (vulpea-note-meta-get-list note c)) "")
                            :on-change (lambda (val)
                                         (sp-collection-query-tables-write-meta note c val)
                                         (vui-set-state :refresh-tick #'1+))))))
                     columns))
                  notes)))
      (vui-vstack
       (vui-text (sp-collection-query-tables-spec-summary spec) :face 'bold)
       (vui-text (format "%d note%s" (length notes) (if (= (length notes) 1) "" "s"))
                 :face 'shadow)
       (vui-newline)
       (apply #'vui-hstack
              (vui-text "Sort by: " :face 'shadow)
              (mapcar
               (lambda (c)
                 (vui-button
                  (concat (sp-collection-query-tables-header-label c)
                          (cond ((not (equal effective-sort c)) "")
                                (descending " ↓") (t " ↑")))
                  :on-click (lambda ()
                              (if (equal effective-sort c)
                                  (progn (vui-set-state :sort-override c)
                                         (vui-set-state :sort-desc (not descending)))
                                (vui-set-state :sort-override c)
                                (vui-set-state :sort-desc nil)))))
               columns))
       (vui-newline)
       (vui-table :columns (mapcar (lambda (c)
                                     (list :header (sp-collection-query-tables-header-label c)
                                           :width 24))
                                   columns)
                  :rows rows :border :ascii)))))

(defun sp-collection-query-tables-vui-open (spec buffer-name)
  "Show SPEC, already resolved, as a live vui table in BUFFER-NAME."
  (vui-mount (vui-component 'sp-collection-query-tables :spec spec) buffer-name))

;;;; Inline mounting

(defvar-local sp-collection-query-tables-vui--instances nil
  "Live inline tables mounted in this buffer.")

(defvar-local sp-collection-query-tables-vui--active nil
  "Non-nil if inline tables should stay live in this buffer across saves.")

(defun sp-collection-query-tables-vui--dblock-regions ()
  "Return (SPEC CONTENT-BEGIN CONTENT-END) for each query table dblock."
  (let (blocks)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*#\\+BEGIN:[ \t]+\\(?:collection-query-table\\|vulpea-table\\)\\(.*\\)$" nil t)
        (let* ((params (ignore-errors (car (read-from-string (format "(%s)" (match-string 1))))))
               (begin (progn (forward-line 1) (point)))
               (end (if (re-search-forward "^[ \t]*#\\+END:" nil t)
                        (line-beginning-position)
                      (point))))
          (when params (push (list params begin end) blocks)))))
    (nreverse blocks)))

(defun sp-collection-query-tables-vui--clear ()
  "Unmount the inline tables and write the plain dblock text back."
  (dolist (instance sp-collection-query-tables-vui--instances)
    (vui-unmount instance))
  (setq sp-collection-query-tables-vui--instances nil)
  (let ((modified (buffer-modified-p)))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*#\\+BEGIN:[ \t]+\\(?:collection-query-table\\|vulpea-table\\)" nil t)
        (beginning-of-line)
        (ignore-errors (org-dblock-update))
        (forward-line 1)))
    (restore-buffer-modified-p modified)))

(defun sp-collection-query-tables-inline-mount ()
  "Replace the content of every query table dblock with a live table."
  (interactive)
  (sp-collection-query-tables-vui--clear)
  (let ((modified (buffer-modified-p)))
    (dolist (block (reverse (sp-collection-query-tables-vui--dblock-regions)))
      (pcase-let ((`(,params ,begin ,end) block))
        ;; Resolved here, in the note's own buffer, so "self" is this note.
        (let ((spec (sp-collection-query-tables-resolve-spec params)))
          (goto-char begin)
          (delete-region begin end)
          (push (vui-mount-inline (vui-component 'sp-collection-query-tables :spec spec))
                sp-collection-query-tables-vui--instances))))
    (restore-buffer-modified-p modified))
  (setq sp-collection-query-tables-vui--active t))

(defun sp-collection-query-tables-inline-unmount ()
  "Unmount the inline tables, restoring plain dblock text."
  (interactive)
  (sp-collection-query-tables-vui--clear)
  (setq sp-collection-query-tables-vui--active nil))

(defun sp-collection-query-tables-inline-toggle ()
  "Toggle live inline query tables in the current buffer."
  (interactive)
  (if sp-collection-query-tables-vui--active
      (progn (sp-collection-query-tables-inline-unmount) (message "Inline query tables: off"))
    (sp-collection-query-tables-inline-mount)
    (message "Inline query tables: on")))

(defun sp-collection-query-tables-vui--before-save ()
  "Put real text in the buffer before it is saved."
  (when sp-collection-query-tables-vui--instances
    (sp-collection-query-tables-vui--clear)))

(defun sp-collection-query-tables-vui--after-save ()
  "Mount the inline tables again after a save, if they were on."
  (when sp-collection-query-tables-vui--active
    (sp-collection-query-tables-inline-mount)))

(add-hook 'org-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'sp-collection-query-tables-vui--before-save nil t)
            (add-hook 'after-save-hook #'sp-collection-query-tables-vui--after-save nil t)))

(define-obsolete-function-alias 'sia-vulpea-inline-tables-toggle
  #'sp-collection-query-tables-inline-toggle "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-inline-tables-mount
  #'sp-collection-query-tables-inline-mount "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-inline-tables-unmount
  #'sp-collection-query-tables-inline-unmount "2026-10-21")

(provide 'sp-collection-query-tables-vui)
;;; sp-collection-query-tables-vui.el ends here
