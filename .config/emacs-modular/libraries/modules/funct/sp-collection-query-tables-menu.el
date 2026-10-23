;;; sp-collection-query-tables-menu.el --- Transient menu to build query table queries -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-collec-query-menu' edits a spec (see `sp-collec-query-spec-keys')
;; one setting at a time, showing the current value next to every key, and
;; then opens the table, previews the count, inserts it as a dynamic block
;; or saves it as a named view.  Nothing runs until you ask: the settings
;; are only collected.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)
(require 'sp-collection-query-tables-core)
(require 'sp-collection-query-tables-views)
(require 'sp-collection-query-tables-org)

(declare-function sp-collec-query-open "sp-collection-query-tables")

(defvar sp-collec-query-menu--spec nil
  "The spec the menu is editing.")

(defvar sp-collec-query-menu--name nil
  "Name of the saved view the menu's spec came from, if any.")

(defvar sp-collec-query-menu--target nil
  "Buffer showing a table that running the menu should redraw, or nil.")

(defvar sp-collec-query-menu--notes nil
  "Notes read for completion while the menu is open.")

;;;; Reading and writing settings

(defun sp-collec-query-menu--get (key)
  "Return the setting KEY of the menu's spec."
  (plist-get sp-collec-query-menu--spec key))

(defun sp-collec-query-menu--set (key value)
  "Set KEY to VALUE in the menu's spec; a nil VALUE removes KEY."
  (let ((spec (copy-sequence sp-collec-query-menu--spec)))
    (cl-remf spec key)
    (when value (setq spec (plist-put spec key value)))
    (setq sp-collec-query-menu--spec spec)))

(defun sp-collec-query-menu--all-notes ()
  "Return all notes, read once per menu session."
  (or sp-collec-query-menu--notes
      (setq sp-collec-query-menu--notes (vulpea-db-query))))

(defun sp-collec-query-menu--candidates (function)
  "Return the sorted unique non-empty strings FUNCTION gives for the notes."
  (sort (delete-dups
         (seq-remove (lambda (s) (or (null s) (string-empty-p s)))
                     (mapcan (lambda (n) (ensure-list (funcall function n)))
                             (sp-collec-query-menu--all-notes))))
        #'string<))

(defun sp-collec-query-menu--meta-keys ()
  "Return every meta key found in the notes."
  (sp-collec-query-menu--candidates
   (lambda (n) (mapcar #'car (vulpea-note-meta n)))))

(defun sp-collec-query-menu--column-candidates ()
  "Return the built-in columns and the meta keys, as strings."
  (append (mapcar #'symbol-name sp-collec-query-builtin-columns)
          (sp-collec-query-menu--meta-keys)))

(defun sp-collec-query-menu--column (string)
  "Return the column STRING names: a keyword for a built-in one."
  (if (string-prefix-p ":" string) (intern string) string))

(defun sp-collec-query-menu--column-name (column)
  "Return COLUMN as the text shown and read back in prompts."
  (if (keywordp column) (symbol-name column) column))

;;;; Descriptions

(defun sp-collec-query-menu--value-text (key)
  "Return the text shown for the setting KEY."
  (let ((value (sp-collec-query-menu--get key)))
    (pcase key
      (:links (mapconcat (lambda (id)
                           (if-let* ((n (ignore-errors (vulpea-db-get-by-id id))))
                               (vulpea-note-title n)
                             id))
                         value ", "))
      (:meta (mapconcat (lambda (c) (if (cdr c) (format "%s=%s" (car c) (cdr c)) (car c)))
                        value ", "))
      (:columns (mapconcat #'sp-collec-query-menu--column-name value " "))
      (:sort-by (and value (sp-collec-query-menu--column-name value)))
      (:sort-desc (and value "descending"))
      (:level (and value (if (eq value 'headings) "headings" "file-level")))
      (:parent-of (and value (format "%s%s" value
                                     (if-let* ((p (sp-collec-query-menu--get :parent-prop)))
                                         (format " via %s" p) ""))))
      (_ (if (listp value) (string-join value ", ") value)))))

(defun sp-collec-query-menu--describe (label key)
  "Return LABEL followed by the current value of KEY, highlighted."
  (let ((text (sp-collec-query-menu--value-text key)))
    (concat (format "%-16s" label)
            (if (and text (not (string-empty-p text)))
                (propertize text 'face 'transient-value)
              (propertize "-" 'face 'transient-inactive-value)))))

(defmacro sp-collec-query-menu--defdesc (name label key)
  "Define NAME, a menu description function for the setting KEY with LABEL."
  `(defun ,name (&optional _obj)
     (sp-collec-query-menu--describe ,label ,key)))

(sp-collec-query-menu--defdesc sp-collec-query-menu--d-tags "Tags (all)" :tags)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-tags-any "Tags (any)" :tags-any)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-tags-none "Tags (none)" :tags-none)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-dirs "Directories" :directories)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-todo "TODO state" :todo)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-links "Links to" :links)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-meta "Meta" :meta)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-parent "Children of" :parent-of)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-level "Level" :level)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-title "Title matches" :title-match)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-columns "Columns" :columns)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-sort "Sort by" :sort-by)
(sp-collec-query-menu--defdesc sp-collec-query-menu--d-desc "Direction" :sort-desc)

(defun sp-collec-query-menu--header ()
  "Return the heading of the menu."
  (concat (propertize (if sp-collec-query-menu--name
                          (format "Query table: %s" sp-collec-query-menu--name)
                        "Query table")
                      'face 'transient-heading)
          "\n"
          (propertize (sp-collec-query-spec-summary sp-collec-query-menu--spec)
                      'face 'shadow)))

;;;; Commands that change one setting

(defun sp-collec-query-menu-tags (key prompt)
  "Read the tag list for KEY with PROMPT, offering the tags in the database."
  (sp-collec-query-menu--set
   key
   (completing-read-multiple
    prompt (vulpea-db-query-tags) nil nil
    (when-let* ((cur (sp-collec-query-menu--get key))) (concat (string-join cur ",") ",")))))

(defun sp-collec-query-menu-set-tags ()
  "Set the tags a note must all have."
  (interactive) (sp-collec-query-menu-tags :tags "Tags, all of: "))

(defun sp-collec-query-menu-set-tags-any ()
  "Set the tags of which a note must have at least one."
  (interactive) (sp-collec-query-menu-tags :tags-any "Tags, any of: "))

(defun sp-collec-query-menu-set-tags-none ()
  "Set the tags a note must not have."
  (interactive) (sp-collec-query-menu-tags :tags-none "Tags, none of: "))

(defun sp-collec-query-menu-set-directories ()
  "Set the directories a note's file must lie under."
  (interactive)
  (let ((dirs (sp-collec-query-menu--candidates
               (lambda (n) (abbreviate-file-name
                            (directory-file-name
                             (file-name-directory (vulpea-note-path n))))))))
    (sp-collec-query-menu--set
     :directories
     (completing-read-multiple
      "Directories (type any path too): " dirs nil nil
      (when-let* ((cur (plist-get sp-collec-query-menu--spec :directories)))
        (concat (string-join cur ",") ","))))))

(defun sp-collec-query-menu-set-todo ()
  "Set the TODO states a note must be in."
  (interactive)
  (sp-collec-query-menu--set
   :todo
   (completing-read-multiple
    "TODO states: "
    (sp-collec-query-menu--candidates #'vulpea-note-todo) nil nil
    (when-let* ((cur (sp-collec-query-menu--get :todo))) (concat (string-join cur ",") ",")))))

(defun sp-collec-query-menu-add-link ()
  "Add a note the table's notes must link to (any of the listed ones)."
  (interactive)
  (when-let* ((note (sp-collec-query-select-note "Links to: ")))
    (sp-collec-query-menu--set
     :links (cl-adjoin (vulpea-note-id note) (sp-collec-query-menu--get :links)
                       :test #'equal))))

(defun sp-collec-query-menu-clear-links ()
  "Remove the link filter."
  (interactive) (sp-collec-query-menu--set :links nil))

(defun sp-collec-query-menu-add-meta ()
  "Require a meta KEY, optionally with a given value."
  (interactive)
  (let* ((key (completing-read "Meta key: " (sp-collec-query-menu--meta-keys)))
         (values (sp-collec-query-menu--candidates
                  (lambda (n) (vulpea-note-meta-get-list n key))))
         (value (completing-read
                 (format "Value of %s (empty: only require the key): " key) values)))
    (unless (string-empty-p key)
      (sp-collec-query-menu--set
       :meta (append (assoc-delete-all key (copy-sequence (sp-collec-query-menu--get :meta)))
                     (list (cons key (unless (string-empty-p value) value))))))))

(defun sp-collec-query-menu-clear-meta ()
  "Remove the meta filter."
  (interactive) (sp-collec-query-menu--set :meta nil))

(defun sp-collec-query-menu-set-parent ()
  "Set the note whose children the table lists, and the meta key that links them."
  (interactive)
  (let ((parent (sp-collec-query-read-parent t)))
    (sp-collec-query-menu--set :parent-of parent)
    (sp-collec-query-menu--set
     :parent-prop
     (when parent
       (let ((prop (read-string "Parent meta key (empty for \"parents\"): ")))
         (unless (string-empty-p prop) prop))))))

(defun sp-collec-query-menu-set-level ()
  "Choose between file-level notes, heading notes and both."
  (interactive)
  (sp-collec-query-menu--set
   :level (pcase (completing-read "Notes: " '("all" "file-level" "headings") nil t)
            ("file-level" 0) ("headings" 'headings))))

(defun sp-collec-query-menu-set-title ()
  "Set a regexp the title must match."
  (interactive)
  (let ((re (read-regexp "Title matches (regexp, empty for any): "
                         (sp-collec-query-menu--get :title-match))))
    (sp-collec-query-menu--set :title-match (unless (string-empty-p re) re))))

(defun sp-collec-query-menu-set-columns ()
  "Set the columns, in order."
  (interactive)
  (let ((cols (completing-read-multiple
               "Columns, in order (:title, :tags, ... or a meta key): "
               (sp-collec-query-menu--column-candidates) nil nil
               (concat (mapconcat #'sp-collec-query-menu--column-name
                                  (or (sp-collec-query-menu--get :columns) '(:title)) ",")
                       ","))))
    (sp-collec-query-menu--set
     :columns (mapcar #'sp-collec-query-menu--column cols))))

(defun sp-collec-query-menu-set-sort ()
  "Set the column to sort by."
  (interactive)
  (let ((col (completing-read "Sort by (empty for none): "
                              (or (mapcar #'sp-collec-query-menu--column-name
                                          (sp-collec-query-menu--get :columns))
                                  (sp-collec-query-menu--column-candidates)))))
    (sp-collec-query-menu--set
     :sort-by (unless (string-empty-p col) (sp-collec-query-menu--column col)))))

(defun sp-collec-query-menu-toggle-desc ()
  "Toggle between ascending and descending order."
  (interactive)
  (sp-collec-query-menu--set :sort-desc (not (sp-collec-query-menu--get :sort-desc))))

(defun sp-collec-query-menu-reset ()
  "Forget every setting."
  (interactive)
  (setq sp-collec-query-menu--spec nil sp-collec-query-menu--name nil))

;;;; Commands that use the whole spec

(defun sp-collec-query-menu--spec-now ()
  "Return the menu's spec, normalized."
  (sp-collec-query-spec-normalize sp-collec-query-menu--spec))

(defun sp-collec-query-menu-run ()
  "Open the table, or redraw the table this menu was started from."
  (interactive)
  (let ((spec (sp-collec-query-menu--spec-now))
        (target sp-collec-query-menu--target))
    (setq sp-collec-query-menu--target nil)
    (sp-collec-query-open spec sp-collec-query-menu--name target)))

(defun sp-collec-query-menu-preview ()
  "Say how many notes the spec matches."
  (interactive)
  (let ((spec (sp-collec-query-resolve-spec sp-collec-query-menu--spec)))
    (message "%d notes: %s" (length (sp-collec-query-query spec))
             (sp-collec-query-spec-summary spec))))

(defun sp-collec-query-menu-insert ()
  "Insert the spec at point in the Org buffer the menu was started from."
  (interactive)
  (unless (derived-mode-p 'org-mode) (user-error "Not in an Org buffer"))
  (sp-collec-query-insert-dblock (sp-collec-query-menu--spec-now)))

(defun sp-collec-query-menu-save ()
  "Save the spec as a named view."
  (interactive)
  (let ((name (read-string "Save view as: " sp-collec-query-menu--name)))
    (when (string-empty-p name) (user-error "A view needs a name"))
    (when (or (not (member name (sp-collec-query-views-names)))
              (string= name sp-collec-query-menu--name)
              (y-or-n-p (format "Replace the view \"%s\"? " name)))
      (sp-collec-query-views-put name (sp-collec-query-menu--spec-now))
      (setq sp-collec-query-menu--name name)
      (message "Saved query table view \"%s\"" name))))

(defun sp-collec-query-menu-load ()
  "Load a saved view into the menu."
  (interactive)
  (let ((name (sp-collec-query-views-read-name "Load view: ")))
    (setq sp-collec-query-menu--spec (copy-tree (sp-collec-query-views-get name))
          sp-collec-query-menu--name name)))

(defun sp-collec-query-menu-delete ()
  "Delete a saved view."
  (interactive)
  (call-interactively #'sp-collec-query-view-delete))

;;;###autoload (autoload 'sp-collec-query-menu "sp-collection-query-tables-menu" nil t)
(transient-define-prefix sp-collec-query-menu ()
  "Build, run and save a table of Vulpea notes."
  [:description sp-collec-query-menu--header
   :class transient-columns
   ["Filter"
    ("t" sp-collec-query-menu-set-tags :description sp-collec-query-menu--d-tags :transient t)
    ("a" sp-collec-query-menu-set-tags-any :description sp-collec-query-menu--d-tags-any :transient t)
    ("x" sp-collec-query-menu-set-tags-none :description sp-collec-query-menu--d-tags-none :transient t)
    ("d" sp-collec-query-menu-set-directories :description sp-collec-query-menu--d-dirs :transient t)
    ("s" sp-collec-query-menu-set-todo :description sp-collec-query-menu--d-todo :transient t)
    ("l" sp-collec-query-menu-add-link :description sp-collec-query-menu--d-links :transient t)
    ("L" "  clear links" sp-collec-query-menu-clear-links :transient t)
    ("m" sp-collec-query-menu-add-meta :description sp-collec-query-menu--d-meta :transient t)
    ("M" "  clear meta" sp-collec-query-menu-clear-meta :transient t)
    ("p" sp-collec-query-menu-set-parent :description sp-collec-query-menu--d-parent :transient t)
    ("v" sp-collec-query-menu-set-level :description sp-collec-query-menu--d-level :transient t)
    ("r" sp-collec-query-menu-set-title :description sp-collec-query-menu--d-title :transient t)]
   ["Shape"
     ("c" sp-collec-query-menu-set-columns :description sp-collec-query-menu--d-columns :transient t)
     ("o" sp-collec-query-menu-set-sort :description sp-collec-query-menu--d-sort :transient t)
     ("O" sp-collec-query-menu-toggle-desc :description sp-collec-query-menu--d-desc :transient t)]
   ["Views"
     ("S" "Save view" sp-collec-query-menu-save :transient t)
     ("V" "Load view" sp-collec-query-menu-load :transient t)
     ("D" "Delete view" sp-collec-query-menu-delete :transient t)]
   ["Run"
     ("RET" "Open table" sp-collec-query-menu-run)
     ("P" "Preview count" sp-collec-query-menu-preview :transient t)
     ("i" "Insert as dblock" sp-collec-query-menu-insert)
     ("R" "Reset" sp-collec-query-menu-reset :transient t)]])

(provide 'sp-collection-query-tables-menu)
;;; sp-collection-query-tables-menu.el ends here
