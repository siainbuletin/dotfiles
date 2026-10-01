;; -*- lexical-binding: t; -*-

(use-package discourse-graphs
  :ensure (discourse-graphs :type git
                            :host github
                            :repo "LuciusChen/discourse-graphs"
                            :files ("*.el"
                            "discourse-graphs-ui/out/*.html"
                            "discourse-graphs-ui/out/assets/*"))
  :config
  (setq dg-directories ;; This is where we scan for nodes
  '("~/notes/")
  )
  (setq dg-recursive t)
  (setq dg-db-file "~/.config/emacs-include/discourse-graphs.db") ;; this is where the SQLite will live

(discourse-graphs-mode 1)
)

;; Use with denote
(setq dg-use-denote t)

(setq dg-context-window-width 0.3)

;; Auto-update context when moving between nodes
(setq dg-context-auto-update t)

;; Maximum lines to display per node in context panel (nil for unlimited)
(setq dg-context-max-lines 30)

;; Show overlays on headings
(setq dg-overlay-enable t)

;; Synthesis dashboard file location
(setq dg-synthesis-file "~/notes/dg-synthesis.org")

(setq dg-discourse-attributes
      '(
        (claim
         . (
            (evidence-score . "{count:Supported By:evidence} - {count:Opposed By:evidence}")
            (robustness . "{count:Supported By:evidence} + {count:Supported By:claim}*0.5 - {count:Opposed By:evidence}")
            (overlay . evidence-score)
                )
           )

        (question
         . (
          (answer-count . "{count:Answered By:claim}")
            (overlay . answer-count)
              )
         )
        ;; ... more types
        )
)

(setq dg-node-types
      '(
        (question . (:short "QUE"
                          :color "lightblue"
                          :desc "Research question"))
        (claim    . (:short "CLM"
                          :color "lightyellow"
                          :desc "Assertion, thesis or position in a debate"))
        (evidence . (:short "EVD"
                          :color "lightgreen"
                          :desc "Argument, proof, or supporting empirical data"))
        (source   . (:short "SRC"
                          :color "lightgray"
                          :desc "Reference material / Philosophical text"))
        (theory   . (:short "THY"
                                  :color "lightcoral"
                          :desc "Theoretical framework"))
        ))

(setq dg-relation-types
      '(
      (supports  . (:inverse "Supported By"
                             :color "green"
                             :style "solid"))
      (opposes   . (:inverse "Opposed By"
                             :color "red"
                             :style "dashed"))
      (informs   . (:inverse "Informed By"
                             :color "blue"
                             :style "solid"))
      (answers   . (:inverse "Answered By"
                             :color "purple"
                             :style "solid"))
      )
      )

(setq dg-relation-patterns
      '((supports . (:source (evidence)
                           :target (claim)))
      (opposes  . (:source (evidence)
                           :target (claim)))
      (informs  . (:source (source)
                           :target (evidence)))
      (answers  . (:source (claim)
                           :target (question)))
      )
        )