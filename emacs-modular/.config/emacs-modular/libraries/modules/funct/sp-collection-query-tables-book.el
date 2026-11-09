;;; sp-collection-query-tables-book.el --- Section tables for books and collections -*- lexical-binding: t; -*-

;;; Commentary:

;; The sections of a book or an edited collection as a query table.
;;
;; A note tagged book or collection is the parent; its chapters (booksection,
;; incollection) link back to it with the meta key bib-parent.  The table
;; lists those chapters in page order, from their pub-pages meta key.
;; The same data feeds the vulpea-ui widget in
;; `sp-collection-query-tables-book-widget'.

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'vulpea)
(require 'sp-collection-query-tables-core)

(declare-function sp-collec-query-open "sp-collection-query-tables")
(declare-function org-entry-get "org")

(defgroup sp-collec-query-book nil
  "Section tables for books and collections."
  :group 'sp-collec-query
  :prefix "sp-collec-query-book-")

(defcustom sp-collec-query-book-tags '("book" "collection")
  "Tags of the notes whose sections are listed."
  :type '(repeat string)
  :group 'sp-collec-query-book)

(defcustom sp-collec-query-book-parent-prop "bib-parent"
  "Meta key a section uses to link to its book or collection."
  :type 'string
  :group 'sp-collec-query-book)

(defcustom sp-collec-query-book-columns
  '(:pages :title "pub-author" :bibtex :dt-page)
  "Columns of a section table, see `sp-collec-query-spec-keys'.
:PAGES is the text of pub-pages; the table is sorted on its first number.
:BIBTEX opens the BibTeX entry of the section's ROAM_REFS and :DT-PAGE the
page of the book's PDF in DEVONthink where the section starts."
  :type '(repeat (choice symbol string))
  :group 'sp-collec-query-book)

(defun sp-collec-query-book-p (note)
  "Non-nil if NOTE carries one of `sp-collec-query-book-tags'."
  (and note
       (seq-some (lambda (tag) (member tag (vulpea-note-tags note)))
                 sp-collec-query-book-tags)))

(defun sp-collec-query-book-parent (note)
  "Return the note NOTE's bib-parent link points at, or nil."
  (and-let* ((id (car (vulpea-note-meta-get-list
                       note sp-collec-query-book-parent-prop 'link))))
    (ignore-errors (vulpea-db-get-by-id id))))

(defun sp-collec-query-book-root (note)
  "Return the book or collection NOTE belongs to, or nil.
NOTE itself when it is one; else the note its bib-parent points at, if
that is one."
  (cond ((null note) nil)
        ((sp-collec-query-book-p note) note)
        (t (let ((parent (sp-collec-query-book-parent note)))
             (and (sp-collec-query-book-p parent) parent)))))

(defun sp-collec-query-book-spec (book)
  "Return the query spec for the sections of BOOK, sorted by first page."
  (list :parent-of (vulpea-note-id book)
        :parent-prop sp-collec-query-book-parent-prop
        :columns (copy-sequence sp-collec-query-book-columns)
        :sort-by :pages))

(defun sp-collec-query-book-sections (book)
  "Return the notes that link to BOOK, in page order.
Sections without a page number come last, in the order they were found."
  (sp-collec-query-query (sp-collec-query-book-spec book)))

(defun sp-collec-query-book-position (note)
  "Return where NOTE sits in its book, or nil when it is in none.
A plist with :BOOK, :SECTIONS (page order), :INDEX (0-based position of
NOTE in :SECTIONS, nil when NOTE is the book itself), :PREVIOUS and :NEXT
(the neighbouring sections, or nil)."
  (when-let* ((book (sp-collec-query-book-root note)))
    (let* ((sections (sp-collec-query-book-sections book))
           (id (vulpea-note-id note))
           (index (seq-position sections id
                                (lambda (n id) (equal (vulpea-note-id n) id)))))
      (list :book book
            :sections sections
            :index index
            :previous (and index (> index 0) (nth (1- index) sections))
            :next (and index (nth (1+ index) sections))))))

(defun sp-collec-query-book--note-at-point ()
  "Return the note at point, the one with the nearest ID, or nil."
  (and (derived-mode-p 'org-mode)
       (when-let* ((id (org-entry-get nil "ID" t)))
         (ignore-errors (vulpea-db-get-by-id id)))))

;;;###autoload
(defun sp-collec-query-book-open (&optional note)
  "Open the section table of the book NOTE belongs to.
NOTE defaults to the note at point; when that is in no book, a book or
collection is asked for."
  (interactive)
  (let ((book (or (sp-collec-query-book-root
                   (or note (sp-collec-query-book--note-at-point)))
                  (sp-collec-query-book-root
                   (sp-collec-query-select-note "Book or collection: ")))))
    (unless book
      (user-error "That note is not tagged %s"
                  (string-join sp-collec-query-book-tags " or ")))
    (sp-collec-query-open (sp-collec-query-book-spec book))))

(with-eval-after-load 'vulpea-ui
  (require 'sp-collection-query-tables-book-widget))

(provide 'sp-collection-query-tables-book)
;;; sp-collection-query-tables-book.el ends here
