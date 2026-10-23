;;; sp-vulpea-grouped-backlinks.el --- Vulpea backlinks grouped by meta property -*- lexical-binding: t; -*-

;;; Commentary:

;; What this does: for a given note, finds every other note linking
;; to it, and sorts each link into either "Mentions" (a plain inline
;; or body-text [[id:...]] link) or a group named after the meta
;; property it was found in -- e.g. a note with
;;   - pub-author :: [[id:...][Christopher Arthur]]
;; contributes to a "pub-author" group when you look at Christopher
;; Arthur's backlinks, distinct from any note that just mentions him
;; in passing prose.
;;
;; NOT YET a real vulpea-ui sidebar widget -- see the top-level
;; docstrings below for why, and `sia-vulpea-classify-backlinks' for
;; the one point of Vulpea API I couldn't fully confirm.

;;; Code:

(require 'vulpea)
(require 'org)
(require 'sp-vulpea-dblock) ; for sia-vulpea-select-note

(defun sia-vulpea--line-meta-key-at (file pos)
  "If POS in FILE sits on a \"- KEY :: ...\" meta line, return KEY.
Otherwise return nil, meaning this link sits in plain prose (a
heading, a paragraph, anywhere that isn't a meta description-list
entry) rather than a structured meta property."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char pos)
      (beginning-of-line)
      (if (looking-at "^[ \t]*-[ \t]+\\([A-Za-z0-9_-]+\\)[ \t]+::[ \t]")
          (match-string 1)
        nil))))

(defun sia-vulpea-classify-backlinks (id)
  "Return an alist of (GROUP . NOTES) for every note linking to ID.
GROUP is \"Mentions\" for a plain inline/body link, or the
meta-property key name (e.g. \"pub-author\") for a link found on
a \"- KEY :: [[id:...]]\" line -- see `sia-vulpea--line-meta-key-at'.
NOTES is a deduplicated list of `vulpea-note' structs: the source
of each such link.

This relies on `vulpea-db-query-links-to' returning link plists
with at least :source (a note ID) and :pos (a buffer position in
the source file). I've seen this shape referenced in Vulpea's own
db/changelog material, but haven't been able to confirm it
against a live Emacs session -- if this errors for you, `C-h f
vulpea-db-query-links-to' will show the real return shape, and
the two `plist-get' calls below are the only things that would
need adjusting."
  (let ((groups (make-hash-table :test #'equal)))
    (dolist (link (vulpea-db-query-links-to id))
      (let* ((source-id (plist-get link :source))
             (pos (plist-get link :pos))
             (source-note (and source-id (vulpea-db-get-by-id source-id))))
        (when (and source-note pos)
          (let* ((key (sia-vulpea--line-meta-key-at (vulpea-note-path source-note) pos))
                 (group (or key "Mentions")))
            (puthash group (cons source-note (gethash group groups)) groups)))))
    (let (result)
      (maphash
       (lambda (group notes)
         (push (cons group
                     (seq-uniq notes (lambda (a b)
                                       (equal (vulpea-note-id a) (vulpea-note-id b)))))
               result))
       groups)
      result)))

(defun sia-vulpea-show-grouped-backlinks (&optional note)
  "Show backlinks to NOTE, grouped into \"Mentions\" plus one section
per meta-property key they were found under (see
`sia-vulpea-classify-backlinks'). Prompts for NOTE, via
`sia-vulpea-select-note' (tag-annotated completion), if not given.

Each entry is a real, clickable [[id:...][Title]] link back to
the note that made the reference -- opened in `org-mode' so
`org-open-at-point' works on them, same pattern as the property-
conversion report."
  (interactive)
  (let* ((note (or note (sia-vulpea-select-note "Show backlinks for: ")))
         (groups (sia-vulpea-classify-backlinks (vulpea-note-id note))))
    (with-current-buffer (get-buffer-create
                           (format "*vulpea backlinks: %s*" (vulpea-note-title note)))
      (erase-buffer)
      (org-mode)
      (insert (format "* Backlinks to %s\n\n" (vulpea-note-title note)))
      (if (null groups)
          (insert "No backlinks found.\n")
        (dolist (group (sort groups (lambda (a b) (string< (car a) (car b)))))
          (insert (format "** %s (%d)\n" (car group) (length (cdr group))))
          (dolist (n (cdr group))
            (insert (format "- %s\n"
                            (org-link-make-string (concat "id:" (vulpea-note-id n))
                                                   (vulpea-note-title n)))))
          (insert "\n")))
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

(provide 'sp-vulpea-grouped-backlinks)
;;; sp-vulpea-grouped-backlinks.el ends here
