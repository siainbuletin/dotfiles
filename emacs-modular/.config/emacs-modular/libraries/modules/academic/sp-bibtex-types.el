;;; sp-bibtex-types.el --- BibTeX entry type to litnote tag -*- lexical-binding: t; -*-

;;; Commentary:

;; One table, `sp-bibtex-types-tag-alist', says which org tag a litnote gets
;; for a BibTeX entry type.  Entry types that are not in it are filed as
;; `sp-bibtex-types-default-tag' (the base-text scheme of sp-vulpea-schemas).
;; See the doc docs/tangles/academic/sp-bibtex-types.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup sp-bibtex-types nil
  "BibTeX entry types and the litnote tags they are filed under."
  :group 'sp-author-notes
  :prefix "sp-bibtex-types-")

(defcustom sp-bibtex-types-tag-alist
  '(("booksection" . "booksection")
    ("incollection" . "incollection")
    ("article" . "journalarticle")
    ("book" . "book")
    ("collection" . "collection")
    ("mvcollection" . "collection")
    ("inreference" . "inreference")
    ("reference" . "reference")
    ("mvreference" . "reference")
    ("phdthesis" . "phdthesis")
    ("mastersthesis" . "mastersthesis"))
  "Org tag of a litnote for each BibTeX entry type (compared ignoring case).
Each element is (TYPE . TAG), both strings without colons."
  :type '(alist :key-type string :value-type string)
  :group 'sp-bibtex-types)

(defcustom sp-bibtex-types-default-tag "text"
  "Tag for an entry type that `sp-bibtex-types-tag-alist' does not list.
It is the tag of the `base-text' scheme in `sp-vulpea-schemas'."
  :type 'string
  :group 'sp-bibtex-types)

(defun sp-bibtex-types-tag (type)
  "The org tag, without colons, for the BibTeX entry TYPE.
TYPE is a string such as \"InCollection\", compared ignoring case; with a
nil or empty TYPE, or one not in `sp-bibtex-types-tag-alist', the result
is `sp-bibtex-types-default-tag'."
  (or (and (stringp type)
           (cdr (assoc-string (string-trim type) sp-bibtex-types-tag-alist t)))
      sp-bibtex-types-default-tag))

(defun sp-bibtex-types-entry-tag (entry)
  "The org tag for ENTRY, an alist as `bibtex-parse-entry' returns."
  (sp-bibtex-types-tag (cdr (assoc "=type=" entry))))

(defun sp-bibtex-types-all-tags ()
  "Every tag `sp-bibtex-types-tag' can return, each once."
  (delete-dups (append (mapcar #'cdr sp-bibtex-types-tag-alist)
                       (list sp-bibtex-types-default-tag))))

(defun sp-bibtex-types-collection-p (type)
  "Non-nil when the BibTeX entry TYPE is filed as a collection."
  (equal (sp-bibtex-types-tag type) "collection"))

(provide 'sp-bibtex-types)
;; sp-bibtex-types.el ends here
