;;; sp-vulpea-table-vui.el --- Vulpea tables as vui components -*- lexical-binding: t; -*-

;;; Commentary:

;; The vui renderer: a live table in its own buffer, and tables mounted
;; inline in place of the `vulpea-table' dynamic blocks of a note.  It
;; was the only renderer before exc and stays as the fallback for when exc
;; or ETAF cannot be loaded (see `sp-vulpea-table-renderer').

;;; Code:

(require 'subr-x)
(require 'vui)
(require 'sp-vulpea-table-core)
(require 'sp-vulpea-table-org)

(vui-defcomponent sp-vulpea-table (spec)
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
        (add-hook 'sp-vulpea-table-refresh-functions fn)
        (lambda () (remove-hook 'sp-vulpea-table-refresh-functions fn))))
    (let* ((columns (plist-get spec :columns))
           (effective-sort (or sort-override (plist-get spec :sort-by)))
           (descending (if sort-override sort-desc (plist-get spec :sort-desc)))
           (notes (sp-vulpea-table-sort
                   (sp-vulpea-table-query (plist-put (copy-sequence spec) :sort-by nil))
                   effective-sort descending))
           (rows (mapcar
                  (lambda (note)
                    (mapcar
                     (lambda (c)
                       (cond
                        ((eq c :title)
                         (vui-button (or (vulpea-note-title note) "")
                                     :on-click (lambda () (find-file (vulpea-note-path note)))))
                        ((keywordp c) (sp-vulpea-table-cell note c))
                        (t (vui-field
                            :value (or (car (vulpea-note-meta-get-list note c)) "")
                            :on-change (lambda (val)
                                         (sp-vulpea-table-write-meta note c val)
                                         (vui-set-state :refresh-tick #'1+))))))
                     columns))
                  notes)))
      (vui-vstack
       (vui-text (sp-vulpea-table-spec-summary spec) :face 'bold)
       (vui-text (format "%d note%s" (length notes) (if (= (length notes) 1) "" "s"))
                 :face 'shadow)
       (vui-newline)
       (apply #'vui-hstack
              (vui-text "Sort by: " :face 'shadow)
              (mapcar
               (lambda (c)
                 (vui-button
                  (concat (sp-vulpea-table-header-label c)
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
                                     (list :header (sp-vulpea-table-header-label c)
                                           :width 24))
                                   columns)
                  :rows rows :border :ascii)))))

(defun sp-vulpea-table-vui-open (spec buffer-name)
  "Show SPEC, already resolved, as a live vui table in BUFFER-NAME."
  (vui-mount (vui-component 'sp-vulpea-table :spec spec) buffer-name))

;;;; Inline mounting

(defvar-local sp-vulpea-table-vui--instances nil
  "Live inline tables mounted in this buffer.")

(defvar-local sp-vulpea-table-vui--active nil
  "Non-nil if inline tables should stay live in this buffer across saves.")

(defun sp-vulpea-table-vui--dblock-regions ()
  "Return (SPEC CONTENT-BEGIN CONTENT-END) for each vulpea-table dblock."
  (let (blocks)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*#\\+BEGIN:[ \t]+vulpea-table\\(.*\\)$" nil t)
        (let* ((params (ignore-errors (car (read-from-string (format "(%s)" (match-string 1))))))
               (begin (progn (forward-line 1) (point)))
               (end (if (re-search-forward "^[ \t]*#\\+END:" nil t)
                        (line-beginning-position)
                      (point))))
          (when params (push (list params begin end) blocks)))))
    (nreverse blocks)))

(defun sp-vulpea-table-vui--clear ()
  "Unmount the inline tables and write the plain dblock text back."
  (dolist (instance sp-vulpea-table-vui--instances)
    (vui-unmount instance))
  (setq sp-vulpea-table-vui--instances nil)
  (let ((modified (buffer-modified-p)))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*#\\+BEGIN:[ \t]+vulpea-table" nil t)
        (beginning-of-line)
        (ignore-errors (org-dblock-update))
        (forward-line 1)))
    (restore-buffer-modified-p modified)))

(defun sp-vulpea-table-inline-mount ()
  "Replace the content of every vulpea-table dblock with a live table."
  (interactive)
  (sp-vulpea-table-vui--clear)
  (let ((modified (buffer-modified-p)))
    (dolist (block (reverse (sp-vulpea-table-vui--dblock-regions)))
      (pcase-let ((`(,params ,begin ,end) block))
        ;; Resolved here, in the note's own buffer, so "self" is this note.
        (let ((spec (sp-vulpea-table-resolve-spec params)))
          (goto-char begin)
          (delete-region begin end)
          (push (vui-mount-inline (vui-component 'sp-vulpea-table :spec spec))
                sp-vulpea-table-vui--instances))))
    (restore-buffer-modified-p modified))
  (setq sp-vulpea-table-vui--active t))

(defun sp-vulpea-table-inline-unmount ()
  "Unmount the inline tables, restoring plain dblock text."
  (interactive)
  (sp-vulpea-table-vui--clear)
  (setq sp-vulpea-table-vui--active nil))

(defun sp-vulpea-table-inline-toggle ()
  "Toggle live inline Vulpea tables in the current buffer."
  (interactive)
  (if sp-vulpea-table-vui--active
      (progn (sp-vulpea-table-inline-unmount) (message "Inline Vulpea tables: off"))
    (sp-vulpea-table-inline-mount)
    (message "Inline Vulpea tables: on")))

(defun sp-vulpea-table-vui--before-save ()
  "Put real text in the buffer before it is saved."
  (when sp-vulpea-table-vui--instances
    (sp-vulpea-table-vui--clear)))

(defun sp-vulpea-table-vui--after-save ()
  "Mount the inline tables again after a save, if they were on."
  (when sp-vulpea-table-vui--active
    (sp-vulpea-table-inline-mount)))

(add-hook 'org-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'sp-vulpea-table-vui--before-save nil t)
            (add-hook 'after-save-hook #'sp-vulpea-table-vui--after-save nil t)))

(define-obsolete-function-alias 'sia-vulpea-inline-tables-toggle
  #'sp-vulpea-table-inline-toggle "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-inline-tables-mount
  #'sp-vulpea-table-inline-mount "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-inline-tables-unmount
  #'sp-vulpea-table-inline-unmount "2026-10-21")

(provide 'sp-vulpea-table-vui)
;;; sp-vulpea-table-vui.el ends here
