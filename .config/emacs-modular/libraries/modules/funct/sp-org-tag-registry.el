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

        ;; People and bodies
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

        ("concept")
        ("emacs")
        ("audio")
        ;; sp-org-tag-add: new tags go above this line
        ))

(provide 'sp-org-tag-registry)
;;; sp-org-tag-registry.el ends here
