;;; sp-org-lint-footnotes.el --- Lint the footnotes of the vulpea vault -*- lexical-binding: t; -*-

;;; Commentary:

;; `sp-org-lint-footnotes-dryrun' lints the footnotes of the whole vulpea vault: it
;; moves the definitions of a trailing `Footnotes' heading to the heading that
;; contains their reference, and reports orphan definitions and dangling
;; references.  A second, headless Emacs loads this file and reads the files,
;; so Emacs stays usable; the report comes first and nothing is changed
;; (after a backup) until you apply it.  Required by `sp-org-lint'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'org)
(require 'org-element)
(require 'subr-x)
(require 'sp-batch-report)
(require 'sp-globals nil t)

(defvar sp-notes-dir)

;;;; Sectional footnotes

(defgroup sp-org-lint nil
  "Lint Org files."
  :group 'org)

(defcustom sp-org-lint-fn-section-title "Footnotes"
  "Title of the heading whose footnote definitions are moved (case is ignored)."
  :type 'string
  :group 'spcustom)

(defcustom sp-org-lint-fn-remove-empty-section t
  "When non-nil, remove a footnotes heading that is empty after its moves.
A heading with children, or with anything but the moved definitions
\(a property drawer, a paragraph), is kept."
  :type 'boolean
  :group 'spcustom)

(defcustom sp-org-lint-fn-directory
  (if (boundp 'sp-notes-dir) sp-notes-dir "~/notes")
  "Folder scanned when the vulpea database is not available."
  :type 'directory
  :group 'spcustom)

(defcustom sp-org-lint-fn-exclude-regexp
  "\\(?:\\`\\|/\\)\\(?:\\.[^/]+\\|ltximg\\|attach\\|data\\)/"
  "Files whose path matches this regexp are not scanned.
The path is taken relative to the scanned folder when the file is in
it.  The default skips hidden folders and the usual attachment ones."
  :type 'regexp
  :group 'spcustom)

