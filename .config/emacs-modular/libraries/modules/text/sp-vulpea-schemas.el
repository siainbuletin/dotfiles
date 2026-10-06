;; -*- lexical-binding: t -*-
;; sp-vulpea-schemas.el

;;; Commentary:

;; These are all the schemas that are used by vulpea.

;;; Code:

;;;; Schema definition
;;;;; Schema for albums
(vulpea-schema-define 'album
  :predicate (lambda (note) (member "album" (vulpea-note-tags note)))
  :fields
  '(
    (:key "creator" :type note   :required t :target-tags ("musician" "person" "group"))
    (:key "name"     :type string :required nil)
    (:key "genre"   :type note :required t :multiple t :target-tags ("genre"))
    (:key "genre-influences" :type note :multiple t :target-tags ("genre"))
    (:key "year"   :type number   :required t :multiple nil)
    (:key "rating"   :type number   :required nil :multiple nil)
))

;;;;; Schema for inquiries
(vulpea-schema-define 'inquiry
  :predicate (lambda (note) (member "inquiry" (vulpea-note-tags note)))
  :fields
  '(
    (:key "q-status" :type string :required t :one-of (solved unsolved))
))

(vulpea-schema-define 'question
		      :predicate (lambda (note) (member "question" (vulpea-note-tags note)))
		      :include 'inquiry)

(vulpea-schema-define 'error
		      :predicate (lambda (note) (member "error" (vulpea-note-tags note)))
		      :include 'inquiry)

(vulpea-schema-define 'research-q
		      :predicate (lambda (note) (member "research-q" (vulpea-note-tags note)))
		      :include 'inquiry)

(vulpea-schema-define 'exploratory ;; not as serious as a research question
		      :predicate (lambda (note) (member "exploratory" (vulpea-note-tags note)))
		      :include 'inquiry)

;; Schema for people
(vulpea-schema-define 'person
		      :predicate (lambda (note) (member "person" (vulpea-note-tags note)))
		      :fields
		      '((:key "DOB" :type number)
			(:key "DOD" :type number))
		      )

(vulpea-schema-define 'musician
		      :predicate (lambda (note) (member "musician" (vulpea-note-tags note)))
		      :include 'person)

;; Schema for groups
(vulpea-schema-define 'group
		      :predicate (lambda (note) (member "group" (vulpea-note-tags note)))
		      :fields
		      '((:key "members" :type note :multiple t))
		      )

(vulpea-schema-define 'institution
		      :predicate (lambda (note) (member "institution" (vulpea-note-tags note)))
		      :include 'group
		      )

(vulpea-schema-define 'company
		      :predicate (lambda (note) (member "company" (vulpea-note-tags note)))
		      :include 'group
		      )

;; Schema for software-related stuff
(vulpea-schema-define 'software
		      :predicate (lambda (note) (member "software" (vulpea-note-tags note)))
		      :fields
		      '((:key "source" :type string :required t :one-of ("closed-source" "open-source"))
			(:key "languages" :type note :required nil :multiple t)
			(:key "maintenance" :type string :required t :one-of ("current" "abandoned" "spotty")))
		      )

(vulpea-schema-define 'package
		      :predicate (lambda (note) (member "package" (vulpea-note-tags note)))
		      :fields
		      '((:key "(m)elpa" :type string :required nil :one-of (yes no)))) ;; change this to boolean

;; Schema for literature notes
(vulpea-schema-define 'base-text
		      :predicate (lambda (note) (member "text" (vulpea-note-tags note)))
		      :fields
		      '((:key "pub-author" :type note :multiple t)
			(:key "pub-year" :type number :required t)
			(:key "pub-title" :type string :required t)
			(:key "relevance" :type string :required nil))
)

(vulpea-schema-define 'article
		      :predicate (lambda (note) (member "journalarticle" (vulpea-note-tags note)))
		      :include 'base-text
		      :fields
		      '((:key "pub-pages" :type string :required nil))
)

(vulpea-schema-define 'booksection
		      :predicate (lambda (note) (member "booksection" (vulpea-note-tags note)))
		      :include 'base-text
		      :fields
		      '((:key "pub-pages" :type string :required nil)
		      (:key "bib-parent" :type note :required t :target-tags ("book")))
		      )

(vulpea-schema-define 'collection
		      :predicate (lambda (note) (member "collection" (vulpea-note-tags note)))
		      :include 'base-text
		      :fields
		      '((:key "pub-editor" :type note :required t))
)

(vulpea-schema-define 'incollection
		      :predicate (lambda (note) (member "incollection" (vulpea-note-tags note)))
		      :include 'base-text
		      :fields
		      '((:key "pub-pages" :type string :required nil)
		      (:key "bib-parent" :type note :required t :target-tags ("collection"))
		      (:key "pub-author" :type note :required t))
		      )

(provide 'sp-vulpea-schemas)
;; sp-vulpea-schemas.el ends here.