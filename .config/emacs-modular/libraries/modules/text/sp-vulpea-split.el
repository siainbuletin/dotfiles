;;; sp-vulpea-split.el --- Split a vulpea heading out with parents and a link left behind -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-split-leave-parents' wraps `vulpea-split-heading'.  On top of the
;; normal split it:
;;
;; 1. Adds a `- parents :: [[id:...][Title]]' meta line to the new note,
;;    pointing at the note the heading came from.  The source is the
;;    nearest ancestor heading with an ID, else the file-level note (its
;;    ID is created when missing).  When the subtree already has a
;;    `parents' line, the new link is put in front of the old value,
;;    separated by a comma.
;;
;; 2. Leaves a plain link to the new note in the source file, as a line
;;    of body text exactly where the heading started (not a heading).
;;    With a prefix argument no link is left.
;;
;; Both steps hook `vulpea-split--write-file', a private function of
;; vulpea, and only act while `sp-split-leave-parents' is running.  A
;; plain `vulpea-split-heading' is unchanged.

;;; Code:

(require 'org)
(require 'org-id)
(require 'subr-x)
(require 'vulpea)

;; These must be defined before the functions below use them in `let',
;; so that the bindings are dynamic.
(defvar sp-split--active nil
  "Non-nil while `sp-split-leave-parents' is running.")

(defvar sp-split--want-link t
  "Non-nil when the split should leave a plain link in the source file.")

(defun sp-split--link-to (id fallback-title)
  "Return an id link to ID, titled from the database or FALLBACK-TITLE."
  (org-link-make-string
   (concat "id:" id)
   (if-let* ((note (vulpea-db-get-by-id id)))
       (vulpea-note-title note)
     fallback-title)))

(defun sp-split--parent-link (id)
  "Return (PARENT-ID . LINK) for the note the heading with ID lives in.
Walks up the ancestors of the heading and takes the first one with an
ID.  If none has one, falls back to the file-level note, creating its
ID when it is missing."
  (when-let* ((note (vulpea-db-get-by-id id))
              (path (vulpea-note-path note)))
    (with-current-buffer (find-file-noselect path)
      (org-with-wide-buffer
       (when-let* ((pos (org-find-entry-with-id id)))
         (goto-char pos)
         (let (pid title)
           (while (and (not pid) (org-up-heading-safe))
             (when-let* ((x (org-entry-get (point) "ID")))
               (setq pid x
                     title (org-link-display-format
                            (org-get-heading t t t t)))))
           (unless pid
             (goto-char (point-min))
             (setq pid (or (org-entry-get (point-min) "ID")
                           (org-id-get-create))
                   title (or (and (fboundp 'vulpea-buffer-title-get)
                                  (vulpea-buffer-title-get))
                             (file-name-base path))))
           (cons pid (sp-split--link-to pid title))))))))

(defun sp-split--body-with-parent (body parent-id link)
  "Return BODY with LINK recorded in its `parents' meta line.
PARENT-ID is the id LINK points to."
  (let* ((case-fold-search nil)
         ;; Only the section before the first child heading: children
         ;; may carry `parents' lines of their own, which stay untouched.
         (top-end (or (string-match "^\\*+ " body) (length body)))
         (top (substring body 0 top-end))
         (rest (substring body top-end)))
    (cond
     ;; A parents line already exists: prepend the new link to its value.
     ((string-match
       "^\\([ \t]*[-+][ \t]+parents[ \t]+::[ \t]*\\)\\(.*\\)$" top)
      ;; Read everything out of the match data before calling anything
      ;; that may clobber it.
      (let* ((mb (match-beginning 0))
             (me (match-end 0))
             (prefix (match-string 1 top))
             (existing (string-trim (match-string 2 top))))
        (if (string-search (concat "id:" parent-id) existing)
            body
          (concat (substring top 0 mb)
                  prefix link
                  (if (string-empty-p existing)
                      ""
                    (concat ", " existing))
                  (substring top me)
                  rest))))
     (t
      (let ((line (concat "- parents :: " link)))
        (cond
         ((string-empty-p body) line)
         ;; Body opens with meta already: join that list.
         ((string-match-p "\\`[ \t]*[-+][ \t]+[^ \t\n]+[ \t]+::" body)
          (concat line "\n" body))
         (t (concat line "\n\n" body))))))))

(defun sp-split--insert-source-link (id title)
  "Insert a plain link to ID on the line where its heading starts.
TITLE is the fallback description.  The link goes in front of the
heading, so it is still there once vulpea cuts the subtree.  Return a
cons of markers around the inserted text, or nil."
  (when-let* ((note (vulpea-db-get-by-id id))
              (path (vulpea-note-path note)))
    (with-current-buffer (find-file-noselect path)
      (org-with-wide-buffer
       (when-let* ((pos (org-find-entry-with-id id)))
         (goto-char pos)
         (let ((beg (copy-marker pos)))
           (insert (sp-split--link-to id (org-link-display-format title))
                   "\n")
           (cons beg (copy-marker (point)))))))))

(defun sp-split--write-file-advice (fn &rest args)
  "Around advice for `vulpea-split--write-file'.
FN is the original function and ARGS its arguments: PATH ID TITLE HEAD
TAGS PROPERTIES BODY.  Does nothing unless `sp-split-leave-parents' is
running."
  (if (not sp-split--active)
      (apply fn args)
    (pcase-let ((`(,path ,id ,title ,head ,tags ,props ,body) args))
      ;; The subtree is still in the source file at this point, and
      ;; vulpea has already run its checks, so a refused split never gets
      ;; this far.
      (let* ((parent (sp-split--parent-link id))
             (body (if parent
                       (sp-split--body-with-parent
                        body (car parent) (cdr parent))
                     body))
             (stub (when sp-split--want-link
                     (sp-split--insert-source-link id title))))
        (condition-case err
            (funcall fn path id title head tags props body)
          (error
           ;; Writing the new file failed: take the link back out.
           (when (and stub (marker-buffer (car stub)))
             (with-current-buffer (marker-buffer (car stub))
               (delete-region (car stub) (cdr stub))))
           (signal (car err) (cdr err))))))))

;;;###autoload
(defun sp-split-leave-parents (&optional no-link)
  "Run `vulpea-split-heading', recording where the heading came from.
The new note gets a `- parents ::' line linking back to the note the
subtree was split out of, and the source note gets a plain link to the
new note on the line where the heading started.  With a prefix
argument NO-LINK, the link in the source is not left."
  (interactive "P")
  (let ((sp-split--active t)
        (sp-split--want-link (not no-link))
        ;; Keep vulpea's own stub option (the prefix argument) out of it.
        (current-prefix-arg nil))
    (call-interactively #'vulpea-split-heading)))

(unless (fboundp 'vulpea-split--write-file)
  (display-warning
   'sp-vulpea-split
   "`vulpea-split--write-file' not found; this vulpea version is not supported"))
(advice-add 'vulpea-split--write-file :around #'sp-split--write-file-advice)

;;; Provide:

(provide 'sp-vulpea-split)
;;; sp-vulpea-split.el ends here