;;; sp-see-also-widget.el --- vulpea-ui widgets for see-also footnotes -*- lexical-binding: t; -*-

;;; Commentary:

;; `see-also' shows the concepts and open questions that the see-also footnotes of
;; the current litnote point at; `concept-usage' shows where the current note is
;; mentioned.  The data comes from `sp-see-also'.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'vulpea)
(require 'vulpea-ui)
(require 'vui)
(require 'sp-see-also)

(defcustom sp-see-also-widget-limit 10
  "Most rows each part of a see-also widget shows."
  :type 'integer
  :group 'sp-see-also)

(defcustom sp-see-also-widget-order 340
  "Order of the see-also widget in the vulpea-ui sidebar; the concept usage widget is one more."
  :type 'integer
  :group 'sp-see-also)

(defun sp-see-also-widget--marks (mention)
  "Return the marker text of MENTION."
  (concat (if (eq (plist-get mention :where) 'quote) "❝" " ")
          (if (plist-get mention :open) "?" " ")))

(defun sp-see-also-widget--jump (mention &optional file)
  "Return a function that visits MENTION, in FILE or the file it was found in."
  (lambda ()
    (sp-see-also-visit (or file (plist-get mention :file)) (plist-get mention :beg))))

(defun sp-see-also-widget--open-concept (id)
  "Visit the note of concept ID."
  (if-let* ((note (and (fboundp 'vulpea-db-get-by-id) (vulpea-db-get-by-id id))))
      (vulpea-visit note)
    (message "There is no note with the ID %s" id)))

(defun sp-see-also-widget--concept-row (file concept)
  "Return the row of CONCEPT, found in FILE."
  (let ((first (car (sort (copy-sequence (plist-get concept :mentions))
                          (lambda (a b) (> (sp-see-also-mention-weight a)
                                           (sp-see-also-mention-weight b)))))))
    (vui-hstack
     (vui-text (format "%5.1f " (plist-get concept :score)))
     (vui-button (plist-get concept :title)
                 :on-click (lambda () (sp-see-also-widget--open-concept (plist-get concept :id))))
     (vui-text " ")
     (vui-button (format "×%d" (plist-get concept :count))
                 :on-click (sp-see-also-widget--jump first file))
     (vui-text (concat (if (> (plist-get concept :quotes) 0)
                           (format " ❝%d" (plist-get concept :quotes)) "")
                       (if (> (plist-get concept :questions) 0)
                           (format " ?%d" (plist-get concept :questions)) ""))))))

(defun sp-see-also-widget--question-row (file question)
  "Return the row of the open QUESTION, found in FILE."
  (vui-hstack
   (vui-text (format "%5.1f " (plist-get question :priority)))
   (vui-button (format "%s %s" (plist-get question :keyword) (plist-get question :title))
               :on-click (lambda ()
                           (sp-see-also-visit file (plist-get question :pos))))
   (vui-text (format " (%d)" (plist-get question :count)))))

(vui-defcomponent sp-see-also-widget ()
  "The see-also concepts and open questions of the current litnote."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (when-let* ((file (vulpea-note-path note))
                  (concepts (sp-see-also-concepts-for-file file)))
        (let ((questions (sp-see-also-questions-for-file file)))
          (vui-component 'vulpea-ui-widget
            :title "See also"
            :count (length concepts)
            :children
            (lambda ()
              (apply #'vui-vstack
                     (append
                      (mapcar (lambda (concept) (sp-see-also-widget--concept-row file concept))
                              (seq-take concepts sp-see-also-widget-limit))
                      (when questions
                        (cons (vui-text "Open questions")
                              (mapcar (lambda (question)
                                        (sp-see-also-widget--question-row file question))
                                      (seq-take questions sp-see-also-widget-limit)))))))))))))

(defun sp-see-also-widget--usage-rows (usage)
  "Return the rows for USAGE, at most `sp-see-also-widget-limit' mentions."
  (let ((left sp-see-also-widget-limit)
        rows)
    (dolist (entry usage)
      (when (> left 0)
        (push (vui-text (format "%s (%d)" (plist-get entry :title)
                                (length (plist-get entry :mentions))))
              rows)
        (dolist (mention (plist-get entry :mentions))
          (when (> left 0)
            (setq left (1- left))
            (push (vui-hstack
                   (vui-text (concat " " (sp-see-also-widget--marks mention) " "))
                   (vui-button (truncate-string-to-width
                                (let ((s (plist-get mention :snippet)))
                                  (if (string-empty-p s) (or (plist-get mention :heading) "…") s))
                                60 nil nil "…")
                               :on-click (sp-see-also-widget--jump mention)))
                  rows)))))
    (nreverse rows)))

(vui-defcomponent sp-see-also-usage-widget ()
  "The litnotes that mention the current note as a see-also concept."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (when-let* ((usage (sp-see-also-concept-usage (vulpea-note-id note))))
        (vui-component 'vulpea-ui-widget
          :title "Mentioned in"
          :count (length usage)
          :children
          (lambda ()
            (apply #'vui-vstack (sp-see-also-widget--usage-rows usage))))))))

(vulpea-ui-register-widget 'see-also
  :component 'sp-see-also-widget
  :order sp-see-also-widget-order)

(vulpea-ui-register-widget 'concept-usage
  :component 'sp-see-also-usage-widget
  :order (1+ sp-see-also-widget-order))

(provide 'sp-see-also-widget)
;;; sp-see-also-widget.el ends here
