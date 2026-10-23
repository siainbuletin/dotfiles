;;; sp-collection-query-tables-menu.el --- Transient menu to build query table queries -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-collection-query-tables-menu' edits a spec (see `sp-collection-query-tables-spec-keys')
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

(declare-function sp-collection-query-tables-open "sp-collection-query-tables")

(defvar sp-collection-query-tables-menu--spec nil
  "The spec the menu is editing.")

(defvar sp-collection-query-tables-menu--name nil
  "Name of the saved view the menu's spec came from, if any.")

(defvar sp-collection-query-tables-menu--target nil
  "Buffer showing a table that running the menu should redraw, or nil.")

(defvar sp-collection-query-tables-menu--notes nil
  "Notes read for completion while the menu is open.")

;;;; Reading and writing settings

(defun sp-collection-query-tables-menu--get (key)
  "Return the setting KEY of the menu's spec."
  (plist-get sp-collection-query-tables-menu--spec key))

(defun sp-collection-query-tables-menu--set (key value)
  "Set KEY to VALUE in the menu's spec; a nil VALUE removes KEY."
  (let ((spec (copy-sequence sp-collection-query-tables-menu--spec)))
    (cl-remf spec key)
    (when value (setq spec (plist-put spec key value)))
    (setq sp-collection-query-tables-menu--spec spec)))

(defun sp-collection-query-tables-menu--all-notes ()
  "Return all notes, read once per menu session."
  (or sp-collection-query-tables-menu--notes
      (setq sp-collection-query-tables-menu--notes (vulpea-db-query))))

