;;; sp-org-tag-registry.el --- The note tags that are allowed -*- lexical-binding: t; -*-

;;; Commentary:

;; The one list of tags a note may carry.  It is data in two variables:
;; `sp-org-tag-groups-alist', the tags sorted into groups, and
;; `sp-org-tag-groups-ungrouped', the tags in no group yet (the `unsorted'
;; group).  `org-tag-persistent-alist' is derived from them, never edited
;; by hand: see ADR 0020.  The task tags (@home, deep, ...) are separate,
;; in `org-tag-alist' (`sp-org-taskman-extra').  `sp-org-tag-lint' reads
;; both lists to find tags that are not registered.
;;
;; This file is data, not a literate module: `M-x sp-org-tag-add' inserts
;; the new tag in the element of its group, or above the marker line at the
;; end of the ungrouped list, saves the file and loads it again, so a new
;; tag works without restarting Emacs.  Never tangle over it.  Edit it by
;; hand too if you like; keep the marker line and one element per group.

;;; Code:

;; `sp-org-tag-groups-to-alist' comes from `sp-org-tag-lint', which loads this file.
(require 'seq)
(declare-function sp-org-tag-groups-to-alist "sp-org-tag-lint")
(defvar sp-org-tag-groups-alist)
(defvar sp-org-tag-groups-ungrouped)

(setq sp-org-tag-groups-alist
      '(("structure"  "area" "project" "agenda" "archive" "cemetery")
        ("who"        "person" "musician" "group" "institution" "company")
        ("music"      "album" "genre")
        ("software"   "software" "package")
        ("literature" "text" "book" "journalarticle" "booksection"
                      "collection" "incollection" "phdthesis" "mastersthesis")
        ("inquiry"    "question" "error" "research-q" "exploratory")))

;; Tags that are in no group yet: the `unsorted' group.
(setq sp-org-tag-groups-ungrouped
      '("concept"
        "emacs"
        "audio"
        "docs"
        "process"
        "library"
        "zettel"
        "thesis"
        "format"
        "website"
        "plugin"
        "workflow"
        "system"
        "litnote"
        "film"
        "hardware"
        "computing"
        "networking"
        ;; sp-org-tag-add: new tags go above this line
        ))

;; A leftover git conflict marker in the lists above reads as the symbols
;; `<<<<<<<', `=======' or `>>>>>>>'.  Drop such entries and say where they
;; came from, so Org still starts.
(let ((bad (append (seq-remove #'consp sp-org-tag-groups-alist)
                   (seq-remove #'stringp sp-org-tag-groups-ungrouped))))
  (when bad
    (setq sp-org-tag-groups-alist (seq-filter #'consp sp-org-tag-groups-alist)
          sp-org-tag-groups-ungrouped (seq-filter #'stringp sp-org-tag-groups-ungrouped))
    (display-warning
     'sp-org-tag-registry
     (format "Ignored %S in sp-org-tag-registry.el: resolve the git conflict markers there"
             bad)
     :error)))

(setq org-tag-persistent-alist
      (sp-org-tag-groups-to-alist sp-org-tag-groups-alist sp-org-tag-groups-ungrouped))

(provide 'sp-org-tag-registry)
;;; sp-org-tag-registry.el ends here
