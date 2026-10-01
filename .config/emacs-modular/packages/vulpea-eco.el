;; -*- lexical-binding: t; -*-

(use-package vulpea
  :ensure (:wait t)
  :init
  (keymap-global-set "M-o f" 'vulpea-find)
  (keymap-global-set "M-o n a" 'vulpea-buffer-alias-add)
)

(setq vulpea-db-sync-directories '("~/notes/"))

(setq vulpea-db-parse-method 'single-temp-buffer)

(vulpea-db-autosync-mode +1) ;; this makes sure that the vault is being updated on each startup.

(setq vulpea-buffer-alias-property "ROAM_ALIASES") ;; By default, aliases are stored in ALIASES. To use ROAM_ALIASES for org-roam compatibility:

(vulpea-db-query-by-tags-every '("project" "active")) ;; Query all active projects

;; Configuring the display of notes in the minibuffer
;; "My Notes → Projects → Task"
(setq vulpea-select-describe-fn #'vulpea-select-describe-outline-full)

;; Default annotation: "(primary title) #tag1 #tag2"
(setq vulpea-select-annotate-fn #'vulpea-select-annotate)

;; Schema definition
;; Schema for albums
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

;; Schema for inquiries
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

;; UI functions
(use-package vulpea-ui
  :ensure (:wait t)
  :after vulpea)

;; opening the vulpea sidebar
(global-set-key (kbd "C-c v s") #'vulpea-ui-sidebar-toggle)

;; Position: 'right (default), 'left, 'top, 'bottom
(setq vulpea-ui-sidebar-position 'right)

;; Size as fraction of frame (0.0-1.0)
(setq vulpea-ui-sidebar-size 0.33)

;; Maximum heading depth (nil = unlimited)
(setq vulpea-ui-outline-max-depth 3)

;; Utility functions for vulpea-ui
(setq vulpea-ui-auto-refresh t) ;; So you don't have to constantly do a manual refresh.

;; Dealing with narrowed Org files

;; Respect narrowing in the sidebar
(setq vulpea-ui-respect-narrowing t)

;; Emacs has no narrowing hook, so the sidebar notices a narrow or widen on the next idle
;; refresh. If you want it instantly, refresh right after toggling:

(defun my/org-toggle-narrow-and-sidebar ()
  "Toggle subtree narrowing and refresh the sidebar immediately."
  (interactive)
  (org-toggle-narrow-to-subtree)
  (vulpea-ui-sidebar-refresh))

(define-key org-mode-map (kbd "M-<insert>") #'my/org-toggle-narrow-and-sidebar)

;; the backlinks widget

;; Show/hide content previews
(setq vulpea-ui-backlinks-show-preview t)

;; Characters before/after link in prose previews
(setq vulpea-ui-backlinks-prose-chars-before 30)
(setq vulpea-ui-backlinks-prose-chars-after 50)

;; Filter which notes appear in backlinks
;; (function receiving vulpea-note, return non-nil to include)
(setq vulpea-ui-backlinks-note-filter
      (lambda (note)
        (not (member "archive" (vulpea-note-tags note)))))

;; Filter by context type
;; t = all types, or a list of: meta, header, table, list, quote, code, footnote, prose
(setq vulpea-ui-backlinks-context-types t)

;; Sorting: nil (no sorting), 'title-asc, 'title-desc, or custom function
(setq vulpea-ui-backlinks-sort 'title-asc)

;; Collection views
(setq vulpea-ui-collection-views
      '(
        ("thesis-reading-list" . (:filter (:tags-all ("book")
					                          :level 0 ;; this is what will bring file-level notes
					                          ;; :meta ("read-status" . t) ;; this one doesn't work yet for some reason
                                    :meta ("bib-project" . "[[ID:806b08ac-3ed1-4338-a26e-3af9e0e9328c][Devalorizarea artei în capitalismul de platformă]]")
                                    )
			                :columns (title (meta "pub-title") (meta "pub-author") (meta "read-status") links tags modified)
			                :sort ("Modified" . t)))
        
        ("open-questions" . (:filter (:tags-all ("question)
                                      :level 1 ;; this will only bring up headings at first
                                      )
                             :columns (title (meta "q-status) links tags modified)
                             :sort ("Modified" . t)
        ))
        
        ("music" . (:filter (:tags-all ("music")
                            :level 0)
                    :columns (title (meta "year") (meta "genre") tags modified)
                    :sort ("title" . t)))
        
        ("albums" . (:filter (:tags-all ("album"))
                     :columns (title
                                (meta "creator" :width 60)
                                (meta "year")
                                (meta "genre")
                                (meta "genre-influences")
                                (meta "rating"
                                (meta "review")
                                context tags modified)
                     :sort ("title" . t)))
        )))

;; JOURNALING
(use-package vulpea-journal
  :ensure (:wait t)
  :after vulpea)

;; Templating for Vulpea

(setq vulpea-create-default-function
      (lambda (title)
        (list :file-name (format "%s_%s.org"
                                 (format-time-string "%Y%m%d%H%M%S")
                                 (vulpea-title-to-slug title))
              :tags (if (string-match-p "TODO" title)
                        '("task")
                      '("note")))))

;; Integration with other packages

(use-package consult-vulpea
  :ensure (:wait t)
  :after vulpea
  :config
  (consult-vulpea-mode 1)
)

(require 'vulpea-para)
(vulpea-para-agenda-mode)

(vulpea-para-setup-defaults)

;; keep a cemetery (or anything) out of the agenda file list
(setq vulpea-para-agenda-files-filter
      (lambda (note)
        (not (vulpea-note-tagged-any-p note "cemetery"))))

;; Getting the custom agenda view for vulpea-para

(setq org-agenda-custom-commands
      `((" " "Agenda"
         (,vulpea-para-agenda-cmd-refile
          ,vulpea-para-agenda-cmd-today
          ,vulpea-para-agenda-cmd-focus
          ,vulpea-para-agenda-cmd-stuck-projects
          ,vulpea-para-agenda-cmd-waiting
          ,(vulpea-para-agenda-cmd-current-quarter)))))

;; the Area > Project prefix in the agenda
(setq org-agenda-prefix-format
      '((agenda . " %(vulpea-para-agenda-category 36) %?-12t %12s")
        (todo   . " %(vulpea-para-agenda-category 36) ")))

;; Other modules for vulpea

;; (use-package vulpea-capf
;;   :ensure (:wait t)
;;   :hook (org-mode . vulpea-capf-mode)
;;   )

;; (setq vulpea-capf-everywhere nil)   ; only complete inside [[...]]
;; (setq vulpea-capf-in-brackets t)

;; (setq vulpea-capf-annotate-function t)