(defcustom sp-org-lint-fn-backup-directory
  (expand-file-name "org-lint-backups/" sp-var-dir)
  "Folder that receives a copy of every file before it is changed.
It is below `sp-var-dir', which Git ignores."
  :type 'directory
  :group 'spcustom)

(defcustom sp-org-lint-fn-files-function #'sp-org-lint-fn-vault-files
  "Function returning the list of Org files to lint."
  :type 'function
  :group 'spcustom)

(defun sp-org-lint-fn--scan ()
  "Scan the current Org buffer for headings and footnotes.
Return (HEADS REFS DEFS).  HEADS lists plists (:begin :title :end
:own-end) sorted by position: :end is the end of the subtree and
:own-end the start of the next heading of any level.  REFS lists
\(LABEL BEGIN) for the standard references `[fn:LABEL]'.  DEFS lists
plists (:label :begin :end :text :inline); a labelled inline
footnote counts as a definition that is already in place."
  (let ((tree (org-element-parse-buffer))
        heads refs defs)
    (org-element-map tree 'headline
      (lambda (h)
        (push (list :begin (org-element-property :begin h)
                    :title (org-element-property :raw-value h)
                    :end (org-element-property :end h)
                    :own-end nil)
              heads)))
    (setq heads (sort heads (lambda (a b)
                              (< (plist-get a :begin) (plist-get b :begin)))))
    (let ((tail heads))
      (while tail
        (plist-put (car tail) :own-end
                   (if (cdr tail) (plist-get (cadr tail) :begin) (point-max)))
        (setq tail (cdr tail))))
    (org-element-map tree '(footnote-reference footnote-definition)
      (lambda (el)
        (let ((label (org-element-property :label el))
              (begin (org-element-property :begin el))
              (end (org-element-property :end el)))
          (when label
            (cond
             ((eq (org-element-type el) 'footnote-definition)
              (push (list :label label :begin begin :end end
                          :text (string-trim-right
                                 (buffer-substring-no-properties begin end)))
                    defs))
             ((eq (org-element-property :type el) 'inline)
              (let ((cb (org-element-property :contents-begin el))
                    (ce (org-element-property :contents-end el)))
                (when (and cb ce)
                  (push (list :label label :begin begin :end end :inline t
                              :text (format "[fn:%s] %s" label
                                            (string-trim
                                             (buffer-substring-no-properties
                                              cb ce))))
                        defs))))
             (t (push (list label begin) refs)))))))
    (list heads (nreverse refs) (nreverse defs))))

(defun sp-org-lint-fn--section (pos heads)
  "Return the start of the section containing POS, given sorted HEADS.
Text before the first heading is section 0."
  (let ((sec 0))
    (dolist (h heads sec)
      (when (<= (plist-get h :begin) pos)
        (setq sec (plist-get h :begin))))))

(defun sp-org-lint-fn--head (sec heads)
  "Return the heading plist of section SEC, or nil for section 0."
  (seq-find (lambda (h) (= (plist-get h :begin) sec)) heads))

(defun sp-org-lint-fn--section-end (sec heads)
  "Return the end of section SEC: the next heading, or the end of buffer."
  (if (zerop sec)
      (if heads (plist-get (car heads) :begin) (point-max))
    (plist-get (sp-org-lint-fn--head sec heads) :own-end)))

(defun sp-org-lint-fn--section-title (sec heads)
  "Return a title for section SEC."
  (if (zerop sec)
      "(before the first heading)"
    (string-trim (plist-get (sp-org-lint-fn--head sec heads) :title))))

(defun sp-org-lint-fn--footnotes-section-p (sec heads)
  "Non-nil when section SEC is a heading titled `sp-org-lint-fn-section-title'."
  (when-let* ((h (sp-org-lint-fn--head sec heads)))
    (string= (downcase (string-trim (plist-get h :title)))
             (downcase sp-org-lint-fn-section-title))))

(defun sp-org-lint-fn--fresh (label used)
  "Return LABEL if it is not in USED, else LABEL-2, LABEL-3, ... likewise."
  (if (not (member label used))
      label
    (let ((n 2))
      (while (member (format "%s-%d" label n) used)
        (setq n (1+ n)))
      (format "%s-%d" label n))))

(defun sp-org-lint-fn--def-with-label (text label)
  "Return the definition TEXT with its label replaced by LABEL."
  (replace-regexp-in-string "\\`\\[fn:[^]\n]*\\]" (format "[fn:%s]" label)
                            text t t))

(defun sp-org-lint-fn--only-deleted-p (head deletions)
  "Non-nil when HEAD's own text is blank once DELETIONS are taken out."
  (let ((pos (save-excursion
               (goto-char (plist-get head :begin))
               (line-end-position)))
        (rest ""))
    (dolist (e (sort (copy-sequence deletions)
                     (lambda (x y) (< (car x) (car y)))))
      (setq rest (concat rest (buffer-substring-no-properties pos (car e)))
            pos (+ (car e) (cadr e))))
    (string-blank-p
     (concat rest (buffer-substring-no-properties pos (plist-get head :own-end))))))

(defun sp-org-lint-fn--plan ()
  "Plan the footnote moves in the current Org buffer; change nothing.
Return a plist: :moves, :orphans, :dangling, :conflicts, :removed (titles
of footnotes headings to remove), and for `sp-org-lint-fn--apply-edits'
:heads, :adds and :edits, with :n-defs, :n-refs and :n-deleted for the
check afterwards."
  (let* ((scan (sp-org-lint-fn--scan))
         (heads (nth 0 scan))
         (refs (nth 1 scan))
         (defs (nth 2 scan))
         (fn-defs (seq-filter
                   (lambda (d)
                     (and (not (plist-get d :inline))
                          (sp-org-lint-fn--footnotes-section-p
                           (sp-org-lint-fn--section (plist-get d :begin)
                                                    heads)
                           heads)))
                   defs))
         (nested-p (lambda (r)
                     (seq-some (lambda (d)
                                 (and (>= (cadr r) (plist-get d :begin))
                                      (< (cadr r) (plist-get d :end))))
                               fn-defs)))
         (cited (seq-remove nested-p refs))
         (def-labels (mapcar (lambda (d) (plist-get d :label)) defs))
         (ref-labels (mapcar #'car refs))
         (used (seq-uniq (append def-labels ref-labels)))
         moves conflicts edits adds removed)
    (dolist (d fn-defs)
      (let* ((label (plist-get d :label))
             (mine (seq-filter (lambda (r) (equal (car r) label)) cited))
             (secs (seq-uniq (mapcar (lambda (r)
                                       (sp-org-lint-fn--section (cadr r) heads))
                                     mine)))
             (from (sp-org-lint-fn--section-title
                    (sp-org-lint-fn--section (plist-get d :begin) heads) heads))
             (line (line-number-at-pos (plist-get d :begin))))
        (cond
         ((> (seq-count (lambda (l) (equal l label)) def-labels) 1)
          (push (cons label "defined more than once") conflicts))
         ((null mine)
          (when (member label (mapcar #'car (seq-filter nested-p refs)))
            (push (cons label "cited only from another footnote") conflicts)))
         ((seq-some (lambda (s) (sp-org-lint-fn--footnotes-section-p s heads))
                    secs)
          (push (cons label "cited from the footnotes section itself")
                conflicts))
         (t
          (let ((first t))
            (dolist (sec secs)
              (let ((new (if first label (sp-org-lint-fn--fresh label used))))
                (push new used)
                (unless (equal new label)
                  (dolist (r (seq-filter
                              (lambda (r)
                                (eql (sp-org-lint-fn--section (cadr r) heads)
                                     sec))
                              mine))
                    ;; Skip `[fn:' to reach the label itself.
                    (push (list (+ (cadr r) 4) (length label) new) edits)))
                (push (sp-org-lint-fn--def-with-label (plist-get d :text) new)
                      (alist-get sec adds nil nil #'eql))
                (push (list :label label :new new :from from
                            :to (sp-org-lint-fn--section-title sec heads)
                            :line line)
                      moves)
                (setq first nil))))
          (push (list (plist-get d :begin)
                      (- (plist-get d :end) (plist-get d :begin))
                      "")
                edits)))))
    (let ((n-deleted (seq-count (lambda (e) (equal (nth 2 e) "")) edits)))
      (when sp-org-lint-fn-remove-empty-section
        (dolist (h heads)
          (let* ((b (plist-get h :begin))
                 (own-end (plist-get h :own-end))
                 (dels (seq-filter (lambda (e)
                                     (and (equal (nth 2 e) "")
                                          (> (car e) b)
                                          (<= (+ (car e) (cadr e)) own-end)))
                                   edits)))
            (when (and dels
                       (>= own-end (plist-get h :end))
                       (sp-org-lint-fn--only-deleted-p h dels))
              (setq edits (cons (list b (- (plist-get h :end) b) "")
                                (seq-difference edits dels))
                    removed (cons (list (string-trim (plist-get h :title))
                                        (= (plist-get h :end) (point-max)))
                                  removed))))))
      (list :moves (nreverse moves)
            :orphans (seq-uniq
                      (mapcar (lambda (d) (plist-get d :label))
                              (seq-filter
                               (lambda (d)
                                 (and (not (plist-get d :inline))
                                      (not (member (plist-get d :label)
                                                   ref-labels))))
                               defs)))
            :dangling (seq-uniq (seq-remove (lambda (l) (member l def-labels))
                                            ref-labels))
            :conflicts (nreverse conflicts)
            :removed removed
            :heads heads :adds adds :edits edits
            :n-defs (length defs) :n-refs (length refs)
            :n-deleted n-deleted))))

