;;; Define many keys in many key maps
(use-package denote
  :ensure t

  :config
  (setq denote-file-type nil) ; default is org
  (setq denote-known-keywords '("book" "book-section" "concept" "course" "docs" "educational-program" "journal-article" "music" "process" "zettel"))
  (setq denote-history-completion-in-prompts nil)
  (setq denote-rename-confirmations '(modify-file-name add-front-matter))
  (setq denote-sort-keywords t)
  ; (denote-link-description-function #'ews-denote-link-description-title-case) ; I need to actually rename this to my own function starting with sia-

  :hook
  (dired-mode . denote-dired-mode)
  (denote-mode . denote-rename-buffer-mode)

  :bind
  ( ;; this block here is taken from Prot's video on use-package
   :map global-map
    ("C-c n n" . denote)
    ("C-c n r" . denote-rename-file)
    ("C-c n f" . denote-rename-file-using-front-matter)

    :map text-mode-map
    ("C-c n i" . denote-link) ; "insert" mnemonic
    ("C-c n I" . denote-add-links)

    :map dired-mode-map
    ("C-c C-d C-i" . denote-link-dired-marked-notes)
    ("C-c C-d C-r" . denote-dired-rename-marked-files)

    ;; these are copied directly from the Emacs Writing Studio configuration
    ("C-c w d b" . denote-find-backlink)
    ("C-c w d d" . denote-date)
    ("C-c w d l" . denote-find-link)
    ("C-c w d i" . denote-link-or-create)
    ("C-c w d k" . denote-rename-file-keywords)))

(add-hook 'dired-mode-hook #'denote-dired-mode-in-directories)

(use-package denote-org
  :ensure t
  :after denote)

(use-package denote-markdown
  :ensure t
  :after denote)

(use-package denote-explore
  :bind
  (;; Statistics
   ("C-c w x c" . denote-explore-count-notes)
   ("C-c w x C" . denote-explore-count-keywords)
   ("C-c w x b" . denote-explore-barchart-keywords)
   ("C-c w x e" . denote-explore-barchart-filetypes)
   ;; Random walks
   ("C-c w x r" . denote-explore-random-note)
   ("C-c w x l" . denote-explore-random-link)
   ("C-c w x k" . denote-explore-random-keyword)
   ("C-c w x x" . denote-explore-random-regex)
   ;; Denote Janitor
   ("C-c w x d" . denote-explore-identify-duplicate-notes)
   ("C-c w x z" . denote-explore-zero-keywords)
   ("C-c w x s" . denote-explore-single-keywords)
   ("C-c w x o" . denote-explore-sort-keywords)
   ("C-c w x w" . denote-explore-rename-keyword)
   ;; Visualise denote
   ("C-c w x n" . denote-explore-network)
   ("C-c w x v" . denote-explore-network-regenerate)
   ("C-c w x D" . denote-explore-barchart-degree)))

(use-package denote-journal)

(use-package denote-sequence)
