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

;;;; Obsidian-style tables
;; `org-table-widget' (see `sp-textui') already draws a table as a clean widget.
;; These settings keep it from fighting `org-modern', switch off the zebra
;; stripes and make the borders and the header quiet, as in Obsidian.  The
;; borders are blended from the theme colours, so they follow every theme.

(defgroup sp-org-tables nil
  "Quiet, Obsidian-like Org tables."
  :group 'org
  :prefix "sp-org-tables-")

(defcustom sp-org-tables-border-strength 0.22
  "How visible table borders are, from 0 (invisible) to 1 (text colour)."
  :type 'number)

(defcustom sp-org-tables-header-strength 0.07
  "How strongly the header row background differs from the buffer background."
  :type 'number)

;; `org-modern' draws its own table borders; the widget must be the only one.
(setq org-modern-table nil)

(defun sp-org-tables--blend (strength)
  "The theme foreground mixed into the background by STRENGTH, as #rrggbb.
Return nil when either colour is unknown (a terminal without colours)."
  (and-let* ((fg (color-name-to-rgb (face-attribute 'default :foreground nil 'default)))
             (bg (color-name-to-rgb (face-attribute 'default :background nil 'default))))
    (apply #'color-rgb-to-hex
           (append (cl-mapcar (lambda (f b) (+ (* strength f) (* (- 1 strength) b)))
                              fg bg)
                   '(2)))))

(defun sp-org-tables-update-faces (&rest _)
  "Make the table widget faces quiet, from the colours of the current theme."
  (when (facep 'org-table-widget-border)
    (when-let* ((border (sp-org-tables--blend sp-org-tables-border-strength)))
      (set-face-attribute 'org-table-widget-border nil
                          :inherit 'unspecified :foreground border))
    (set-face-attribute 'org-table-widget-header nil
                        :inherit 'bold
                        :background (or (sp-org-tables--blend sp-org-tables-header-strength)
                                        'unspecified))))

(with-eval-after-load 'org-table-widget
  (setq org-table-widget-zebra-stripe nil
        org-table-widget-use-unicode-borders t)
  (sp-org-tables-update-faces))

(add-hook 'enable-theme-functions #'sp-org-tables-update-faces)

;;;; Quiet pipes in the plain-text table
;; In a terminal, or while a table is revealed for editing, the source shows.
;; This mode dims its `|' separators and rule lines, so the cell text stands out.

(defface sp-org-tables-pipe
  '((t :inherit shadow))
  "Face for the separators and rule lines of a plain-text Org table.")

(defun sp-org-tables--pipe-matcher (limit)
  "Find the next table `|' or rule line up to LIMIT, for font-lock."
  (catch 'found
    (while (re-search-forward "^[ \t]*|[-+|]*$\\||" limit t)
      (when (memq 'org-table (ensure-list (get-text-property (match-beginning 0) 'face)))
        (throw 'found t)))))

(defvar sp-org-tables--pipe-keywords
  '((sp-org-tables--pipe-matcher 0 'sp-org-tables-pipe prepend)))

;;;###autoload
(define-minor-mode sp-org-tables-quiet-pipes-mode
  "Dim the `|' separators and rule lines of plain-text Org tables."
  :global nil
  (if sp-org-tables-quiet-pipes-mode
      (font-lock-add-keywords nil sp-org-tables--pipe-keywords 'append)
    (font-lock-remove-keywords nil sp-org-tables--pipe-keywords))
  (font-lock-flush))

(add-hook 'org-mode-hook #'sp-org-tables-quiet-pipes-mode)

;;;; Following links in table widgets
;; The widget draws a row as an overlay `before-string'; the source of the row
;; stays hidden underneath.  A click or RET therefore lands on the source, not
;; on the link that was drawn, and `org-open-at-point' then offers every link of
;; the entry.  These functions read the link from the drawn text instead.

(defun sp-org-tables--string-links (string)
  "The links drawn in STRING, as a list of (URI . TEXT) in order, without repeats.
URI comes from the `htmlize-link' property that Org puts on a link, which the
widget keeps in its cells."
  (let ((pos 0) (len (length string)) links)
    (while (< pos len)
      (let* ((next (or (next-single-property-change pos 'htmlize-link string) len))
             (uri (plist-get (get-text-property pos 'htmlize-link string) :uri)))
        (when (stringp uri)
          (let ((text (string-trim
                       (apply #'concat
                              (cl-loop for i from pos below next
                                       unless (get-text-property i 'invisible string)
                                       collect (string (aref string i)))))))
            (if-let* ((old (assoc uri links)))
                (when (string-empty-p (cdr old)) (setcdr old text))
              (push (cons uri text) links))))
        (setq pos next)))
    (nreverse links)))

(defun sp-org-tables--widget-overlay (&optional position)
  "The table widget row overlay at POSITION (point by default), or nil."
  (seq-find (lambda (overlay) (overlay-get overlay 'org-table-widget))
            (overlays-at (or position (point)))))

(defun sp-org-tables--open-uri (uri)
  "Follow the Org link target URI, as `org-open-at-point' does on a link."
  (org-link-open-from-string (format "[[%s]]" uri)))

(defun sp-org-tables--choose-link (links)
  "Follow the only link in LINKS, or ask which of them to follow."
  (sp-org-tables--open-uri
   (if (null (cdr links))
       (caar links)
     (let* ((choices (mapcar (lambda (link)
                               (cons (format "%s  (%s)" (cdr link) (car link))
                                     (car link)))
                             links))
            (choice (completing-read "Follow link: " (mapcar #'car choices) nil t)))
       (cdr (assoc choice choices))))))

(defun sp-org-tables-open-row-link ()
  "Follow a link of the table widget row at point; return nil if there is none.
One link is followed at once.  The choice menu only appears when the row has
several links, because RET cannot tell which one was meant (a click can)."
  (when-let* ((overlay (sp-org-tables--widget-overlay))
              (links (sp-org-tables--string-links
                      (or (overlay-get overlay 'before-string) ""))))
    (sp-org-tables--choose-link links)
    t))

(defun sp-org-tables-follow-link ()
  "Follow the link of the table widget row at point, or do what RET did before."
  (interactive)
  (unless (sp-org-tables-open-row-link)
    (call-interactively #'org-return)))

(defun sp-org-tables--clicked-uri (event)
  "The link target drawn at the position of mouse EVENT in a table widget, or nil."
  (let* ((posn (event-start event))
         (hit (posn-string posn)))
    (and (consp hit) (stringp (car hit))
         (bound-and-true-p org-table-widget-mode)
         (sp-org-tables--widget-overlay (posn-point posn))
         (plist-get (get-text-property (cdr hit) 'htmlize-link (car hit)) :uri))))

(define-advice org-open-at-mouse (:around (orig event) sp-org-tables-widget-link)
  "Follow the link that was clicked in a table widget, with no menu."
  (if-let* ((uri (sp-org-tables--clicked-uri event)))
      (progn (select-window (posn-window (event-start event)))
             (sp-org-tables--open-uri uri))
    (funcall orig event)))

;; `C-c C-o' on a widget row follows its link too.
(add-hook 'org-open-at-point-functions #'sp-org-tables-open-row-link)

(with-eval-after-load 'org-table-widget
  (keymap-set org-table-widget-map "RET" #'sp-org-tables-follow-link))

(provide 'sp-org-tables)
;; sp-org-tables.el ends here.
