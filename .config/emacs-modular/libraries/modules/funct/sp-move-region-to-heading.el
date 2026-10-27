;;; sp-move-region-to-heading.el --- Move a region under a heading in another note -*- lexical-binding: t; -*-

;;; Commentary:

;; Provides one command, `sp-move-region-to-heading', bound globally to `M-a'.

;;; Code:

(require 'vulpea)
(require 'org-id)
(require 'denote)

(defconst sp--new-heading-candidate "[+ Create new heading here]"
  "Special entry in the heading-selection prompt.
Choosing it creates a new top-level heading at the end of the
file instead of picking one of the existing headings.")

(defun sp--denote-create-and-get-path (title)
  "Create a new Denote note titled TITLE and return its file path.
The note is created with `denote' using default keywords/subdirectory/etc.
(rename it afterwards with your usual `denote-rename-file' /
`denote-rename-file-using-front-matter' bindings if needed). The
creation buffer is not left on screen -- window layout is
restored once the file path is captured."
  (let (path)
    (save-window-excursion
      (denote title)
      (setq path (buffer-file-name)))
    path))

(defun sp--vulpea-select-or-create-file ()
  "Select an existing note via Vulpea, or create one with Denote.
Uses the same note database as `vulpea-find', with the prompt of
`sp-select-note'. If
your input at the prompt doesn't match any existing note (i.e.
nothing in the completion corresponds to an actual file), you're
asked to confirm creating a new Denote note with that text as
its title; the new note becomes the target file."
  (let ((selection (sp-select-note "Move region to note: ")))
    (cond
     ;; An existing note was chosen.
     ((and (vulpea-note-p selection) (vulpea-note-path selection))
      (vulpea-note-path selection))
     ;; Vulpea couldn't match anything -- it may hand back a stub
     ;; note with no path, a plain string, or nil, depending on
     ;; how the prompt was left. Offer to create a note either way.
     (t
      (let ((title (cond ((vulpea-note-p selection) (vulpea-note-title selection))
                          ((stringp selection) selection)
                          (t (read-string "Title for new note: ")))))
        (unless (and title (not (string-empty-p title)))
          (user-error "No target selected"))
        (unless (y-or-n-p
                 (format "No note found for \"%s\" -- create it with Denote? " title))
          (user-error "No target selected"))
        (sp--denote-create-and-get-path title))))))

(defun sp--org-heading-candidates (file)
  "Return an alist of (OUTLINE-PATH . MARKER) for each heading in FILE.
OUTLINE-PATH is the full ancestor chain joined with \" > \", so
headings with the same text under different parents are shown
distinctly. Returns nil if FILE has no headings."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (org-map-entries
      (lambda ()
        (cons (mapconcat #'identity
                          (append (org-get-outline-path)
                                  (list (org-get-heading t t t t)))
                          " > ")
              (point-marker)))))))

(defun sp--create-heading-at-end (file)
  "Prompt for a title and insert a new top-level heading at the end of FILE.
Return a cons cell (MARKER . TITLE)."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (let ((title (read-string "New heading title: ")))
        (insert "* " title "\n")
        (cons (point-marker) title)))))

(defun sp--read-org-heading (file)
  "Prompt for a heading in FILE with completion.
Return a cons cell (MARKER . PATH), where PATH is the full
outline path string (used later as the link description).

If FILE has no headings at all, the prompt is skipped entirely
and a new top-level heading is created directly. Otherwise, the
prompt includes an extra option to create a new heading at the
end of the file instead of picking an existing one."
  (let ((candidates (sp--org-heading-candidates file)))
    (if (null candidates)
        (sp--create-heading-at-end file)
      (let ((choice (completing-read
                     "Under heading: "
                     (cons sp--new-heading-candidate candidates)
                     nil t)))
        (if (string= choice sp--new-heading-candidate)
            (sp--create-heading-at-end file)
          (cons (cdr (assoc choice candidates)) choice))))))

(defun sp--org-file-title ()
  "Return the #+title: keyword of the current buffer.
Falls back to the file name if no #+title: line is present."
  (or (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" nil t)
          (string-trim (match-string 1))))
      (file-name-nondirectory (or (buffer-file-name) ""))))

(defun sp--org-file-id ()
  "Return the file-level :ID: of the current buffer, creating one if needed.
This lives in the file's own property drawer, before the first
heading, and is what a whole-file id: link points at."
  (save-excursion
    (goto-char (point-min))
    (org-id-get-create)))

(defun sp--resources-heading-p (title)
  "Non-nil if TITLE (a clean heading string, tags/TODO/priority stripped) is
\"Resources\", regardless of case (so \"resources\", \"RESOURCES\",
\"ReSoUrCeS\", etc. all match)."
  (string-equal (downcase title) "resources"))

(defun sp--link-target-at-point (path)
  "Return (ID . DESCRIPTION) to link to for the heading at point.
Normally this is the heading itself: an ID is created for it if
needed (via `org-id-get-create'), and PATH (its outline path, or
its title if newly created) is used as the description.

But if the heading is called \"Resources\", in any case (see
`sp--resources-heading-p'), it's treated as a generic bucket
that shouldn't be linked to directly, and no ID is added to it
at all:
 - a level-1 \"Resources\" heading falls back to the file itself
   (file-level ID and #+title:);
 - a lower-level \"Resources\" heading falls back to its parent
   heading (or, in the unusual case that it has no parent, to
   the file itself)."
  (let ((heading-title (org-get-heading t t t t)))
    (if (sp--resources-heading-p heading-title)
        (if (eql (org-current-level) 1)
            (cons (sp--org-file-id) (sp--org-file-title))
          (save-excursion
            (if (org-up-heading-safe)
                (cons (org-id-get-create) (org-get-heading t t t t))
              (cons (sp--org-file-id) (sp--org-file-title)))))
      (cons (org-id-get-create) path))))

(defun sp-move-region-to-heading (start end target path)
  "Cut the region from START to END and insert it under the heading at TARGET.
TARGET is a marker pointing at the chosen heading; PATH is its
full outline path (or its title, if newly created). Prompts for
a target note via Vulpea's ID-based selection (so you search by
title/ID rather than navigating directories); if nothing
matches, offers to create a new Denote note on the spot. Then
prompts for a heading within that note (with completion,
disambiguated by full outline path, plus an option to create a
new heading) -- or, if the note has no headings yet, skips
straight to creating one.

The text is always inserted as the last content of the TARGET
heading's subtree -- after any existing body text or
sub-headings, but before the next heading of equal or higher
level.

The link left behind at point in the source buffer normally
points to TARGET itself. The exception is a heading literally
named \"Resources\" (see `sp--link-target-at-point'): no ID is
added to it, and the link instead points to the file (for a
level-1 \"Resources\" heading) or to its parent heading
(otherwise) -- Resources sections are treated as a generic
bucket, not something worth linking to directly."
  (interactive
   (let* ((start (region-beginning))
          (end (region-end))
          (file (sp--vulpea-select-or-create-file))
          (result (sp--read-org-heading file))
          (target (car result))
          (path (cdr result)))
     (list start end target path)))
  (let ((text (buffer-substring-no-properties start end))
        id desc)
    (delete-region start end)
    (with-current-buffer (marker-buffer target)
      (save-excursion
        (goto-char target)
        (pcase-let ((`(,link-id . ,link-desc) (sp--link-target-at-point path)))
          (setq id link-id
                desc link-desc))
        (goto-char target)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n"))
        (insert text)
        (unless (string-suffix-p "\n" text) (insert "\n")))
      (save-buffer))
    (insert (org-link-make-string (concat "id:" id) desc))))

(keymap-global-set "M-a" #'sp-move-region-to-heading)

(provide 'sp-move-region-to-heading)
;;; sp-move-region-to-heading.el ends here
