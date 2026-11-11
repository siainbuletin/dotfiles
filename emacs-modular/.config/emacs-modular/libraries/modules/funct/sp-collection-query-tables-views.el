;;; sp-collection-query-tables-views.el --- Saved views for query tables -*- lexical-binding: t; -*-

;;; Commentary:

;; A view is a name and a spec (see `sp-collec-query-spec-keys').  Views
;; live in `sp-collec-query-views-file' as readable Lisp.  Files written by
;; the first version of this module, one (NAME TAGS COLUMNS SORT-BY
;; PARENT-OF PARENT-PROP) list per view, are read and converted; the next
;; save writes the new format.

;;; Code:

(require 'pp)
(require 'subr-x)
(require 'cl-lib)
(require 'sp-collection-query-tables-core)

(defcustom sp-collec-query-views-file
  (expand-file-name "views/sp-collection-query-tables-views.el" user-emacs-directory)
  "File where the views you save are written.
It is inside the configuration (`user-emacs-directory'), so with Stow it
is a link to the file in the dotfiles repository: a saved view shows up in
`git status' there, ready to commit."
  :type 'file
  :group 'sp-collec-query)

(defconst sp-collec-query-views--etc-file
  (expand-file-name "sp-collection-query-tables-views.el" sp-etc-dir)
  "Where the views were saved before they moved into the configuration.")

(defconst sp-collec-query-views--old-file
  (expand-file-name "sp-collection-query-tables-views.el" user-emacs-directory)
  "Where the views were saved before they moved below `sp-etc-dir'.")

(defconst sp-collec-query-views--legacy-file
  (expand-file-name "sp-vulpea-table-views.el" user-emacs-directory)
  "Where the views were saved before the module was renamed.")

(defconst sp-collec-query-views-defaults
  '(("book-sections"
     :parent-of "self" :parent-prop "bib-parent"
     :columns (:pages :title "pub-author" :tags :check)
     :sort-by :pages)
    ("collection-articles"
     :parent-of "self" :parent-prop "bib-parent"
     :columns (:pages :title "pub-author" "pub-year" :tags :check)
     :sort-by :pages)
    ("reference-entries"
     :parent-of "self" :parent-prop "bib-parent"
     :columns (:pages :title "pub-author" "pub-year" :tags :check)
     :sort-by :title)
    ("encyclopedia-articles"
     :parent-of "self" :parent-prop "bib-parent"
     :columns (:title "pub-author" "pub-year" :pages :tags :check)
     :sort-by :title)
    ("bib-parent-mismatches"
     :meta (("bib-parent")) :flagged t
     :columns (:title :tags "bib-parent" :check)
     :sort-by :title))
  "Views that come with the configuration, as (NAME . SPEC).
\"book-sections\" and \"collection-articles\" list the notes linking to the
note they are used in (\"self\"), by page; \"reference-entries\" and
\"encyclopedia-articles\" do the same by title, for the entries of a
reference work and the articles of an encyclopedia.  All flag those whose tags do not
fit (see `sp-collec-query-check').  \"bib-parent-mismatches\" lists every
note in the vault with such a warning.  A saved view with the same name wins.")

(defvar sp-collec-query-views nil
  "Alist of (NAME . SPEC) for the saved query table views.")

(defvar sp-collec-query-views--loaded nil
  "Non-nil once `sp-collec-query-views-file' has been read.")

(defun sp-collec-query-views--legacy-entry-p (entry)
  "Non-nil if ENTRY is a (NAME TAGS COLUMNS ...) list of the first version."
  (and (stringp (car entry))
       (listp (cdr entry))
       (not (keywordp (cadr entry)))))

(defun sp-collec-query-views--convert-legacy (entry)
  "Return the (NAME . SPEC) cons for the first-version ENTRY."
  (pcase-let ((`(,name ,tags ,columns ,sort-by ,parent-of ,parent-prop) entry))
    (cons name (sp-collec-query-spec-normalize
                (list :tags tags :columns columns :sort-by sort-by
                      :parent-of parent-of :parent-prop parent-prop)))))

(defun sp-collec-query-views--read-file (file)
  "Return the data in FILE, or nil when it is missing or holds no views."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (read (current-buffer)))))

(defun sp-collec-query-views--source ()
  "Return the file to read the views from, or nil.
That is `sp-collec-query-views-file' when it holds views; else the first
older file that does (below `sp-etc-dir', in `user-emacs-directory', and
from before the rename), so views saved there carry over.  The next save
writes `sp-collec-query-views-file'."
  (cl-find-if #'sp-collec-query-views--read-file
              (list sp-collec-query-views-file
                    sp-collec-query-views--etc-file
                    sp-collec-query-views--old-file
                    sp-collec-query-views--legacy-file)))

(defun sp-collec-query-views-load ()
  "Read the saved views from `sp-collec-query-views-file', if present."
  (interactive)
  (setq sp-collec-query-views
        (when-let* ((file (sp-collec-query-views--source)))
          (let ((data (sp-collec-query-views--read-file file)))
            (mapcar (lambda (entry)
                      (if (sp-collec-query-views--legacy-entry-p entry)
                          (sp-collec-query-views--convert-legacy entry)
                        (cons (car entry) (sp-collec-query-spec-normalize (cdr entry)))))
                    data)))
        sp-collec-query-views--loaded t))

(defun sp-collec-query-views--ensure-loaded ()
  "Read the views file once."
  (unless sp-collec-query-views--loaded
    (sp-collec-query-views-load)))

(defun sp-collec-query-views-save-to-disk ()
  "Write `sp-collec-query-views' to `sp-collec-query-views-file'."
  (make-directory (file-name-directory sp-collec-query-views-file) t)
  (with-temp-file sp-collec-query-views-file
    (insert ";;; Saved query table views  -*- mode: lisp-data; -*-\n"
            ";; Written by `sp-collec-query-views-save-to-disk'.  Each entry is\n"
            ";; (NAME . SPEC); SPEC is a plist, see `sp-collec-query-spec-keys'.\n")
    (let ((print-length nil) (print-level nil))
      (pp sp-collec-query-views (current-buffer)))))

(defun sp-collec-query-views-names ()
  "Return the names of the saved views."
  (sp-collec-query-views--ensure-loaded)
  (delete-dups (append (mapcar #'car sp-collec-query-views)
                       (mapcar #'car sp-collec-query-views-defaults))))

(defun sp-collec-query-views-get (name)
  "Return the spec of the view NAME, or nil.
A saved view wins over one of `sp-collec-query-views-defaults'."
  (sp-collec-query-views--ensure-loaded)
  (cdr (or (assoc name sp-collec-query-views)
           (assoc name sp-collec-query-views-defaults))))

(defun sp-collec-query-views-put (name spec)
  "Save SPEC as the view NAME, replacing a view of that name, and write the file."
  (sp-collec-query-views--ensure-loaded)
  (setf (alist-get name sp-collec-query-views nil nil #'string=)
        (sp-collec-query-spec-normalize spec))
  (sp-collec-query-views-save-to-disk))

(defun sp-collec-query-views-read-name (prompt)
  "Ask with PROMPT for the name of a saved view, with completion."
  (unless (sp-collec-query-views-names)
    (user-error "No saved query table views yet; build one with `sp-collec-query-menu'"))
  (completing-read prompt (sp-collec-query-views-names) nil t))

(defun sp-collec-query-view-delete (name)
  "Delete the saved view NAME, asked for with completion."
  (interactive (list (sp-collec-query-views-read-name "Delete view: ")))
  (sp-collec-query-views--ensure-loaded)
  (unless (assoc name sp-collec-query-views)
    (user-error "\"%s\" is a built-in view; save a view of that name to override it" name))
  (setq sp-collec-query-views (assoc-delete-all name sp-collec-query-views))
  (sp-collec-query-views-save-to-disk)
  (message "Deleted query table view \"%s\"" name))

(provide 'sp-collection-query-tables-views)
;;; sp-collection-query-tables-views.el ends here
