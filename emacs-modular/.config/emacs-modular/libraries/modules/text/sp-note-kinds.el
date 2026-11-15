;;; sp-note-kinds.el --- Footnotes, see-also notes and endnotes told by label -*- lexical-binding: t; -*-

;;; Commentary:

;; Org has one kind of footnote.  This module tells three kinds apart by the
;; label: `[fn:see-1]' is a see-also note (a Tufte sidenote), `[fn:end-1]' an
;; endnote (collected in a Notes section), anything else a plain footnote.
;; It also inserts new notes and the endnotes section.
;; See docs/tangles/text/sp-note-kinds.org.

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'cl-lib)

(declare-function org-end-of-subtree "org")
(declare-function org-in-block-p "org")
(declare-function org-at-comment-p "org")

(defgroup sp-note-kinds nil
  "Footnotes, see-also notes and endnotes, told by label."
  :group 'org)

(defcustom sp-note-see-also-prefix "see-"
  "Label prefix of a see-also note: `[fn:see-1]'."
  :type 'string
  :group 'sp-note-kinds)

(defcustom sp-note-endnote-prefix "end-"
  "Label prefix of an endnote: `[fn:end-1]'."
  :type 'string
  :group 'sp-note-kinds)

(defcustom sp-note-definitions-title "Footnotes"
  "Title of the heading that holds the definitions of new notes.
Do not use \"See also\": `sp-see-also' reads such a section as a list of
mentions."
  :type 'string
  :group 'sp-note-kinds)

(defcustom sp-note-auto-renumber t
  "Non-nil: renumber the see-also notes and endnotes after each change.
A new note, `org-footnote-normalize' and Org's own footnote adjusting all
renumber them in the order of their first reference in the text."
  :type 'boolean
  :group 'sp-note-kinds)

(defcustom sp-note-guard-org-footnotes t
  "Non-nil: Org's footnote normalizing and sorting leave these notes alone.
`org-footnote-normalize' turns every label into a number; with this on it does
not touch `see-N' and `end-N' notes (see `sp-note--guarded')."
  :type 'boolean
  :group 'sp-note-kinds)

(defcustom sp-note-endnotes-title "Notes"
  "Title of the heading that the endnotes template inserts."
  :type 'string
  :group 'sp-note-kinds)

(defun sp-note-prefix (kind)
  "The label prefix of KIND (`see-also' or `endnote'), or nil."
  (pcase kind
    ('see-also sp-note-see-also-prefix)
    ('endnote sp-note-endnote-prefix)))

(defun sp-note--prefixed-p (label prefix)
  "Non-nil when LABEL is PREFIX followed by at least one character."
  (and (stringp label)
       (stringp prefix)
       (not (string-empty-p prefix))
       (string-prefix-p prefix label)
       (> (length label) (length prefix))))

(defun sp-note-kind (label)
  "The kind of the footnote LABEL: `see-also', `endnote' or `footnote'.
LABEL nil (an anonymous footnote) is a `footnote'."
  (cond ((sp-note--prefixed-p label sp-note-see-also-prefix) 'see-also)
        ((sp-note--prefixed-p label sp-note-endnote-prefix) 'endnote)
        (t 'footnote)))

(defun sp-note-next-label (kind)
  "The next free label of KIND in the buffer: the prefix and the highest number plus one."
  (let ((prefix (sp-note-prefix kind))
        (highest 0))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (let ((case-fold-search nil)
              (regexp (format "\\[fn:%s\\([0-9]+\\)[]:]"
                              (regexp-quote prefix))))
          (while (re-search-forward regexp nil t)
            (setq highest (max highest
                               (string-to-number (match-string 1))))))))
    (format "%s%d" prefix (1+ highest))))

(defun sp-note--goto-definitions ()
  "Move point to the end of the definitions section, making it when missing."
  (widen)
  (goto-char (point-min))
  (let ((case-fold-search nil))
    (if (re-search-forward
         (format "^\\*+ %s[ \t]*\\(?::[[:alnum:]_@#%%:]+:\\)?[ \t]*$"
                 (regexp-quote sp-note-definitions-title))
         nil t)
        (progn (org-end-of-subtree t t)
               (skip-chars-backward " \t\n"))
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "\n* " sp-note-definitions-title))))

;;;###autoload
(defun sp-note-new (kind &optional text)
  "Insert a note of KIND (`see-also' or `endnote') at point; return its label.
The reference `[fn:LABEL]' goes at point and the definition, with TEXT when
given, at the end of the section `sp-note-definitions-title'.  Point is left
in the definition.  With `sp-note-auto-renumber' the notes are renumbered in
the order of the text first, so the returned label can differ from the one
inserted."
  (unless (derived-mode-p 'org-mode)
    (user-error "Notes need an Org buffer"))
  (let ((label (sp-note-next-label kind)))
    (push-mark)
    (insert (format "[fn:%s]" label))
    (sp-note--goto-definitions)
    (insert (format "\n\n[fn:%s] %s" label (or text "")))
    (when sp-note-auto-renumber
      (setq label (or (cdr (assoc label (sp-note-renumber))) label)))
    (goto-char (point-min))
    (when (re-search-forward (format "^\\[fn:%s\\]" (regexp-quote label)) nil t)
      (end-of-line))
    (message "Note %s: C-u C-SPC returns to the text" label)
    label))

;;;###autoload
(defun sp-note-endnote-new ()
  "Insert an endnote at point and open its definition."
  (interactive)
  (sp-note-new 'endnote))

(defun sp-note--scan (prefix)
  "The labels `PREFIX<number>' of the buffer as (REFERENCES . DEFINITIONS).
Each is a list of (LABEL . POSITION-OF-THE-LABEL) in buffer order.
Notes in blocks that Org does not read and on comment lines are left out."
  (let ((case-fold-search nil)
        (regexp (format "\\[fn:\\(%s[0-9]+\\)\\([]:]\\)" (regexp-quote prefix)))
        references definitions)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward regexp nil t)
        (let ((label (match-string-no-properties 1))
              (position (match-beginning 1))
              (definition (and (= (match-beginning 0) (line-beginning-position))
                               (equal (match-string 2) "]"))))
          (unless (save-excursion
                    (goto-char position)
                    (or (org-in-block-p '("src" "example" "export" "comment"))
                        (org-at-comment-p)))
            (push (cons label position) (if definition definitions references))))))
    (cons (nreverse references) (nreverse definitions))))

(defun sp-note--renumber-kind (kind)
  "The edits that number the notes of KIND in the order of the text.
A list of (POSITION OLD NEW), for the labels that change."
  (let* ((prefix (sp-note-prefix kind))
         (scan (sp-note--scan prefix))
         (order (seq-uniq (append (mapcar #'car (car scan))
                                  (mapcar #'car (cdr scan)))))
         (number 0)
         (names (mapcar (lambda (label)
                          (cons label (format "%s%d" prefix (cl-incf number))))
                        order))
         edits)
    (dolist (entry (append (car scan) (cdr scan)))
      (let ((new (cdr (assoc (car entry) names))))
        (unless (equal new (car entry))
          (push (list (cdr entry) (car entry) new) edits))))
    edits))

;;;###autoload
(defun sp-note-renumber ()
  "Number the see-also notes and the endnotes in the order of the text.
Return the alist of (OLD . NEW) for the labels that changed."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Notes need an Org buffer"))
  (let (changed)
    (save-excursion
      (save-restriction
        (widen)
        (dolist (kind '(see-also endnote))
          (let ((edits (sp-note--renumber-kind kind)))
            ;; From the end, so the positions before stay right.
            (dolist (edit (sort (copy-sequence edits)
                                (lambda (a b) (> (car a) (car b)))))
              (goto-char (nth 0 edit))
              (delete-region (point) (+ (point) (length (nth 1 edit))))
              (insert (nth 2 edit)))
            (dolist (edit edits)
              (cl-pushnew (cons (nth 1 edit) (nth 2 edit)) changed :test #'equal))))))
    (when (called-interactively-p 'any)
      (message "%d note label%s renumbered" (length changed)
               (if (= (length changed) 1) "" "s")))
    changed))

(defvar org-footnote-section)

(defconst sp-note--mask "\u200b"
  "Zero-width space put after `fn' to hide a note from Org's footnote commands.")

(defun sp-note--guard-regexp (&optional masked)
  "Regexp of the references and definitions of notes, to the end of the label.
With MASKED, the ones hidden by `sp-note--mask'."
  (format "\\[fn%s:\\(?:%s\\)[-_[:word:]]+"
          (if masked sp-note--mask "")
          (mapconcat #'regexp-quote
                     (seq-filter (lambda (prefix) (and prefix (not (string-empty-p prefix))))
                                 (list sp-note-see-also-prefix sp-note-endnote-prefix))
                     "\\|")))

(defun sp-note--mask-notes (mask)
  "Hide the notes from Org when MASK is non-nil, show them again otherwise."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search nil)
            (regexp (sp-note--guard-regexp (not mask))))
        (while (re-search-forward regexp nil t)
          (let ((end (copy-marker (match-end 0))))
            (goto-char (+ (match-beginning 0) 3))
            (if mask (insert sp-note--mask) (delete-char 1))
            (goto-char end)))))))

(defun sp-note--guarded (function &rest arguments)
  "Call FUNCTION with ARGUMENTS while Org cannot see the see-also notes and endnotes.
An `:around' advice for `org-footnote-normalize' and `org-footnote-sort'."
  (if (not (and sp-note-guard-org-footnotes (derived-mode-p 'org-mode)))
      (apply function arguments)
    (when (and org-footnote-section
               (save-restriction
                 (widen)
                 (save-excursion
                   (goto-char (point-min))
                   (let ((case-fold-search nil))
                     (re-search-forward (sp-note--guard-regexp) nil t)))))
      (user-error "`org-footnote-section' is set: Org would rewrite the footnotes section and lose the see-also notes and endnotes"))
    (sp-note--mask-notes t)
    (unwind-protect (apply function arguments)
      (sp-note--mask-notes nil))))

(defun sp-note--after-org (&rest _)
  "Renumber the notes after Org changed the footnotes (an `:after' advice)."
  (when (and sp-note-auto-renumber sp-note-guard-org-footnotes
             (derived-mode-p 'org-mode))
    (sp-note-renumber)))

(with-eval-after-load 'org-footnote
  (advice-add 'org-footnote-normalize :around #'sp-note--guarded)
  (advice-add 'org-footnote-sort :around #'sp-note--guarded)
  (advice-add 'org-footnote-normalize :after #'sp-note--after-org)
  (advice-add 'org-footnote-auto-adjust-maybe :after #'sp-note--after-org))

(defconst sp-note--endnotes-block
  "#+begin_export typst\n#endnotes()\n#+end_export\n"
  "The export block that prints the endnotes in a Typst export.")

;;;###autoload
(defun sp-note-insert-endnotes-section ()
  "Insert the endnotes template (a Notes heading) at the start of this line."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Notes need an Org buffer"))
  (when (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (search-forward "#endnotes()" nil t)))
    (user-error "This buffer already has an endnotes section"))
  (beginning-of-line)
  (insert "* " sp-note-endnotes-title "\n" sp-note--endnotes-block "\n"))

(provide 'sp-note-kinds)
;;; sp-note-kinds.el ends here
