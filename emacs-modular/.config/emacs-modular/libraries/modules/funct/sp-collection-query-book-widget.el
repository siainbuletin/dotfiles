;;; sp-collection-query-book-widget.el --- vulpea-ui widget: position in a book -*- lexical-binding: t; -*-

;;; Commentary:

;; A `vulpea-ui' sidebar widget that shows where the current note sits among
;; the sections of its book or collection: the sections in page order, the
;; current one marked, and buttons for the previous and next section.
;; The data comes from `sp-collec-query-book-position'.

;;; Code:

(require 'subr-x)
(require 'vulpea)
(require 'vulpea-ui)
(require 'vui)
(require 'sp-collection-query-book)

(defcustom sp-collec-query-book-widget-order 345
  "Order of the book position widget in the vulpea-ui sidebar.
Lower numbers come first; the unlinked mentions widget is 350."
  :type 'integer
  :group 'sp-collec-query-book)

(defun sp-collec-query-book-widget--label (section)
  "Return the text of the row of SECTION: its pages, then its title."
  (let ((pages (sp-collec-query-cell section :pages)))
    (format "%-9s %s" (if (string-empty-p pages) "-" pages)
            (or (vulpea-note-title section) ""))))

(defun sp-collec-query-book-widget--row (section current)
  "Return the row for SECTION; it is marked when it is CURRENT."
  (vui-hstack
   (vui-text (if current "▶ " "  "))
   (vui-button (if current
                   (propertize (sp-collec-query-book-widget--label section) 'face 'bold)
                 (sp-collec-query-book-widget--label section))
               :on-click (lambda () (vulpea-visit section)))))

(vui-defcomponent sp-collec-query-book-widget ()
  "Position of the current note among the sections of its book."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (when-let* ((pos (vui-use-memo (note) (sp-collec-query-book-position note))))
        (let ((book (plist-get pos :book))
              (sections (plist-get pos :sections))
              (index (plist-get pos :index))
              (previous (plist-get pos :previous))
              (next (plist-get pos :next)))
          (vui-component 'vulpea-ui-widget
            :title "Book position"
            :count (length sections)
            :children
            (lambda ()
              (apply #'vui-vstack
                     (vui-button (or (vulpea-note-title book) "Book")
                                 :on-click (lambda () (vulpea-visit book)))
                     (vui-text (if index
                                   (format "Section %d of %d" (1+ index) (length sections))
                                 (format "%d sections" (length sections))))
                     (vui-hstack
                      (vui-button "previous"
                                  :on-click (lambda ()
                                              (if previous
                                                  (vulpea-visit previous)
                                                (message "This is the first section"))))
                      (vui-text " ")
                      (vui-button "next"
                                  :on-click (lambda ()
                                              (if next
                                                  (vulpea-visit next)
                                                (message "This is the last section")))))
                     (mapcar (lambda (section)
                               (sp-collec-query-book-widget--row
                                section (equal (vulpea-note-id section)
                                               (vulpea-note-id note))))
                             sections)))))))))

(vulpea-ui-register-widget 'book-position
  :component 'sp-collec-query-book-widget
  :order sp-collec-query-book-widget-order)

(provide 'sp-collection-query-book-widget)
;;; sp-collection-query-book-widget.el ends here
