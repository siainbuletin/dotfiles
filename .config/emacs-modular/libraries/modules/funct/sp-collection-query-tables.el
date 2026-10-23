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
;; `sp-collec-query-menu' (C-c w T) is the front door; `sp-collec-query-open'
;; is the function the others call.
;;
;; The files and features are called sp-collection-query-tables-*, the
;; symbols sp-collec-query-* ("collec" is "collection", the set of notes a
;; query runs against), to keep command names short.

;;; Code:

(require 'subr-x)

(require 'sp-collection-query-tables-core)
(require 'sp-collection-query-tables-views)
(require 'sp-collection-query-tables-org)
(require 'sp-collection-query-tables-menu)

(declare-function sp-collec-query-exc-open "sp-collection-query-tables-exc")
(declare-function sp-collec-query-exc-available-p "sp-collection-query-tables-exc")
(declare-function sp-collec-query-vui-open "sp-collection-query-tables-vui")
(defvar sp-collec-query-exc--spec)

(autoload 'sp-collec-query-inline-toggle "sp-collection-query-tables-vui" nil t)
(autoload 'sp-collec-query-inline-mount "sp-collection-query-tables-vui" nil t)
(autoload 'sp-collec-query-inline-unmount "sp-collection-query-tables-vui" nil t)

(defcustom sp-collec-query-renderer 'auto
  "How `sp-collec-query-open' shows a table.
`exc' is the exc grid (needs Emacs 29.1 and exc, etaf, ebox and ecss),
`vui' the vui component, `org' a read-only Org buffer.  `auto' takes the
first of these that can be loaded."
  :type '(choice (const :tag "First one available" auto)
                 (const :tag "exc grid" exc)
                 (const :tag "vui component" vui)
                 (const :tag "Org table buffer" org))
  :group 'sp-collec-query)

(defcustom sp-collec-query-install-exc t
  "Non-nil to have Elpaca install exc and its ETAF libraries.
Set it before this module loads; nil leaves installing them to you."
  :type 'boolean
  :group 'sp-collec-query)

(when (and sp-collec-query-install-exc (fboundp 'elpaca))
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

(defun sp-collec-query--renderer ()
  "Return the renderer to use: `exc', `vui' or `org'."
  (if (not (eq sp-collec-query-renderer 'auto))
      sp-collec-query-renderer
    (cond ((progn (require 'sp-collection-query-tables-exc)
                  (sp-collec-query-exc-available-p))
           'exc)
          ((require 'vui nil t) 'vui)
          (t 'org))))

(defun sp-collec-query--buffer-name (name spec)
  "Return the buffer name for the table called NAME with SPEC."
  (cond (name (format "*query-table: %s*" name))
        ((plist-get spec :parent-of)
         (let ((note (ignore-errors (vulpea-db-get-by-id (plist-get spec :parent-of)))))
           (format "*query-table: children of %s*"
                   (if note (vulpea-note-title note) (plist-get spec :parent-of)))))
        (t "*query table*")))

(defun sp-collec-query-open (spec &optional name target)
  "Show the table SPEC describes, in the renderer `sp-collec-query-renderer' picks.
A \"self\" :parent-of is resolved against the current buffer first.  NAME
(a view name) names the buffer; with TARGET, an exc table buffer, that
buffer is redrawn with SPEC instead of opening another."
  (let* ((spec (sp-collec-query-resolve-spec spec))
         (renderer (sp-collec-query--renderer)))
    (if (and (eq renderer 'exc) target (buffer-live-p target)
             (buffer-local-value 'sp-collec-query-exc--spec target))
        (progn (require 'sp-collection-query-tables-exc)
               (with-current-buffer target (sp-collec-query-exc--draw spec))
               (pop-to-buffer target))
      (let ((buffer-name (sp-collec-query--buffer-name name spec)))
        (pcase renderer
          ('exc (require 'sp-collection-query-tables-exc)
                (sp-collec-query-exc-open spec buffer-name))
          ('vui (require 'sp-collection-query-tables-vui)
                (sp-collec-query-vui-open spec buffer-name))
          (_ (sp-collec-query-org-open spec buffer-name)))))))

(declare-function sp-collec-query-exc--draw "sp-collection-query-tables-exc")

(defun sp-collec-query-open-view (name)
  "Open the saved view NAME, picked with completion."
  (interactive (list (sp-collec-query-views-read-name "View: ")))
  (sp-collec-query-open (sp-collec-query-views-get name) name))

(defun sp-collec-query-view-save (&optional name spec)
  "Save SPEC as the view NAME.  Without arguments, open the menu to build one."
  (interactive)
  (if (and name spec)
      (sp-collec-query-views-put name spec)
    (call-interactively #'sp-collec-query-menu)))

(define-obsolete-function-alias 'sia-vulpea-open-table
  #'sp-collec-query-menu "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-open-saved-table
  #'sp-collec-query-open-view "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-insert-table-from-view
  #'sp-collec-query-insert-dblock "2026-10-21")

(keymap-global-set "C-c w T" #'sp-collec-query-menu)
(keymap-global-set "C-c w v" #'sp-collec-query-open-view)
(keymap-global-set "C-c w V" #'sp-collec-query-view-save)
(keymap-global-set "C-c w t" #'sp-collec-query-inline-toggle)

(provide 'sp-collection-query-tables)
;;; sp-collection-query-tables.el ends here
