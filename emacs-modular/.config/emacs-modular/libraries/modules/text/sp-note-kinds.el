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

(defcustom sp-note-definitions-title "Notes / Appendix"
  "Title of the heading that holds the definitions of the notes.
All footnote definitions, those of see-also notes and endnotes too, go here
when `org-footnote-normalize' is used.  Do not use \"See also\": `sp-see-also'
reads such a section as a list of mentions."
  :type 'string
  :group 'sp-note-kinds)

(defcustom sp-note-legacy-definition-titles '("Footnotes")
  "Titles of older definition sections, which are still found and used.
A new note goes to the section with `sp-note-definitions-title' when there
is one, else to the first of these that exists."
  :type '(repeat string)
  :group 'sp-note-kinds)

(defcustom sp-note-definition-order '(endnote see-also)
  "The order of the kinds in the definitions section.
The kinds not named, the plain footnotes, come after them."
  :type '(repeat (choice (const endnote) (const see-also)))
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

(defun sp-note--heading-regexp (title)
  "Regexp of a heading titled TITLE, with or without tags."
  (format "^\\*+ %s[ \t]*\\(?::[[:alnum:]_@#%%:]+:\\)?[ \t]*$" (regexp-quote title)))

(defun sp-note--find-section ()
  "Move to the start of the definitions section heading; nil when there is none.
The section with `sp-note-definitions-title' comes first, then the older ones.
The buffer must be widened."
  (let ((case-fold-search nil))
    (seq-some (lambda (title)
                (goto-char (point-min))
                (and (re-search-forward (sp-note--heading-regexp title) nil t)
                     (progn (beginning-of-line) t)))
              (cons sp-note-definitions-title sp-note-legacy-definition-titles))))

(defun sp-note--ensure-section ()
  "Move to the heading of the definitions section, making the section if needed."
  (widen)
  (unless (sp-note--find-section)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "\n* " sp-note-definitions-title "\n")
    (forward-line -1)))

(defun sp-note--goto-definitions ()
  "Move point to the end of the definitions section, making it when missing."
  (sp-note--ensure-section)
  (org-end-of-subtree t t)
  (skip-chars-backward " \t\n"))

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
    (sp-note-sort-definitions)
    (goto-char (point-min))
    (when (re-search-forward (format "^\\[fn:%s\\]" (regexp-quote label)) nil t)
      (end-of-line)
      ;; Sorting trims the blank at the end of the text; put it back.
      (when (eq (char-before) ?\]) (insert " ")))
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
An `:around' advice for `org-footnote-sort'."
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

(defun sp-note--definition-end (text-beg)
  "Where the definition whose text starts at TEXT-BEG ends (trailing blanks left out)."
  (save-excursion
    (goto-char text-beg)
    (let ((end (point-max)))
      (when (re-search-forward
             "\\(?:\n\\[fn:[-_[:word:]]+\\]\\|\n\\*+[ \t]\\|\n[ \t]*\n[ \t]*\n\\)" nil t)
        (setq end (match-beginning 0)))
      (goto-char end)
      (skip-chars-backward " \t\n" text-beg)
      (point))))

