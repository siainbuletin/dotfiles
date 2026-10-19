;;; sp-vulpea-hierarchy.el --- Parent/child views of vulpea notes -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (vulpea "2.7.0"))

;;; Commentary:

;; Builds a hierarchy from a `- parent :: [[id:...][Title]]' entry in
;; each note's zeroth section and shows it two ways:
;;
;;   M-x vulpea-hierarchy-outline  foldable Org outline of id links
;;   M-x vulpea-hierarchy-graph    Graphviz tree rendered as SVG
;;
;; The graph view needs the `dot' executable (Graphviz).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'vulpea)

(defgroup vulpea-hierarchy nil
  "Parent/child views of vulpea notes."
  :group 'vulpea)

(defcustom vulpea-hierarchy-parent-key "parents"
  "Metadata key that holds a note's parent link."
  :type 'string)

(defcustom vulpea-hierarchy-graph-file
  (expand-file-name "vulpea-hierarchy.svg" temporary-file-directory)
  "Where `vulpea-hierarchy-graph' writes its SVG."
  :type 'file)

(defcustom vulpea-hierarchy-rankdir "LR"
  "Graphviz layout direction: \"LR\" (left to right) or \"TB\" (top down)."
  :type '(choice (const "LR") (const "TB")))

(defun vulpea-hierarchy--build ()
  "Return a plist describing the hierarchy.
:notes maps id to note, :children maps parent id to child ids,
:roots lists ids that are parents but have no parent themselves."
  (let ((notes (make-hash-table :test #'equal))
        (children (make-hash-table :test #'equal))
        (has-parent (make-hash-table :test #'equal))
        parent-ids)
    (dolist (note (vulpea-db-query-by-meta-key vulpea-hierarchy-parent-key))
      (puthash (vulpea-note-id note) note notes)
      (dolist (pid (vulpea-note-meta-get-list
                    note vulpea-hierarchy-parent-key 'link))
        (puthash (vulpea-note-id note) t has-parent)
        (push (vulpea-note-id note) (gethash pid children))
        (push pid parent-ids)))
    ;; Parents that carry no parent key themselves are not loaded yet.
    (dolist (note (vulpea-db-query-by-ids
                   (seq-remove (lambda (id) (gethash id notes))
                               (delete-dups parent-ids))))
      (puthash (vulpea-note-id note) note notes))
    (list :notes notes
          :children children
          :roots (sort (seq-remove (lambda (id) (gethash id has-parent))
                                   (delete-dups (copy-sequence parent-ids)))
                       (lambda (a b)
                         (string< (vulpea-hierarchy--title a notes)
                                  (vulpea-hierarchy--title b notes)))))))

(defun vulpea-hierarchy--title (id notes)
  "Title of note ID from NOTES, or a marker for a dangling link."
  (if-let ((note (gethash id notes)))
      (vulpea-note-title note)
    (format "<missing %s>" id)))

(defun vulpea-hierarchy--sorted-children (id tree)
  "Child ids of ID in TREE, sorted by title."
  (let ((notes (plist-get tree :notes)))
    (sort (copy-sequence (gethash id (plist-get tree :children)))
          (lambda (a b)
            (string< (vulpea-hierarchy--title a notes)
                     (vulpea-hierarchy--title b notes))))))

;;; Outline view

(defun vulpea-hierarchy--insert-outline (id tree depth seen)
  "Insert ID and its descendants from TREE as Org headings at DEPTH.
SEEN guards against parent cycles."
  (let* ((notes (plist-get tree :notes))
         (note (gethash id notes))
         (kids (vulpea-hierarchy--sorted-children id tree)))
    (insert (make-string depth ?*) " "
            (format "[[id:%s][%s]]" id (vulpea-hierarchy--title id notes)))
    (when kids
      (insert (format " [%d]" (length kids))))
    (when-let ((tags (and note (vulpea-note-tags note))))
      (insert " :" (string-join tags ":") ":"))
    (insert "\n")
    (if (member id seen)
        (insert (make-string (1+ depth) ?*) " cycle back to this note\n")
      (dolist (kid kids)
        (vulpea-hierarchy--insert-outline kid tree (1+ depth) (cons id seen))))))

;;;###autoload
(defun vulpea-hierarchy-outline ()
  "Show the note hierarchy as a foldable Org outline of id links."
  (interactive)
  (let ((tree (vulpea-hierarchy--build))
        (buf (get-buffer-create "*vulpea hierarchy*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (org-mode)
        (dolist (root (plist-get tree :roots))
          (vulpea-hierarchy--insert-outline root tree 1 nil))
        (goto-char (point-min))
        (org-content 2))
      (setq buffer-read-only t))
    (pop-to-buffer buf)))

;;; Graph view

(defun vulpea-hierarchy--dot (tree)
  "Return Graphviz source for TREE, one cluster per root."
  (let ((notes (plist-get tree :notes))
        (children (plist-get tree :children))
        (drawn (make-hash-table :test #'equal)))
    (with-temp-buffer
      (insert "digraph vulpea {\n"
              (format "  rankdir=%s;\n" vulpea-hierarchy-rankdir)
              "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#f4f4f4\","
              " fontname=\"Helvetica\"];\n"
              "  edge [color=\"#888888\"];\n")
      (let ((n 0))
        (dolist (root (plist-get tree :roots))
          (insert (format "  subgraph cluster_%d {\n    style=invis;\n" (cl-incf n)))
          (let ((queue (list root)))
            (while queue
              (let ((id (pop queue)))
                (unless (gethash id drawn)
                  (puthash id t drawn)
                  (insert (format "    %S [label=%S%s];\n"
                                  id (vulpea-hierarchy--title id notes)
                                  (if (equal id root)
                                      ", fillcolor=\"#d8e6f5\", penwidth=2"
                                    "")))
                  (setq queue (append queue (gethash id children)))))))
          (insert "  }\n")))
      (maphash (lambda (pid kids)
                 (dolist (kid kids)
                   (insert (format "  %S -> %S;\n" pid kid))))
               children)
      (insert "}\n")
      (buffer-string))))

;;;###autoload
(defun vulpea-hierarchy-graph ()
  "Render the note hierarchy with Graphviz and display the SVG."
  (interactive)
  (unless (executable-find "dot")
    (user-error "Graphviz `dot' not found on PATH"))
  (let ((dot (vulpea-hierarchy--dot (vulpea-hierarchy--build))))
    (with-temp-buffer
      (insert dot)
      (unless (zerop (call-process-region (point-min) (point-max) "dot" nil t nil
                                          "-Tsvg" "-o" vulpea-hierarchy-graph-file))
        (error "Graphviz failed: %s" (buffer-string))))
    (let ((buf (find-file-noselect vulpea-hierarchy-graph-file)))
      (with-current-buffer buf
        (revert-buffer t t))
      (pop-to-buffer buf))))

(provide 'sp-vulpea-hierarchy)
;;; sp-vulpea-hierarchy.el ends here
