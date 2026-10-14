;; -*- lexical-binding: t; -*-
;; sp-vulpea-ext.el

;;; Commentary:

;;;; Recursive loading for the modules
(let ((default-directory (expand-file-name "modules/" sp-library-dir)))
  (normal-top-level-add-to-load-path '("."))
  (normal-top-level-add-subdirs-to-load-path))

;; Integration with other packages

;;; Code:

;; JOURNALING
(use-package vulpea-journal
  :ensure t
  :after vulpea)

;; Other modules for vulpea
   
(use-package vulpea-capf
  :ensure (:host github :repo "neonmei/vulpea-capf")
  :hook (org-mode . vulpea-capf-mode)
)

(setq vulpea-capf-everywhere nil)   ; only complete inside [[...]]
(setq vulpea-capf-in-brackets t)
(setq vulpea-capf-annotate-function t)

;; Create dataview-like tables through the vulpea query system
(require 'sp-vulpea-dblock)
(require 'sp-vulpea-vui-table)
(require 'sp-vulpea-table-views)

;; Batch converting properties to plug into vulpea instead

(require 'sp-vulpea-convert-properties)

;; Grouping backlinks based on the property that it's representing

(require 'sp-vulpea-grouped-backlinks)

;;; Making vulpea-split-heading smart (ensure backlinks)

(defvar sp-split--active nil
  "Non-nil while `sp-split-leave-parents' is running.")

;;;###autoload
(defun sp-split-leave-parents ()
  "Run `vulpea-split-heading', recording where the heading came from.
The new note gets a `- parents ::' line linking back to the note the
subtree was split out of.  A prefix argument is passed through, so it
still means \"leave a link stub behind\"."
  (interactive)
  (let ((sp-split--active t))
    (call-interactively #'vulpea-split-heading)))

(defun sp-split--link-to (id fallback-title)
  "Return an id link to ID, titled from the database or FALLBACK-TITLE."
  (org-link-make-string
   (concat "id:" id)
   (if-let* ((note (vulpea-db-get-by-id id)))
       (vulpea-note-title note)
     fallback-title)))

(defun sp-split--parent-link (id)
  "Return (PARENT-ID . LINK) for the note the heading with ID lives in.
Walks up the ancestors of the heading and takes the first one with an
ID.  If none has one, falls back to the file-level note, creating its
ID when it is missing."
  (when-let* ((note (vulpea-db-get-by-id id))
              (path (vulpea-note-path note)))
    (with-current-buffer (find-file-noselect path)
      (org-with-wide-buffer
       (when-let* ((pos (org-find-entry-with-id id)))
         (goto-char pos)
         (let (pid title)
           (while (and (not pid) (org-up-heading-safe))
             (when-let* ((x (org-entry-get (point) "ID")))
               (setq pid x
                     title (org-link-display-format
                            (org-get-heading t t t t)))))
           (unless pid
             (goto-char (point-min))
             (setq pid (or (org-entry-get (point-min) "ID")
                           (org-id-get-create))
                   title (or (vulpea-buffer-title-get)
                             (file-name-base path))))
           (cons pid (sp-split--link-to pid title))))))))

(defun sp-split--body-with-parent (body parent-id link)
  "Return BODY with LINK recorded in its `parents' meta line."
  (let* ((case-fold-search nil)
         ;; Only the section before the first child heading: children
         ;; may carry `parents' lines of their own, which stay untouched.
         (top-end (or (string-match "^\\*+ " body) (length body)))
         (top (substring body 0 top-end))
         (rest (substring body top-end)))
    (cond
     ;; A parents line already exists: prepend the new link to its value.
     ((string-match
       "^\\([ \t]*[-+][ \t]+parents[ \t]+::[ \t]*\\)\\(.*\\)$" top)
      (let ((prefix (match-string 1 top))
            (existing (string-trim (match-string 2 top))))
        (if (string-search (concat "id:" parent-id) existing)
            body
          (concat (replace-match
                   (concat prefix link
                           (if (string-empty-p existing)
                               ""
                             (concat ", " existing)))
                   t t top)
                  rest))))
     (t
      (let ((line (concat "- parents :: " link)))
        (cond
         ((string-empty-p body) line)
         ;; Body opens with meta already: join that list.
         ((string-match-p "\\`[ \t]*[-+][ \t]+[^ \t\n]+[ \t]+::" body)
          (concat line "\n" body))
         (t (concat line "\n\n" body))))))))

(defun sp-split--add-parents (args)
  "Filter ARGS of `vulpea-split--write-file' while splitting with parents."
  (if (not sp-split--active)
      args
    (pcase-let ((`(,path ,id ,title ,head ,tags ,props ,body) args))
      (if-let* ((parent (sp-split--parent-link id)))
          (list path id title head tags props
                (sp-split--body-with-parent body (car parent) (cdr parent)))
        args))))

(with-eval-after-load 'vulpea
  (advice-add 'vulpea-split--write-file :filter-args #'sp-split--add-parents))

;;; Provide:

(provide 'sp-vulpea-ext)
;; sp-vulpea-ext.el