;;; sp-refile.el --- One command to refile a heading or merge a note -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-refile' moves the heading at point to another heading of the same
;; note, to another note, or into a note of its own (`sp-split-leave-parents').
;; Before the first heading it merges the whole note under a heading of
;; another note.  See docs/tangles/funct/sp-refile.org.

;;; Code:

(require 'org)
(require 'org-id)
(require 'subr-x)
(require 'seq)
(require 'sp-split-leave-parents)
(require 'sp-move-region-to-heading)

(declare-function sp-select-note "sp-org-tag-groups")
(declare-function vulpea-note-path "vulpea")
(declare-function vulpea-note-p "vulpea")

(defconst sp-refile--new-note "[New note: own file]"
  "Prompt entry that splits the heading into a note of its own.")

(defconst sp-refile--other-note "[Another note...]"
  "Prompt entry that asks for another note, then a heading in it.")

(defconst sp-refile--top "[Top of note]"
  "Heading prompt entry for a new top-level heading at the end of a note.")

(defun sp-refile--local-candidates ()
  "Return (OUTLINE-PATH . MARKER) for the headings of this buffer.
The subtree at point is left out, so it cannot be moved into itself."
  (let ((self (save-excursion (org-back-to-heading t) (point)))
        (self-end (save-excursion (org-back-to-heading t)
                                  (org-end-of-subtree t t) (point))))
    (org-with-wide-buffer
     (delq nil
           (org-map-entries
            (lambda ()
              (unless (and (>= (point) self) (< (point) self-end))
                (cons (mapconcat #'identity
                                 (append (org-get-outline-path)
                                         (list (org-get-heading t t t t)))
                                 " > ")
                      (point-marker)))))))))

(defun sp-refile--insert (text target buffer)
  "Insert the subtree TEXT as the last child of TARGET in BUFFER.
TARGET is a marker, or nil for the end of BUFFER as a top-level heading.
BUFFER is saved when it visits a file."
  (with-current-buffer buffer
    (org-with-wide-buffer
     (let ((level 1))
       (if target
           (progn (goto-char target)
                  (setq level (1+ (org-current-level)))
                  (org-end-of-subtree t t))
         (goto-char (point-max)))
       (unless (bolp) (insert "\n"))
       (let ((start (point)))
         (insert text)
         (unless (bolp) (insert "\n"))
         ;; Re-level the inserted tree to LEVEL.
         (save-excursion
           (goto-char start)
           (let ((delta (- level (org-current-level))))
             (unless (zerop delta)
               (org-map-region
                (lambda ()
                  (if (> delta 0)
                      (dotimes (_ delta) (org-do-demote))
                    (dotimes (_ (- delta)) (org-do-promote))))
                start (point-max))))))))
    (when buffer-file-name (save-buffer))))

(defun sp-refile--move-heading (target buffer)
  "Move the subtree at point under TARGET in BUFFER (see `sp-refile--insert').
The copy is made and saved first, the original is removed after."
  (let* ((src (current-buffer))
         (beg (save-excursion (org-back-to-heading t) (copy-marker (point))))
         (end (save-excursion (org-back-to-heading t)
                              (org-end-of-subtree t t) (copy-marker (point))))
         (text (buffer-substring-no-properties beg end)))
    (when (and (eq buffer src) target
               (>= target beg) (< target end))
      (user-error "Cannot refile a heading into itself"))
    (sp-refile--insert text target buffer)
    (with-current-buffer src
      (org-with-wide-buffer
       (delete-region beg end))
      (when buffer-file-name (save-buffer)))))

