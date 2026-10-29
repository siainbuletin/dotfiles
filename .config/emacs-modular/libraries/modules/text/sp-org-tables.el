;;; sp-org-tables.el --- Org table rendering, wrapping and monospace -*- lexical-binding: t; -*-

;;; Commentary:

;; This is specific functionality for dealing with org-mode tables
;; better. It would be great if they could be rendered in the manner
;; that Dataview tables are in Obsidian (clean, dynamic, so on).
;;
;; It's worth exploring using ~textui~, as it develops.

;;; Code:

(defun sia-render-org-table-at-point ()
  (interactive)
  (save-excursion
    (beginning-of-line)
    (if (overlays-at (point))
        ;; this is a rough solution, because there can
        ;; be other overlays at point
        (delete-overlay (car (overlays-at (point))))

      (let* ((element-type (org-element-type (org-element-at-point))))
        (if (and (not (eq element-type 'table))
                 (not (eq element-type 'table-row)))
            (error "not at an org table")

          (while (not (eq 'table (org-element-type (org-element-at-point))))
            (forward-line -1))

          (sia-render-org-table (org-element-at-point)))))))

(defun sia-render-org-table (table)
  (interactive)
  (let* ((begin (org-element-property :begin table))
         (end (let ((pos (org-element-property :end table)))
                (goto-char pos)
                (beginning-of-line)
                ;; skip possible space after table
                (while (not (looking-at " *[|#]"))
                  (setq pos (point))
                  (forward-line -1))
                pos))
         (tabletxt (buffer-substring-no-properties begin end))
         (img (with-temp-buffer
                (insert tabletxt)
                (mark-whole-buffer)
                (org-latex-convert-region-to-latex)
                (org-preview-latex-fragment)
                (goto-char (point-min))
                (overlay-get  (car (overlays-at (point))) 'display)))
         (overlay (make-overlay begin end)))
    (overlay-put overlay 'display img)
    (forward-line -1)))

(defun sia-render-org-tables-in-buffer ()
  (save-excursion
    (org-element-map (org-element-parse-buffer) 'table 'sia-render-org-table)))

;;;; Org Table Wrap
;; see https://emacs.stackexchange.com/a/30871/11934
(defun org-table-wrap-to-width (width)
  "Wrap current column to WIDTH."
  (interactive (list (read-number "Enter column width: ")))
  (org-table-check-inside-data-field)
  (org-table-align)

  (let (cline (ccol (org-table-current-column)) new-row-count (more t))
    (org-table-goto-line 1)
    (org-table-goto-column ccol)

    (while more
      (setq cline (org-table-current-line))

      ;; Cut current field
      (org-table-copy-region (point) (point) 'cut)

      ;; Justify for width
      (setq org-table-clip
            (mapcar 'list (org-wrap (caar org-table-clip) width nil)))

      ;; Add new lines and fill
      (setq new-row-count (1- (length org-table-clip)))
      (if (> new-row-count 0)
          (org-table-insert-n-row-below new-row-count))
      (org-table-goto-line cline)
      (org-table-goto-column ccol)
      (org-table-paste-rectangle)
      (org-table-goto-line (+ cline new-row-count))

      ;; Move to next line
      (setq more (org-table-goto-line (+ cline new-row-count 1)))
      (org-table-goto-column ccol))

    (org-table-goto-line 1)
    (org-table-goto-column ccol)))

(defun org-table-insert-n-row-below (n)
  "Insert N new lines below the current."
  (let* ((line (buffer-substring (point-at-bol) (point-at-eol)))
         (new (org-table-clean-line line)))
    ;; Fix the first field if necessary
    (if (string-match "^[ \t]*| *[#$] *|" line)
        (setq new (replace-match (match-string 0 line) t t new)))
    (beginning-of-line 2)
    (setq new
          (apply 'concat (make-list n (concat new "\n"))))
    (let (org-table-may-need-update) (insert-before-markers new))  ;;; remove?
    (beginning-of-line 0)
    (re-search-forward "| ?" (point-at-eol) t)
    (and (or org-table-may-need-update org-table-overlay-coordinates) ;;; remove?
         (org-table-align))
    (org-table-fix-formulas "@" nil (1- (org-table-current-dline)) n)))

;;;; Force monospace font in org tables
;; If you use variable-pitch (a.k.a. “proportional”) fonts in Org buffers (e.g. using
;; org-variable-pitch), you probably use monospace fonts for Org tables, so they align
;; properly. However, other elements in a table (such as links, or perhaps timestamps)
;; may still use variable-pitch fonts, which breaks alignment. This code fixes that by
;; forcibly applying the org-table face family to entire Org tables (which are detected
;; by finding existing text with the org-table face, which makes use of Org’s built-in
;; fontification).
;;
;; To use, activate unpackaged/org-table-face-mode. You may want to add it to org-mode-hook.
;;
;; source: https://github.com/alphapapa/unpackaged.el#force-monospace-face-in-tables

;;;###autoload
(define-minor-mode unpackaged/org-table-face-mode
  "Apply `org-table' face family to all text in Org tables.
Useful for forcibly applying the face to portions of table data
that might have a different face, which could affect alignment."
  :global nil
  (let ((keywords '((unpackaged/org-table-face-matcher 0 'org-table))))
    (if unpackaged/org-table-face-mode
        (font-lock-add-keywords nil keywords 'append)
      (font-lock-remove-keywords nil keywords))
    (font-lock-flush)))

(cl-defun unpackaged/org-table-face-matcher
    (limit &optional (face `(:family ,(face-attribute 'org-table :family))))
  "Apply FACE to entire Org tables.
A `font-lock-keywords' function that searches up to LIMIT."
  (cl-flet* ((find-face (face &optional limit not)
                        ;; Return next position up to LIMIT that has FACE, or doesn't if NOT.
                        (cl-loop with prev-pos
                                 with pos = (point)
                                 while (not (eobp))
                                 do (setf pos (next-single-property-change pos 'face nil limit))
                                 while (and pos (not (equal pos prev-pos)))
                                 for face-at = (get-text-property pos 'face)
                                 for face-matches-p = (or (eq face-at face)
                                                          (when (listp face-at)
                                                            (member face face-at)))
                                 when (or (and not (not face-matches-p))
                                          face-matches-p)
                                 return pos
                                 do (setf prev-pos pos)))
             (apply-face-from (pos face)
                              (unless (eobp)
                                (let* ((property-at-start (get-text-property pos 'face))
                                       (table-face-start (if (or (eq property-at-start 'org-table)
                                                                 (when (listp property-at-start)
                                                                   (member 'org-table property-at-start)))
                                                             (point)
                                                           (find-face 'org-table limit)))
                                       table-face-end)
                                  (when table-face-start
                                    (goto-char table-face-start)
                                    (setf table-face-end (line-end-position))
                                    (add-face-text-property table-face-start table-face-end face)
                                    (goto-char table-face-end))))))
    (cl-loop with applied-p
             for applied = (apply-face-from (point) face)
             when applied
             do (setf applied-p t)
             while applied
             finally return applied-p)))

(provide 'sp-org-tables)
;; sp-org-tables.el ends here.
