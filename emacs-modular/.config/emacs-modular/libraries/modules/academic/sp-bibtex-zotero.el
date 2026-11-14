;;; sp-bibtex-zotero.el --- Move the Zotero attachments of a .bib file into the literature folder -*- lexical-binding: t; -*-

;;; Commentary:

;; Finds the PDFs that the Zotero paths of `file' fields point to in
;; literature/inbox/zotero-backup, moves them to the top of the literature folder
;; (through DEVONthink, so records keep their tags and highlights) and rewrites the
;; field.  A dry run, an apply and a restore, like the other lint groups.
;; Literate source: docs/tangles/academic/sp-bibtex-zotero.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'ucs-normalize)
(require 'ol)
(require 'sp-batch-report)

;; Provided by sp-bibprocess, which is loaded before this file in the configuration.
(defvar sp-literature-dir)
(defvar sp-bibtex-files-devonthink-tool)
(defvar sp-bibtex-lint-backup-directory)
(declare-function sp-bibtex-files--move "sp-bibprocess")
(declare-function sp-bibtex-files--call-tool "sp-bibprocess")
(declare-function sp-bibtex-lint--backup "sp-bibprocess")
(declare-function sp-bibtex-lint--read-file "sp-bibprocess")
(declare-function sp-bibtex-lint--unsaved-check "sp-bibprocess")

(defgroup sp-bibtex-zotero nil
  "Move Zotero attachments of .bib files into the literature folder."
  :group 'sp-bibtex)

(defcustom sp-bibtex-zotero-backup-directory "inbox/zotero-backup"
  "The folder with the Zotero storage folders, relative to `sp-literature-dir'."
  :type 'string
  :group 'sp-bibtex-zotero)

