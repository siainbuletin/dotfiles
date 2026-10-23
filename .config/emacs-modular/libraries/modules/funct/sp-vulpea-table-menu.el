;;; sp-vulpea-table-menu.el --- Transient menu to build Vulpea table queries -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-vulpea-table-menu' edits a spec (see `sp-vulpea-table-spec-keys')
;; one setting at a time, showing the current value next to every key, and
;; then opens the table, previews the count, inserts it as a dynamic block
;; or saves it as a named view.  Nothing runs until you ask: the settings
;; are only collected.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)
(require 'sp-vulpea-table-core)
(require 'sp-vulpea-table-views)
(require 'sp-vulpea-table-org)

(declare-function sp-vulpea-table-open "sp-vulpea-table")

(defvar sp-vulpea-table-menu--spec nil
  "The spec the menu is editing.")

(defvar sp-vulpea-table-menu--name nil
  "Name of the saved view the menu's spec came from, if any.")

(defvar sp-vulpea-table-menu--target nil
  "Buffer showing a table that running the menu should redraw, or nil.")

(defvar sp-vulpea-table-menu--notes nil
  "Notes read for completion while the menu is open.")

;;;; Reading and writing settings

(defun sp-vulpea-table-menu--get (key)
  "Return the setting KEY of the menu's spec."
  (plist-get sp-vulpea-table-menu--spec key))

(defun sp-vulpea-table-menu--set (key value)
  "Set KEY to VALUE in the menu's spec; a nil VALUE removes KEY."
  (let ((spec (copy-sequence sp-vulpea-table-menu--spec)))
    (cl-remf spec key)
    (when value (setq spec (plist-put spec key value)))
    (setq sp-vulpea-table-menu--spec spec)))

(defun sp-vulpea-table-menu--all-notes ()
  "Return all notes, read once per menu session."
  (or sp-vulpea-table-menu--notes
      (setq sp-vulpea-table-menu--notes (vulpea-db-query))))

(defun sp-vulpea-table-menu--candidates (function)
  "Return the sorted unique non-empty strings FUNCTION gives for the notes."
  (sort (delete-dups
         (seq-remove (lambda (s) (or (null s) (string-empty-p s)))
                     (mapcan (lambda (n) (ensure-list (funcall function n)))
                             (sp-vulpea-table-menu--all-notes))))
        #'string<))

(defun sp-vulpea-table-menu--meta-keys ()
  "Return every meta key found in the notes."
  (sp-vulpea-table-menu--candidates
   (lambda (n) (mapcar #'car (vulpea-note-meta n)))))

(defun sp-vulpea-table-menu--column-candidates ()
  "Return the built-in columns and the meta keys, as strings."
  (append (mapcar #'symbol-name sp-vulpea-table-builtin-columns)
          (sp-vulpea-table-menu--meta-keys)))

(defun sp-vulpea-table-menu--column (string)
  "Return the column STRING names: a keyword for a built-in one."
  (if (string-prefix-p ":" string) (intern string) string))

(defun sp-vulpea-table-menu--column-name (column)
  "Return COLUMN as the text shown and read back in prompts."
  (if (keywordp column) (symbol-name column) column))

;;;; Descriptions

(defun sp-vulpea-table-menu--value-text (key)
  "Return the text shown for the setting KEY."
  (let ((value (sp-vulpea-table-menu--get key)))
    (pcase key
      (:links (mapconcat (lambda (id)
                           (if-let* ((n (ignore-errors (vulpea-db-get-by-id id))))
                               (vulpea-note-title n)
                             id))
                         value ", "))
      (:meta (mapconcat (lambda (c) (if (cdr c) (format "%s=%s" (car c) (cdr c)) (car c)))
                        value ", "))
      (:columns (mapconcat #'sp-vulpea-table-menu--column-name value " "))
      (:sort-by (and value (sp-vulpea-table-menu--column-name value)))
      (:sort-desc (and value "descending"))
      (:level (and value (if (eq value 'headings) "headings" "file-level")))
      (:parent-of (and value (format "%s%s" value
                                     (if-let* ((p (sp-vulpea-table-menu--get :parent-prop)))
                                         (format " via %s" p) ""))))
      (_ (if (listp value) (string-join value ", ") value)))))

(defun sp-vulpea-table-menu--describe (label key)
  "Return LABEL followed by the current value of KEY, highlighted."
  (let ((text (sp-vulpea-table-menu--value-text key)))
    (concat (format "%-16s" label)
            (if (and text (not (string-empty-p text)))
                (propertize text 'face 'transient-value)
              (propertize "-" 'face 'transient-inactive-value)))))

(defmacro sp-vulpea-table-menu--defdesc (name label key)
  "Define NAME, a menu description function for the setting KEY with LABEL."
  `(defun ,name (&optional _obj)
     (sp-vulpea-table-menu--describe ,label ,key)))

(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-tags "Tags (all)" :tags)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-tags-any "Tags (any)" :tags-any)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-tags-none "Tags (none)" :tags-none)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-dirs "Directories" :directories)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-todo "TODO state" :todo)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-links "Links to" :links)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-meta "Meta" :meta)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-parent "Children of" :parent-of)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-level "Level" :level)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-title "Title matches" :title-match)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-columns "Columns" :columns)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-sort "Sort by" :sort-by)
(sp-vulpea-table-menu--defdesc sp-vulpea-table-menu--d-desc "Direction" :sort-desc)

(defun sp-vulpea-table-menu--header ()
  "Return the heading of the menu."
  (concat (propertize (if sp-vulpea-table-menu--name
                          (format "Vulpea table: %s" sp-vulpea-table-menu--name)
                        "Vulpea table")
                      'face 'transient-heading)
          "\n"
          (propertize (sp-vulpea-table-spec-summary sp-vulpea-table-menu--spec)
                      'face 'shadow)))

;;;; Commands that change one setting

(defun sp-vulpea-table-menu-tags (key prompt)
  "Read the tag list for KEY with PROMPT, offering the tags in the database."
  (sp-vulpea-table-menu--set
   key
   (completing-read-multiple
    prompt (vulpea-db-query-tags) nil nil
    (when-let* ((cur (sp-vulpea-table-menu--get key))) (concat (string-join cur ",") ",")))))

(defun sp-vulpea-table-menu-set-tags ()
  "Set the tags a note must all have."
  (interactive) (sp-vulpea-table-menu-tags :tags "Tags, all of: "))

(defun sp-vulpea-table-menu-set-tags-any ()
  "Set the tags of which a note must have at least one."
  (interactive) (sp-vulpea-table-menu-tags :tags-any "Tags, any of: "))

(defun sp-vulpea-table-menu-set-tags-none ()
  "Set the tags a note must not have."
  (interactive) (sp-vulpea-table-menu-tags :tags-none "Tags, none of: "))

(defun sp-vulpea-table-menu-set-directories ()
  "Set the directories a note's file must lie under."
  (interactive)
  (let ((dirs (sp-vulpea-table-menu--candidates
               (lambda (n) (abbreviate-file-name
                            (directory-file-name
                             (file-name-directory (vulpea-note-path n))))))))
    (sp-vulpea-table-menu--set
     :directories
     (completing-read-multiple
      "Directories (type any path too): " dirs nil nil
      (when-let* ((cur (plist-get sp-vulpea-table-menu--spec :directories)))
        (concat (string-join cur ",") ","))))))

(defun sp-vulpea-table-menu-set-todo ()
  "Set the TODO states a note must be in."
  (interactive)
  (sp-vulpea-table-menu--set
   :todo
   (completing-read-multiple
    "TODO states: "
    (sp-vulpea-table-menu--candidates #'vulpea-note-todo) nil nil
    (when-let* ((cur (sp-vulpea-table-menu--get :todo))) (concat (string-join cur ",") ",")))))

(defun sp-vulpea-table-menu-add-link ()
  "Add a note the table's notes must link to (any of the listed ones)."
  (interactive)
  (when-let* ((note (sp-vulpea-table-select-note "Links to: ")))
    (sp-vulpea-table-menu--set
     :links (cl-adjoin (vulpea-note-id note) (sp-vulpea-table-menu--get :links)
                       :test #'equal))))

(defun sp-vulpea-table-menu-clear-links ()
  "Remove the link filter."
  (interactive) (sp-vulpea-table-menu--set :links nil))

(defun sp-vulpea-table-menu-add-meta ()
  "Require a meta KEY, optionally with a given value."
  (interactive)
  (let* ((key (completing-read "Meta key: " (sp-vulpea-table-menu--meta-keys)))
         (values (sp-vulpea-table-menu--candidates
                  (lambda (n) (vulpea-note-meta-get-list n key))))
         (value (completing-read
                 (format "Value of %s (empty: only require the key): " key) values)))
    (unless (string-empty-p key)
      (sp-vulpea-table-menu--set
       :meta (append (assoc-delete-all key (copy-sequence (sp-vulpea-table-menu--get :meta)))
                     (list (cons key (unless (string-empty-p value) value))))))))

(defun sp-vulpea-table-menu-clear-meta ()
  "Remove the meta filter."
  (interactive) (sp-vulpea-table-menu--set :meta nil))

(defun sp-vulpea-table-menu-set-parent ()
  "Set the note whose children the table lists, and the meta key that links them."
  (interactive)
  (let ((parent (sp-vulpea-table-read-parent t)))
    (sp-vulpea-table-menu--set :parent-of parent)
    (sp-vulpea-table-menu--set
     :parent-prop
     (when parent
       (let ((prop (read-string "Parent meta key (empty for \"parents\"): ")))
         (unless (string-empty-p prop) prop))))))

(defun sp-vulpea-table-menu-set-level ()
  "Choose between file-level notes, heading notes and both."
  (interactive)
  (sp-vulpea-table-menu--set
   :level (pcase (completing-read "Notes: " '("all" "file-level" "headings") nil t)
            ("file-level" 0) ("headings" 'headings))))

(defun sp-vulpea-table-menu-set-title ()
  "Set a regexp the title must match."
  (interactive)
  (let ((re (read-regexp "Title matches (regexp, empty for any): "
                         (sp-vulpea-table-menu--get :title-match))))
    (sp-vulpea-table-menu--set :title-match (unless (string-empty-p re) re))))

(defun sp-vulpea-table-menu-set-columns ()
  "Set the columns, in order."
  (interactive)
  (let ((cols (completing-read-multiple
               "Columns, in order (:title, :tags, ... or a meta key): "
               (sp-vulpea-table-menu--column-candidates) nil nil
               (concat (mapconcat #'sp-vulpea-table-menu--column-name
                                  (or (sp-vulpea-table-menu--get :columns) '(:title)) ",")
                       ","))))
    (sp-vulpea-table-menu--set
     :columns (mapcar #'sp-vulpea-table-menu--column cols))))

(defun sp-vulpea-table-menu-set-sort ()
  "Set the column to sort by."
  (interactive)
  (let ((col (completing-read "Sort by (empty for none): "
                              (or (mapcar #'sp-vulpea-table-menu--column-name
                                          (sp-vulpea-table-menu--get :columns))
                                  (sp-vulpea-table-menu--column-candidates)))))
    (sp-vulpea-table-menu--set
     :sort-by (unless (string-empty-p col) (sp-vulpea-table-menu--column col)))))

(defun sp-vulpea-table-menu-toggle-desc ()
  "Toggle between ascending and descending order."
  (interactive)
  (sp-vulpea-table-menu--set :sort-desc (not (sp-vulpea-table-menu--get :sort-desc))))

(defun sp-vulpea-table-menu-reset ()
  "Forget every setting."
  (interactive)
  (setq sp-vulpea-table-menu--spec nil sp-vulpea-table-menu--name nil))

;;;; Commands that use the whole spec

(defun sp-vulpea-table-menu--spec-now ()
  "Return the menu's spec, normalized."
  (sp-vulpea-table-spec-normalize sp-vulpea-table-menu--spec))

(defun sp-vulpea-table-menu-run ()
  "Open the table, or redraw the table this menu was started from."
  (interactive)
  (let ((spec (sp-vulpea-table-menu--spec-now))
        (target sp-vulpea-table-menu--target))
    (setq sp-vulpea-table-menu--target nil)
    (sp-vulpea-table-open spec sp-vulpea-table-menu--name target)))

(defun sp-vulpea-table-menu-preview ()
  "Say how many notes the spec matches."
  (interactive)
  (let ((spec (sp-vulpea-table-resolve-spec sp-vulpea-table-menu--spec)))
    (message "%d notes: %s" (length (sp-vulpea-table-query spec))
             (sp-vulpea-table-spec-summary spec))))

(defun sp-vulpea-table-menu-insert ()
  "Insert the spec at point in the Org buffer the menu was started from."
  (interactive)
  (unless (derived-mode-p 'org-mode) (user-error "Not in an Org buffer"))
  (sp-vulpea-table-insert-dblock (sp-vulpea-table-menu--spec-now)))

(defun sp-vulpea-table-menu-save ()
  "Save the spec as a named view."
  (interactive)
  (let ((name (read-string "Save view as: " sp-vulpea-table-menu--name)))
    (when (string-empty-p name) (user-error "A view needs a name"))
    (when (or (not (member name (sp-vulpea-table-views-names)))
              (string= name sp-vulpea-table-menu--name)
              (y-or-n-p (format "Replace the view \"%s\"? " name)))
      (sp-vulpea-table-views-put name (sp-vulpea-table-menu--spec-now))
      (setq sp-vulpea-table-menu--name name)
      (message "Saved Vulpea table view \"%s\"" name))))

(defun sp-vulpea-table-menu-load ()
  "Load a saved view into the menu."
  (interactive)
  (let ((name (sp-vulpea-table-views-read-name "Load view: ")))
    (setq sp-vulpea-table-menu--spec (copy-tree (sp-vulpea-table-views-get name))
          sp-vulpea-table-menu--name name)))

(defun sp-vulpea-table-menu-delete ()
  "Delete a saved view."
  (interactive)
  (call-interactively #'sp-vulpea-table-view-delete))

;;;###autoload (autoload 'sp-vulpea-table-menu "sp-vulpea-table-menu" nil t)
(transient-define-prefix sp-vulpea-table-menu ()
  "Build, run and save a table of Vulpea notes."
  [:description sp-vulpea-table-menu--header
   :class transient-columns
   ["Filter"
    ("t" sp-vulpea-table-menu-set-tags :description sp-vulpea-table-menu--d-tags :transient t)
    ("a" sp-vulpea-table-menu-set-tags-any :description sp-vulpea-table-menu--d-tags-any :transient t)
    ("x" sp-vulpea-table-menu-set-tags-none :description sp-vulpea-table-menu--d-tags-none :transient t)
    ("d" sp-vulpea-table-menu-set-directories :description sp-vulpea-table-menu--d-dirs :transient t)
    ("s" sp-vulpea-table-menu-set-todo :description sp-vulpea-table-menu--d-todo :transient t)
    ("l" sp-vulpea-table-menu-add-link :description sp-vulpea-table-menu--d-links :transient t)
    ("L" "  clear links" sp-vulpea-table-menu-clear-links :transient t)
    ("m" sp-vulpea-table-menu-add-meta :description sp-vulpea-table-menu--d-meta :transient t)
    ("M" "  clear meta" sp-vulpea-table-menu-clear-meta :transient t)
    ("p" sp-vulpea-table-menu-set-parent :description sp-vulpea-table-menu--d-parent :transient t)
    ("v" sp-vulpea-table-menu-set-level :description sp-vulpea-table-menu--d-level :transient t)
    ("r" sp-vulpea-table-menu-set-title :description sp-vulpea-table-menu--d-title :transient t)]
   ["Shape"
     ("c" sp-vulpea-table-menu-set-columns :description sp-vulpea-table-menu--d-columns :transient t)
     ("o" sp-vulpea-table-menu-set-sort :description sp-vulpea-table-menu--d-sort :transient t)
     ("O" sp-vulpea-table-menu-toggle-desc :description sp-vulpea-table-menu--d-desc :transient t)]
   ["Views"
     ("S" "Save view" sp-vulpea-table-menu-save :transient t)
     ("V" "Load view" sp-vulpea-table-menu-load :transient t)
     ("D" "Delete view" sp-vulpea-table-menu-delete :transient t)]
   ["Run"
     ("RET" "Open table" sp-vulpea-table-menu-run)
     ("P" "Preview count" sp-vulpea-table-menu-preview :transient t)
     ("i" "Insert as dblock" sp-vulpea-table-menu-insert)
     ("R" "Reset" sp-vulpea-table-menu-reset :transient t)]])

(provide 'sp-vulpea-table-menu)
;;; sp-vulpea-table-menu.el ends here
