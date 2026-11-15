;;; sp-batch-report-view.el --- Special-mode view of the batch reports -*- lexical-binding: t; -*-

;;; Commentary:

;; The default view of `sp-batch-report': a read-only `special-mode' buffer in
;; the style of the `vulpea-ui' dashboards.  Sections fold with TAB and show
;; their count at the window edge; entries are rows; a file is a link.
;; Dropping an entry only restyles its row, so it costs the same with ten
;; entries or ten thousand.  See docs/tangles/funct/sp-batch-report-view.org.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'sp-batch-report)

(declare-function org-link-open-from-string "ol")
(declare-function org-link-unescape "ol")
(declare-function sp-echo-help-set "sp-interaction")

(defface sp-batch-report-title
  '((t :inherit bold :height 1.2))
  "Face of the title of a report."
  :group 'sp-batch-report)

(defface sp-batch-report-section
  '((t :inherit bold))
  "Face of the name of a section of a report."
  :group 'sp-batch-report)

(defface sp-batch-report-count
  '((t :inherit shadow))
  "Face of the count at the right of a section header."
  :group 'sp-batch-report)

(defface sp-batch-report-column
  '((t :inherit bold :underline t))
  "Face of the column names of a table section."
  :group 'sp-batch-report)

(defface sp-batch-report-link
  '((t :inherit link))
  "Face of a link to a file or a note in a report."
  :group 'sp-batch-report)

(defface sp-batch-report-action
  '((t :inherit button))
  "Face of an entry that runs a command when you press RET on it."
  :group 'sp-batch-report)

(defface sp-batch-report-dropped
  '((t :inherit shadow :strike-through t))
  "Face of an entry that was dropped from the list."
  :group 'sp-batch-report)

(defconst sp-batch-report-view--count-width 18
  "Width of the count in a section header.
It is fixed, so a drop changes the count in place and no position moves.")

(defconst sp-batch-report-view--link-regexp
  "\\[\\[\\(\\(?:\\\\.\\|[^][\\\\]\\)+\\)\\]\\(?:\\[\\(\\(?:\\\\.\\|[^][\\\\]\\)+\\)\\]\\)?\\]"
  "Match an Org link: group 1 is the target, group 2 the description.")

(defvar-local sp-batch-report-view--rows nil
  "Vector of the rows, each (BEG END SECTION), in buffer order.")

(defvar-local sp-batch-report-view--sections nil
  "Vector of the sections: [BODY-BEG BODY-END KEPT TOTAL OVERLAY HEADER ARROW COUNT TITLE].
It stays when the mode is called again, so a refresh finds which sections were folded.")
(put 'sp-batch-report-view--sections 'permanent-local t)

(defvar-local sp-batch-report-view--by-key nil
  "Hash table from a key to the indexes of the rows that have it.")

(defvar-local sp-batch-report-view--dropped 0
  "The number of rows that are dropped now.")

(defvar-local sp-batch-report-view--folded nil
  "The titles of the folded sections; they stay folded when the report is made again.")
(put 'sp-batch-report-view--folded 'permanent-local t)

(defun sp-batch-report-view--linkify (text)
  "TEXT with each Org link in it turned into a button-like label."
  (if (not (string-search "[[" text))
      text
    (let ((pos 0) parts)
      (while (string-match sp-batch-report-view--link-regexp text pos)
        (let ((target (org-link-unescape (match-string 1 text)))
              (label (org-link-unescape (or (match-string 2 text) (match-string 1 text)))))
          (push (substring text pos (match-beginning 0)) parts)
          (push (propertize label 'face 'sp-batch-report-link 'mouse-face 'highlight
                            'help-echo "RET: visit" 'sp-batch-report-link target)
                parts)
          (setq pos (match-end 0))))
      (push (substring text pos) parts)
      (apply #'concat (nreverse parts)))))

(defun sp-batch-report-view--file-target (file &optional line)
  "The Org link target that visits FILE, at LINE when it is given."
  (concat "file:" (expand-file-name file)
          (cond ((integerp line) (format "::%d" line))
                ((stringp line) (concat "::" line)))))

(defun sp-batch-report-view--head (item)
  "The label of ITEM that visits its file, or nil when it has no file."
  (when-let* ((file (plist-get item :file)))
    (let ((line (plist-get item :line)))
      (propertize (or (plist-get item :label)
                      (concat (file-name-nondirectory (directory-file-name file))
                              (and (integerp line) (format ":%d" line))))
                  'face 'sp-batch-report-link 'mouse-face 'highlight
                  'help-echo "RET: visit"
                  'sp-batch-report-link (sp-batch-report-view--file-target file line)))))

(defun sp-batch-report-view--list-row (item)
  "The text of the list ITEM: a bullet, the file, the text, then the children."
  (let* ((head (sp-batch-report-view--head item))
         (text (plist-get item :text))
         (text (and text (sp-batch-report-view--linkify
                          (sp-batch-report--indent text "      ")))))
    (when (and (plist-get item :action) (not head) text)
      (setq text (propertize text 'face 'sp-batch-report-action 'mouse-face 'highlight)))
    (concat "  • " head (and head text "  ") text "\n"
            (mapconcat (lambda (child)
                         (concat "      · "
                                 (sp-batch-report-view--linkify
                                  (sp-batch-report--indent child "        "))
                                 "\n"))
                       (plist-get item :children) ""))))

(defun sp-batch-report-view--cell (cell)
  "CELL as one line of text, its links turned into labels."
  (sp-batch-report-view--linkify
   (replace-regexp-in-string "[\n\r]+" " " (format "%s" (or cell "")))))

(defun sp-batch-report-view--table-line (cells widths face)
  "The line of CELLS padded to WIDTHS; FACE, when given, is the face of the line."
  (let ((i -1) (n (length cells)))
    (concat "  "
            (mapconcat
             (lambda (cell)
               (setq i (1+ i))
               (let ((cell (if face (propertize (substring-no-properties cell) 'face face) cell)))
                 (if (= i (1- n))
                     cell
                   (concat cell (make-string (max 0 (- (or (nth i widths) 0) (string-width cell)))
                                             ?\s)))))
             cells "  ")
            "\n")))

(defun sp-batch-report-view--count-string (kept total)
  "The count of a section, KEPT of TOTAL, padded to the fixed width."
  (propertize (string-pad (if (= kept total)
                              (format "%d %s" total (if (= total 1) "entry" "entries"))
                            (format "%d of %d" kept total))
                          sp-batch-report-view--count-width nil t)
              'face 'sp-batch-report-count))

(defun sp-batch-report-view--render (model)
  "Draw the report MODEL in the current buffer.
MODEL is a plist with :title, :intro, :sections, :excluded and :key-label."
  (let* ((inhibit-read-only t)
         (excluded (plist-get model :excluded))
         (folded (if sp-batch-report-view--sections
                     (cl-loop for s across sp-batch-report-view--sections
                              when (aref s 4) collect (aref s 8))
                   sp-batch-report-view--folded))
         (by-key (make-hash-table :test #'equal))
         (rows nil) (nrows 0) (sections nil) (nsections 0) (ndropped 0)
         (known (make-hash-table :test #'equal))
         (all (plist-get model :sections)))
    (when-let* ((key-label (plist-get model :key-label))
                (_ excluded))
      (ignore key-label))
    (dolist (section all)
      (dolist (item (plist-get section :items))
        (when-let* ((key (sp-batch-report--item-key item)))
          (puthash key t known))))
    ;; Keys dropped earlier that this report no longer has go to a section of their own.
    (when-let* ((stale (seq-remove (lambda (key) (gethash key known)) excluded)))
      (setq all (append all
                        (list (sp-batch-report-section
                               "Dropped earlier, not in this report"
                               (mapcar (lambda (key)
                                         (sp-batch-report-item
                                          (funcall (or (plist-get model :key-label)
                                                       #'sp-batch-report--key-label)
                                                   key)
                                          :key key))
                                       stale))))))
    (erase-buffer)
    (remove-overlays)
    (insert (propertize (or (plist-get model :title) "Report") 'face 'sp-batch-report-title) "\n")
    (when-let* ((intro (plist-get model :intro)))
      (insert (sp-batch-report-view--linkify intro) "\n"))
    (insert "\n")
    (dolist (section all)
      (let* ((sec nsections)
             (header (plist-get section :header))
             (items (plist-get section :items))
             (hs (point))
             arrow count-pos body-beg (total 0) (dropped 0) widths cells)
        (setq arrow (point))
        (insert (propertize "▼" 'face 'sp-batch-report-section) " "
                (propertize (plist-get section :title) 'face 'sp-batch-report-section)
                (propertize " " 'display
                            `(space :align-to (- right ,(1+ sp-batch-report-view--count-width)))))
        (setq count-pos (point))
        (insert (sp-batch-report-view--count-string (length items) (length items)) "\n")
        (add-text-properties hs (point) (list 'sp-batch-report-section sec 'sp-batch-report-header t))
        (setq body-beg (point))
        (when header
          (setq cells (mapcar (lambda (item) (mapcar #'sp-batch-report-view--cell (plist-get item :row)))
                              items))
          (setq widths (apply #'cl-mapcar
                              (lambda (&rest column) (apply #'max (mapcar #'string-width column)))
                              header cells))
          (let ((line-start (point)))
            (insert (sp-batch-report-view--table-line header widths 'sp-batch-report-column))
            (put-text-property line-start (point) 'sp-batch-report-section sec)))
        (if (null items)
            (let ((start (point)))
              (insert "  " (or (plist-get section :empty) "none") "\n")
              (add-text-properties start (point) (list 'face 'shadow 'sp-batch-report-section sec)))
          (dolist (item items)
            (let* ((key (sp-batch-report--item-key item))
                   (drop (and key (member key excluded) t))
                   (beg (point))
                   (action (plist-get item :action)))
              (insert (if header
                          (sp-batch-report-view--table-line (pop cells) widths nil)
                        (sp-batch-report-view--list-row item)))
              (add-text-properties
               beg (point)
               (append (sp-batch-report--item-props item drop)
                       (and action (list 'sp-batch-report-action action))
                       (list 'sp-batch-report-row nrows 'sp-batch-report-section sec
                             'wrap-prefix "      ")))
              (when drop
                (add-face-text-property beg (point) 'sp-batch-report-dropped)
                (cl-incf dropped) (cl-incf ndropped))
              (push (list beg (point) sec) rows)
              (when key (puthash key (cons nrows (gethash key by-key)) by-key))
              (cl-incf nrows) (cl-incf total))))
        (let ((inhibit-modification-hooks t))
          (save-excursion
            (goto-char count-pos)
            (delete-region count-pos (+ count-pos sp-batch-report-view--count-width))
            (insert (sp-batch-report-view--count-string (- total dropped) total))))
        (push (vector body-beg (point) (- total dropped) total nil hs arrow count-pos
                      (plist-get section :title))
              sections)
        (cl-incf nsections)))
    (setq sp-batch-report-view--rows (vconcat (nreverse rows))
          sp-batch-report-view--sections (vconcat (nreverse sections))
          sp-batch-report-view--by-key by-key
          sp-batch-report-view--dropped ndropped
          sp-batch-report-view--folded nil)
    (dotimes (i nsections)
      (when (member (aref (aref sp-batch-report-view--sections i) 8) folded)
        (sp-batch-report-view--fold i t)))
    (set-buffer-modified-p nil)
    (goto-char (point-min))))

(defun sp-batch-report-view--fold (sec folded)
  "Fold the section number SEC when FOLDED is non-nil, else unfold it."
  (let* ((s (aref sp-batch-report-view--sections sec))
         (overlay (aref s 4))
         (inhibit-read-only t))
    (if folded
        (unless overlay
          (setq overlay (make-overlay (aref s 0) (aref s 1) nil t))
          (overlay-put overlay 'invisible 'sp-batch-report)
          (aset s 4 overlay))
      (when overlay
        (delete-overlay overlay)
        (aset s 4 nil)))
    (put-text-property (aref s 6) (1+ (aref s 6)) 'display (and folded "▶"))
    (set-buffer-modified-p nil)))

(defun sp-batch-report-toggle-section ()
  "Fold or unfold the section at point."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (org-cycle)
    (let ((sec (get-text-property (point) 'sp-batch-report-section)))
      (unless sec (user-error "No section here"))
      (let ((folded (not (aref (aref sp-batch-report-view--sections sec) 4))))
        (sp-batch-report-view--fold sec folded)
        (when folded
          (goto-char (aref (aref sp-batch-report-view--sections sec) 5)))))))

(defun sp-batch-report-toggle-all ()
  "Fold every section, or unfold them all when every one is folded."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (org-shifttab)
    (let* ((n (length sp-batch-report-view--sections))
           (fold (cl-some (lambda (s) (not (aref s 4))) sp-batch-report-view--sections)))
      (dotimes (i n) (sp-batch-report-view--fold i fold))
      (goto-char (point-min)))))

(defun sp-batch-report-view--first-row-after (pos)
  "The index of the first row that starts after POS, or the number of rows."
  (let ((lo 0) (hi (length sp-batch-report-view--rows)))
    (while (< lo hi)
      (let ((mid (/ (+ lo hi) 2)))
        (if (> (car (aref sp-batch-report-view--rows mid)) pos)
            (setq hi mid)
          (setq lo (1+ mid)))))
    lo))

(defun sp-batch-report-view--goto-row (index step)
  "Go to the row INDEX or the next visible one in the direction of STEP."
  (let ((n (length sp-batch-report-view--rows)))
    (while (and (>= index 0) (< index n)
                (invisible-p (car (aref sp-batch-report-view--rows index))))
      (setq index (+ index step)))
    (when (and (>= index 0) (< index n))
      (goto-char (car (aref sp-batch-report-view--rows index)))
      t)))

(defun sp-batch-report-next ()
  "Go to the next entry."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (org-next-link)
    (unless (sp-batch-report-view--goto-row (sp-batch-report-view--first-row-after (point)) 1)
      (user-error "No next entry"))))

(defun sp-batch-report-previous ()
  "Go to the previous entry."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (org-previous-link)
    (unless (sp-batch-report-view--goto-row
             (1- (sp-batch-report-view--first-row-after (1- (point)))) -1)
      (user-error "No previous entry"))))

(defun sp-batch-report-view--update-count (sec)
  "Write the count of the section SEC again, in place."
  (let* ((s (aref sp-batch-report-view--sections sec))
         (pos (aref s 7))
         (inhibit-read-only t)
         (inhibit-modification-hooks t))
    (save-excursion
      (goto-char pos)
      (delete-region pos (+ pos sp-batch-report-view--count-width))
      (insert (sp-batch-report-view--count-string (aref s 2) (aref s 3))))))

(defun sp-batch-report-view--remove-face (beg end face)
  "Take FACE out of the faces of the text between BEG and END.
`remove-face-text-property' only exists from Emacs 30."
  (let ((pos beg))
    (while (< pos end)
      (let ((next (min end (next-single-property-change pos 'face nil end)))
            (current (get-text-property pos 'face)))
        (when (and (consp current) (not (keywordp (car current))))
          (setq current (remq face current))
          (when (null (cdr current)) (setq current (car current))))
        (when (eq current face) (setq current nil))
        (put-text-property pos next 'face current)
        (setq pos next)))))

(defun sp-batch-report-view--mark (key dropped)
  "Style every row with the KEY as dropped, or as kept when DROPPED is nil.
Only text properties of those rows and the count of their sections change, so
the cost does not depend on the size of the report."
  (let ((inhibit-read-only t)
        (inhibit-modification-hooks t)
        touched)
    (dolist (index (gethash key sp-batch-report-view--by-key))
      (pcase-let ((`(,beg ,end ,sec) (aref sp-batch-report-view--rows index)))
        (unless (eq (and (get-text-property beg 'sp-batch-report-dropped) t) dropped)
          (if dropped
              (progn (put-text-property beg end 'sp-batch-report-dropped t)
                     (add-face-text-property beg end 'sp-batch-report-dropped))
            (remove-text-properties beg end '(sp-batch-report-dropped nil))
            (sp-batch-report-view--remove-face beg end 'sp-batch-report-dropped))
          (cl-incf (aref (aref sp-batch-report-view--sections sec) 2) (if dropped -1 1))
          (cl-incf sp-batch-report-view--dropped (if dropped 1 -1))
          (push sec touched))))
    (dolist (sec (delete-dups touched))
      (sp-batch-report-view--update-count sec))
    (set-buffer-modified-p nil)))

(defun sp-batch-report-visit ()
  "Visit the link at point, run its action, or visit the file of the entry."
  (interactive)
  (let ((link (get-text-property (point) 'sp-batch-report-link))
        (action (get-text-property (point) 'sp-batch-report-action))
        (file (get-text-property (point) 'sp-batch-report-file)))
    (cond
     ((derived-mode-p 'org-mode) (org-open-at-point))
     (action (funcall action))
     (link (org-link-open-from-string (format "[[%s]]" link)))
     ((get-text-property (point) 'sp-batch-report-header) (sp-batch-report-toggle-section))
     (file (org-link-open-from-string
            (format "[[%s]]"
                    (sp-batch-report-view--file-target
                     file (get-text-property (point) 'sp-batch-report-line)))))
     (t (user-error "Nothing to visit here")))))

(defun sp-batch-report-visit-click (event)
  "Visit what the mouse EVENT clicked."
  (interactive "e")
  (mouse-set-point event)
  (sp-batch-report-visit))

(defun sp-batch-report-view--header-line ()
  "The summary line of the report."
  (let ((sections (length sp-batch-report-view--sections))
        (rows (length sp-batch-report-view--rows)))
    (format " %d section%s · %d entr%s · %d dropped"
            sections (if (= sections 1) "" "s")
            rows (if (= rows 1) "y" "ies")
            sp-batch-report-view--dropped)))

(define-derived-mode sp-batch-report-mode special-mode "Report"
  "Read-only view of the report of a batch command.
Sections fold with \\<sp-batch-report-mode-map>\\[sp-batch-report-toggle-section], and \\[sp-batch-report-toggle-all] folds them all.
\\[sp-batch-report-visit] visits the link or the file of the entry, \\[sp-batch-report-next] and \\[sp-batch-report-previous] move between entries.
\\[sp-batch-report-drop] drops the entry at point, \\[sp-batch-report-restore] brings it back, \\[sp-batch-report-apply] applies what is left,
\\[sp-batch-report-refresh] makes the report again and \\[quit-window] closes it.
\\[sp-backup-open] and \\[sp-backup-diff] open or diff a backup of the file of the entry.

\\{sp-batch-report-mode-map}"
  (setq buffer-undo-list t)
  (setq-local truncate-lines nil)
  (setq header-line-format '(:eval (sp-batch-report-view--header-line)))
  (sp-echo-help-set (sp-batch-report--hints)))

(provide 'sp-batch-report-view)
;;; sp-batch-report-view.el ends here
