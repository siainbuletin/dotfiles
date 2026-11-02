;;; sp-org-tag-registry.el --- The note tags that are allowed -*- lexical-binding: t; -*-

;;; Commentary:

;; The one list of tags a note may carry, in `org-tag-persistent-alist'.
;; The task tags (@home, deep, ...) are separate, in `org-tag-alist'
;; (`sp-org-taskman-extra').  `sp-org-tag-lint' reads both lists to find
;; tags that are not registered.
;;
;; This file is data, not a literate module: `M-x sp-org-tag-add' inserts
;; the new tag above the marker line at the end of the list, saves the file
;; and loads it again, so a new tag works without restarting Emacs.  Never
;; tangle over it.  Edit it by hand too if you like; keep the marker line.

;;; Code:

(setq org-tag-persistent-alist
      '(;; Structure (PARA)
        ("area")
        ("project")
        ("agenda")
        ("archive")
        ("cemetery")

        ;; People and institutions
        ("person")
        ("musician")
        ("group")
        ("institution")
        ("company")

        ;; Music
        ("album")
        ("genre")

        ;; Software
        ("software")
        ("package")

        ;; Literature
        ("text")
        ("book")
        ("journalarticle")
        ("booksection")
        ("collection")
        ("incollection")

        ;; Inquiries
        ("inquiry")
        ("question")
        ("error")
        ("research-q")
        ("exploratory")

        ;; Others
        ("concept")
        ("emacs")
        ("audio")
        ("docs")
        ("process")
        ("library")
        ("zettel")
        ("thesis")
        ("format")
        ("website")
        ;; sp-org-tag-add: new tags go above this line
        ))

;; A leftover git conflict marker in the list above reads as the symbols `<<<<<<<',
;; `=======' or `>>>>>>>' and makes Org fail with "Invalid association in tag
;; alist".  Drop such entries and say where they came from.
(let ((bad (seq-remove (lambda (e) (or (stringp e) (consp e)))
                       org-tag-persistent-alist)))
  (when bad
    (setq org-tag-persistent-alist
          (seq-filter (lambda (e) (or (stringp e) (consp e)))
                      org-tag-persistent-alist))
    (display-warning
     'sp-org-tag-registry
     (format "Ignored %S in sp-org-tag-registry.el: resolve the git conflict markers there"
             bad)
     :error)))

(provide 'sp-org-tag-registry)
;;; sp-org-tag-registry.el ends here
