;;; sp-batch-lint.el --- Batch linters: footnotes, author notes and litnotes -*- lexical-binding: t; -*-

;;; Commentary:

;; Requires the batch linters (many files or notes at once, with a report and a
;; backup); see docs/tangles/funct/sp-batch-lint.org.  The one-off lint of the
;; current Org buffer is `sp-org-lint'.

;;; Code:

(require 'sp-org-lint-footnotes)
(require 'sp-author-notes)
(require 'sp-author-notes-bibtex)
(require 'sp-litnotes-refs)
(require 'sp-litnotes-titles)

(provide 'sp-batch-lint)
;;; sp-batch-lint.el ends here
