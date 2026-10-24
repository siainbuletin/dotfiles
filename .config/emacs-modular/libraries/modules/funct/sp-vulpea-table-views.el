;;; sp-vulpea-table-views.el --- Saved views for Vulpea tables -*- lexical-binding: t; -*-

;;; Commentary:

;; A view is a name and a spec (see `sp-vulpea-table-spec-keys').  Views
;; live in `sp-vulpea-table-views-file' as readable Lisp.  Files written by
;; the first version of this module, one (NAME TAGS COLUMNS SORT-BY
;; PARENT-OF PARENT-PROP) list per view, are read and converted; the next
;; save writes the new format.

;;; Code:

(require 'pp)
(require 'subr-x)
(require 'sp-vulpea-table-core)

(defcustom sp-vulpea-table-views-file
  (expand-file-name "sp-vulpea-table-views.el" user-emacs-directory)
  "File where named Vulpea table views are saved."
  :type 'file
  :group 'spcustom)

(defvar sp-vulpea-table-views nil
  "Alist of (NAME . SPEC) for the saved Vulpea table views.")

(defvar sp-vulpea-table-views--loaded nil
  "Non-nil once `sp-vulpea-table-views-file' has been read.")

(defun sp-vulpea-table-views--legacy-entry-p (entry)
  "Non-nil if ENTRY is a (NAME TAGS COLUMNS ...) list of the first version."
  (and (stringp (car entry))
       (listp (cdr entry))
       (not (keywordp (cadr entry)))))

(defun sp-vulpea-table-views--convert-legacy (entry)
  "Return the (NAME . SPEC) cons for the first-version ENTRY."
  (pcase-let ((`(,name ,tags ,columns ,sort-by ,parent-of ,parent-prop) entry))
    (cons name (sp-vulpea-table-spec-normalize
                (list :tags tags :columns columns :sort-by sort-by
                      :parent-of parent-of :parent-prop parent-prop)))))

(defun sp-vulpea-table-views-load ()
  "Read the saved views from `sp-vulpea-table-views-file', if present."
  (interactive)
  (setq sp-vulpea-table-views
        (when (file-exists-p sp-vulpea-table-views-file)
          (let ((data (with-temp-buffer
                        (insert-file-contents sp-vulpea-table-views-file)
                        (read (current-buffer)))))
            (mapcar (lambda (entry)
                      (if (sp-vulpea-table-views--legacy-entry-p entry)
                          (sp-vulpea-table-views--convert-legacy entry)
                        (cons (car entry) (sp-vulpea-table-spec-normalize (cdr entry)))))
                    data)))
        sp-vulpea-table-views--loaded t))

(defun sp-vulpea-table-views--ensure-loaded ()
  "Read the views file once."
  (unless sp-vulpea-table-views--loaded
    (sp-vulpea-table-views-load)))

(defun sp-vulpea-table-views-save-to-disk ()
  "Write `sp-vulpea-table-views' to `sp-vulpea-table-views-file'."
  (make-directory (file-name-directory sp-vulpea-table-views-file) t)
  (with-temp-file sp-vulpea-table-views-file
    (insert ";;; Saved Vulpea table views  -*- mode: lisp-data; -*-\n"
            ";; Written by `sp-vulpea-table-views-save-to-disk'.  Each entry is\n"
            ";; (NAME . SPEC); SPEC is a plist, see `sp-vulpea-table-spec-keys'.\n")
    (let ((print-length nil) (print-level nil))
      (pp sp-vulpea-table-views (current-buffer)))))

(defun sp-vulpea-table-views-names ()
  "Return the names of the saved views."
  (sp-vulpea-table-views--ensure-loaded)
  (mapcar #'car sp-vulpea-table-views))

(defun sp-vulpea-table-views-get (name)
  "Return the spec of the saved view NAME, or nil."
  (sp-vulpea-table-views--ensure-loaded)
  (cdr (assoc name sp-vulpea-table-views)))

(defun sp-vulpea-table-views-put (name spec)
  "Save SPEC as the view NAME, replacing a view of that name, and write the file."
  (sp-vulpea-table-views--ensure-loaded)
  (setf (alist-get name sp-vulpea-table-views nil nil #'string=)
        (sp-vulpea-table-spec-normalize spec))
  (sp-vulpea-table-views-save-to-disk))

(defun sp-vulpea-table-views-read-name (prompt)
  "Ask with PROMPT for the name of a saved view, with completion."
  (unless (sp-vulpea-table-views-names)
    (user-error "No saved Vulpea table views yet; build one with `sp-vulpea-table-menu'"))
  (completing-read prompt (sp-vulpea-table-views-names) nil t))

(defun sp-vulpea-table-view-delete (name)
  "Delete the saved view NAME, asked for with completion."
  (interactive (list (sp-vulpea-table-views-read-name "Delete view: ")))
  (sp-vulpea-table-views--ensure-loaded)
  (setq sp-vulpea-table-views (assoc-delete-all name sp-vulpea-table-views))
  (sp-vulpea-table-views-save-to-disk)
  (message "Deleted Vulpea table view \"%s\"" name))

(provide 'sp-vulpea-table-views)
;;; sp-vulpea-table-views.el ends here