(defun sp-org-lint-fn--apply-edits (heads adds edits)
  "Apply footnote changes to the current buffer.
ADDS maps a section to the definition texts to put at the end of it
\(newest first).  EDITS is a list of (POS LENGTH STRING) replacements.
Everything is positioned against the buffer as it is now."
  (dolist (a adds)
    (let* ((pos (sp-org-lint-fn--section-end (car a) heads))
           (prefix (cond ((= pos (point-min)) "")
                         ((and (>= (- pos (point-min)) 2)
                               (string= (buffer-substring-no-properties
                                         (- pos 2) pos)
                                        "\n\n"))
                          "")
                         ((save-excursion (goto-char pos) (bolp)) "\n")
                         (t "\n\n")))
           (suffix (if (= pos (point-max)) "\n" "\n\n")))
      (push (list pos 0 (concat prefix
                                (mapconcat #'identity (reverse (cdr a)) "\n\n")
                                suffix))
            edits)))
  (dolist (e (sort edits (lambda (x y)
                           (or (> (car x) (car y))
                               (and (= (car x) (car y)) (> (cadr x) (cadr y)))))))
    (goto-char (car e))
    (delete-region (car e) (+ (car e) (cadr e)))
    (insert (nth 2 e))))

(defun sp-org-lint-fn--counts (text)
  "Return (N-DEFS N-REFS DANGLING) for the footnotes in TEXT."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert text)
    (pcase-let* ((`(,_ ,refs ,defs) (sp-org-lint-fn--scan))
                 (def-labels (mapcar (lambda (d) (plist-get d :label)) defs)))
      (list (length defs) (length refs)
            (sort (seq-uniq (seq-remove (lambda (l) (member l def-labels))
                                        (mapcar #'car refs)))
                  #'string<)))))

(defun sp-org-lint-fn-plan-text (text)
  "Plan the footnote moves for the Org TEXT.
Return a plist: :moves, :orphans, :dangling, :conflicts, :removed, and
when something moves :changed t and :text, the new text.  A text whose
result fails the check gets :error instead."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert text)
    (let* ((plan (sp-org-lint-fn--plan))
           (result (list :moves (plist-get plan :moves)
                         :orphans (plist-get plan :orphans)
                         :dangling (plist-get plan :dangling)
                         :conflicts (plist-get plan :conflicts)
                         :removed (mapcar #'car (plist-get plan :removed)))))
      (if (null (plist-get plan :moves))
          result
        (sp-org-lint-fn--apply-edits (plist-get plan :heads)
                                     (plist-get plan :adds)
                                     (plist-get plan :edits))
        ;; A footnotes heading removed from the end of the file would
        ;; leave blank lines behind.
        (when (seq-some #'cadr (plist-get plan :removed))
          (goto-char (point-max))
          (skip-chars-backward " \t\n")
          (delete-region (point) (point-max))
          (insert "\n"))
        (let* ((new (buffer-string))
               (after (sp-org-lint-fn--counts new))
               (want-defs (+ (plist-get plan :n-defs)
                             (length (plist-get plan :moves))
                             (- (plist-get plan :n-deleted)))))
          (if (and (= (nth 0 after) want-defs)
                   (= (nth 1 after) (plist-get plan :n-refs))
                   (equal (nth 2 after) (sort (copy-sequence
                                               (plist-get plan :dangling))
                                              #'string<)))
              (append result (list :changed t :text new))
            (append result
                    (list :error "the result failed the footnote check; file left alone"))))))))

(defun sp-org-lint-fn--read (file)
  "Return the text of FILE, read as UTF-8.
Signal an error for a file that is not clean UTF-8 or has carriage returns,
since writing it back could change it."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (when (search-forward "\r" nil t)
      (error "carriage returns in the file; not touched"))
    (when (memq 'eight-bit (find-charset-region (point-min) (point-max)))
      (error "the file is not valid UTF-8; not touched"))
    (buffer-string)))

(defun sp-org-lint-fn-plan-file (file)
  "Plan FILE: the plist of `sp-org-lint-fn-plan-text' with :file and :sha."
  (condition-case err
      (let ((text (sp-org-lint-fn--read file)))
        (append (list :file file :sha (secure-hash 'sha1 text))
                (sp-org-lint-fn-plan-text text)))
    (error (list :file file :error (error-message-string err)))))

(defun sp-org-lint-fn--backup (file root)
  "Copy FILE below the folder ROOT, keeping its path.  Return the copy."
  (let* ((file (file-truename file))
         (dest (expand-file-name
               (replace-regexp-in-string "\\`\\(?:[A-Za-z]:\\)?[/\\\\]*" ""
                                         file)
               root)))
    (make-directory (file-name-directory dest) t)
    (copy-file file dest t t)
    (unless (= (file-attribute-size (file-attributes file))
               (file-attribute-size (file-attributes dest)))
      (error "backup of the file is incomplete"))
    dest))

(defun sp-org-lint-fn--write (file text)
  "Replace the contents of FILE with TEXT, through a temporary file.
When FILE is a symbolic link the file it points to is replaced, so the link
stays a link."
  (let* ((file (file-truename file))
         (tmp (make-temp-file (concat file ".sp-lint-")))
         (modes (file-modes file)))
    (condition-case err
        (progn
          (let ((coding-system-for-write 'utf-8-unix))
            (write-region text nil tmp nil 'silent))
          (when modes (set-file-modes tmp modes))
          (rename-file tmp file t))
      (error (ignore-errors (delete-file tmp))
             (signal (car err) (cdr err))))))

(defun sp-org-lint-fn-apply-file (file sha backup-root)
  "Apply the plan to FILE if its text still has the SHA-1 SHA.
The file is copied below BACKUP-ROOT first.  Return a plist with :file
and :status, `written' (with :backup and :moves) or `skipped' (with
:reason)."
  (condition-case err
      (let ((text (sp-org-lint-fn--read file)))
        (if (not (equal (secure-hash 'sha1 text) sha))
            (list :file file :status 'skipped
                  :reason "changed since the preview")
          (let ((plan (sp-org-lint-fn-plan-text text)))
            (cond
             ((plist-get plan :error)
              (list :file file :status 'skipped :reason (plist-get plan :error)))
             ((not (plist-get plan :changed))
              (list :file file :status 'skipped :reason "nothing to move"))
             (t
              (let ((backup (sp-org-lint-fn--backup file backup-root)))
                ;; The last look, just before the write: it leaves a gap
                ;; of milliseconds for someone else to save the file.
                (cond
                 ((file-locked-p file)
                  (list :file file :status 'skipped
                        :reason "open with unsaved changes in another Emacs"))
                 ((not (equal (secure-hash 'sha1 (sp-org-lint-fn--read file))
                              sha))
                  (list :file file :status 'skipped
                        :reason "changed while it was being linted"))
                 (t
                  (sp-org-lint-fn--write file (plist-get plan :text))
                  (list :file file :status 'written :backup backup
                        :moves (length (plist-get plan :moves)))))))))))
    (error (list :file file :status 'skipped
                 :reason (error-message-string err)))))

(defvar sp-org-lint--library (or load-file-name (locate-library "sp-org-lint-footnotes"))
  "File this library was loaded from; the headless Emacs loads the same one.")

(defun sp-org-lint-fn--emit (object)
  "Print OBJECT as one line for the main Emacs to read."
  (let ((print-length nil) (print-level nil)
        (print-escape-newlines t) (print-escape-multibyte t)
        (print-escape-nonascii t))
    (princ (concat "SPLINT " (prin1-to-string object) "\n"))))

(defun sp-org-lint-fn--batch (control-file)
  "Run the job described in CONTROL-FILE and print one result per file."
  (let* ((ctl (with-temp-buffer
                (insert-file-contents control-file)
                (read (current-buffer))))
         (files (plist-get ctl :files)))
    (if (eq (plist-get ctl :mode) 'apply)
        (dolist (f files)
          (sp-org-lint-fn--emit
           (sp-org-lint-fn-apply-file (car f) (cdr f)
                                      (plist-get ctl :backup-root))))
      (dolist (f files)
        (let ((plan (sp-org-lint-fn-plan-file f)))
          (sp-org-lint-fn--emit (if (plist-get plan :changed)
                                    (plist-put plan :text nil)
                                  plan)))))
    (sp-org-lint-fn--emit '(:done t))))

(defun sp-org-lint-fn--org-files (candidates root)
  "Return the existing Org files in CANDIDATES, sorted, minus the excluded ones.
Paths inside ROOT are matched against `sp-org-lint-fn-exclude-regexp'
relative to it."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (sort
     (seq-uniq
      (seq-filter
       (lambda (f)
         (and (string-suffix-p ".org" f)
              (file-regular-p f)
              (not (string-match-p
                    sp-org-lint-fn-exclude-regexp
                    (if (string-prefix-p root f) (substring f (length root)) f)))))
       (mapcar #'expand-file-name candidates)))
     #'string<)))

(defun sp-org-lint-fn-vault-files ()
  "Return the Org files of the vulpea database, else of `sp-org-lint-fn-directory'."
  (let ((paths (when (and (fboundp 'vulpea-db-query) (fboundp 'vulpea-note-path))
                 (ignore-errors (mapcar #'vulpea-note-path (vulpea-db-query))))))
    (sp-org-lint-fn--org-files
     (or (delq nil paths)
         (directory-files-recursively sp-org-lint-fn-directory "\\.org\\'"))
     sp-org-lint-fn-directory)))

(defconst sp-org-lint-fn--buffer-name "*sp-org-lint footnotes*"
  "Name of the report buffer.")

(defvar-local sp-org-lint-fn--run nil
  "Plist with the state of the run shown in this report buffer.")

(defun sp-org-lint-fn--get (key)
  "Return KEY of the run state."
  (plist-get sp-org-lint-fn--run key))

(defun sp-org-lint-fn--set (key value)
  "Set KEY of the run state to VALUE."
  (setq sp-org-lint-fn--run (plist-put sp-org-lint-fn--run key value)))

(defun sp-org-lint-fn--header ()
  "Header line of the report buffer."
  (let ((phase (sp-org-lint-fn--get :phase)))
    (pcase phase
      ((or 'scan 'apply)
       (format " Footnote lint: %s %d/%d"
               (if (eq phase 'scan) "scanning" "applying")
               (or (sp-org-lint-fn--get :done) 0)
               (or (sp-org-lint-fn--get :total) 0)))
      ('ready (if (derived-mode-p 'sp-org-lint-fn-batch-mode)
                  " Footnote lint: RET visit, d drop, u restore, a apply, g rescan, q quit"
                " Footnote lint: RET visit, a apply, g rescan, q quit"))
      ('applied " Footnote lint: applied; RET visit, g rescan, q quit")
      (_ " Footnote lint"))))

(defvar sp-org-lint-fn-report-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'sp-org-lint-fn-visit)
    (define-key map (kbd "a") #'sp-org-lint-footnotes-convert)
    (define-key map (kbd "g") #'sp-org-lint-footnotes-dryrun)
    map)
  "Keymap of `sp-org-lint-fn-report-mode'.")

(define-derived-mode sp-org-lint-fn-report-mode special-mode "FnLint"
  "Report of the footnote lint of the vault."
  (setq-local header-line-format '(:eval (sp-org-lint-fn--header))))

;; The shared `sp-batch-report-mode' view replaces this one; the old one stays
;; for now, `sp-batch-report-interface' set to `old' brings it back.
(make-obsolete 'sp-org-lint-fn-report-mode 'sp-org-lint-fn-batch-mode "2026-11-09")
(make-obsolete-variable 'sp-org-lint-fn-report-mode-map 'sp-org-lint-fn-batch-mode-map "2026-11-09")

(defvar sp-org-lint-fn-batch-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'sp-org-lint-footnotes-convert)
    map)
  "Keymap of `sp-org-lint-fn-batch-mode'.")

(define-derived-mode sp-org-lint-fn-batch-mode sp-batch-report-mode "FnLint"
  "Report of the footnote lint of the vault, in the shared report buffer.
\\<sp-org-lint-fn-batch-mode-map>\\[sp-org-lint-footnotes-convert] applies the moves, d drops a file from them."
  (setq-local header-line-format '(:eval (sp-org-lint-fn--header))
              sp-batch-report-apply-function #'sp-org-lint-footnotes-convert
              sp-batch-report-redraw-function #'sp-org-lint-fn--render))

(defun sp-org-lint-fn--report-mode ()
  "The report mode `sp-batch-report-interface' picks."
  (if (sp-batch-report-new-p) 'sp-org-lint-fn-batch-mode 'sp-org-lint-fn-report-mode))

(defun sp-org-lint-fn-visit ()
  "Visit the file and line of the report line at point."
  (interactive)
  (let ((file (get-text-property (line-beginning-position) 'sp-file))
        (line (get-text-property (line-beginning-position) 'sp-line)))
    (unless file (user-error "No file on this line"))
    (find-file-other-window file)
    (goto-char (point-min))
    (forward-line (1- (or line 1)))))

(defun sp-org-lint-fn--shown-p (plan)
  "Non-nil when PLAN has anything to report."
  (or (plist-get plan :moves) (plist-get plan :orphans)
      (plist-get plan :dangling) (plist-get plan :conflicts)
      (plist-get plan :error)))

(defun sp-org-lint-fn--plan-item (plan)
  "The report item of PLAN, for `sp-batch-report-text'."
  (let ((file (plist-get plan :file)))
    (cl-flet ((at (line text)
                (concat (sp-batch-report-file-link file (format "line %d" line) line) ": " text)))
      (list :text ""
            :file file :label (abbreviate-file-name file)
            :children
            (append
             (when-let* ((err (plist-get plan :error))) (list (format "error: %s" err)))
             (mapcar (lambda (m)
                       (at (plist-get m :line)
                           (format "[fn:%s] %s -> %s%s"
                                   (plist-get m :label) (plist-get m :from) (plist-get m :to)
                                   (if (equal (plist-get m :new) (plist-get m :label))
                                       ""
                                     (format " (as [fn:%s])" (plist-get m :new))))))
                     (plist-get plan :moves))
             (mapcar (lambda (l) (format "orphan: [fn:%s] is defined and never cited" l))
                     (plist-get plan :orphans))
             (mapcar (lambda (l) (format "dangling: [fn:%s] is cited and never defined" l))
                     (plist-get plan :dangling))
             (mapcar (lambda (c) (format "left alone: [fn:%s] is %s" (car c) (cdr c)))
                     (plist-get plan :conflicts))
             (mapcar (lambda (title) (format "the empty \"%s\" heading would be removed" title))
                     (plist-get plan :removed)))))))

(defun sp-org-lint-fn--batch-text ()
  "The whole report, as Org text, from the state of the run."
  (let* ((plans (reverse (sp-org-lint-fn--get :plans)))
         (results (reverse (sp-org-lint-fn--get :results)))
         (shown (seq-filter #'sp-org-lint-fn--shown-p
                            (mapcar (lambda (p)
                                      ;; What was applied is no longer pending.
                                      (if (seq-some (lambda (r) (and (eq (plist-get r :status) 'written)
                                                                     (equal (plist-get r :file)
                                                                            (plist-get p :file))))
                                                    results)
                                          (plist-put (plist-put (copy-sequence p) :moves nil) :removed nil)
                                        p))
                                    plans))))
    (sp-batch-report-text
     "Footnote lint"
     (append
      (when results
        (list (sp-batch-report-section
               (format "Applied (backups are in %s)"
                       (abbreviate-file-name (or (sp-org-lint-fn--get :backup-root) "")))
               (mapcar (lambda (r)
                         (list :text (if (eq (plist-get r :status) 'written)
                                         (format "written (%d move(s)); backup %s"
                                                 (plist-get r :moves)
                                                 (abbreviate-file-name (plist-get r :backup)))
                                       (format "skipped (%s)" (plist-get r :reason)))
                               :file (plist-get r :file) :label (abbreviate-file-name (plist-get r :file))
                               :key nil))
                       results))))
      (list (sp-batch-report-section "Files with footnotes to look at"
                                     (mapcar #'sp-org-lint-fn--plan-item shown))))
     :intro (sp-org-lint-fn--summary)
     :excluded sp-batch-report-excluded)))

(defun sp-org-lint-fn--render-batch ()
  "Draw the whole report in the shared view."
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (insert (sp-org-lint-fn--batch-text))
    (outline-show-all)
    (goto-char (point-min))
    (forward-line (1- line))))

(defun sp-org-lint-fn--insert-plan (plan)
  "Insert the report of PLAN at the end of the buffer, in the view of this buffer."
  (if (derived-mode-p 'sp-org-lint-fn-batch-mode)
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char (point-max))
          (insert (sp-batch-report--item-string (sp-org-lint-fn--plan-item plan)))))
    (sp-org-lint-fn--insert-plan-old plan)))

(defun sp-org-lint-fn--insert-plan-old (plan)
  "Insert the report of PLAN at the end of the buffer."
  (let ((file (plist-get plan :file))
        (inhibit-read-only t))
    (save-excursion
      (goto-char (point-max))
      (cl-flet ((line (line text)
                  (insert (propertize (concat "  " text "\n")
                                      'sp-file file 'sp-line line))))
        (insert (propertize (format "* %s\n" (abbreviate-file-name file))
                            'sp-file file 'sp-line 1 'face 'bold))
        (when-let* ((err (plist-get plan :error)))
          (line 1 (format "error: %s" err)))
        (dolist (m (plist-get plan :moves))
          (line (plist-get m :line)
                (format "[fn:%s] %s -> %s%s"
                        (plist-get m :label) (plist-get m :from) (plist-get m :to)
                        (if (equal (plist-get m :new) (plist-get m :label))
                            ""
                          (format " (as [fn:%s])" (plist-get m :new))))))
        (dolist (l (plist-get plan :orphans))
          (line 1 (format "orphan: [fn:%s] is defined and never cited" l)))
        (dolist (l (plist-get plan :dangling))
          (line 1 (format "dangling: [fn:%s] is cited and never defined" l)))
        (dolist (c (plist-get plan :conflicts))
          (line 1 (format "left alone: [fn:%s] is %s" (car c) (cdr c))))
        (dolist (title (plist-get plan :removed))
          (line 1 (format "the empty \"%s\" heading would be removed" title)))
        (insert "\n")))))

(defun sp-org-lint-fn--summary ()
  "Return the summary line of a finished scan."
  (let ((plans (sp-org-lint-fn--get :plans)))
    (format "%d file(s) scanned: %d with footnotes to move (%d move(s)), %d orphan definition(s), %d dangling reference(s), %d error(s).\n"
            (or (sp-org-lint-fn--get :scanned) 0)
            (seq-count (lambda (p) (plist-get p :changed)) plans)
            (apply #'+ (mapcar (lambda (p) (length (plist-get p :moves))) plans))
            (apply #'+ (mapcar (lambda (p) (length (plist-get p :orphans))) plans))
            (apply #'+ (mapcar (lambda (p) (length (plist-get p :dangling))) plans))
            (seq-count (lambda (p) (plist-get p :error)) plans))))

(defun sp-org-lint-fn--render ()
  "Draw the whole report, from the state of the run, in the view of this buffer."
  (if (derived-mode-p 'sp-org-lint-fn-batch-mode)
      (sp-org-lint-fn--render-batch)
    (sp-org-lint-fn--render-old)))

(make-obsolete 'sp-org-lint-fn--render-old 'sp-org-lint-fn--render-batch "2026-11-09")
(make-obsolete 'sp-org-lint-fn--insert-plan-old 'sp-org-lint-fn--plan-item "2026-11-09")

(defun sp-org-lint-fn--render-old ()
  "Draw the whole report in the old view, from the state of the run."
  (let ((inhibit-read-only t)
        (plans (reverse (sp-org-lint-fn--get :plans)))
        (results (reverse (sp-org-lint-fn--get :results))))
    (erase-buffer)
    (insert (propertize "Footnote lint\n" 'face 'bold)
            (sp-org-lint-fn--summary) "\n")
    (when results
      (insert (propertize "Applied\n" 'face 'bold)
              (format "Backups are in %s\n\n"
                      (abbreviate-file-name (sp-org-lint-fn--get :backup-root))))
      (dolist (r results)
        (insert (propertize
                 (if (eq (plist-get r :status) 'written)
                     (format "  written: %s (%d move(s)); backup %s\n"
                             (abbreviate-file-name (plist-get r :file))
                             (plist-get r :moves)
                             (abbreviate-file-name (plist-get r :backup)))
                   (format "  skipped: %s (%s)\n"
                           (abbreviate-file-name (plist-get r :file))
                           (plist-get r :reason)))
                 'sp-file (plist-get r :file) 'sp-line 1)))
      (insert "\n"))
    (dolist (p plans)
      ;; What was applied is no longer pending.
      (when (seq-some (lambda (r) (and (eq (plist-get r :status) 'written)
                                       (equal (plist-get r :file) (plist-get p :file))))
                      results)
        (setq p (plist-put (plist-put (copy-sequence p) :moves nil) :removed nil)))
      (when (sp-org-lint-fn--shown-p p)
        (sp-org-lint-fn--insert-plan p)))
    (goto-char (point-min))))

(defun sp-org-lint-fn--handle (item)
  "Handle one result ITEM from the worker."
  (unless (plist-get item :done)
    (sp-org-lint-fn--set :done (1+ (or (sp-org-lint-fn--get :done) 0)))
    (if (eq (sp-org-lint-fn--get :phase) 'scan)
        (progn
          (sp-org-lint-fn--set :plans (cons item (sp-org-lint-fn--get :plans)))
          (when (sp-org-lint-fn--shown-p item)
            (sp-org-lint-fn--insert-plan item)))
      (sp-org-lint-fn--set :results (cons item (sp-org-lint-fn--get :results))))
    (force-mode-line-update)))

(defun sp-org-lint-fn--filter (buffer proc string)
  "Process filter: handle the complete lines of STRING in BUFFER."
  (if (not (buffer-live-p buffer))
      (delete-process proc)
    (with-current-buffer buffer
      (let ((data (concat (sp-org-lint-fn--get :partial) string))
            (start 0))
        (while (string-match "\n" data start)
          (let ((line (substring data start (match-beginning 0))))
            (setq start (match-end 0))
            (when (string-prefix-p "SPLINT " line)
              (sp-org-lint-fn--handle
               (car (read-from-string (substring line 7)))))))
        (sp-org-lint-fn--set :partial (substring data start))))))

(defun sp-org-lint-fn--sync-vulpea (files)
  "Ask vulpea to re-read FILES, one per idle moment."
  (when (and files (fboundp 'vulpea-db-update-file))
    (ignore-errors (vulpea-db-update-file (car files)))
    (when (cdr files)
      (run-with-idle-timer 0.2 nil #'sp-org-lint-fn--sync-vulpea (cdr files)))))

(defun sp-org-lint-fn--finish-apply ()
  "After an apply: refresh the buffers and the database for the written files."
  (let ((written (mapcar (lambda (r) (plist-get r :file))
                         (seq-filter (lambda (r) (eq (plist-get r :status) 'written))
                                     (sp-org-lint-fn--get :results)))))
    (dolist (f written)
      (when-let* ((b (find-buffer-visiting f)))
        (unless (buffer-modified-p b)
          (with-current-buffer b (revert-buffer t t t)))))
    (sp-org-lint-fn--sync-vulpea written)))

(defun sp-org-lint-fn--sentinel (buffer proc _event)
  "Process sentinel: finish the run in BUFFER when PROC has exited."
  (unless (process-live-p proc)
    (let ((err (process-get proc 'stderr))
          (ctl (process-get proc 'control-file)))
      (when ctl (ignore-errors (delete-file ctl)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (let ((failed (not (zerop (process-exit-status proc)))))
            (when (eq (sp-org-lint-fn--get :phase) 'apply)
              (sp-org-lint-fn--finish-apply))
            (sp-org-lint-fn--set :phase (cond (failed 'failed)
                                              ((eq (sp-org-lint-fn--get :phase) 'apply) 'applied)
                                              (t 'ready)))
            (sp-org-lint-fn--render)
            (when failed
              (let ((inhibit-read-only t))
                (goto-char (point-max))
                (insert "The worker Emacs failed:\n"
                        (if (buffer-live-p err)
                            (with-current-buffer err (buffer-string))
                          "")))))))
      (when (buffer-live-p err) (kill-buffer err)))))

(defun sp-org-lint-fn--start (phase files extra)
  "Start the worker for PHASE (`scan' or `apply') on FILES in this buffer.
EXTRA is a plist merged into the control file."
  (unless (and sp-org-lint--library (file-exists-p sp-org-lint--library))
    (user-error "Cannot find sp-org-lint-footnotes.el to load in the worker Emacs"))
  (let* ((buffer (current-buffer))
         (ctl (make-temp-file "sp-org-lint-" nil ".eld"))
         (err (generate-new-buffer " *sp-org-lint stderr*"))
         proc)
    (with-temp-file ctl
      (let ((print-length nil) (print-level nil))
        (prin1 (append (list :mode (if (eq phase 'scan) 'plan 'apply)
                             :files files)
                       extra)
               (current-buffer))))
    (setq proc (make-process
                :name "sp-org-lint-footnotes"
                :buffer nil
                :command (list (expand-file-name invocation-name
                                                 invocation-directory)
                               "-Q" "--batch"
                               "-L" (file-name-directory sp-org-lint--library)
                               "-l" sp-org-lint--library
                               "--eval"
                               (format "(sp-org-lint-fn--batch %S)" ctl))
                :connection-type 'pipe
                :coding 'utf-8-unix
                :noquery t
                :stderr err
                :filter (lambda (p s) (sp-org-lint-fn--filter buffer p s))
                :sentinel (lambda (p e) (sp-org-lint-fn--sentinel buffer p e))))
    (process-put proc 'control-file ctl)
    (process-put proc 'stderr err)
    (sp-org-lint-fn--set :process proc)
    (sp-org-lint-fn--set :phase phase)
    (when (eq phase 'scan)
      (sp-org-lint-fn--set :scanned (length files)))
    (sp-org-lint-fn--set :total (length files))
    (sp-org-lint-fn--set :done 0)
    (sp-org-lint-fn--set :partial "")))

(defun sp-org-lint-fn--stop ()
  "Stop the worker of this report buffer, if it runs."
  (let ((proc (sp-org-lint-fn--get :process)))
    (when (process-live-p proc)
      (set-process-sentinel proc nil)
      (delete-process proc)
      (when-let* ((ctl (process-get proc 'control-file)))
        (ignore-errors (delete-file ctl))))))

;;;###autoload
(defun sp-org-lint-footnotes-dryrun (&optional dir)
  "Scan the vault for footnotes to move into the section that cites them.
Footnote definitions in a trailing `Footnotes' heading are planned to
move to the end of the text of the heading that contains their
reference.  A second Emacs does the work, so this one stays usable; the
report fills in as files are read, and nothing is changed until you
press \\<sp-org-lint-fn-report-mode-map>\\[sp-org-lint-footnotes-convert] in the report.  With a prefix argument, ask for a folder
instead of using the vulpea database."
  (interactive (list (when current-prefix-arg
                       (read-directory-name "Lint footnotes under: "
                                            sp-org-lint-fn-directory))))
  (let ((buffer (get-buffer-create sp-org-lint-fn--buffer-name))
        (files (if dir
                   (sp-org-lint-fn--org-files
                    (directory-files-recursively dir "\\.org\\'") dir)
                 (funcall sp-org-lint-fn-files-function))))
    (unless files (user-error "No Org files to lint"))
    (with-current-buffer buffer
      (sp-org-lint-fn--stop)
      (unless (eq major-mode (sp-org-lint-fn--report-mode))
        (funcall (sp-org-lint-fn--report-mode)))
      (setq sp-org-lint-fn--run nil)
      (when (derived-mode-p 'sp-org-lint-fn-batch-mode)
        (setq sp-batch-report-refresh-function (lambda () (sp-org-lint-footnotes-dryrun))))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if (derived-mode-p 'sp-org-lint-fn-batch-mode)
            (insert "#+title: Footnote lint\n\n"
                    (format "Reading %d file(s) in a second Emacs; nothing is changed.\n\n* Files with footnotes to look at\n"
                            (length files)))
          (insert (propertize "Footnote lint\n" 'face 'bold)
                  (format "Reading %d file(s) in a second Emacs; nothing is changed.\n\n"
                          (length files)))))
      (sp-org-lint-fn--start 'scan files nil))
    (display-buffer buffer)
    (message "Linting footnotes of %d file(s) in the background" (length files))))


;;;###autoload
(defun sp-org-lint-footnotes-convert ()
  "Apply the moves of the footnote lint shown in this report buffer.
Every file is copied to `sp-org-lint-fn-backup-directory' first.  Files
that are open with unsaved changes, or that changed since the scan,
are skipped.  The work is done by a second Emacs."
  (interactive)
  (unless (or (derived-mode-p 'sp-org-lint-fn-report-mode)
              (derived-mode-p 'sp-org-lint-fn-batch-mode))
    (user-error "Run this in the footnote lint report"))
  (unless (eq (sp-org-lint-fn--get :phase) 'ready)
    (user-error "The scan has not finished"))
  (let* ((plans (seq-filter (lambda (p) (and (plist-get p :changed)
                                             (not (member (plist-get p :file)
                                                          sp-batch-report-excluded))))
                            (sp-org-lint-fn--get :plans)))
         (busy (seq-filter (lambda (p)
                             (when-let* ((b (find-buffer-visiting
                                             (plist-get p :file))))
                               (buffer-modified-p b)))
                           plans))
         (plans (seq-difference plans busy))
         (root (expand-file-name (format-time-string "%Y%m%d-%H%M%S/")
                                 sp-org-lint-fn-backup-directory)))
    (unless plans (user-error "Nothing to apply"))
    (when (yes-or-no-p
           (format "Move footnotes in %d file(s)%s? Copies go to %s "
                   (length plans)
                   (if busy (format " (%d open with unsaved changes are left out)"
                                    (length busy))
                     "")
                   (abbreviate-file-name root)))
      (sp-org-lint-fn--set :results nil)
      (sp-org-lint-fn--set :backup-root root)
      (sp-org-lint-fn--start 'apply
                             (mapcar (lambda (p)
                                       (cons (plist-get p :file) (plist-get p :sha)))
                                     plans)
                             (list :backup-root root)))))

(provide 'sp-org-lint-footnotes)
;;; sp-org-lint-footnotes.el ends here
