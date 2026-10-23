;;; sp-collection-query-tables-views.el --- Saved views for query tables -*- lexical-binding: t; -*-

;;; Commentary:

;; A view is a name and a spec (see `sp-collection-query-tables-spec-keys').  Views
;; live in `sp-collection-query-tables-views-file' as readable Lisp.  Files written by
;; the first version of this module, one (NAME TAGS COLUMNS SORT-BY
;; PARENT-OF PARENT-PROP) list per view, are read and converted; the next
;; save writes the new format.

;;; Code:

(require 'pp)
(require 'subr-x)
(require 'cl-lib)
(require 'sp-collection-query-tables-core)

(defcustom sp-collection-query-tables-views-file
  (expand-file-name "sp-collection-query-tables-views.el" user-emacs-directory)
  "File where named query table views are saved."
  :type 'file
  :group 'sp-collection-query-tables)

(defconst sp-collection-query-tables-views--legacy-file
  (expand-file-name "sp-vulpea-table-views.el" user-emacs-directory)
  "Where the views were saved before the module was renamed.")

(defvar sp-collection-query-tables-views nil
  "Alist of (NAME . SPEC) for the saved query table views.")

(defvar sp-collection-query-tables-views--loaded nil
  "Non-nil once `sp-collection-query-tables-views-file' has been read.")

(defun sp-collection-query-tables-views--legacy-entry-p (entry)
  "Non-nil if ENTRY is a (NAME TAGS COLUMNS ...) list of the first version."
  (and (stringp (car entry))
       (listp (cdr entry))
       (not (keywordp (cadr entry)))))

(defun sp-collection-query-tables-views--convert-legacy (entry)
  "Return the (NAME . SPEC) cons for the first-version ENTRY."
  (pcase-let ((`(,name ,tags ,columns ,sort-by ,parent-of ,parent-prop) entry))
    (cons name (sp-collection-query-tables-spec-normalize
                (list :tags tags :columns columns :sort-by sort-by
                      :parent-of parent-of :parent-prop parent-prop)))))

(defun sp-collection-query-tables-views--source ()
  "Return the file to read the views from, or nil.
That is `sp-collection-query-tables-views-file'; while it does not exist yet,
the file the views had before the rename, so saved views carry over."
  (cl-find-if #'file-exists-p
              (list sp-collection-query-tables-views-file
                    sp-collection-query-tables-views--legacy-file)))

(defun sp-collection-query-tables-views-load ()
  "Read the saved views from `sp-collection-query-tables-views-file', if present."
  (interactive)
  (setq sp-collection-query-tables-views
        (when-let* ((file (sp-collection-query-tables-views--source)))
          (let ((data (with-temp-buffer
                        (insert-file-contents file)
                        (read (current-buffer)))))
            (mapcar (lambda (entry)
                      (if (sp-collection-query-tables-views--legacy-entry-p entry)
                          (sp-collection-query-tables-views--convert-legacy entry)
                        (cons (car entry) (sp-collection-query-tables-spec-normalize (cdr entry)))))
                    data)))
        sp-collection-query-tables-views--loaded t))

(defun sp-collection-query-tables-views--ensure-loaded ()
  "Read the views file once."
  (unless sp-collection-query-tables-views--loaded
    (sp-collection-query-tables-views-load)))

(defun sp-collection-query-tables-views-save-to-disk ()
  "Write `sp-collection-query-tables-views' to `sp-collection-query-tables-views-file'."
  (make-directory (file-name-directory sp-collection-query-tables-views-file) t)
  (with-temp-file sp-collection-query-tables-views-file
    (insert ";;; Saved query table views  -*- mode: lisp-data; -*-\n"
            ";; Written by `sp-collection-query-tables-views-save-to-disk'.  Each entry is\n"
            ";; (NAME . SPEC); SPEC is a plist, see `sp-collection-query-tables-spec-keys'.\n")
    (let ((print-length nil) (print-level nil))
      (pp sp-collection-query-tables-views (current-buffer)))))

(defun sp-collection-query-tables-views-names ()
  "Return the names of the saved views."
  (sp-collection-query-tables-views--ensure-loaded)
  (mapcar #'car sp-collection-query-tables-views))

(defun sp-collection-query-tables-views-get (name)
  "Return the spec of the saved view NAME, or nil."
  (sp-collection-query-tables-views--ensure-loaded)
  (cdr (assoc name sp-collection-query-tables-views)))

(defun sp-collection-query-tables-views-put (name spec)
  "Save SPEC as the view NAME, replacing a view of that name, and write the file."
  (sp-collection-query-tables-views--ensure-loaded)
  (setf (alist-get name sp-collection-query-tables-views nil nil #'string=)
        (sp-collection-query-tables-spec-normalize spec))
  (sp-collection-query-tables-views-save-to-disk))

(defun sp-collection-query-tables-views-read-name (prompt)
  "Ask with PROMPT for the name of a saved view, with completion."
  (unless (sp-collection-query-tables-views-names)
    (user-error "No saved query table views yet; build one with `sp-collection-query-tables-menu'"))
  (completing-read prompt (sp-collection-query-tables-views-names) nil t))

(defun sp-collection-query-tables-view-delete (name)
  "Delete the saved view NAME, asked for with completion."
  (interactive (list (sp-collection-query-tables-views-read-name "Delete view: ")))
  (sp-collection-query-tables-views--ensure-loaded)
  (setq sp-collection-query-tables-views (assoc-delete-all name sp-collection-query-tables-views))
  (sp-collection-query-tables-views-save-to-disk)
  (message "Deleted query table view \"%s\"" name))

(provide 'sp-collection-query-tables-views)
;;; sp-collection-query-tables-views.el ends here
