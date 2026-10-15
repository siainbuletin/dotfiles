;; -*- lexical-binding: t; -*-
;; sp-org-id-link.el

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

;;; Adding non-existent link generation
;;; -*- lexical-binding: t; -*-
(defun sp-org-slugify (title)
  "Turn TITLE into a filesystem-safe slug."
  (let ((slug (string-trim
               (downcase (replace-regexp-in-string "[^[:alnum:]]+" "-" title))
               "-" "-")))
    (if (string-empty-p slug) "note" slug)))

(defun sp-org-create-note-and-link (title)
  "Create a new org note TITLE in `org-directory' and insert an ID link to it.
The note is written straight to disk: no buffer is visited and no window
is created.  If the region is active (if text is selected), its text is used as the title and
is replaced by the link."
  (interactive
   (list (if (use-region-p)
             (buffer-substring-no-properties (region-beginning) (region-end))
           (read-string "New note title: "))))
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (let ((title (string-trim (replace-regexp-in-string "[\n\r]+" " " title))))
    (when (string-empty-p title)
      (user-error "Empty title"))
    (let* ((dir  (file-name-as-directory (expand-file-name org-directory)))
           (id   (org-id-new))
           (file (expand-file-name
                  (format "%s-%s.org"
                          (format-time-string "%Y%m%dT%H%M%S")
                          (sp-org-slugify title))
                  dir))
           (coding-system-for-write 'utf-8))
      (make-directory dir t)
      (when (file-exists-p file)
        (user-error "File already exists: %s" file))
      
      ;; Write the note without ever creating a visiting buffer.
      (with-temp-file file
        (insert (format ":PROPERTIES:\n:ID:       %s\n:END:\n#+title: %s\n\n"
                        id title)))
      
      ;; Register the ID so org can resolve the link immediately.
      (org-id-add-location id file)
      (org-id-locations-save)
      
      ;; Insert the link at point (replacing the region if there was one).
      (when (use-region-p)
        (delete-region (region-beginning) (region-end)))
      (insert (org-link-make-string (concat "id:" id) title))
      (message "Created %s" (file-name-nondirectory file)))))

;;; Provide:

(provide 'sp-org-id-link)
;; sp-org-id-link.el ends here.