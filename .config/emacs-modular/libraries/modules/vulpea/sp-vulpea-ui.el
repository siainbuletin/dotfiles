;;; sp-vulpea-ui.el --- Vulpea UI sidebar and collection views -*- lexical-binding: t; -*-

;;; Commentary:

;; UI functions for vulpea.
;;
;; This includes the sidebar and the possibility to render collection views.
;;
;; The functions I wrote later on for vulpea (ex. sp-collection-query-tables-views.el)
;; are based on this rendering done here, as well as the information that is
;; found in sp-vulpea-schemas.el

;;; Code:

;;;; Calling the initial packages
(use-package vulpea-ui
  :ensure (:wait t)
  :after vulpea
  
  :config
  )

;; opening the vulpea sidebar
(global-set-key (kbd "C-x t s") #'vulpea-ui-sidebar-toggle)

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

(defun sp-org-toggle-narrow-and-sidebar ()
  "Toggle subtree narrowing and refresh the sidebar immediately."
  (interactive)
  (org-toggle-narrow-to-subtree)
  (vulpea-ui-sidebar-refresh))

(define-key org-mode-map (kbd "M-<insert>") #'sp-org-toggle-narrow-and-sidebar)

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
        
        ("open-questions" . (:filter (:tags-all ("question")
                                      :level 1 ;; this will only bring up headings at first
                                      )
                             :columns (title (meta "q-status") links tags modified)
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
                                (meta "rating")
                                (meta "review")
                                context tags modified)
                     :sort ("title" . t)))))

;; Automatically collapse all widgets
(setq vulpea-ui-default-widget-collapsed t)

;;;; Custom vulpea-ui widget for unlinked mentions in a tab folder
;;;; vulpea-ui get unlinked mentioned without an ID property
;; (require 'sp-tab-inbox) ;; this is required in init el so I can see progress for loading

(provide 'sp-vulpea-ui)
;; sp-vulpea-ui.el ends here.
