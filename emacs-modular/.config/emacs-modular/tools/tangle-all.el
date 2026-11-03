;;; tangle-all.el --- Tangle every module doc in batch mode  -*- lexical-binding: t; -*-

;; Usage, from .config/emacs-modular:
;;   emacs -Q --batch -l tools/tangle-all.el
;; Same selection as `sp-tangle-docs': every docs/tangles/**/sp-*.org whose text
;; has a `:tangle' path into libraries/modules/.  It needs no packages, so it
;; runs in CI and in a fresh checkout.  It does not touch the hash cache of
;; `sp-tangle-changed'.

(require 'org)
(require 'ob-tangle)
(require 'seq)

(setq org-confirm-babel-evaluate nil)

(let* ((root (expand-file-name "docs/tangles/"))
       (docs (seq-filter
              (lambda (f)
                (with-temp-buffer
                  (insert-file-contents f)
                  (re-search-forward ":tangle [./]*libraries/modules/" nil t)))
              (directory-files-recursively root "^sp-.*[.]org\\'")))
       (start (float-time))
       (files 0))
  (dolist (doc docs)
    (setq files (+ files (length (org-babel-tangle-file doc)))))
  (message "tangle-all: %d files from %d docs in %.1fs"
           files (length docs) (- (float-time) start)))

;;; tangle-all.el ends here