(defun sp-refile--read-other-note ()
  "Ask for a note and one of its headings.
Return (MARKER-OR-NIL . BUFFER); a nil marker means the end of the note."
  (let* ((note (sp-select-note "Refile to note: " :require-match t))
         (path (and (vulpea-note-p note) (vulpea-note-path note))))
    (unless path (user-error "No target note selected"))
    (let* ((cands (sp--org-heading-candidates path))
           (choice (completing-read "Under heading: "
                                    (cons sp-refile--top (mapcar #'car cands))
                                    nil t))
           (buf (find-file-noselect path)))
      (cons (unless (string= choice sp-refile--top)
              (cdr (assoc choice cands)))
            buf))))

(defun sp-refile--note-as-subtree ()
  "Return the whole current note as a level 1 subtree string.
The title becomes the heading, `#+filetags' its tags, the note's ID
stays in a property drawer, the text before the first heading comes
first and the headings follow, one level deeper."
  (let* ((text (org-with-wide-buffer (buffer-substring-no-properties
                                      (point-min) (point-max))))
         title tags id)
    (with-temp-buffer
      (insert text)
      (delay-mode-hooks (org-mode))
      (goto-char (point-min))
      (let ((kw (org-collect-keywords '("TITLE" "FILETAGS"))))
        (setq title (car (cdr (assoc "TITLE" kw)))
              tags (split-string (or (car (cdr (assoc "FILETAGS" kw))) "")
                                 ":" t "[ \t]+")))
      (setq id (org-entry-get (point-min) "ID"))
      (goto-char (point-min))
      ;; Drop the front matter: the top property drawer and #+keywords.
      (when (looking-at-p "[ \t]*:PROPERTIES:")
        (when (re-search-forward "^[ \t]*:END:[ \t]*\n?" nil t)
          (delete-region (point-min) (point))))
      (goto-char (point-min))
      (while (looking-at "[ \t]*#\\+[A-Za-z_]+:.*\n?")
        (replace-match ""))
      ;; Demote every existing heading by one.
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*+\\) " nil t)
        (replace-match "\\1* "))
      (concat "* " (or title "Untitled")
              (if tags (format " :%s:" (string-join tags ":")) "")
              "\n"
              (if id (format ":PROPERTIES:\n:ID:       %s\n:END:\n" id) "")
              (string-trim-left (buffer-string) "\n+")))))

(defun sp-refile--merge-note (target buffer)
  "Merge the current note as a subtree under TARGET in BUFFER.
Asks before the file of the current note is deleted afterwards."
  (let ((file buffer-file-name)
        (src (current-buffer)))
    (unless file (user-error "This buffer is not a note file"))
    (when (eq buffer src) (user-error "Cannot merge a note into itself"))
    (unless (y-or-n-p (format "Merge %s into %s and delete it? "
                              (file-name-nondirectory file)
                              (buffer-name buffer)))
      (user-error "Merge cancelled"))
    (let ((text (sp-refile--note-as-subtree)))
      (sp-refile--insert text target buffer)
      (set-buffer-modified-p nil)
      (kill-buffer src)
      (delete-file file delete-by-moving-to-trash)
      (when (fboundp 'vulpea-db-update-file)
        (ignore-errors (vulpea-db-update-file file))))
    (message "Merged %s" (file-name-nondirectory file))))

;;;###autoload
(defun sp-refile (&optional arg)
  "Move the heading at point, or merge the note when before its first heading.
On a heading, choose from the headings of this note, `[New note: own
file]' (split, see `sp-split-leave-parents'; a plain prefix argument
leaves no link) or `[Another note...]'.  Before the first heading, or
with `C-u C-u', the whole note is merged under a heading of another note."
  (interactive "P")
  (unless (derived-mode-p 'org-mode) (user-error "Not an Org buffer"))
  (let ((merge (or (equal arg '(16))
                   (org-with-wide-buffer
                    (and (not (ignore-errors (org-back-to-heading t) t)))))))
    (if merge
        (pcase-let ((`(,target . ,buf) (sp-refile--read-other-note)))
          (sp-refile--merge-note target buf))
      (let* ((cands (sp-refile--local-candidates))
             (choice (completing-read
                      "Refile to: "
                      (append (list sp-refile--new-note sp-refile--other-note)
                              (mapcar #'car cands))
                      nil t)))
        (cond
         ((string= choice sp-refile--new-note)
          (let ((current-prefix-arg arg))
            (sp-split-leave-parents (and arg t))))
         ((string= choice sp-refile--other-note)
          (pcase-let ((`(,target . ,buf) (sp-refile--read-other-note)))
            (sp-refile--move-heading target buf)))
         (t
          (sp-refile--move-heading (cdr (assoc choice cands))
                                   (current-buffer))))))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-w") #'sp-refile))

(provide 'sp-refile)
;;; sp-refile.el ends here
