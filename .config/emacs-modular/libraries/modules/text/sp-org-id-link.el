;;; sp-org-id-link.el --- Org IDs and link utilities -*- lexical-binding: t; -*-

;;; Commentary:

;; This is isolating every function that has to do with ID creation. It also deals
;; with links within org-mode.

;;; Code:

;;;; Org ID
;; Use org ids for reference
(use-package org-id
  :ensure nil
  :after org
  :custom
  (org-id-locations-file (concat sp-cache-dir ".org-id-locations")) ;; this keeps in line with the no-littering principle
  (org-id-method 'ts) ;; use timestamp for id
  (org-id-link-to-org-use-id 'create-if-interactive)) ;; create ids

;;;;; Org link Syntax
(defun org-update-link-syntax (&optional no-query)
  "Update syntax for links in current buffer.
Query before replacing a link, unless optional argument NO-QUERY
is non-nil."
  (interactive "P")
  (org-with-point-at 1
    (let ((case-fold-search t))
      (while (re-search-forward "\\[\\[[^]]*?%\\(?:2[05]\\|5[BD]\\)" nil t)
        (let ((object (save-match-data (org-element-context))))
          (when (and (eq 'link (org-element-type object))
                     (= (match-beginning 0)
                        (org-element-property :begin object)))
            (goto-char (org-element-property :end object))
            (let* ((uri-start (+ 2 (match-beginning 0)))
                   (uri-end (save-excursion
                              (goto-char uri-start)
                              (re-search-forward "\\][][]" nil t)
                              (match-beginning 0)))
                   (uri (buffer-substring-no-properties uri-start uri-end)))
              (when (or no-query
                        (y-or-n-p
                         (format "Possibly obsolete URI syntax: %S.  Fix? "
                                 uri)))
                (setf (buffer-substring uri-start uri-end)
                      (org-link-escape (org-link-decode uri)))))))))))

;;;;; Org Copy Link
;; see https://emacs.stackexchange.com/a/63038/11934
(defun lem-org-link-copy-at-point ()
  (interactive)
  (save-excursion
    (let* ((ol-regex "\\[\\[.*?:.*?\\]\\(\\[.*?\\]\\)?\\]")
           (beg (re-search-backward "\\[\\["))
           (end (re-search-forward ol-regex))
           (link-string (buffer-substring-no-properties (match-beginning 0) (match-end 0))))
      (kill-new link-string)
      (message "Org link %s is copied." link-string))))

;;;;; Remove Org Links
;; https://emacs.stackexchange.com/a/10714/11934
(defun lem-org-replace-link-by-link-description ()
  "Replace an org link by its description or, if empty, its address"
  (interactive)
  (if (org-in-regexp org-link-bracket-re 1)
      (save-excursion
        (let ((remove (list (match-beginning 0) (match-end 0)))
              (description
               (if (match-end 2)
                   (org-match-string-no-properties 2)
                 (org-match-string-no-properties 1))))
          (apply 'delete-region remove)
          (insert description)))))

;;;;; Link to the configuration docs
;; Plain `file:' links, so the docs stay out of the vulpea database.
(declare-function sp-find-file-pick "sp-navi")

(defcustom sp-config-docs-directory (expand-file-name "docs/" sp-load-path)
  "Directory holding the literate and architecture docs of this configuration."
  :type 'directory)

(defun sp-org-doc-title (file)
  "Return the #+title of the Org FILE, or nil if it has none."
  (with-temp-buffer
    (insert-file-contents file nil 0 4096)
    (let ((case-fold-search t))
      (when (re-search-forward "^#\\+title:[ \t]*\\(.+?\\)[ \t]*$" nil t)
        (match-string 1)))))

(defun sp-org-insert-config-doc-link (&optional edit-description)
  "Insert an Org link to a file of the configuration docs at point.
Pick the file with the fuzzy search of `sp-find-file', restricted to the
Org files under `sp-config-docs-directory'.  The description is the
#+title of the file, or its name without extension when it has none.
With a prefix argument EDIT-DESCRIPTION, ask for the description."
  (interactive "P")
  (require 'sp-navi)
  (unless (file-directory-p sp-config-docs-directory)
    (user-error "No docs directory at %s" sp-config-docs-directory))
  (when-let* ((file (sp-find-file-pick sp-config-docs-directory "\\.org\\'")))
    (let* ((title (or (sp-org-doc-title file) (file-name-base file)))
           (description (if edit-description
                            (read-string "Description: " title)
                          title)))
      (insert (org-link-make-string
               (concat "file:" (abbreviate-file-name file))
               description)))))

;; Other libraries
;; - sp-org-create-note-and-link.el

(provide 'sp-org-id-link)
;; sp-org-id-link.el ends here.
