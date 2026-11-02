;;; sp-org-lint.el --- Lint and tidy Org lists, footnotes, author notes and litnotes -*- lexical-binding: t; -*-

;;; Commentary:

;; Requires the submodules; see docs/tangles/funct/sp-org-lint.org.

;;; Code:

(require 'sp-org-lint-others)
(require 'sp-org-lint-footnotes)
(require 'sp-author-notes)
(require 'sp-author-notes-bibtex)
(require 'sp-litnotes-refs)
(require 'sp-litnotes-titles)

(provide 'sp-org-lint)
;;; sp-org-lint.el ends here
