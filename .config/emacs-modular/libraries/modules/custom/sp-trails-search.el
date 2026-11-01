;;; sp-trails-search.el --- Search from a trail and record chosen results as pages -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `sp-trails-search' runs a consult-omni search whose chosen result is
;; opened in the browser (RET) and recorded in the current trail as a
;; TOREAD page.  See docs/tangles/custom/sp-trails-search.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'sp-trails)

(defcustom sp-trails-search-commands
  '(("web and notes" . consult-omni)
    ("web only" . consult-omni-web)
    ("scholarly sources" . consult-omni-scholar)
    ("my notes" . consult-omni-local))
  "Searches offered by `sp-trails-search': (LABEL . COMMAND).
Commands that are not defined are left out of the choice."
  :type '(alist :key-type string :value-type function)
  :group 'spcustom)

(defun sp-trails-search--url (cand)
  "Address of the consult-omni candidate CAND, or nil.
Falls back to the DOI address of scholarly results."
  (let ((url (get-text-property 0 :url cand))
        (doi (get-text-property 0 :doi cand)))
    (cond ((and (stringp url) (not (string-blank-p url))) (string-trim url))
          ((and (stringp doi) (not (string-blank-p doi)))
           (concat "https://doi.org/" (string-trim doi))))))

(defun sp-trails-search--focus-url ()
  "Address of the trail page at point, or nil.
Used as the referrer so the new page becomes a branch of that page."
  (when (and (derived-mode-p 'org-mode)
             buffer-file-name
             (file-equal-p buffer-file-name sp-trails-file)
             (not (org-before-first-heading-p)))
    (org-entry-get nil "URL" t)))

(defun sp-trails-search-record (cand)
  "Add the consult-omni result CAND to the current trail as a page.
Return the node marker, or nil when CAND has no address."
  (when (listp cand) (setq cand (car-safe cand)))
  (when-let* (((stringp cand))
              (url (sp-trails-search--url cand)))
    (unless sp-trails-current
      (call-interactively #'sp-trails-resume-or-start))
    (let* ((title (or (get-text-property 0 :title cand) url))
           (authors (get-text-property 0 :authors cand))
           (node (sp-trails-add-page (substring-no-properties url)
                                     (substring-no-properties title)
                                     (sp-trails-search--focus-url))))
      (org-with-point-at node
        (cl-flet ((put-prop (key val)
                    (when (and val (not (equal val "")))
                      (org-entry-put nil key (substring-no-properties
                                              (format "%s" val))))))
          (put-prop "SEARCH_QUERY" (get-text-property 0 :query cand))
          (put-prop "SEARCH_SOURCE" (get-text-property 0 :source cand))
          (put-prop "DOI" (get-text-property 0 :doi cand))
          (put-prop "AUTHORS" (if (listp authors) (string-join authors ", ") authors)))
        (save-buffer))
      (message "Trail ← %s" title)
      node)))

(defvar sp-trails-search--active nil
  "Non-nil while `sp-trails-search' runs a search.")

(define-advice consult-omni--get-source-prop
    (:around (fn source prop) sp-trails-search-record)
  "While `sp-trails-search' runs, record the chosen result in the trail.
Only the `:on-callback' of SOURCE is wrapped."
  (let ((callback (funcall fn source prop)))
    (if (and sp-trails-search--active (eq prop :on-callback) (functionp callback))
        (lambda (cand &rest args)
          (ignore-errors (sp-trails-search-record cand))
          (apply callback cand args))
      callback)))

(defun sp-trails-search--available ()
  "The entries of `sp-trails-search-commands' whose command exists."
  (cl-remove-if-not (lambda (e) (fboundp (cdr e))) sp-trails-search-commands))

;;;###autoload
(defun sp-trails-search (&optional command)
  "Run a consult-omni search from the current trail.
A result chosen with RET is opened as usual (in the external browser)
and added to the trail as a TOREAD page.  COMMAND is asked for unless
it is given."
  (interactive)
  (let* ((choices (or (sp-trails-search--available)
                      (user-error "No consult-omni search command is defined")))
         (command (or command
                      (cdr (assoc (completing-read "Search: " choices nil t nil nil
                                                   (caar choices))
                                  choices)))))
    (unless sp-trails-current
      (call-interactively #'sp-trails-resume-or-start))
    (let ((sp-trails-search--active t))
      (call-interactively command))))

(defun sp-trails-search-embark-record (cand)
  "Embark action: add the consult-omni result CAND to the current trail."
  (unless (sp-trails-search-record cand)
    (user-error "This result has no address")))

(with-eval-after-load 'consult-omni-embark
  (defvar consult-omni-embark-general-actions-map)
  (keymap-set consult-omni-embark-general-actions-map
              "t" #'sp-trails-search-embark-record))

(keymap-set sp-trails-map "o" #'sp-trails-search)

(provide 'sp-trails-search)
;;; sp-trails-search.el ends here
