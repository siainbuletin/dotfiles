;;; sp-vulpea-grouped-backlinks-widget.el --- Grouped backlinks as a vulpea-ui widget -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "29.1") (vulpea "2") (vulpea-ui "0") (vui "0"))

;;; Commentary:

;; A vulpea-ui sidebar widget with the backlinks of the current note,
;; grouped by the meta property they were found in.  The grouping lives in
;; `sp-vulpea-grouped-backlinks'.

;;; Code:

(require 'vulpea)
(require 'vulpea-ui)
(require 'vui)
(require 'sp-vulpea-grouped-backlinks)

(defun sp-vulpea-grouped-backlinks-widget--pad (blocks)
  "Return BLOCKS with blank lines between them (`sp-vulpea-grouped-backlinks--padding')."
  (let (out)
    (dolist (block blocks)
      (when out
        (dotimes (_ (max 0 sp-vulpea-grouped-backlinks-block-padding))
          (push (vui-text "") out)))
      (push block out))
    (nreverse out)))

(defun sp-vulpea-grouped-backlinks-widget--block (title notes)
  "Return a heading TITLE with its count, and a link to each of NOTES under it."
  (vui-vstack
   (vui-text (format "%s (%d)" title (length notes))
             :face 'font-lock-keyword-face)
   (apply #'vui-vstack
          :indent 2
          (mapcar (lambda (n)
                    (vui-component 'vulpea-ui-note-link :note n))
                  notes))))

(defun sp-vulpea-grouped-backlinks-widget--section (section)
  "Return the block of SECTION: a flat group, or a heading over its subsections."
  (if (sp-vulpea-grouped-backlinks--flat-p section)
      (sp-vulpea-grouped-backlinks-widget--block
       (car section) (cdr (cadr section)))
    (vui-vstack
     (vui-text (format "%s (%d)" (car section)
                       (sp-vulpea-grouped-backlinks-section-count section))
               :face 'font-lock-keyword-face)
     (apply #'vui-vstack
            :indent 2
            (sp-vulpea-grouped-backlinks-widget--pad
             (mapcar (lambda (sub)
                       (sp-vulpea-grouped-backlinks-widget--block
                        (car sub) (cdr sub)))
                     (cdr section)))))))

(vui-defcomponent sp-vulpea-grouped-backlinks-widget ()
  "Backlinks of the current note, grouped by meta property."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (let ((sections (vui-use-memo (note)
                        (sp-vulpea-grouped-backlinks-sections
                         (vulpea-note-id note)))))
        (vui-component 'vulpea-ui-widget
          :title "Grouped backlinks"
          :count (apply #'+ (mapcar #'sp-vulpea-grouped-backlinks-section-count
                                    sections))
          :children
          (lambda ()
            (if (null sections)
                (vui-text "No backlinks")
              (apply #'vui-vstack
                     (sp-vulpea-grouped-backlinks-widget--pad
                      (mapcar #'sp-vulpea-grouped-backlinks-widget--section
                              sections))))))))))

(vulpea-ui-register-widget 'grouped-backlinks
  :component 'sp-vulpea-grouped-backlinks-widget
  :order 310) ; right after backlinks (300)

(provide 'sp-vulpea-grouped-backlinks-widget)
;;; sp-vulpea-grouped-backlinks-widget.el ends here