(defun sp-note--extract-definitions ()
  "Cut the definitions of see-also notes and endnotes out of the buffer.
Return them as a list of (LABEL KIND TEXT) in buffer order.  Definitions in
blocks that Org does not read and on comment lines are left where they are.
The buffer must be widened."
  (let ((case-fold-search nil)
        found)
    (goto-char (point-min))
    (while (re-search-forward "^\\[fn:\\([-_[:word:]]+\\)\\]" nil t)
      (let* ((label (match-string-no-properties 1))
             (kind (sp-note-kind label))
             (beg (match-beginning 0)))
        (unless (or (eq kind 'footnote)
                    (org-in-block-p '("src" "example" "export" "comment"))
                    (org-at-comment-p))
          (let ((end (sp-note--definition-end (match-end 0))))
            (push (list label kind (buffer-substring-no-properties beg end)) found)
            (delete-region beg end)
            (skip-chars-forward " \t\n")
            (delete-region beg (point))))))
    (nreverse found)))

(defun sp-note--ordered (notes)
  "NOTES (from `sp-note--extract-definitions') in the order of `sp-note-definition-order'.
Within a kind they are in the order of their numbers; a name has no number and
goes after the numbers.  Notes of other kinds, plain footnotes, follow."
  (let ((number (lambda (note)
                  (let ((rest (substring (car note)
                                         (length (sp-note-prefix (nth 1 note))))))
                    (if (string-match-p "\\`[0-9]+\\'" rest)
                        (string-to-number rest)
                      most-positive-fixnum)))))
    (append
     (apply #'append
            (mapcar (lambda (kind)
                      (sort (seq-filter (lambda (note) (eq (nth 1 note) kind)) notes)
                            (lambda (a b) (< (funcall number a) (funcall number b)))))
                    sp-note-definition-order))
     ;; The other kinds (plain footnotes) keep their order, after these.
     (seq-remove (lambda (note) (memq (nth 1 note) sp-note-definition-order))
                 notes))))

(defun sp-note--insert-definitions (notes)
  "Write NOTES at the start of the definitions section, making the section if needed."
  (when notes
    (sp-note--ensure-section)
    (end-of-line)
    (insert "\n\n"
            (mapconcat (lambda (note) (nth 2 note)) (sp-note--ordered notes) "\n\n")
            "\n")))

(defun sp-note--remove-empty-sections ()
  "Remove the definitions sections that have nothing in them."
  (let ((case-fold-search nil))
    (dolist (title (cons sp-note-definitions-title sp-note-legacy-definition-titles))
      (goto-char (point-min))
      (while (re-search-forward (sp-note--heading-regexp title) nil t)
        (beginning-of-line)
        (let ((beg (point)))
          (end-of-line)
          (let ((body (point)))
            (org-end-of-subtree t t)
            (if (string-blank-p (buffer-substring-no-properties body (point)))
                (progn (delete-region beg (point))
                       (goto-char beg))
              (goto-char (min (point-max) (1+ body))))))))
    ;; Blank lines that the removed heading left at the end of the buffer.
    (goto-char (point-max))
    (skip-chars-backward " \t\n")
    (when (and (> (point) (point-min)) (< (point) (point-max)))
      (delete-region (point) (point-max))
      (insert "\n"))))

(defun sp-note--tidy-section ()
  "Leave one blank line between the definitions of the section, and one newline at its end."
  (let ((case-fold-search nil))
    (when (sp-note--find-section)
      (let ((beg (point))
            (end (progn (org-end-of-subtree t t) (point-marker))))
        (goto-char beg)
        (while (re-search-forward "\n\n\n+" end t)
          (replace-match "\n\n"))
        (when (>= (marker-position end) (point-max))
          (goto-char (point-max))
          (skip-chars-backward " \t\n")
          (delete-region (point) (point-max))
          (insert "\n"))
        (set-marker end nil)))))

;;;###autoload
(defun sp-note-sort-definitions ()
  "Put the definitions of the see-also notes and endnotes in order.
They go to the start of the definitions section, first the endnotes and then
the see-also notes (`sp-note-definition-order'); the plain footnotes stay
after them in the same section."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Notes need an Org buffer"))
  (save-excursion
    (save-restriction
      (widen)
      (atomic-change-group
        (goto-char (point-min))
        (sp-note--insert-definitions (sp-note--extract-definitions))
        (sp-note--remove-empty-sections)
        (sp-note--tidy-section)))))

(defun sp-note--normalize (function &rest arguments)
  "Call FUNCTION, `org-footnote-normalize', with ARGUMENTS, and keep the notes.
An `:around' advice.  The definitions of the see-also notes and endnotes are cut
out and their references hidden from Org, which numbers the plain footnotes and
writes them in the section `sp-note-definitions-title'; then the notes are put
back at the start of that section, renumbered and in order."
  (if (not (and sp-note-guard-org-footnotes (derived-mode-p 'org-mode)))
      (apply function arguments)
    (let ((notes (save-restriction (widen) (save-excursion (sp-note--extract-definitions)))))
      (sp-note--mask-notes t)
      (unwind-protect
          (let ((org-footnote-section sp-note-definitions-title))
            (apply function arguments))
        (sp-note--mask-notes nil)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (sp-note--insert-definitions notes)
            (sp-note--remove-empty-sections)
            (sp-note--tidy-section))))
      (when sp-note-auto-renumber (sp-note-renumber))
      (sp-note-sort-definitions))))

(defun sp-note--after-org (&rest _)
  "Renumber and order the notes after Org adjusted the footnotes (an `:after' advice)."
  (when (and sp-note-auto-renumber sp-note-guard-org-footnotes
             (derived-mode-p 'org-mode))
    (sp-note-renumber)
    (sp-note-sort-definitions)))

(with-eval-after-load 'org-footnote
  (advice-add 'org-footnote-normalize :around #'sp-note--normalize)
  (advice-add 'org-footnote-sort :around #'sp-note--guarded)
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
