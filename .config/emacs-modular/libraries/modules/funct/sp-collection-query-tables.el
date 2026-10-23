;;; sp-collection-query-tables.el --- Tables of Vulpea notes: one entry point -*- lexical-binding: t; -*-

;;; Commentary:

;; Everything about query tables is loaded from here:
;;
;;   sp-collection-query-tables-core    spec -> notes -> cells, writing meta back
;;   sp-collection-query-tables-views   saved views
;;   sp-collection-query-tables-org     the `collection-query-table' dynamic block, Org buffer renderer
;;   sp-collection-query-tables-menu    the transient menu that builds a spec
;;   sp-collection-query-tables-exc     exc grid renderer (loaded when first used)
;;   sp-collection-query-tables-vui     vui renderer and inline tables (loaded when first used)
;;
;; `sp-collection-query-tables-menu' (C-c w T) is the front door; `sp-collection-query-tables-open'
;; is the function the others call.

;;; Code:

(require 'subr-x)

;; Names before the rename.  Settings come first, so a value set under an old
;; name before this file loads carries over to the new variable.
(define-obsolete-variable-alias 'sp-vulpea-table-refresh-delay
  'sp-collection-query-tables-refresh-delay "2026-10-23")
(define-obsolete-variable-alias 'sp-vulpea-table-exc-column-widths
  'sp-collection-query-tables-exc-column-widths "2026-10-23")
(define-obsolete-variable-alias 'sp-vulpea-table-link-titles
  'sp-collection-query-tables-link-titles "2026-10-23")
(define-obsolete-variable-alias 'sp-vulpea-table-views-file
  'sp-collection-query-tables-views-file "2026-10-23")
(define-obsolete-variable-alias 'sp-vulpea-table-renderer
  'sp-collection-query-tables-renderer "2026-10-23")
(define-obsolete-variable-alias 'sp-vulpea-table-install-exc
  'sp-collection-query-tables-install-exc "2026-10-23")

(define-obsolete-function-alias 'sp-vulpea-table-menu
  #'sp-collection-query-tables-menu "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-open
  #'sp-collection-query-tables-open "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-open-view
  #'sp-collection-query-tables-open-view "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-view-save
  #'sp-collection-query-tables-view-save "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-view-delete
  #'sp-collection-query-tables-view-delete "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-insert-dblock
  #'sp-collection-query-tables-insert-dblock "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-inline-toggle
  #'sp-collection-query-tables-inline-toggle "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-inline-mount
  #'sp-collection-query-tables-inline-mount "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-inline-unmount
  #'sp-collection-query-tables-inline-unmount "2026-10-23")
(define-obsolete-function-alias 'sp-vulpea-table-refresh-all
  #'sp-collection-query-tables-refresh-all "2026-10-23")

(require 'sp-collection-query-tables-core)
(require 'sp-collection-query-tables-views)
(require 'sp-collection-query-tables-org)
(require 'sp-collection-query-tables-menu)

(declare-function sp-collection-query-tables-exc-open "sp-collection-query-tables-exc")
(declare-function sp-collection-query-tables-exc-available-p "sp-collection-query-tables-exc")
(declare-function sp-collection-query-tables-vui-open "sp-collection-query-tables-vui")
(defvar sp-collection-query-tables-exc--spec)

(autoload 'sp-collection-query-tables-inline-toggle "sp-collection-query-tables-vui" nil t)
(autoload 'sp-collection-query-tables-inline-mount "sp-collection-query-tables-vui" nil t)
(autoload 'sp-collection-query-tables-inline-unmount "sp-collection-query-tables-vui" nil t)

(defcustom sp-collection-query-tables-renderer 'auto
  "How `sp-collection-query-tables-open' shows a table.
`exc' is the exc grid (needs Emacs 29.1 and exc, etaf, ebox and ecss),
`vui' the vui component, `org' a read-only Org buffer.  `auto' takes the
first of these that can be loaded."
  :type '(choice (const :tag "First one available" auto)
                 (const :tag "exc grid" exc)
                 (const :tag "vui component" vui)
                 (const :tag "Org table buffer" org))
  :group 'sp-collection-query-tables)

(defcustom sp-collection-query-tables-install-exc t
  "Non-nil to have Elpaca install exc and its ETAF libraries.
Set it before this module loads; nil leaves installing them to you."
  :type 'boolean
  :group 'sp-collection-query-tables)

(when (and sp-collection-query-tables-install-exc (fboundp 'elpaca))
  ;; ecss, ebox and etaf keep their code in lisp/, which Elpaca's default
  ;; :files does not copy.  exc is the renamed grid-table; its README says
  ;; yibie/exc but only yibie/grid-table resolves on GitHub (checked 2026-10-21).
  (use-package ecss
    :ensure (:host github :repo "emacs-taf/ecss" :files ("*.el" "lisp/*.el"))
    :defer t)
  (use-package ebox
    :ensure (:host github :repo "emacs-taf/ebox" :files ("*.el" "lisp/*.el"))
    :defer t)
  (use-package etaf
    :ensure (:host github :repo "emacs-taf/etaf" :files ("*.el" "lisp/*.el"))
    :defer t)
  (use-package exc
    :ensure (:host github :repo "yibie/grid-table")
    :defer t))

(defun sp-collection-query-tables--renderer ()
  "Return the renderer to use: `exc', `vui' or `org'."
  (if (not (eq sp-collection-query-tables-renderer 'auto))
      sp-collection-query-tables-renderer
    (cond ((progn (require 'sp-collection-query-tables-exc)
                  (sp-collection-query-tables-exc-available-p))
           'exc)
          ((require 'vui nil t) 'vui)
          (t 'org))))

(defun sp-collection-query-tables--buffer-name (name spec)
  "Return the buffer name for the table called NAME with SPEC."
  (cond (name (format "*query-table: %s*" name))
        ((plist-get spec :parent-of)
         (let ((note (ignore-errors (vulpea-db-get-by-id (plist-get spec :parent-of)))))
           (format "*query-table: children of %s*"
                   (if note (vulpea-note-title note) (plist-get spec :parent-of)))))
        (t "*query table*")))

(defun sp-collection-query-tables-open (spec &optional name target)
  "Show the table SPEC describes, in the renderer `sp-collection-query-tables-renderer' picks.
A \"self\" :parent-of is resolved against the current buffer first.  NAME
(a view name) names the buffer; with TARGET, an exc table buffer, that
buffer is redrawn with SPEC instead of opening another."
  (let* ((spec (sp-collection-query-tables-resolve-spec spec))
         (renderer (sp-collection-query-tables--renderer)))
    (if (and (eq renderer 'exc) target (buffer-live-p target)
             (buffer-local-value 'sp-collection-query-tables-exc--spec target))
        (progn (require 'sp-collection-query-tables-exc)
               (with-current-buffer target (sp-collection-query-tables-exc--draw spec))
               (pop-to-buffer target))
      (let ((buffer-name (sp-collection-query-tables--buffer-name name spec)))
        (pcase renderer
          ('exc (require 'sp-collection-query-tables-exc)
                (sp-collection-query-tables-exc-open spec buffer-name))
          ('vui (require 'sp-collection-query-tables-vui)
                (sp-collection-query-tables-vui-open spec buffer-name))
          (_ (sp-collection-query-tables-org-open spec buffer-name)))))))

(declare-function sp-collection-query-tables-exc--draw "sp-collection-query-tables-exc")

(defun sp-collection-query-tables-open-view (name)
  "Open the saved view NAME, picked with completion."
  (interactive (list (sp-collection-query-tables-views-read-name "View: ")))
  (sp-collection-query-tables-open (sp-collection-query-tables-views-get name) name))

(defun sp-collection-query-tables-view-save (&optional name spec)
  "Save SPEC as the view NAME.  Without arguments, open the menu to build one."
  (interactive)
  (if (and name spec)
      (sp-collection-query-tables-views-put name spec)
    (call-interactively #'sp-collection-query-tables-menu)))

(define-obsolete-function-alias 'sia-vulpea-open-table
  #'sp-collection-query-tables-menu "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-open-saved-table
  #'sp-collection-query-tables-open-view "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-insert-table-from-view
  #'sp-collection-query-tables-insert-dblock "2026-10-21")

(keymap-global-set "C-c w T" #'sp-collection-query-tables-menu)
(keymap-global-set "C-c w v" #'sp-collection-query-tables-open-view)
(keymap-global-set "C-c w V" #'sp-collection-query-tables-view-save)
(keymap-global-set "C-c w t" #'sp-collection-query-tables-inline-toggle)

(provide 'sp-collection-query-tables)
;;; sp-collection-query-tables.el ends here
