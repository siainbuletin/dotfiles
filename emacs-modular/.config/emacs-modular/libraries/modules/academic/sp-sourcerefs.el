;;; sp-sourcerefs.el --- Turn SOURCEREFS lines of a litnote into citations -*- lexical-binding: t; -*-

;;; Commentary:

;; A line `SOURCEREFS text' in a litnote marks a reference met in the PDF being
;; read.  `sp-sourcerefs-convert' matches those lines against the BibTeX files
;; (`sp-cite-match', with the reference list of the PDF from `sp-cite-open') and
;; turns the matches into [cite:@key] links.  Unmatched lines go to the Cited
;; works table.
;; Literate source: docs/tangles/academic/sp-sourcerefs.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'sp-cite-match)
(require 'sp-cite-open)

(defgroup sp-sourcerefs nil
  "Turn SOURCEREFS lines into citations."
  :group 'convenience)

(defcustom sp-sourcerefs-keyword "SOURCEREFS"
  "The word that starts a line holding a reference met in the PDF."
  :type 'string)

(defcustom sp-sourcerefs-reference-text-function #'sp-sourcerefs-front-reference-text
  "Function of the litnote's citekey (or nil) returning the PDF's reference list.
It returns a string, or nil when there is no reference list."
  :type 'function)

(defun sp-sourcerefs--line-regexp ()
  "The regexp of a SOURCEREFS line; group 1 is the bullet, group 2 the text."
  (concat "^\\([ \t]*\\(?:[-+][ \t]+\\)?\\)"
          (regexp-quote sp-sourcerefs-keyword)
          "\\_>:?[ \t]+\\(.*[^ \t\n]\\)[ \t]*$"))

(defun sp-sourcerefs-collect (&optional beg end)
  "The SOURCEREFS lines between BEG and END (default the buffer).
Each is a plist (:marker M :bullet B :text T), in buffer order."
  (let ((case-fold-search nil)
        (re (sp-sourcerefs--line-regexp))
        found)
    (save-excursion
      (save-restriction
        (narrow-to-region (or beg (point-min)) (or end (point-max)))
        (goto-char (point-min))
        (while (re-search-forward re nil t)
          (push (list :marker (copy-marker (match-beginning 0))
                      :bullet (match-string-no-properties 1)
                      :text (match-string-no-properties 2))
                found))))
    (nreverse found)))

(defun sp-sourcerefs-citekey ()
  "The citekey of the litnote in the current buffer, from #+reference: or ROAM_REFS."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward
               "^\\(?:#\\+reference:\\|:ROAM_REFS:\\)[ \t]*[^@\n]*@?\\([^ \t\n;,]+\\)" nil t)
          (match-string-no-properties 1))))))

(defun sp-sourcerefs-front-reference-text (key)
  "The reference list of the record in front in DEVONthink when its citekey is KEY."
  (when-let* ((front (sp-cite-open--front))
              (uuid (plist-get front :uuid))
              ((or (null key) (null (plist-get front :key))
                   (equal key (plist-get front :key))))
              (plain (sp-cite-open--plain-text uuid)))
    (sp-cite-open-references plain)))

(defun sp-sourcerefs--match (text reference-text candidates)
  "Match TEXT; return (STATUS . RANKED) like `sp-cite-match-text'.
A reference list widens a short TEXT to its full entry first."
  (let ((entry (and reference-text (sp-cite-open-entry text reference-text))))
    (sp-cite-match-text (or entry text) candidates)))

(defun sp-sourcerefs--report (rows)
  "Show ROWS, a list of (REF STATUS RANKED), in a report buffer."
  (with-current-buffer (get-buffer-create "*sp-sourcerefs*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "%d %s lines\n\n" (length rows) sp-sourcerefs-keyword))
      (dolist (row rows)
        (pcase-let ((`(,ref ,status ,ranked) row))
          (insert (format "%-9s %s\n" status
                          (truncate-string-to-width (plist-get ref :text) 90 nil nil "…")))
          (when ranked
            (insert (format "          -> %.2f  %s\n" (caar ranked)
                            (plist-get (cdar ranked) :label))))))
      (goto-char (point-min))
      (special-mode))
    (display-buffer (current-buffer))))

(defun sp-sourcerefs--replace (ref key)
  "Replace the line of REF by its bullet and the citation of KEY."
  (save-excursion
    (goto-char (plist-get ref :marker))
    (delete-region (line-beginning-position) (line-end-position))
    (insert (plist-get ref :bullet) (format "[cite:@%s]" key))))

;;;###autoload
(defun sp-sourcerefs-convert (&optional beg end)
  "Turn the SOURCEREFS lines of the region (or buffer) into [cite:@key] links.
A report is shown and you confirm once.  Lines that match nothing stay as they
are and go to the Cited works table as unmatched."
  (interactive (when (use-region-p) (list (region-beginning) (region-end))))
  (let ((refs (sp-sourcerefs-collect beg end)))
    (unless refs (user-error "No %s lines here" sp-sourcerefs-keyword))
    (let* ((candidates (sp-cite-match-candidates))
           (reference-text (funcall sp-sourcerefs-reference-text-function
                                    (sp-sourcerefs-citekey)))
           (rows (mapcar (lambda (ref)
                           (let ((m (sp-sourcerefs--match (plist-get ref :text)
                                                          reference-text candidates)))
                             (list ref (car m) (cdr m))))
                         refs)))
      (message "sp-sourcerefs: %s" (if reference-text "using the PDF's reference list"
                                     "no reference list for this PDF"))
      (sp-sourcerefs--report rows)
      (when (y-or-n-p (format "Convert %d lines in %s? " (length rows) (buffer-name)))
        (let (items (done 0))
          (atomic-change-group
            (dolist (row (reverse rows))
              (pcase-let ((`(,ref ,status ,ranked) row))
                (let ((cand (pcase status
                              ('accept (cdar ranked))
                              ('ambiguous (sp-cite-match--choose ranked)))))
                  (if cand
                      (progn (sp-sourcerefs--replace ref (plist-get cand :key))
                             (cl-incf done)
                             (push cand items))
                    (push (plist-get ref :text) items))))))
          (sp-cite-match-write-section items candidates)
          (message "sp-sourcerefs: %d of %d converted, %d left for reading"
                   done (length rows) (- (length rows) done))
          done)))))

(keymap-global-set "C-c o s" #'sp-sourcerefs-convert)

(provide 'sp-sourcerefs)
;; sp-sourcerefs.el ends here