(defun sp-collection-query-tables-menu--candidates (function)
  "Return the sorted unique non-empty strings FUNCTION gives for the notes."
  (sort (delete-dups
         (seq-remove (lambda (s) (or (null s) (string-empty-p s)))
                     (mapcan (lambda (n) (ensure-list (funcall function n)))
                             (sp-collection-query-tables-menu--all-notes))))
        #'string<))

(defun sp-collection-query-tables-menu--meta-keys ()
  "Return every meta key found in the notes."
  (sp-collection-query-tables-menu--candidates
   (lambda (n) (mapcar #'car (vulpea-note-meta n)))))

(defun sp-collection-query-tables-menu--column-candidates ()
  "Return the built-in columns and the meta keys, as strings."
  (append (mapcar #'symbol-name sp-collection-query-tables-builtin-columns)
          (sp-collection-query-tables-menu--meta-keys)))

(defun sp-collection-query-tables-menu--column (string)
  "Return the column STRING names: a keyword for a built-in one."
  (if (string-prefix-p ":" string) (intern string) string))

(defun sp-collection-query-tables-menu--column-name (column)
  "Return COLUMN as the text shown and read back in prompts."
  (if (keywordp column) (symbol-name column) column))

;;;; Descriptions

(defun sp-collection-query-tables-menu--value-text (key)
  "Return the text shown for the setting KEY."
  (let ((value (sp-collection-query-tables-menu--get key)))
    (pcase key
      (:links (mapconcat (lambda (id)
                           (if-let* ((n (ignore-errors (vulpea-db-get-by-id id))))
                               (vulpea-note-title n)
                             id))
                         value ", "))
      (:meta (mapconcat (lambda (c) (if (cdr c) (format "%s=%s" (car c) (cdr c)) (car c)))
                        value ", "))
      (:columns (mapconcat #'sp-collection-query-tables-menu--column-name value " "))
      (:sort-by (and value (sp-collection-query-tables-menu--column-name value)))
      (:sort-desc (and value "descending"))
      (:level (and value (if (eq value 'headings) "headings" "file-level")))
      (:parent-of (and value (format "%s%s" value
                                     (if-let* ((p (sp-collection-query-tables-menu--get :parent-prop)))
                                         (format " via %s" p) ""))))
      (_ (if (listp value) (string-join value ", ") value)))))

(defun sp-collection-query-tables-menu--describe (label key)
  "Return LABEL followed by the current value of KEY, highlighted."
  (let ((text (sp-collection-query-tables-menu--value-text key)))
    (concat (format "%-16s" label)
            (if (and text (not (string-empty-p text)))
                (propertize text 'face 'transient-value)
              (propertize "-" 'face 'transient-inactive-value)))))

(defmacro sp-collection-query-tables-menu--defdesc (name label key)
  "Define NAME, a menu description function for the setting KEY with LABEL."
  `(defun ,name (&optional _obj)
     (sp-collection-query-tables-menu--describe ,label ,key)))

(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-tags "Tags (all)" :tags)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-tags-any "Tags (any)" :tags-any)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-tags-none "Tags (none)" :tags-none)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-dirs "Directories" :directories)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-todo "TODO state" :todo)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-links "Links to" :links)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-meta "Meta" :meta)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-parent "Children of" :parent-of)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-level "Level" :level)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-title "Title matches" :title-match)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-columns "Columns" :columns)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-sort "Sort by" :sort-by)
(sp-collection-query-tables-menu--defdesc sp-collection-query-tables-menu--d-desc "Direction" :sort-desc)

(defun sp-collection-query-tables-menu--header ()
  "Return the heading of the menu."
  (concat (propertize (if sp-collection-query-tables-menu--name
                          (format "Query table: %s" sp-collection-query-tables-menu--name)
                        "Query table")
                      'face 'transient-heading)
          "\n"
          (propertize (sp-collection-query-tables-spec-summary sp-collection-query-tables-menu--spec)
                      'face 'shadow)))

;;;; Commands that change one setting

(defun sp-collection-query-tables-menu-tags (key prompt)
  "Read the tag list for KEY with PROMPT, offering the tags in the database."
  (sp-collection-query-tables-menu--set
   key
   (completing-read-multiple
    prompt (vulpea-db-query-tags) nil nil
    (when-let* ((cur (sp-collection-query-tables-menu--get key))) (concat (string-join cur ",") ",")))))

(defun sp-collection-query-tables-menu-set-tags ()
  "Set the tags a note must all have."
  (interactive) (sp-collection-query-tables-menu-tags :tags "Tags, all of: "))

(defun sp-collection-query-tables-menu-set-tags-any ()
  "Set the tags of which a note must have at least one."
  (interactive) (sp-collection-query-tables-menu-tags :tags-any "Tags, any of: "))

(defun sp-collection-query-tables-menu-set-tags-none ()
  "Set the tags a note must not have."
  (interactive) (sp-collection-query-tables-menu-tags :tags-none "Tags, none of: "))

(defun sp-collection-query-tables-menu-set-directories ()
  "Set the directories a note's file must lie under."
  (interactive)
  (let ((dirs (sp-collection-query-tables-menu--candidates
               (lambda (n) (abbreviate-file-name
                            (directory-file-name
                             (file-name-directory (vulpea-note-path n))))))))
    (sp-collection-query-tables-menu--set
     :directories
     (completing-read-multiple
      "Directories (type any path too): " dirs nil nil
      (when-let* ((cur (plist-get sp-collection-query-tables-menu--spec :directories)))
        (concat (string-join cur ",") ","))))))

(defun sp-collection-query-tables-menu-set-todo ()
  "Set the TODO states a note must be in."
  (interactive)
  (sp-collection-query-tables-menu--set
   :todo
   (completing-read-multiple
    "TODO states: "
    (sp-collection-query-tables-menu--candidates #'vulpea-note-todo) nil nil
    (when-let* ((cur (sp-collection-query-tables-menu--get :todo))) (concat (string-join cur ",") ",")))))

(defun sp-collection-query-tables-menu-add-link ()
  "Add a note the table's notes must link to (any of the listed ones)."
  (interactive)
  (when-let* ((note (sp-collection-query-tables-select-note "Links to: ")))
    (sp-collection-query-tables-menu--set
     :links (cl-adjoin (vulpea-note-id note) (sp-collection-query-tables-menu--get :links)
                       :test #'equal))))

(defun sp-collection-query-tables-menu-clear-links ()
  "Remove the link filter."
  (interactive) (sp-collection-query-tables-menu--set :links nil))

(defun sp-collection-query-tables-menu-add-meta ()
  "Require a meta KEY, optionally with a given value."
  (interactive)
  (let* ((key (completing-read "Meta key: " (sp-collection-query-tables-menu--meta-keys)))
         (values (sp-collection-query-tables-menu--candidates
                  (lambda (n) (vulpea-note-meta-get-list n key))))
         (value (completing-read
                 (format "Value of %s (empty: only require the key): " key) values)))
    (unless (string-empty-p key)
      (sp-collection-query-tables-menu--set
       :meta (append (assoc-delete-all key (copy-sequence (sp-collection-query-tables-menu--get :meta)))
                     (list (cons key (unless (string-empty-p value) value))))))))

(defun sp-collection-query-tables-menu-clear-meta ()
  "Remove the meta filter."
  (interactive) (sp-collection-query-tables-menu--set :meta nil))

(defun sp-collection-query-tables-menu-set-parent ()
  "Set the note whose children the table lists, and the meta key that links them."
  (interactive)
  (let ((parent (sp-collection-query-tables-read-parent t)))
    (sp-collection-query-tables-menu--set :parent-of parent)
    (sp-collection-query-tables-menu--set
     :parent-prop
     (when parent
       (let ((prop (read-string "Parent meta key (empty for \"parents\"): ")))
         (unless (string-empty-p prop) prop))))))

(defun sp-collection-query-tables-menu-set-level ()
  "Choose between file-level notes, heading notes and both."
  (interactive)
  (sp-collection-query-tables-menu--set
   :level (pcase (completing-read "Notes: " '("all" "file-level" "headings") nil t)
            ("file-level" 0) ("headings" 'headings))))

(defun sp-collection-query-tables-menu-set-title ()
  "Set a regexp the title must match."
  (interactive)
  (let ((re (read-regexp "Title matches (regexp, empty for any): "
                         (sp-collection-query-tables-menu--get :title-match))))
    (sp-collection-query-tables-menu--set :title-match (unless (string-empty-p re) re))))

(defun sp-collection-query-tables-menu-set-columns ()
  "Set the columns, in order."
  (interactive)
  (let ((cols (completing-read-multiple
               "Columns, in order (:title, :tags, ... or a meta key): "
               (sp-collection-query-tables-menu--column-candidates) nil nil
               (concat (mapconcat #'sp-collection-query-tables-menu--column-name
                                  (or (sp-collection-query-tables-menu--get :columns) '(:title)) ",")
                       ","))))
    (sp-collection-query-tables-menu--set
     :columns (mapcar #'sp-collection-query-tables-menu--column cols))))

(defun sp-collection-query-tables-menu-set-sort ()
  "Set the column to sort by."
  (interactive)
  (let ((col (completing-read "Sort by (empty for none): "
                              (or (mapcar #'sp-collection-query-tables-menu--column-name
                                          (sp-collection-query-tables-menu--get :columns))
                                  (sp-collection-query-tables-menu--column-candidates)))))
    (sp-collection-query-tables-menu--set
     :sort-by (unless (string-empty-p col) (sp-collection-query-tables-menu--column col)))))

(defun sp-collection-query-tables-menu-toggle-desc ()
  "Toggle between ascending and descending order."
  (interactive)
  (sp-collection-query-tables-menu--set :sort-desc (not (sp-collection-query-tables-menu--get :sort-desc))))

(defun sp-collection-query-tables-menu-reset ()
  "Forget every setting."
  (interactive)
  (setq sp-collection-query-tables-menu--spec nil sp-collection-query-tables-menu--name nil))

;;;; Commands that use the whole spec

(defun sp-collection-query-tables-menu--spec-now ()
  "Return the menu's spec, normalized."
  (sp-collection-query-tables-spec-normalize sp-collection-query-tables-menu--spec))

(defun sp-collection-query-tables-menu-run ()
  "Open the table, or redraw the table this menu was started from."
  (interactive)
  (let ((spec (sp-collection-query-tables-menu--spec-now))
        (target sp-collection-query-tables-menu--target))
    (setq sp-collection-query-tables-menu--target nil)
    (sp-collection-query-tables-open spec sp-collection-query-tables-menu--name target)))

(defun sp-collection-query-tables-menu-preview ()
  "Say how many notes the spec matches."
  (interactive)
  (let ((spec (sp-collection-query-tables-resolve-spec sp-collection-query-tables-menu--spec)))
    (message "%d notes: %s" (length (sp-collection-query-tables-query spec))
             (sp-collection-query-tables-spec-summary spec))))

(defun sp-collection-query-tables-menu-insert ()
  "Insert the spec at point in the Org buffer the menu was started from."
  (interactive)
  (unless (derived-mode-p 'org-mode) (user-error "Not in an Org buffer"))
  (sp-collection-query-tables-insert-dblock (sp-collection-query-tables-menu--spec-now)))

(defun sp-collection-query-tables-menu-save ()
  "Save the spec as a named view."
  (interactive)
  (let ((name (read-string "Save view as: " sp-collection-query-tables-menu--name)))
    (when (string-empty-p name) (user-error "A view needs a name"))
    (when (or (not (member name (sp-collection-query-tables-views-names)))
              (string= name sp-collection-query-tables-menu--name)
              (y-or-n-p (format "Replace the view \"%s\"? " name)))
      (sp-collection-query-tables-views-put name (sp-collection-query-tables-menu--spec-now))
      (setq sp-collection-query-tables-menu--name name)
      (message "Saved query table view \"%s\"" name))))

(defun sp-collection-query-tables-menu-load ()
  "Load a saved view into the menu."
  (interactive)
  (let ((name (sp-collection-query-tables-views-read-name "Load view: ")))
    (setq sp-collection-query-tables-menu--spec (copy-tree (sp-collection-query-tables-views-get name))
          sp-collection-query-tables-menu--name name)))

(defun sp-collection-query-tables-menu-delete ()
  "Delete a saved view."
  (interactive)
  (call-interactively #'sp-collection-query-tables-view-delete))

;;;###autoload (autoload 'sp-collection-query-tables-menu "sp-collection-query-tables-menu" nil t)
(transient-define-prefix sp-collection-query-tables-menu ()
  "Build, run and save a table of Vulpea notes."
  [:description sp-collection-query-tables-menu--header
   :class transient-columns
   ["Filter"
    ("t" sp-collection-query-tables-menu-set-tags :description sp-collection-query-tables-menu--d-tags :transient t)
    ("a" sp-collection-query-tables-menu-set-tags-any :description sp-collection-query-tables-menu--d-tags-any :transient t)
    ("x" sp-collection-query-tables-menu-set-tags-none :description sp-collection-query-tables-menu--d-tags-none :transient t)
    ("d" sp-collection-query-tables-menu-set-directories :description sp-collection-query-tables-menu--d-dirs :transient t)
    ("s" sp-collection-query-tables-menu-set-todo :description sp-collection-query-tables-menu--d-todo :transient t)
    ("l" sp-collection-query-tables-menu-add-link :description sp-collection-query-tables-menu--d-links :transient t)
    ("L" "  clear links" sp-collection-query-tables-menu-clear-links :transient t)
    ("m" sp-collection-query-tables-menu-add-meta :description sp-collection-query-tables-menu--d-meta :transient t)
    ("M" "  clear meta" sp-collection-query-tables-menu-clear-meta :transient t)
    ("p" sp-collection-query-tables-menu-set-parent :description sp-collection-query-tables-menu--d-parent :transient t)
    ("v" sp-collection-query-tables-menu-set-level :description sp-collection-query-tables-menu--d-level :transient t)
    ("r" sp-collection-query-tables-menu-set-title :description sp-collection-query-tables-menu--d-title :transient t)]
   ["Shape"
     ("c" sp-collection-query-tables-menu-set-columns :description sp-collection-query-tables-menu--d-columns :transient t)
     ("o" sp-collection-query-tables-menu-set-sort :description sp-collection-query-tables-menu--d-sort :transient t)
     ("O" sp-collection-query-tables-menu-toggle-desc :description sp-collection-query-tables-menu--d-desc :transient t)]
   ["Views"
     ("S" "Save view" sp-collection-query-tables-menu-save :transient t)
     ("V" "Load view" sp-collection-query-tables-menu-load :transient t)
     ("D" "Delete view" sp-collection-query-tables-menu-delete :transient t)]
   ["Run"
     ("RET" "Open table" sp-collection-query-tables-menu-run)
     ("P" "Preview count" sp-collection-query-tables-menu-preview :transient t)
     ("i" "Insert as dblock" sp-collection-query-tables-menu-insert)
     ("R" "Reset" sp-collection-query-tables-menu-reset :transient t)]])

(provide 'sp-collection-query-tables-menu)
;;; sp-collection-query-tables-menu.el ends here
