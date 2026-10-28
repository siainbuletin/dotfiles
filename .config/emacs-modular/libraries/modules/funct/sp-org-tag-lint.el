;;; sp-org-tag-lint.el --- Lint Org tags against the tag registry -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-org-tag-lint' reports the tags of the vault that are in neither
;; `org-tag-alist' (task tags) nor `org-tag-persistent-alist' (note tags,
;; from sp-org-tag-registry.el), with the registered tag each one is
;; probably a typo of, and the notes that have no #+filetags: line.
;; `sp-org-tag-add' registers a new note tag in the registry file and
;; loads it again, so it works at once.  `sp-org-tag-read-note-tags' asks
;; for the tags of a new note, in a menu grouped by `sp-org-tag-groups-alist'
when `sp-org-tag-groups' is loaded.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'sp-globals nil t)

(defvar sp-notes-dir)
(defvar org-tag-persistent-alist)

(defgroup sp-org-tag-lint nil
  "Lint Org tags against the tag registry."
  :group 'org
  :prefix "sp-org-tag-lint-")

(defcustom sp-org-tag-lint-registry-file
  (expand-file-name "sp-org-tag-registry.el"
                    (file-name-directory
                     (or load-file-name buffer-file-name default-directory)))
  "The file that sets `org-tag-persistent-alist', edited by `sp-org-tag-add'."
  :type 'file
  :group 'sp-org-tag-lint)

(defcustom sp-org-tag-lint-directory
  (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes")
  "Folder scanned when the vulpea database is not available."
  :type 'directory
  :group 'sp-org-tag-lint)

(defcustom sp-org-tag-lint-exclude-regexp
  "\\(?:\\`\\|/\\)\\(?:\\.[^/]+\\|ltximg\\|attach\\|data\\)/"
  "Files whose path matches this regexp are not scanned.
The path is taken relative to the scanned folder when the file is in it."
  :type 'regexp
  :group 'sp-org-tag-lint)

(defcustom sp-org-tag-lint-ignored-tags '("ARCHIVE" "ATTACH" "noexport" "crypt")
  "Tags that are never reported, such as the special tags of Org itself."
  :type '(repeat string)
  :group 'sp-org-tag-lint)

(defconst sp-org-tag-lint--sentinel
  ";; sp-org-tag-add: new tags go above this line"
  "The line of the registry file above which new tags are inserted.")

(defconst sp-org-tag-lint--tag-re "[[:alnum:]_@#%]+"
  "One Org tag.")

(when (file-exists-p sp-org-tag-lint-registry-file)
  (load sp-org-tag-lint-registry-file nil t))

(defun sp-org-tag-lint--alist-tags (alist)
  "The tag names in the tag ALIST, without group markers or keys."
  (delq nil (mapcar (lambda (entry)
                      (cond ((stringp entry) entry)
                            ((and (consp entry) (stringp (car entry))) (car entry))))
                    alist)))

(defun sp-org-tag-lint-note-tags ()
  "The registered note tags, from `org-tag-persistent-alist'."
  (sp-org-tag-lint--alist-tags org-tag-persistent-alist))

(defun sp-org-tag-lint-registered-tags ()
  "Every registered tag: the task tags and the note tags."
  (seq-uniq (append (sp-org-tag-lint--alist-tags org-tag-alist)
                    (sp-org-tag-lint-note-tags))
            #'string=))

(defun sp-org-tag-lint--closest (tag candidates)
  "The tag in CANDIDATES that TAG is most likely a typo of, or nil."
  (let ((limit (if (> (length tag) 4) 2 1))
        best (best-distance most-positive-fixnum))
    (dolist (candidate candidates)
      (let ((distance (if (string= (downcase candidate) (downcase tag))
                          0
                        (string-distance tag candidate))))
        (when (and (<= distance limit) (< distance best-distance))
          (setq best candidate
                best-distance distance))))
    best))

(defun sp-org-tag-lint--insert-in-registry (tag)
  "Write TAG into `sp-org-tag-lint-registry-file', above the marker line."
  (let ((file sp-org-tag-lint-registry-file)
        (visiting (find-buffer-visiting sp-org-tag-lint-registry-file)))
    (unless (file-writable-p file)
      (user-error "Cannot write %s" file))
    (when (and visiting (buffer-modified-p visiting))
      (user-error "Save %s first" (buffer-name visiting)))
    (let ((coding-system-for-read 'utf-8)
          (coding-system-for-write 'utf-8))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (unless (search-forward sp-org-tag-lint--sentinel nil t)
          (user-error "No marker line \"%s\" in %s"
                      sp-org-tag-lint--sentinel file))
        (beginning-of-line)
        (insert (make-string (current-indentation) ?\s) (format "(%S)\n" tag))
        (write-region nil nil file nil 'silent)))
    (when visiting
      (with-current-buffer visiting (revert-buffer t t t)))))

;;;###autoload
(defun sp-org-tag-add (tag)
  "Register TAG as a note tag and make it available at once.
TAG is inserted in `sp-org-tag-lint-registry-file', which is then
loaded again.  Ask first when TAG looks like a typo of a registered
tag.  Return TAG."
  (interactive (list (read-string "New note tag: ")))
  (let ((tag (string-trim tag "[ \t:]+" "[ \t:]+"))
        (registered (sp-org-tag-lint-registered-tags)))
    (unless (string-match-p (concat "\\`" sp-org-tag-lint--tag-re "\\'") tag)
      (user-error "Not a valid Org tag: %S" tag))
    (when (member tag registered)
      (user-error "The tag %S is already registered" tag))
    (let ((near (sp-org-tag-lint--closest tag registered)))
      (when (and near
                 (not (y-or-n-p (format "%S is close to the registered tag %S.  Add it anyway? "
                                        tag near))))
        (user-error "Not added")))
    (sp-org-tag-lint--insert-in-registry tag)
    (load-file sp-org-tag-lint-registry-file)
    (message "Registered the note tag %S" tag)
    tag))

;;;###autoload
(defun sp-org-tag-read-note-tags (&optional prompt)
  "Ask for one or more note tags and return them as a list of strings.
PROMPT replaces the default prompt.  Tags that are not registered are
offered for registration with `sp-org-tag-add' and left out when you
decline."
  (let (result)
    (while (null result)
      (let ((tags (delete-dups
                   (seq-remove #'string-empty-p
                               (let ((prompt (or prompt "Note tags (comma-separated): "))
                                     (candidates (sp-org-tag-lint-note-tags)))
                                 (if (fboundp 'sp-org-tag-groups-read-tags)
                                     (sp-org-tag-groups-read-tags prompt candidates)
                                   (completing-read-multiple prompt candidates)))))))
        (setq result
              (seq-filter
               (lambda (tag)
                 (or (member tag (sp-org-tag-lint-registered-tags))
                     (and (y-or-n-p (format "%S is not registered.  Register it? " tag))
                          (condition-case nil
                              (progn (sp-org-tag-add tag) t)
                            (user-error nil)))))
               tags))
        (unless result
          (message "A note needs at least one tag (C-g to abort)")
          (sit-for 1))))
    result))

(defconst sp-org-tag-lint--heading-re
  (concat "^\\*+[ \t]+\\(?:.*?[ \t]+\\)?"
          "\\(:" sp-org-tag-lint--tag-re "\\(?::" sp-org-tag-lint--tag-re "\\)*:\\)"
          "[ \t]*$")
  "A heading with tags; group 1 is the tag string.")

(defun sp-org-tag-lint--scan ()
  "Scan the current buffer for tags.
Return (HAS-FILETAGS . OCCURRENCES), OCCURRENCES being a list of
(TAG . LINE) in buffer order."
  (let ((case-fold-search t)
        (line 1)
        in-block has-filetags occurrences)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (cond
         ((looking-at "[ \t]*#\\+begin_\\(?:src\\|example\\|export\\|comment\\)\\_>")
          (setq in-block t))
         ((looking-at "[ \t]*#\\+end_\\(?:src\\|example\\|export\\|comment\\)\\_>")
          (setq in-block nil))
         (in-block)
         ((looking-at "#\\+filetags:[ \t]*\\(.*\\)$")
          (let ((tags (split-string (match-string-no-properties 1) "[: \t]+" t)))
            (when tags (setq has-filetags t))
            (dolist (tag tags)
              (push (cons tag line) occurrences))))
         ((looking-at sp-org-tag-lint--heading-re)
          (dolist (tag (split-string (match-string-no-properties 1) ":" t))
            (push (cons tag line) occurrences))))
        (forward-line 1)
        (cl-incf line)))
    (cons has-filetags (nreverse occurrences))))

(defun sp-org-tag-lint-files ()
  "The Org files to lint: those of the vulpea database, else of the vault folder."
  (let* ((root (file-name-as-directory (expand-file-name sp-org-tag-lint-directory)))
         (paths (when (and (fboundp 'vulpea-db-query) (fboundp 'vulpea-note-path))
                  (ignore-errors (mapcar #'vulpea-note-path (vulpea-db-query)))))
         (candidates (or (delq nil paths)
                         (directory-files-recursively root "\\.org\\'"))))
    (sort
     (seq-uniq
      (seq-filter
       (lambda (file)
         (and (string-suffix-p ".org" file)
              (file-regular-p file)
              (not (string-match-p
                    sp-org-tag-lint-exclude-regexp
                    (if (string-prefix-p root file) (substring file (length root)) file)))))
       (mapcar #'expand-file-name candidates)))
     #'string<)))

(defun sp-org-tag-lint--insert-file (file)
  "Insert the text of FILE, from its buffer when it is open."
  (let ((buffer (find-buffer-visiting file)))
    (if buffer
        (insert (with-current-buffer buffer
                  (buffer-substring-no-properties (point-min) (point-max))))
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents file)))))

(defun sp-org-tag-lint--run (files)
  "Lint FILES and return a plist of :files, :unknown and :untagged."
  (let ((registered (sp-org-tag-lint-registered-tags))
        unknown untagged)
    (dolist (file files)
      (with-temp-buffer
        (sp-org-tag-lint--insert-file file)
        (pcase-let ((`(,has-filetags . ,occurrences) (sp-org-tag-lint--scan)))
          (unless has-filetags (push file untagged))
          (dolist (occurrence occurrences)
            (let ((tag (car occurrence)))
              (unless (or (member tag registered)
                          (member tag sp-org-tag-lint-ignored-tags))
                (push (cons file (cdr occurrence))
                      (alist-get tag unknown nil nil #'string=))))))))
    (list :files (length files)
          :unknown (sort (mapcar (lambda (entry) (cons (car entry) (nreverse (cdr entry))))
                                 unknown)
                         (lambda (a b) (string< (car a) (car b))))
          :untagged (nreverse untagged))))

(defconst sp-org-tag-lint--buffer-name "*sp-org-tag-lint*"
  "Name of the report buffer.")

(defvar-local sp-org-tag-lint--files nil
  "The files the report buffer was made from, for `g'.")

(defvar sp-org-tag-lint-report-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'sp-org-tag-lint-visit)
    (define-key map (kbd "a") #'sp-org-tag-lint-register-at-point)
    (define-key map (kbd "g") #'sp-org-tag-lint-refresh)
    map)
  "Keymap of `sp-org-tag-lint-report-mode'.")

(define-derived-mode sp-org-tag-lint-report-mode special-mode "TagLint"
  "Major mode of the tag lint report.
\\{sp-org-tag-lint-report-mode-map}")

(defun sp-org-tag-lint--abbreviate (file)
  "FILE shortened for display."
  (abbreviate-file-name file))

(defun sp-org-tag-lint--insert-location (file line tag)
  "Insert a line pointing at FILE and LINE, carrying TAG as a property."
  (insert "    "
          (propertize (if line
                          (format "%s:%d" (sp-org-tag-lint--abbreviate file) line)
                        (sp-org-tag-lint--abbreviate file))
                      'sp-tag-file file 'sp-tag-line line 'sp-tag-name tag
                      'face 'link 'mouse-face 'highlight)
          "\n"))

(defun sp-org-tag-lint--render (result)
  "Insert the report for RESULT in the current buffer."
  (let ((registered (sp-org-tag-lint-registered-tags))
        (unknown (plist-get result :unknown))
        (untagged (plist-get result :untagged)))
    (insert (format "Org tag lint: %d files, %d registered tags\n\n"
                    (plist-get result :files) (length registered)))
    (insert (propertize (format "Unregistered tags (%d)" (length unknown)) 'face 'bold) "\n")
    (if (null unknown)
        (insert "  none\n")
      (dolist (entry unknown)
        (let* ((tag (car entry))
               (near (sp-org-tag-lint--closest tag registered)))
          (insert "  "
                  (propertize (format ":%s:" tag) 'face 'warning 'sp-tag-name tag)
                  (format "  x%d" (length (cdr entry)))
                  (if near (format "  (probably %s)" near) "")
                  "\n")
          (dolist (occurrence (cdr entry))
            (sp-org-tag-lint--insert-location (car occurrence) (cdr occurrence) tag)))))
    (insert "\n" (propertize (format "Notes without #+filetags (%d)" (length untagged))
                             'face 'bold)
            "\n")
    (if (null untagged)
        (insert "  none\n")
      (dolist (file untagged)
        (sp-org-tag-lint--insert-location file nil nil)))
    (insert "\nRET visit   a register the tag at point   g run again\n")))

(defun sp-org-tag-lint--show (files)
  "Lint FILES and show the report."
  (let ((result (sp-org-tag-lint--run files))
        (buffer (get-buffer-create sp-org-tag-lint--buffer-name)))
    (with-current-buffer buffer
      (sp-org-tag-lint-report-mode)
      (setq sp-org-tag-lint--files files)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (sp-org-tag-lint--render result))
      (goto-char (point-min)))
    (pop-to-buffer buffer)
    (message "%d unregistered tags, %d notes without tags"
             (length (plist-get result :unknown))
             (length (plist-get result :untagged)))
    result))

(defun sp-org-tag-lint-visit ()
  "Visit the file on the report line at point."
  (interactive)
  (let ((file (get-text-property (point) 'sp-tag-file))
        (line (get-text-property (point) 'sp-tag-line)))
    (unless file (user-error "No file on this line"))
    (find-file-other-window file)
    (when line
      (goto-char (point-min))
      (forward-line (1- line)))))

(defun sp-org-tag-lint-refresh ()
  "Run the lint again on the same files."
  (interactive)
  (sp-org-tag-lint--show (or sp-org-tag-lint--files (sp-org-tag-lint-files))))

(defun sp-org-tag-lint-register-at-point ()
  "Register the tag on the report line at point, then lint again."
  (interactive)
  (let ((tag (get-text-property (point) 'sp-tag-name)))
    (unless tag (user-error "No tag on this line"))
    (sp-org-tag-add tag)
    (sp-org-tag-lint-refresh)))

;;;###autoload
(defun sp-org-tag-lint ()
  "Lint the tags of the whole vault against the tag registry.
Report the tags that are in neither `org-tag-alist' nor
`org-tag-persistent-alist', and the notes with no #+filetags line."
  (interactive)
  (sp-org-tag-lint--show (sp-org-tag-lint-files)))

;;;###autoload
(defun sp-org-tag-lint-buffer ()
  "Lint the tags of the file of the current buffer, unsaved changes included."
  (interactive)
  (unless buffer-file-name
    (user-error "This buffer is not visiting a file"))
  (sp-org-tag-lint--show (list (expand-file-name buffer-file-name))))

(provide 'sp-org-tag-lint)
;;; sp-org-tag-lint.el ends here
