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

(vui-defcomponent sp-vulpea-grouped-backlinks-widget ()
  "Backlinks of the current note, grouped by meta property."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (let ((groups (vui-use-memo (note)
                      (sp-vulpea-grouped-backlinks-sorted
                       (vulpea-note-id note)))))
        (vui-component 'vulpea-ui-widget
          :title "Grouped backlinks"
          :count (apply #'+ (mapcar (lambda (g) (length (cdr g))) groups))
          :children
          (lambda ()
            (if (null groups)
                (vui-text "No backlinks")
              (apply #'vui-vstack
                     (mapcar
                      (lambda (group)
                        (vui-vstack
                         (vui-text (format "%s (%d)" (car group)
                                           (length (cdr group)))
                                   :face 'font-lock-keyword-face)
                         (apply #'vui-vstack
                                :indent 2
                                (mapcar (lambda (n)
                                          (vui-component 'vulpea-ui-note-link
                                                         :note n))
                                        (cdr group)))))
                      groups)))))))))

(vulpea-ui-register-widget 'grouped-backlinks
  :component 'sp-vulpea-grouped-backlinks-widget
  :order 310) ; right after backlinks (300)

(provide 'sp-vulpea-grouped-backlinks-widget)
;;; sp-vulpea-grouped-backlinks-widget.el ends here
