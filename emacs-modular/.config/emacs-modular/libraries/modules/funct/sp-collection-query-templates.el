;;; sp-collection-query-templates.el --- Insert query table views as dynamic blocks -*- lexical-binding: t; -*-

;;; Commentary:

;; Offers every query table view to `sp-org-dblock-insert-template', in
;; groups: Academic for the literature note views, Collections for the rest.

;;; Code:

(require 'subr-x)
(require 'sp-collection-query-views)

(defcustom sp-collec-query-view-categories
  '(("book-sections" . "Academic")
    ("collection-articles" . "Academic")
    ("reference-entries" . "Academic")
    ("encyclopedia-articles" . "Academic")
    ("bib-parent-mismatches" . "Academic"))
  "The group of a view in `sp-org-dblock-insert-template', by view name.
Elements are (VIEW-NAME . CATEGORY)."
  :type '(alist :key-type (string :tag "View") :value-type (string :tag "Group"))
  :group 'sp-collec-query)

(defcustom sp-collec-query-default-category "Collections"
  "The group of a view that `sp-collec-query-view-categories' does not list."
  :type 'string
  :group 'sp-collec-query)

(defun sp-collec-query-view-category (name)
  "The group of the view called NAME."
  (or (cdr (assoc name sp-collec-query-view-categories))
      sp-collec-query-default-category))

(defun sp-collec-query-dblock-templates ()
  "Templates for `sp-org-dblock-insert-template', one per view.
Each inserts a `collection-query-table' block with that :view."
  (mapcar (lambda (name)
            (list name
                  :category (sp-collec-query-view-category name)
                  :name "collection-query-table"
                  :view name))
          (sp-collec-query-views-names)))

(add-hook 'sp-org-dblock-template-functions #'sp-collec-query-dblock-templates)

(provide 'sp-collection-query-templates)
;;; sp-collection-query-templates.el ends here
