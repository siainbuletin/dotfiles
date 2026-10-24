;;; sp-vulpea-table.el --- Tables of Vulpea notes: one entry point -*- lexical-binding: t; -*-

;;; Commentary:

;; Everything about Vulpea tables is loaded from here:
;;
;;   sp-vulpea-table-core    spec -> notes -> cells, writing meta back
;;   sp-vulpea-table-views   saved views
;;   sp-vulpea-table-org     the `vulpea-table' dynamic block, Org buffer renderer
;;   sp-vulpea-table-menu    the transient menu that builds a spec
;;   sp-vulpea-table-exc     exc grid renderer (loaded when first used)
;;   sp-vulpea-table-vui     vui renderer and inline tables (loaded when first used)
;;
;; `sp-vulpea-table-menu' (C-c w T) is the front door; `sp-vulpea-table-open'
;; is the function the others call.

;;; Code:

(require 'subr-x)
(require 'sp-vulpea-table-core)
(require 'sp-vulpea-table-views)
(require 'sp-vulpea-table-org)
(require 'sp-vulpea-table-menu)

(declare-function sp-vulpea-table-exc-open "sp-vulpea-table-exc")
(declare-function sp-vulpea-table-exc-available-p "sp-vulpea-table-exc")
(declare-function sp-vulpea-table-vui-open "sp-vulpea-table-vui")
(defvar sp-vulpea-table-exc--spec)

(autoload 'sp-vulpea-table-inline-toggle "sp-vulpea-table-vui" nil t)
(autoload 'sp-vulpea-table-inline-mount "sp-vulpea-table-vui" nil t)
(autoload 'sp-vulpea-table-inline-unmount "sp-vulpea-table-vui" nil t)

(defcustom sp-vulpea-table-renderer 'auto
  "How `sp-vulpea-table-open' shows a table.
`exc' is the exc grid (needs Emacs 29.1 and exc, etaf, ebox and ecss),
`vui' the vui component, `org' a read-only Org buffer.  `auto' takes the
first of these that can be loaded."
  :type '(choice (const :tag "First one available" auto)
                 (const :tag "exc grid" exc)
                 (const :tag "vui component" vui)
                 (const :tag "Org table buffer" org))
  :group 'spcustom)

(defcustom sp-vulpea-table-install-exc t
  "Non-nil to have Elpaca install exc and its ETAF libraries.
Set it before this module loads; nil leaves installing them to you."
  :type 'boolean
  :group 'spcustom)

(when (and sp-vulpea-table-install-exc (fboundp 'elpaca))
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

(defun sp-vulpea-table--renderer ()
  "Return the renderer to use: `exc', `vui' or `org'."
  (if (not (eq sp-vulpea-table-renderer 'auto))
      sp-vulpea-table-renderer
    (cond ((progn (require 'sp-vulpea-table-exc)
                  (sp-vulpea-table-exc-available-p))
           'exc)
          ((require 'vui nil t) 'vui)
          (t 'org))))

(defun sp-vulpea-table--buffer-name (name spec)
  "Return the buffer name for the table called NAME with SPEC."
  (cond (name (format "*vulpea: %s*" name))
        ((plist-get spec :parent-of)
         (let ((note (ignore-errors (vulpea-db-get-by-id (plist-get spec :parent-of)))))
           (format "*vulpea: children of %s*"
                   (if note (vulpea-note-title note) (plist-get spec :parent-of)))))
        (t "*vulpea table*")))

(defun sp-vulpea-table-open (spec &optional name target)
  "Show the table SPEC describes, in the renderer `sp-vulpea-table-renderer' picks.
A \"self\" :parent-of is resolved against the current buffer first.  NAME
(a view name) names the buffer; with TARGET, an exc table buffer, that
buffer is redrawn with SPEC instead of opening another."
  (let* ((spec (sp-vulpea-table-resolve-spec spec))
         (renderer (sp-vulpea-table--renderer)))
    (if (and (eq renderer 'exc) target (buffer-live-p target)
             (buffer-local-value 'sp-vulpea-table-exc--spec target))
        (progn (require 'sp-vulpea-table-exc)
               (with-current-buffer target (sp-vulpea-table-exc--draw spec))
               (pop-to-buffer target))
      (let ((buffer-name (sp-vulpea-table--buffer-name name spec)))
        (pcase renderer
          ('exc (require 'sp-vulpea-table-exc)
                (sp-vulpea-table-exc-open spec buffer-name))
          ('vui (require 'sp-vulpea-table-vui)
                (sp-vulpea-table-vui-open spec buffer-name))
          (_ (sp-vulpea-table-org-open spec buffer-name)))))))

(declare-function sp-vulpea-table-exc--draw "sp-vulpea-table-exc")

(defun sp-vulpea-table-open-view (name)
  "Open the saved view NAME, picked with completion."
  (interactive (list (sp-vulpea-table-views-read-name "View: ")))
  (sp-vulpea-table-open (sp-vulpea-table-views-get name) name))

(defun sp-vulpea-table-view-save (&optional name spec)
  "Save SPEC as the view NAME.  Without arguments, open the menu to build one."
  (interactive)
  (if (and name spec)
      (sp-vulpea-table-views-put name spec)
    (call-interactively #'sp-vulpea-table-menu)))

(define-obsolete-function-alias 'sia-vulpea-open-table
  #'sp-vulpea-table-menu "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-open-saved-table
  #'sp-vulpea-table-open-view "2026-10-21")
(define-obsolete-function-alias 'sia-vulpea-insert-table-from-view
  #'sp-vulpea-table-insert-dblock "2026-10-21")

(keymap-global-set "C-c w T" #'sp-vulpea-table-menu)
(keymap-global-set "C-c w v" #'sp-vulpea-table-open-view)
(keymap-global-set "C-c w V" #'sp-vulpea-table-view-save)
(keymap-global-set "C-c w t" #'sp-vulpea-table-inline-toggle)

(provide 'sp-vulpea-table)
;;; sp-vulpea-table.el ends here