(defcustom sp-bibtex-zotero-key-regexp "[A-Z0-9]\\{8\\}"
  "Regular expression for the name of a Zotero storage folder."
  :type 'regexp
  :group 'sp-bibtex-zotero)

(defcustom sp-bibtex-zotero-extensions '("pdf")
  "File extensions (lower case) of the attachments to move; others are left alone."
  :type '(repeat string)
  :group 'sp-bibtex-zotero)

(defcustom sp-bibtex-zotero-check-devonthink t
  "Non-nil: the dry run asks the DEVONthink tool what it would do with the moves."
  :type 'boolean
  :group 'sp-bibtex-zotero)

(defcustom sp-bibtex-zotero-require-devonthink t
  "Non-nil: do not apply or restore unless DEVONthink can move the records.
That needs `sp-bibtex-files-devonthink-tool' and a running DEVONthink.  Nil lets
the files be renamed on disk, which DEVONthink sees as missing files."
  :type 'boolean
  :group 'sp-bibtex-zotero)

(defcustom sp-bibtex-zotero-devonthink-processes '("DEVONthink" "DEVONthink 3")
  "Process names that mean DEVONthink is running."
  :type '(repeat string)
  :group 'sp-bibtex-zotero)

;;;; Reading the file fields

(defun sp-bibtex-zotero--scan ()
  "The `file' fields of the entries in the current buffer.
Each is (KEY LINE VSTART VEND VALUE): the entry key, the line of the entry, the
bounds of the text between the braces and that text."
  (let ((case-fold-search t) (line 1) (last (point-min)) heads result)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*@[[:alpha:]]+[ \t]*[{(][ \t\n]*\\([^, \t\n]+\\)[ \t]*," nil t)
        (push (list (match-string-no-properties 1) (match-beginning 0) (match-end 0)) heads))
      (setq heads (nreverse heads))
      (while heads
        (pcase-let* ((`(,key ,beg ,hend) (pop heads))
                     (end (if heads (nth 1 (car heads)) (point-max))))
          (goto-char hend)
          (when (re-search-forward "^[ \t]*file[ \t]*=[ \t\n]*{" end t)
            (let ((vstart (point)) (depth 1))
              (while (and (> depth 0) (re-search-forward "[{}]" end t))
                (setq depth (+ depth (if (eq (char-before) ?{) 1 -1))))
              (when (zerop depth)
                (cl-incf line (count-lines last beg))
                (setq last beg)
                (push (list key line vstart (1- (point))
                            (buffer-substring-no-properties vstart (1- (point))))
                      result)))))))
    (nreverse result)))

(defun sp-bibtex-zotero--split (value)
  "Split the field VALUE at the semicolons that are not escaped."
  (let ((parts nil) (start 0) (i 0) (n (length value)))
    (while (< i n)
      (pcase (aref value i)
        (?\\ (setq i (+ i 2)))
        (?\; (push (substring value start i) parts)
             (setq i (1+ i) start i))
        (_ (setq i (1+ i)))))
    (push (substring value (min start n)) parts)
    (nreverse parts)))

(defun sp-bibtex-zotero--unescape (text)
  "TEXT without the backslash of an escaped punctuation mark (\\; \\: \\{ \\\\ ...)."
  (replace-regexp-in-string "\\\\\\([^[:alnum:]]\\)" "\\1" text))

(defun sp-bibtex-zotero--parse (raw)
  "The Zotero path in the part RAW of a field: (:key KEY :name NAME), or nil.
RAW is a bare path or `label:path:mime'."
  (let ((text (sp-bibtex-zotero--unescape
               (replace-regexp-in-string "[ \t]*\n[ \t]*" " " (string-trim raw)))))
    (when (string-match
           (concat "\\(?:\\`\\|/\\)Zotero/storage/\\(" sp-bibtex-zotero-key-regexp
                   "\\)/\\(.+?\\)\\(?::[A-Za-z]+/[A-Za-z0-9.+-]+\\)?\\'")
           text)
      (list :key (match-string 1 text) :name (match-string 2 text)))))

;;;; Comparing file names

(defun sp-bibtex-zotero--fold (name)
  "NAME as the file system compares it: NFC, lower case."
  (downcase (ucs-normalize-NFC-string name)))

(defun sp-bibtex-zotero--loose (name)
  "The letters and digits of NAME's stem without accents, then its extension.
It is \"\" when the stem has none (a Greek name, say), so such names never match loosely."
  (let ((stem (replace-regexp-in-string
               "[^a-z0-9]" ""
               (downcase (replace-regexp-in-string
                          "[\u0300-\u036f]" "" (ucs-normalize-NFKD-string (file-name-sans-extension name)))))))
    (if (string-empty-p stem) "" (concat stem "." (downcase (or (file-name-extension name) ""))))))

(defun sp-bibtex-zotero--same-name-p (a b)
  "Non-nil when the file names A and B are the same but for spacing, case, accents or quotes."
  (or (equal (replace-regexp-in-string "[ \t ]+" " " (sp-bibtex-zotero--fold a))
             (replace-regexp-in-string "[ \t ]+" " " (sp-bibtex-zotero--fold b)))
      (let ((loose (sp-bibtex-zotero--loose a)))
        (and (not (string-empty-p loose))
             (equal loose (sp-bibtex-zotero--loose b))))))

(defun sp-bibtex-zotero--ext (name)
  "The extension of NAME in lower case, or \"\"."
  (downcase (or (file-name-extension name) "")))

;;;; The library

(cl-defstruct (sp-bibtex-zotero--ctx (:constructor sp-bibtex-zotero--ctx-create))
  "The library the matching reads: ROOT, BACKUP and what was listed of them."
  root backup
  (listings (make-hash-table :test #'equal))
  names
  (top (make-hash-table :test #'equal))
  (moved (make-hash-table :test #'equal))
  (hashes (make-hash-table :test #'equal)))

(defun sp-bibtex-zotero--visible-files (dir)
  "The names of the files (not folders, not hidden ones) in DIR."
  (seq-remove (lambda (n) (file-directory-p (expand-file-name n dir)))
              (directory-files dir nil "\\`[^.]")))

(defun sp-bibtex-zotero--listing (ctx key)
  "The files in the Zotero folder KEY of CTX, or `:none' when there is no such folder."
  (let ((cache (sp-bibtex-zotero--ctx-listings ctx)))
    (or (gethash key cache)
        (puthash key
                 (let ((dir (expand-file-name key (sp-bibtex-zotero--ctx-backup ctx))))
                   (if (file-directory-p dir)
                       (or (sp-bibtex-zotero--visible-files dir) :empty)
                       :none))
                 cache))))

(defun sp-bibtex-zotero--files-of (ctx key)
  "The list of files in the Zotero folder KEY of CTX; nil when empty, `:none' when missing."
  (let ((l (sp-bibtex-zotero--listing ctx key)))
    (if (eq l :empty) nil l)))

(defun sp-bibtex-zotero--names (ctx)
  "A hash table from loose name to the \"KEY/NAME\" paths of the whole backup of CTX."
  (or (sp-bibtex-zotero--ctx-names ctx)
      (let ((table (make-hash-table :test #'equal))
            (backup (sp-bibtex-zotero--ctx-backup ctx)))
        (dolist (key (directory-files backup nil "\\`[^.]"))
          (let ((files (and (file-directory-p (expand-file-name key backup))
                            (sp-bibtex-zotero--files-of ctx key))))
            (when (listp files)
              (dolist (name files)
                (let ((loose (sp-bibtex-zotero--loose name)))
                  (unless (string-empty-p loose)
                    (push (concat key "/" name) (gethash loose table))))))))
        (setf (sp-bibtex-zotero--ctx-names ctx) table))))

(defun sp-bibtex-zotero--read-moves (ctx)
  "Fill the moved table of CTX from the manifests and move logs of earlier runs."
  (let ((dir (and (boundp 'sp-bibtex-lint-backup-directory) sp-bibtex-lint-backup-directory))
        (table (sp-bibtex-zotero--ctx-moved ctx)))
    (when (and dir (file-directory-p dir))
      (dolist (log (directory-files dir t "\\`files-moves-.*\\.tsv\\'"))
        (with-temp-buffer
          (insert-file-contents log)
          (dolist (line (split-string (buffer-string) "\n" t))
            (pcase (split-string line "\t")
              (`(,from ,to) (puthash from to table))))))
      (dolist (manifest (directory-files-recursively dir "\\`zotero-manifest\\.eld\\'"))
        (dolist (move (plist-get (sp-bibtex-zotero--read-manifest manifest) :moves))
          (puthash (car move) (cdr move) table))))))

(defun sp-bibtex-zotero--context (&optional root)
  "The context for ROOT, `sp-literature-dir' by default; a `user-error' when it is no folder."
  (let ((root (file-name-as-directory
               (expand-file-name (or root (and (boundp 'sp-literature-dir) sp-literature-dir)
                                     (user-error "`sp-literature-dir' is not set"))))))
    (unless (file-directory-p root)
      (user-error "`sp-literature-dir' is not a folder: %s" root))
    (let* ((backup (file-name-as-directory (expand-file-name sp-bibtex-zotero-backup-directory root)))
           (ctx (sp-bibtex-zotero--ctx-create :root root :backup backup)))
      (unless (file-directory-p backup)
        (user-error "No Zotero backup folder: %s" backup))
      (dolist (name (sp-bibtex-zotero--visible-files root))
        (puthash (sp-bibtex-zotero--fold name) name (sp-bibtex-zotero--ctx-top ctx)))
      (sp-bibtex-zotero--read-moves ctx)
      ctx)))

;;;; Matching one path

(defun sp-bibtex-zotero--match (key name ctx)
  "Match the Zotero path KEY/NAME to a file of the backup of CTX.
Return (:status STATUS :from PATH :candidates LIST).  See the doc for the statuses."
  (let* ((backup (sp-bibtex-zotero--ctx-backup ctx))
         (wanted (expand-file-name name (expand-file-name key backup)))
         (files (sp-bibtex-zotero--files-of ctx key))
         (logged (gethash wanted (sp-bibtex-zotero--ctx-moved ctx))))
    (cond
     ((and logged (not (file-exists-p wanted)) (file-exists-p logged))
      (list :status 'moved-before :to logged))
     ((eq files :none)
      (let ((found (gethash (sp-bibtex-zotero--loose name) (sp-bibtex-zotero--names ctx))))
        (cond ((and found (null (cdr found)))
               (list :status 'by-name :from (expand-file-name (car found) backup)))
              (found (list :status 'ambiguous :candidates (sort (copy-sequence found) #'string<)))
              (t (list :status 'no-dir)))))
     ((member name files) (list :status 'exact :from wanted))
     (t
      (let ((same (seq-filter (lambda (f) (sp-bibtex-zotero--same-name-p f name)) files))
            (ext (sp-bibtex-zotero--ext name)))
        (if same
            (if (cdr same)
                (list :status 'ambiguous :candidates same)
              (list :status 'normalised :from (expand-file-name (car same) (file-name-directory wanted))))
          (let ((kind (seq-filter (lambda (f) (or (string-empty-p ext)
                                                  (equal ext (sp-bibtex-zotero--ext f))))
                                  files)))
            (cond ((null kind) (list :status 'no-file))
                  ((cdr kind) (list :status 'ambiguous :candidates kind))
                  (t (list :status 'by-dir
                           :from (expand-file-name (car kind) (file-name-directory wanted))))))))))))

;;;; Planning

(cl-defstruct (sp-bibtex-zotero--item (:constructor sp-bibtex-zotero--item-create))
  "One part of a file field."
  entry-key line raw zkey name status from to class why (strength 'strong) dropped)

(cl-defstruct (sp-bibtex-zotero--ent (:constructor sp-bibtex-zotero--ent-create))
  "One entry with a file field: its VSTART, VEND, VALUE and ITEMS."
  key line vstart vend value items)

(cl-defstruct (sp-bibtex-zotero--plan (:constructor sp-bibtex-zotero--plan-create))
  "The plan for FILE: its ENTS, the CTX it was made in, the file's HASH."
  file ents ctx hash)

(defun sp-bibtex-zotero--file-hash (file)
  "The SHA-256 of the contents of FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun sp-bibtex-zotero--same-content-p (a b ctx)
  "Non-nil when the files A and B have the same size and SHA-256."
  (and (= (file-attribute-size (file-attributes a)) (file-attribute-size (file-attributes b)))
       (let ((hashes (sp-bibtex-zotero--ctx-hashes ctx)))
         (equal (or (gethash a hashes) (puthash a (sp-bibtex-zotero--file-hash a) hashes))
                (or (gethash b hashes) (puthash b (sp-bibtex-zotero--file-hash b) hashes))))))

(defun sp-bibtex-zotero--unsafe-name-p (name)
  "Non-nil when NAME cannot be written in a file field."
  (or (string-match-p "[;{}:\\\n\t]" name)
      (string-match-p "\\`[ \t]\\|[ \t]\\'" name)))

(defun sp-bibtex-zotero--make-item (entry-key line raw ctx)
  "The item for the part RAW of the entry ENTRY-KEY at LINE, matched in CTX."
  (let* ((parsed (sp-bibtex-zotero--parse raw))
         (item (sp-bibtex-zotero--item-create :entry-key entry-key :line line :raw raw)))
    (if (null parsed)
        (setf (sp-bibtex-zotero--item-class item) 'other)
      (let* ((key (plist-get parsed :key)) (name (plist-get parsed :name)))
        (setf (sp-bibtex-zotero--item-zkey item) key
              (sp-bibtex-zotero--item-name item) name)
        (if (not (member (sp-bibtex-zotero--ext name)
                         (append sp-bibtex-zotero-extensions '(""))))
            (setf (sp-bibtex-zotero--item-class item) 'skip
                  (sp-bibtex-zotero--item-status item) (sp-bibtex-zotero--ext name))
          (let* ((m (sp-bibtex-zotero--match key name ctx))
                 (status (plist-get m :status)))
            (setf (sp-bibtex-zotero--item-status item) status
                  (sp-bibtex-zotero--item-from item) (plist-get m :from))
            (pcase status
              ('moved-before
               (setf (sp-bibtex-zotero--item-to item) (plist-get m :to)
                     (sp-bibtex-zotero--item-class item) 'link
                     (sp-bibtex-zotero--item-why item) "moved by an earlier run"))
              ((or 'exact 'normalised)
               (setf (sp-bibtex-zotero--item-class item) 'move))
              ((or 'by-dir 'by-name)
               (setf (sp-bibtex-zotero--item-class item) 'review
                     (sp-bibtex-zotero--item-strength item) 'weak))
              (_
               (setf (sp-bibtex-zotero--item-class item) 'problem
                     (sp-bibtex-zotero--item-why item)
                     (pcase status
                       ('no-dir "no folder in the backup and no file of that name")
                       ('no-file "the folder has no file of that type (Zotero caches only)")
                       ('ambiguous (format "several files could be meant: %s"
                                           (string-join (plist-get m :candidates) ", ")))
                       (_ (symbol-name status))))))))))
    item))

(defun sp-bibtex-zotero--resolve (items ctx)
  "Decide the destination of ITEMS that have a source, all together, in CTX."
  (let ((root (sp-bibtex-zotero--ctx-root ctx))
        (top (sp-bibtex-zotero--ctx-top ctx))
        (groups (make-hash-table :test #'equal)) order)
    (dolist (it items)
      (when (and (sp-bibtex-zotero--item-from it)
                 (memq (sp-bibtex-zotero--item-class it) '(move review)))
        (let ((base (file-name-nondirectory (sp-bibtex-zotero--item-from it))))
          (if (sp-bibtex-zotero--unsafe-name-p base)
              (setf (sp-bibtex-zotero--item-class it) 'problem
                    (sp-bibtex-zotero--item-status it) 'unsafe-name
                    (sp-bibtex-zotero--item-why it) (format "the name %s cannot be written in a file field" base))
            (let ((fold (sp-bibtex-zotero--fold base)))
              (unless (gethash fold groups) (push fold order))
              (push it (gethash fold groups)))))))
    (dolist (fold (nreverse order))
      (let* ((its (nreverse (gethash fold groups)))
             (existing (gethash fold top))
             (froms (delete-dups (mapcar #'sp-bibtex-zotero--item-from its)))
             (mover (sp-bibtex-zotero--item-from
                     (or (seq-find (lambda (i) (eq (sp-bibtex-zotero--item-strength i) 'strong)) its)
                         (car its))))
             (dest (expand-file-name (or existing (file-name-nondirectory mover)) root)))
        (cond
         (existing
          (dolist (it its)
            (if (sp-bibtex-zotero--same-content-p (sp-bibtex-zotero--item-from it) dest ctx)
                (sp-bibtex-zotero--set-link it dest 'identical "the same file is already in the library")
              (sp-bibtex-zotero--set-problem
               it 'collision (format "a different file called %s is already in the library" existing)))))
         ((and (cdr froms)
               (not (seq-every-p (lambda (f) (sp-bibtex-zotero--same-content-p f mover ctx)) froms)))
          (dolist (it its)
            (sp-bibtex-zotero--set-problem
             it 'collision (format "%d different files would be called %s"
                                   (length froms) (file-name-nondirectory mover)))))
         (t
          (dolist (it its)
            (setf (sp-bibtex-zotero--item-to it) dest)
            (unless (equal (sp-bibtex-zotero--item-from it) mover)
              (sp-bibtex-zotero--set-link it dest 'duplicate "the same file as another entry's")))))))
    items))

(defun sp-bibtex-zotero--set-link (item dest status why)
  "Make ITEM a rewrite-only item that points to DEST; keep a weak item for review."
  (setf (sp-bibtex-zotero--item-to item) dest
        (sp-bibtex-zotero--item-status item) status
        (sp-bibtex-zotero--item-why item) why)
  (when (eq (sp-bibtex-zotero--item-strength item) 'strong)
    (setf (sp-bibtex-zotero--item-class item) 'link)))

(defun sp-bibtex-zotero--set-problem (item status why)
  "Make ITEM a problem with STATUS and WHY."
  (setf (sp-bibtex-zotero--item-class item) 'problem
        (sp-bibtex-zotero--item-status item) status
        (sp-bibtex-zotero--item-why item) why
        (sp-bibtex-zotero--item-to item) nil))

(defvar sp-bibtex-zotero--excluded)

(defun sp-bibtex-zotero--plan (file &optional ctx)
  "The plan for the .bib FILE, in CTX (made from `sp-literature-dir' by default)."
  (let* ((ctx (or ctx (sp-bibtex-zotero--context)))
         (hash (sp-bibtex-zotero--file-hash file))
         (ents (with-temp-buffer
                 (insert-file-contents file)
                 (mapcar
                  (lambda (f)
                    (pcase-let ((`(,key ,line ,vstart ,vend ,value) f))
                      (sp-bibtex-zotero--ent-create
                       :key key :line line :vstart vstart :vend vend :value value
                       :items (mapcar (lambda (raw) (sp-bibtex-zotero--make-item key line raw ctx))
                                      (sp-bibtex-zotero--split value)))))
                  (sp-bibtex-zotero--scan)))))
    (sp-bibtex-zotero--resolve
     (apply #'append (mapcar #'sp-bibtex-zotero--ent-items ents)) ctx)
    (dolist (it (seq-filter #'sp-bibtex-zotero--item-zkey
                            (apply #'append (mapcar #'sp-bibtex-zotero--ent-items ents))))
      (when (member (sp-bibtex-zotero--item-key file it) sp-bibtex-zotero--excluded)
        (setf (sp-bibtex-zotero--item-dropped it) t)))
    (sp-bibtex-zotero--plan-create
     :file file :ctx ctx :hash hash
     :ents (seq-filter (lambda (e) (seq-some #'sp-bibtex-zotero--item-zkey (sp-bibtex-zotero--ent-items e)))
                       ents))))

(defun sp-bibtex-zotero--items (plan)
  "All the items of PLAN that are Zotero paths."
  (seq-filter #'sp-bibtex-zotero--item-zkey
              (apply #'append (mapcar #'sp-bibtex-zotero--ent-items (sp-bibtex-zotero--plan-ents plan)))))

(defun sp-bibtex-zotero--applied-p (item weak)
  "Non-nil when ITEM is carried out: a move or a link, or with WEAK a weak match too."
  (and (not (sp-bibtex-zotero--item-dropped item))
       (or (memq (sp-bibtex-zotero--item-class item) '(move link))
           (and weak (eq (sp-bibtex-zotero--item-class item) 'review)
                (sp-bibtex-zotero--item-to item)))))

(defun sp-bibtex-zotero--moves (plan weak)
  "The moves (FROM . TO) of PLAN, each once; with WEAK the weak matches too."
  (let (moves)
    (dolist (it (sp-bibtex-zotero--items plan))
      (when (and (sp-bibtex-zotero--applied-p it weak)
                 (sp-bibtex-zotero--item-from it)
                 (sp-bibtex-zotero--item-to it)
                 (not (memq (sp-bibtex-zotero--item-status it) '(identical duplicate moved-before))))
        (cl-pushnew (cons (sp-bibtex-zotero--item-from it) (sp-bibtex-zotero--item-to it))
                    moves :test #'equal)))
    (nreverse moves)))

;;;; The new field value

(defun sp-bibtex-zotero--new-value (ent done-p)
  "The value of the file field of ENT with the items for which DONE-P holds rewritten."
  (let (out)
    (dolist (it (sp-bibtex-zotero--ent-items ent))
      (if (and (sp-bibtex-zotero--item-zkey it) (funcall done-p it))
          (let ((base (file-name-nondirectory (sp-bibtex-zotero--item-to it))))
            (unless (member base out) (push base out)))
        (push (sp-bibtex-zotero--item-raw it) out)))
    (string-join (nreverse out) ";")))

;;;; DEVONthink

(defun sp-bibtex-zotero--devonthink-running-p ()
  "Non-nil when DEVONthink is running.  It does not start it."
  (and (executable-find "pgrep")
       (seq-some (lambda (name) (eq 0 (call-process "pgrep" nil nil nil "-x" name)))
                 sp-bibtex-zotero-devonthink-processes)))

(defun sp-bibtex-zotero--check-devonthink ()
  "Signal a `user-error' when DEVONthink cannot move the records.
Only when `sp-bibtex-zotero-require-devonthink' is non-nil."
  (when sp-bibtex-zotero-require-devonthink
    (unless (and sp-bibtex-files-devonthink-tool
                 (file-readable-p (expand-file-name sp-bibtex-files-devonthink-tool)))
      (user-error "`sp-bibtex-files-devonthink-tool' is not set to devonthink-move.py; nothing was changed"))
    (unless (sp-bibtex-zotero--devonthink-running-p)
      (user-error "DEVONthink is not running; open it and run this again (nothing was changed)"))))

(defun sp-bibtex-zotero--write-moves (moves file)
  "Write MOVES, (FROM . TO) pairs, to FILE as the tab separated lines the tool reads."
  (write-region (mapconcat (lambda (m) (format "%s\t%s\n" (car m) (cdr m))) moves "")
                nil file nil 'silent))

(defun sp-bibtex-zotero--devonthink-lines (moves)
  "Lines for the report about what DEVONthink would do with MOVES."
  (cond
   ((null moves) nil)
   ((not (and sp-bibtex-files-devonthink-tool
              (file-readable-p (expand-file-name sp-bibtex-files-devonthink-tool))))
    (list (if sp-bibtex-zotero-require-devonthink
              "DEVONthink: =sp-bibtex-files-devonthink-tool= is not set, so applying is refused."
            "DEVONthink: no tool is set; the files would be renamed on disk and DEVONthink would lose them.")))
   ((not (sp-bibtex-zotero--devonthink-running-p))
    (list "DEVONthink is not running, so its records were not checked and applying is refused. Open it and press =g=."))
   ((not sp-bibtex-zotero-check-devonthink) nil)
   (t
    (let ((list (make-temp-file "sp-bibtex-zotero" nil ".tsv")))
      (unwind-protect
          (progn
            (sp-bibtex-zotero--write-moves moves list)
            (let* ((done (sp-bibtex-files--call-tool (list "move" "--json" "--moves" list)))
                   (report (and (eq (car done) 0)
                                (ignore-errors (json-parse-string (cdr done) :object-type 'alist)))))
              (if (null report)
                  (list (format "DEVONthink check failed: %s" (truncate-string-to-width (cdr done) 200)))
                (list (format "DEVONthink: %d records would be moved (tags and highlights stay), %d files are not in DEVONthink (moved on disk), %d blocked, %d already moved."
                              (+ (or (alist-get 'to_move report) 0) (or (alist-get 'to_rename report) 0))
                              (or (alist-get 'plain report) 0)
                              (length (alist-get 'blocked report))
                              (or (alist-get 'done report) 0))))))
        (delete-file list))))))

;;;; The report

(defvar sp-bibtex-zotero--excluded nil
  "Rows dropped from the plan with `d', as keys \"FILE::ENTRY::ZOTERO-PATH\".
The list lasts for the Emacs session; `u' in the report brings a row back.")

(defun sp-bibtex-zotero--item-key (file item)
  "The key that drops the ITEM of the plan for FILE."
  (format "%s::%s::%s" (expand-file-name file)
          (sp-bibtex-zotero--item-entry-key item) (sp-bibtex-zotero--zpath item)))

(defun sp-bibtex-zotero--zpath (it)
  "The Zotero path of the item IT, as the report shows it."
  (concat (sp-bibtex-zotero--item-zkey it) "/" (sp-bibtex-zotero--item-name it)))

(defconst sp-bibtex-zotero--status-labels
  '((exact . "exact name") (normalised . "same name (case, spacing or accents differ)")
    (by-dir . "only file of that type in the folder, name differs")
    (by-name . "no folder; the only file of that name in the backup")
    (identical . "identical file already in the library") (duplicate . "same file as another entry")
    (moved-before . "moved by an earlier run"))
  "What the report says for each match status.")

(defun sp-bibtex-zotero--label (it)
  "The words for the match status of the item IT."
  (or (alist-get (sp-bibtex-zotero--item-status it) sp-bibtex-zotero--status-labels)
      (symbol-name (sp-bibtex-zotero--item-status it))))

(defun sp-bibtex-zotero--button (kind file label)
  "The Org link that runs KIND on FILE, labelled LABEL."
  (org-link-make-string (format "sp-bibtex-zotero:%s:%s" kind file) label))

(defun sp-bibtex-zotero--rows (file plan class cells)
  "The report items of the items of PLAN of CLASS (a symbol or a list), for FILE.
CELLS gives the cells of a row after the entry key."
  (let ((classes (ensure-list class)))
    (mapcar (lambda (it)
              (sp-batch-report-item
               nil :row (cons (sp-bibtex-zotero--item-entry-key it) (funcall cells it))
               :file file :line (sp-bibtex-zotero--item-line it)
               :key (sp-bibtex-zotero--item-key file it)))
            (seq-filter (lambda (i) (memq (sp-bibtex-zotero--item-class i) classes))
                        (sp-bibtex-zotero--items plan)))))

(defun sp-bibtex-zotero--key-label (key)
  "The text of the dropped KEY in the report."
  (pcase-let ((`(,file ,entry ,zpath) (split-string key "::")))
    (format "%s: %s (%s)" entry zpath (sp-batch-report-file-link file))))

(defun sp-bibtex-zotero--render (file plan &optional excluded)
  "The Org text of the dry run of PLAN for FILE; EXCLUDED are the dropped keys."
  (let* ((items (sp-bibtex-zotero--items plan))
         (ctx (sp-bibtex-zotero--plan-ctx plan))
         (count (lambda (class) (length (seq-filter (lambda (i) (eq (sp-bibtex-zotero--item-class i) class)) items))))
         (moves (sp-bibtex-zotero--moves plan nil))
         (all-moves (sp-bibtex-zotero--moves plan t))
         (skipped (seq-group-by #'sp-bibtex-zotero--item-status
                                (seq-filter (lambda (i) (eq (sp-bibtex-zotero--item-class i) 'skip)) items)))
         (new-name (lambda (it) (file-name-nondirectory (sp-bibtex-zotero--item-to it))))
         (found (lambda (it) (file-relative-name (sp-bibtex-zotero--item-from it)
                                                 (sp-bibtex-zotero--ctx-backup ctx))))
         (dt (sp-bibtex-zotero--devonthink-lines moves)))
    (sp-batch-report-text
     (format "Zotero paths of %s (dry run, nothing changed)" (file-name-nondirectory file))
     (list
      (sp-batch-report-table-section
       "To move" '("Entry" "Zotero path" "Match" "New path")
       (sp-bibtex-zotero--rows
        file plan 'move
        (lambda (it) (list (sp-bibtex-zotero--zpath it) (sp-bibtex-zotero--label it) (funcall new-name it)))))
      (sp-batch-report-table-section
       "Already in the library, only the field changes" '("Entry" "Zotero path" "Why" "New path")
       (sp-bibtex-zotero--rows
        file plan 'link
        (lambda (it) (list (sp-bibtex-zotero--zpath it) (sp-bibtex-zotero--label it) (funcall new-name it)))))
      (sp-batch-report-table-section
       "Review: weak matches, not applied unless asked" '("Entry" "Zotero path" "Found" "Match")
       (sp-bibtex-zotero--rows
        file plan 'review
        (lambda (it) (list (sp-bibtex-zotero--zpath it) (funcall found it) (sp-bibtex-zotero--label it)))))
      (sp-batch-report-table-section
       "Not matched, left as they are" '("Entry" "Zotero path" "Status" "Why")
       (sp-bibtex-zotero--rows
        file plan 'problem
        (lambda (it) (list (sp-bibtex-zotero--zpath it) (symbol-name (sp-bibtex-zotero--item-status it))
                           (sp-bibtex-zotero--item-why it)))))
      (sp-batch-report-section
       "Left alone"
       (mapcar (lambda (g)
                 (sp-batch-report-item
                  (format "%d =.%s= attachments are not handled." (length (cdr g))
                          (if (string-empty-p (car g)) "?" (car g)))))
               skipped)
       "none"))
     :excluded excluded
     :key-label #'sp-bibtex-zotero--key-label
     :intro
     (concat
      (format "- File: %s; the backup is =%s=.\n" (sp-batch-report-file-link file)
              (abbreviate-file-name (sp-bibtex-zotero--ctx-backup ctx)))
      (format "- %d files would move to the top of the library (%d with the weak matches), %d fields would only be rewritten, %d weak matches are for review, %d paths are not matched.\n"
              (length moves) (length all-moves) (funcall count 'link) (funcall count 'review)
              (funcall count 'problem))
      (mapconcat (lambda (l) (concat "- " l "\n")) dt "")
      "- Nothing is deleted and no file is overwritten; the .bib file is copied first and the moves are written to a manifest, so the run can be restored.\n"
      "- =d= drops a row from the plan, =u= brings it back, =A= applies the sure matches.\n"
      (format "- %s, %s, %s\n"
              (sp-bibtex-zotero--button "apply" file (format "apply the sure matches (%d)" (length moves)))
              (sp-bibtex-zotero--button "apply-weak" file (format "apply with the weak matches (%d)" (length all-moves)))
              (sp-bibtex-zotero--button "restore" file "restore a run"))))))

(defun sp-bibtex-zotero--show (file plan excluded)
  "Show the dry run of PLAN for FILE without the EXCLUDED rows."
  (setq sp-bibtex-zotero--excluded excluded)
  (sp-batch-report-open
   "*Zotero paths*" (sp-bibtex-zotero--render file plan excluded)
   :refresh (lambda (&rest _) (sp-bibtex-zotero-dryrun file))
   :redraw (lambda (excl) (sp-bibtex-zotero--show file plan excl))
   :apply (lambda (excl)
            (setq sp-bibtex-zotero--excluded excl)
            (sp-bibtex-zotero-convert file))
   :excluded excluded))

;;;###autoload
(defun sp-bibtex-zotero-dryrun (file)
  "Show what moving the Zotero attachments of the .bib FILE would do.  Nothing is changed.
FILE is the .bib file of the current buffer, or it is read with completion; a
prefix argument always asks.  See `sp-bibtex-zotero-convert' to apply the plan."
  (interactive (list (sp-bibtex-lint--read-file current-prefix-arg)))
  (message "Matching the Zotero paths of %s..." (file-name-nondirectory file))
  (sp-bibtex-zotero--show file (sp-bibtex-zotero--plan file) sp-bibtex-zotero--excluded))

(defun sp-bibtex-zotero--follow (path &optional _arg)
  "Follow the link PATH, \"KIND:FILE\", of a button in the report."
  (unless (string-match "\\`\\([a-z-]+\\):\\(.*\\)\\'" path)
    (user-error "Not a Zotero button: %s" path))
  (let ((file (match-string 2 path)))
    (pcase (match-string 1 path)
      ("apply" (sp-bibtex-zotero-convert file))
      ("apply-weak" (sp-bibtex-zotero-convert file t))
      ("restore" (sp-bibtex-zotero-restore file))
      (other (user-error "Unknown Zotero button: %s" other)))))

(org-link-set-parameters "sp-bibtex-zotero" :follow #'sp-bibtex-zotero--follow)

;;;; Manifest

(defun sp-bibtex-zotero--manifest-file (stamp)
  "The manifest of the run STAMP, next to the copy of the .bib file."
  (expand-file-name (concat stamp "/zotero-manifest.eld") sp-bibtex-lint-backup-directory))

(defun sp-bibtex-zotero--write-manifest (path data)
  "Write the plist DATA to the manifest PATH."
  (make-directory (file-name-directory path) t)
  (with-temp-file path
    (let ((print-length nil) (print-level nil))
      (insert ";; Written by sp-bibtex-zotero; read back by `sp-bibtex-zotero-restore'.\n")
      (prin1 data (current-buffer))
      (insert "\n"))))

(defun sp-bibtex-zotero--read-manifest (path)
  "The plist in the manifest PATH, or nil when it cannot be read."
  (ignore-errors
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (read (current-buffer)))))

;;;; Applying

(defun sp-bibtex-zotero--item-done-p (item weak)
  "Non-nil when ITEM is applied under WEAK and its file is where the field will say.
A moved file is at the new place and gone from the old one; a linked one only has
to be at the new place."
  (and (sp-bibtex-zotero--applied-p item weak)
       (sp-bibtex-zotero--item-to item)
       (file-exists-p (sp-bibtex-zotero--item-to item))
       (or (memq (sp-bibtex-zotero--item-status item) '(identical duplicate moved-before))
           (not (and (sp-bibtex-zotero--item-from item)
                     (file-exists-p (sp-bibtex-zotero--item-from item)))))))

(defun sp-bibtex-zotero--write-bib (file plan weak)
  "Rewrite the fields of FILE for the items of PLAN that are done; return the entries changed."
  (let ((changed 0))
    (with-temp-buffer
      (insert-file-contents file)
      (dolist (ent (reverse (sp-bibtex-zotero--plan-ents plan)))
        (let ((new (sp-bibtex-zotero--new-value
                    ent (lambda (it) (sp-bibtex-zotero--item-done-p it weak)))))
          (when (and (not (equal new (sp-bibtex-zotero--ent-value ent)))
                     (equal (buffer-substring-no-properties (sp-bibtex-zotero--ent-vstart ent)
                                                            (sp-bibtex-zotero--ent-vend ent))
                            (sp-bibtex-zotero--ent-value ent)))
            (goto-char (sp-bibtex-zotero--ent-vstart ent))
            (delete-region (sp-bibtex-zotero--ent-vstart ent) (sp-bibtex-zotero--ent-vend ent))
            (insert new)
            (cl-incf changed))))
      (write-region (point-min) (point-max) file nil 'silent))
    (when-let* ((visiting (find-buffer-visiting file)))
      (unless (buffer-modified-p visiting)
        (with-current-buffer visiting (revert-buffer t t t))))
    changed))

;;;###autoload
(defun sp-bibtex-zotero-convert (file &optional weak)
  "Move the Zotero attachments of the .bib FILE to the literature folder and rewrite the fields.
FILE is the .bib file of the current buffer, or it is read with completion.  A
prefix argument WEAK also applies the weak matches (same extension but another
name, or found by name outside its folder).  Read the dry run first
\(`sp-bibtex-zotero-dryrun').  The .bib file is copied to
`sp-bibtex-lint-backup-directory' and the moves are written to a manifest there, so
`sp-bibtex-zotero-restore' can undo the run.  Nothing is deleted or overwritten."
  (interactive (list (sp-bibtex-lint--read-file) current-prefix-arg))
  (sp-bibtex-lint--unsaved-check file)
  (sp-bibtex-zotero--check-devonthink)
  (let* ((plan (sp-bibtex-zotero--plan file))
         (moves (sp-bibtex-zotero--moves plan weak))
         (links (seq-filter (lambda (i) (sp-bibtex-zotero--applied-p i weak))
                            (sp-bibtex-zotero--items plan))))
    (cond
     ((null links) (message "No Zotero paths to fix in %s" (file-name-nondirectory file)))
     ((not (yes-or-no-p (format "Move %d file%s to the top of the library%s and rewrite %d path%s in %s (a backup is made first)? "
                                (length moves) (if (= 1 (length moves)) "" "s")
                                (if sp-bibtex-files-devonthink-tool " through DEVONthink" " on disk")
                                (length links) (if (= 1 (length links)) "" "s")
                                (file-name-nondirectory file))))
      (message "Nothing changed"))
     (t
      (let* ((stamp (format-time-string "%Y%m%dT%H%M%S"))
             (manifest (sp-bibtex-zotero--manifest-file stamp))
             (failure nil))
        (unless (equal (sp-bibtex-zotero--plan-hash plan) (sp-bibtex-zotero--file-hash file))
          (user-error "%s changed on disk since it was read; run the command again" (file-name-nondirectory file)))
        (sp-bibtex-lint--backup file stamp)
        (sp-bibtex-zotero--write-manifest
         manifest (list :file file :stamp stamp :moves moves :weak weak))
        (when moves
          (condition-case err
              (sp-bibtex-files--move moves)
            (error (setq failure (error-message-string err)))))
        (let ((changed (sp-bibtex-zotero--write-bib file plan weak)))
          (sp-bibtex-zotero--write-manifest
           manifest (list :file file :stamp stamp :moves moves :weak weak
                          :hash-after (sp-bibtex-zotero--file-hash file) :changed changed))
          (message "Zotero paths of %s: %d entr%s rewritten, %d file%s planned to move; backup and manifest in %s%s"
                   (file-name-nondirectory file) changed (if (= 1 changed) "y" "ies")
                   (length moves) (if (= 1 (length moves)) "" "s")
                   (abbreviate-file-name (file-name-directory manifest))
                   (if failure (format ".  STOPPED: %s.  Run the dry run again to see what is left" failure) ""))
          (when failure (user-error "Moving stopped: %s" failure))))))))

;;;; Restoring

(defun sp-bibtex-zotero--manifests (file)
  "The manifests of the runs on FILE, newest first, as (PATH . PLIST)."
  (let ((dir (and (boundp 'sp-bibtex-lint-backup-directory) sp-bibtex-lint-backup-directory)))
    (when (and dir (file-directory-p dir))
      (sort (delq nil
                  (mapcar (lambda (path)
                            (let ((data (sp-bibtex-zotero--read-manifest path)))
                              (and data (equal (plist-get data :file) file) (cons path data))))
                          (directory-files-recursively dir "\\`zotero-manifest\\.eld\\'")))
            (lambda (a b) (string> (plist-get (cdr a) :stamp) (plist-get (cdr b) :stamp)))))))

;;;###autoload
(defun sp-bibtex-zotero-restore (file)
  "Undo a run of `sp-bibtex-zotero-convert' on the .bib FILE.
Moves the files back and puts the copy of the .bib file made before the run back.
It refuses when the .bib file changed after the run.  Nothing is deleted."
  (interactive (list (sp-bibtex-lint--read-file)))
  (sp-bibtex-lint--unsaved-check file)
  (let* ((runs (or (seq-remove (lambda (r) (plist-get (cdr r) :restored))
                               (sp-bibtex-zotero--manifests file))
                   (user-error "No run to restore for %s" (file-name-nondirectory file))))
         (pick (if (cdr runs)
                   (let ((stamps (mapcar (lambda (r) (plist-get (cdr r) :stamp)) runs)))
                     (assoc (completing-read "Restore the run: " stamps nil t nil nil (car stamps))
                            (mapcar (lambda (r) (cons (plist-get (cdr r) :stamp) r)) runs)))
                 (cons nil (car runs))))
         (run (cdr pick))
         (path (car run)) (data (cdr run))
         (copy (expand-file-name (file-name-nondirectory file) (file-name-directory path)))
         (back (mapcar (lambda (m) (cons (cdr m) (car m))) (plist-get data :moves)))
         (todo (seq-filter (lambda (m) (and (file-exists-p (car m)) (not (file-exists-p (cdr m))))) back)))
    (unless (file-readable-p copy)
      (user-error "The copy of the .bib file from before the run is missing: %s" copy))
    (unless (equal (plist-get data :hash-after) (sp-bibtex-zotero--file-hash file))
      (user-error "%s changed after that run (or the run did not finish); restore it by hand from %s"
                  (file-name-nondirectory file) (abbreviate-file-name copy)))
    (sp-bibtex-zotero--check-devonthink)
    (when (yes-or-no-p (format "Move %d file%s back and put the earlier %s back? "
                               (length todo) (if (= 1 (length todo)) "" "s") (file-name-nondirectory file)))
      (when todo (sp-bibtex-files--move todo))
      (copy-file file (expand-file-name "before-restore.bib" (file-name-directory path)) t)
      (copy-file copy file t)
      (when-let* ((visiting (find-buffer-visiting file)))
        (with-current-buffer visiting (revert-buffer t t t)))
      (sp-bibtex-zotero--write-manifest path (plist-put (copy-sequence data) :restored t))
      (message "Restored %s; %d file%s moved back (the .bib file as it was before the restore is %s)"
               (file-name-nondirectory file) (length todo) (if (= 1 (length todo)) "" "s")
               (abbreviate-file-name (expand-file-name "before-restore.bib" (file-name-directory path)))))))

(provide 'sp-bibtex-zotero)
;;; sp-bibtex-zotero.el ends here
