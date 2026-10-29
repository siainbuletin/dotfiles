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

;;;;; Show links by their description
;; Used by the query tables and by `org-other-agenda', so a link in text
;; that is not in an Org buffer looks and works like one in a buffer.
(defvar sp-org-link-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'sp-org-link-open)
    (define-key map [mouse-1] #'sp-org-link-open)
    (define-key map [mouse-2] #'sp-org-link-open)
    map)
  "Keymap on a link shown by `sp-org-link-linkify'.")

(defun sp-org-link-open ()
  "Follow the Org link at point or at the last mouse click."
  (interactive)
  (when (mouse-event-p last-input-event)
    (mouse-set-point last-input-event))
  (let ((link (get-text-property (point) 'sp-org-link)))
    (if link
        (org-link-open-from-string (format "[[%s]]" link))
      (user-error "No link here"))))

(defun sp-org-link-has-link-p (text)
  "Non-nil if TEXT contains an Org bracket link."
  (and (string-match-p org-link-bracket-re text) t))

(defun sp-org-link-linkify (text)
  "Return TEXT with its Org links shown the way an Org buffer shows them.
Each [[target][description]] becomes its description alone in `org-link'
face, and RET or a click follows the link.  Text is returned as is when
`org-link-descriptive' is nil."
  (if (not (and org-link-descriptive (sp-org-link-has-link-p text)))
      text
    (let ((pos 0) out)
      (while (string-match org-link-bracket-re text pos)
        (let* ((link (org-link-unescape (match-string 1 text)))
               (desc (or (match-string 2 text) link)))
          (push (substring text pos (match-beginning 0)) out)
          (push (propertize desc 'face 'org-link 'mouse-face 'highlight
                            'help-echo link 'keymap sp-org-link-map
                            'sp-org-link link)
                out)
          (setq pos (match-end 0))))
      (push (substring text pos) out)
      (apply #'concat (nreverse out)))))

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

;;;;; Completion for help, info and man links
;; `org-insert-link' (C-c C-l) completes the path of a link type that has a
;; `:complete' parameter.  Org defines `help:' and `info:' without one and
;; `man:' may be missing, so they are set here.  `help:' also gets its own
;; follow function, which takes faces too.
(declare-function Info-read-node-name "info")
(declare-function Man-completion-table "man")
(declare-function org-link-get-parameter "ol")
(declare-function org-link-set-parameters "ol")

(defun sp-org-link-complete-help (&optional _arg)
  "Return a `help:' link to a function, variable or face read with completion."
  (let ((symbol (completing-read
                 "Help for symbol: " obarray
                 (lambda (s) (or (fboundp s) (boundp s) (facep s)))
                 t)))
    (concat "help:" symbol)))

(defun sp-org-link-follow-help (path _arg)
  "Describe the function, variable or face named by the `help:' link PATH.
Unlike Org's own follow function this also takes the faces that
`sp-org-link-complete-help' offers."
  (unless (and (stringp path) (not (string-empty-p path)))
    (user-error "The help link has no symbol"))
  (let ((symbol (intern path)))
    (cond ((fboundp symbol) (describe-function symbol))
          ((boundp symbol) (describe-variable symbol))
          ((facep symbol) (describe-face symbol))
          (t (user-error "Unknown function, variable or face: %s" path)))))

(defun sp-org-link-complete-info (&optional _arg)
  "Return an `info:' link to a manual and node read with completion.
The link has Org's form MANUAL#NODE, with the node Top when none is given."
  (require 'info)
  (let ((node (Info-read-node-name "Info node: ")))
    (if (string-match "\\`(\\([^)]+\\))\\(.*\\)\\'" node)
        (concat "info:" (match-string 1 node) "#"
                (if (string-empty-p (match-string 2 node)) "Top" (match-string 2 node)))
      (concat "info:" node))))

(defun sp-org-link-complete-man (&optional _arg)
  "Return a `man:' link to a manual page read with completion."
  (require 'man)
  (concat "man:" (completing-read "Man page: " #'Man-completion-table)))

(defun sp-org-link-follow-man (path _arg)
  "Open the manual page PATH of a `man:' link."
  (require 'man)
  (man path))

(with-eval-after-load 'org
  (org-link-set-parameters "help"
                           :follow #'sp-org-link-follow-help
                           :complete #'sp-org-link-complete-help)
  (org-link-set-parameters "info" :complete #'sp-org-link-complete-info)
  ;; Only add the follow function when Org does not provide `man:' itself.
  (unless (org-link-get-parameter "man" :follow)
    (org-link-set-parameters "man" :follow #'sp-org-link-follow-man))
  (org-link-set-parameters "man" :complete #'sp-org-link-complete-man))

;; Other libraries
;; - sp-org-create-note-and-link.el

(provide 'sp-org-id-link)
;; sp-org-id-link.el ends here.
