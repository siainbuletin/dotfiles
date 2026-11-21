;;; thesis-desk-litnotes.el --- Claude proposes summaries for the litnotes of a project -*- lexical-binding: t; -*-

;;; Commentary:

;; `thesis-desk-litnotes-propose' collects the litnotes whose `bib-project'
;; line links a project note, sends them to `claude -p' a few at a time,
;; and keeps what comes back in `proposals/litnotes-PROJECT.eld':
;;
;;   - a summary of the text, aimed at the project;
;;   - its role: what it does for the argument, in one line;
;;   - a theme, then (in a last call over all notes) a group that organises
;;     the material into a handful of headings;
;;   - relevance lines with a kind (adopts, adapts, ...), a strength 0-3 and a
;;     one-line nuance, towards the claims of the map or named concepts;
;;   - what the note lacks to be up to standard.
;;
;; Claude only reads the text Emacs hands it (no tools), so the scope is
;; exactly the notes of the project.  `thesis-desk-litnotes-review' shows the
;; proposals in a batch report by group: d drops one, A writes the rest into
;; their litnotes (a "Summary for PROJECT" heading), after a backup.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'org)
(require 'org-id)
(require 'thesis-desk-map)
(require 'thesis-desk-views)

(declare-function thesis-desk-file "thesis-desk")

(defcustom thesis-desk-project-id nil
  "ID of the project note that `bib-project' lines link, or nil to ask."
  :type '(choice (const nil) string) :group 'thesis-desk)

(defcustom thesis-desk-litnote-directory "~/notes/litnotes/"
  "Folder searched for litnotes."
  :type 'directory :group 'thesis-desk)

(defcustom thesis-desk-claude-program "claude"
  "The Claude Code command line program."
  :type 'string :group 'thesis-desk)

(defcustom thesis-desk-claude-args '("-p" "--output-format" "json")
  "Arguments of `thesis-desk-claude-program'; the prompt goes to standard input."
  :type '(repeat string) :group 'thesis-desk)

(defcustom thesis-desk-propose-batch-size 8
  "Litnotes sent to Claude in one call."
  :type 'integer :group 'thesis-desk)

(defcustom thesis-desk-propose-max-chars 12000
  "Characters of each litnote sent to Claude; longer notes are cut."
  :type 'integer :group 'thesis-desk)

(defcustom thesis-desk-relevance-kinds
  '("adopts" "adapts" "extends" "presupposes" "contrasts" "critiques"
    "analogy" "method" "background")
  "Kinds of relevance a text can have to a claim or concept."
  :type '(repeat string) :group 'thesis-desk)

;;;; Finding the litnotes

(defun thesis-desk-litnote-meta (text key)
  "The value of the meta line KEY (`- KEY :: value') in TEXT, or nil."
  (when (string-match (format "^[ \t]*-[ \t]+%s[ \t]*::[ \t]*\\(.*\\)$" (regexp-quote key)) text)
    (string-trim (match-string 1 text))))

(defun thesis-desk-litnote-info (file)
  "A plist (:file :id :title :text) for FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((text (buffer-string)))
      (list :file file
            :id (and (string-match "^[ \t]*:ID:[ \t]+\\(\\S-+\\)" text) (match-string 1 text))
            :title (if (string-match "^#\\+title:[ \t]*\\(.*\\)$" text)
                       (string-trim (match-string 1 text))
                     (file-name-base file))
            :text text))))

(defun thesis-desk-litnotes-of-project (project-id &optional directory)
  "Litnotes in DIRECTORY whose bib-project line links PROJECT-ID, as plists."
  (let ((dir (expand-file-name (or directory thesis-desk-litnote-directory)))
        (needle (concat "id:" project-id))
        result)
    (dolist (file (directory-files-recursively dir "\\`[^.].*\\.org\\'"))
      (let ((info (thesis-desk-litnote-info file)))
        (when-let* ((value (thesis-desk-litnote-meta (plist-get info :text) "bib-project")))
          (when (string-search needle value)
            (push info result)))))
    (sort result (lambda (a b) (string< (plist-get a :title) (plist-get b :title))))))

;;;; The prompts

(defun thesis-desk--claims-block (claims)
  "CLAIMS as lines for a prompt."
  (if claims
      (mapconcat (lambda (c) (format "- %s [%s] (id: %s)" (plist-get c :title)
                                     (plist-get c :type) (plist-get c :id)))
                 claims "\n")
    "(no claims declared yet: name concepts or problems instead)"))

(defun thesis-desk-propose-prompt (project-title claims notes)
  "The prompt for NOTES of PROJECT-TITLE with CLAIMS.
NOTES are plists with :id, :title and :text."
  (concat
   "You help a philosophy student organise the literature notes of one thesis project.\n"
   "Project: " project-title "\n\n"
   "Claims and questions of the thesis so far:\n" (thesis-desk--claims-block claims) "\n\n"
   "For each note below, propose (in the language the note is mostly written in):\n"
   "- summary: 2 to 4 sentences on what the text argues, aimed at what this project needs from it;\n"
   "- role: one line on what the text does for the argument;\n"
   "- theme: 2 to 5 words naming the problem it belongs to;\n"
   "- relevance: up to 4 entries {target, kind, strength, nuance}. target is a claim id from the list,\n"
   "  or else the name of a concept or problem. kind is one of: "
   (string-join thesis-desk-relevance-kinds ", ") ".\n"
   "  strength is 0 to 3. nuance is one line saying exactly how it bears on the target (what is kept,\n"
   "  what is changed, where it stops). Prefer precise nuance to a strong claim;\n"
   "- missing: what the note lacks to be useful later (pages, the author's thesis, a quote), or \"\".\n"
   "Work only from the note text. Do not invent pages, quotes or positions the note does not state;\n"
   "when the note is too thin to say, write that in summary and keep relevance empty.\n\n"
   "Answer with JSON only, no prose: {\"notes\": [{\"id\", \"summary\", \"role\", \"theme\", \"relevance\", \"missing\"}]}\n\n"
   (mapconcat (lambda (n)
                (format "=== NOTE id=%s title=%s ===\n%s\n"
                        (plist-get n :id) (plist-get n :title)
                        (truncate-string-to-width (plist-get n :text) thesis-desk-propose-max-chars)))
              notes "\n")))

(defun thesis-desk-group-prompt (project-title proposals)
  "The prompt that groups the themes of PROPOSALS of PROJECT-TITLE."
  (concat
   "These are literature notes of the thesis project \"" project-title "\", each with a theme and a role.\n"
   "Propose between 5 and 12 groups that would organise this material for writing the thesis.\n"
   "Name each group by the problem it addresses, in the language of the notes. Every note goes in\n"
   "exactly one group. Answer with JSON only: {\"groups\": [{\"name\", \"why\", \"ids\": [...]}]}\n\n"
   (mapconcat (lambda (p) (format "- id=%s | %s | theme: %s | role: %s"
                                  (plist-get p :id) (plist-get p :title)
                                  (plist-get p :theme) (plist-get p :role)))
              proposals "\n")))

;;;; Reading the answers

(defun thesis-desk-claude-result (output)
  "The JSON object in Claude's OUTPUT (the `--output-format json' envelope)."
  (let* ((envelope (json-parse-string output :object-type 'plist :array-type 'list
                                      :null-object nil :false-object nil))
         (result (plist-get envelope :result)))
    (when (plist-get envelope :is_error)
      (error "Claude: %s" result))
    (unless (stringp result) (error "Claude gave no result"))
    (when (string-match "```\\(?:json\\)?[ \t]*\n\\(\\(?:.\\|\n\\)*?\\)```" result)
      (setq result (match-string 1 result)))
    (json-parse-string (string-trim result) :object-type 'plist :array-type 'list
                       :null-object nil :false-object nil)))

(defun thesis-desk-proposals-merge (notes answer)
  "Proposals for NOTES (plists :id :title :file) from Claude's parsed ANSWER."
  (let (result)
    (dolist (item (plist-get answer :notes))
      (when-let* ((note (seq-find (lambda (n) (equal (plist-get n :id) (plist-get item :id))) notes)))
        (push (list :id (plist-get note :id) :title (plist-get note :title) :file (plist-get note :file)
                    :mtime (file-attribute-modification-time (file-attributes (plist-get note :file)))
                    :summary (plist-get item :summary) :role (plist-get item :role)
                    :theme (plist-get item :theme) :missing (plist-get item :missing)
                    :relevance (plist-get item :relevance))
              result)))
    (nreverse result)))

(defun thesis-desk-proposals-group (proposals answer)
  "PROPOSALS with the :group of the grouping ANSWER (its theme when no group)."
  (mapcar (lambda (p)
            (let ((group (seq-find (lambda (g) (member (plist-get p :id) (plist-get g :ids)))
                                   (plist-get answer :groups))))
              (append (list :group (if group (plist-get group :name) (plist-get p :theme)))
                      p)))
          proposals))

;;;; The proposals file

(defun thesis-desk--proposals-file (project-id)
  "The proposals file of PROJECT-ID."
  (thesis-desk-file (format "proposals/litnotes-%s.eld" project-id)))

(defun thesis-desk-proposals-read (project-id)
  "The saved proposals of PROJECT-ID: a plist (:project-title :items)."
  (let ((file (thesis-desk--proposals-file project-id)))
    (when (file-readable-p file)
      (with-temp-buffer (insert-file-contents file) (read (current-buffer))))))

(defun thesis-desk-proposals-write (project-id data)
  "Save DATA as the proposals of PROJECT-ID."
  (let ((file (thesis-desk--proposals-file project-id)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert ";; Proposals from Claude for the litnotes of one project.  -*- mode: lisp-data -*-\n")
      (let ((print-length nil) (print-level nil)) (pp data (current-buffer))))))

;;;; Running Claude

(defun thesis-desk--claude (prompt callback)
  "Run Claude on PROMPT asynchronously.
CALLBACK gets the parsed answer, or a plist with :error."
  (let* ((buffer (generate-new-buffer " *thesis-desk-claude*"))
         (proc (make-process
                :name "thesis-desk-claude" :buffer buffer
                :command (cons thesis-desk-claude-program thesis-desk-claude-args)
                :connection-type 'pipe
                :noquery t
                :sentinel
                (lambda (p _event)
                  (unless (process-live-p p)
                    (let ((out (with-current-buffer buffer (buffer-string))))
                      (kill-buffer buffer)
                      (funcall callback
                               (condition-case err
                                   (if (zerop (process-exit-status p))
                                       (thesis-desk-claude-result out)
                                     (list :error (format "exit %d: %s" (process-exit-status p)
                                                          (string-trim out))))
                                 (error (list :error (error-message-string err)))))))))))
    (process-send-string proc prompt)
    (process-send-eof proc)
    proc))

(defun thesis-desk--project-title (project-id)
  "The title of the note PROJECT-ID, or the ID."
  (or (ignore-errors
        (when-let* ((file (org-id-find-id-file project-id)))
          (plist-get (thesis-desk-litnote-info file) :title)))
      project-id))

(defun thesis-desk--read-project ()
  "The project ID: `thesis-desk-project-id', or asked."
  (or thesis-desk-project-id
      (let ((answer (read-string "Project note ID (the id: that bib-project links): ")))
        (when (string-empty-p answer) (user-error "No project"))
        (replace-regexp-in-string "\\`id:" "" answer))))

;;;###autoload
(defun thesis-desk-litnotes-propose (project-id &optional all)
  "Ask Claude for summaries of the litnotes of PROJECT-ID, in the background.
Notes that already have a proposal and did not change since are skipped,
unless ALL (prefix argument).  The report opens when every batch is back."
  (interactive (list (thesis-desk--read-project) current-prefix-arg))
  (let* ((title (thesis-desk--project-title project-id))
         (saved (thesis-desk-proposals-read project-id))
         (done (plist-get saved :items))
         (notes (seq-remove
                 (lambda (n)
                   (and (not all)
                        (when-let* ((p (seq-find (lambda (p) (equal (plist-get p :id) (plist-get n :id))) done)))
                          (equal (plist-get p :mtime)
                                 (file-attribute-modification-time
                                  (file-attributes (plist-get n :file)))))))
                 (thesis-desk-litnotes-of-project project-id)))
         (notes (seq-filter (lambda (n) (plist-get n :id)) notes))
         (batches (seq-partition notes thesis-desk-propose-batch-size))
         (claims (thesis-desk-claims))
         (total (length batches))
         (items (seq-remove (lambda (p) (seq-find (lambda (n) (equal (plist-get n :id) (plist-get p :id)))
                                                 notes))
                            done))
         (errors 0))
    (if (null notes)
        (progn (message "No litnote of %s needs a proposal" title)
               (thesis-desk-litnotes-review project-id))
      (message "Asking Claude about %d litnotes of %s, in %d calls..." (length notes) title total)
      (cl-labels
          ((finish ()
             (message "Grouping %d proposals..." (length items))
             (thesis-desk--claude
              (thesis-desk-group-prompt title items)
              (lambda (answer)
                (let ((grouped (if (plist-get answer :error)
                                   (progn (message "[thesis-desk] grouping failed: %s" (plist-get answer :error))
                                          (mapcar (lambda (p) (append (list :group (plist-get p :theme)) p))
                                                  items))
                                 (thesis-desk-proposals-group
                                  (mapcar (lambda (p) (cl-loop for (k v) on p by #'cddr
                                                               unless (eq k :group) append (list k v)))
                                          items)
                                  answer))))
                  (thesis-desk-proposals-write project-id (list :project-title title :items grouped))
                  (message "Proposals ready%s" (if (> errors 0) (format " (%d batches failed)" errors) ""))
                  (thesis-desk-litnotes-review project-id)))))
           (next (rest n)
             (if (null rest)
                 (finish)
               (let ((batch (car rest)))
                 (thesis-desk--claude
                  (thesis-desk-propose-prompt title claims batch)
                  (lambda (answer)
                    (if (plist-get answer :error)
                        (progn (setq errors (1+ errors))
                               (message "[thesis-desk] batch %d/%d failed: %s" n total (plist-get answer :error)))
                      (setq items (append items (thesis-desk-proposals-merge batch answer)))
                      (thesis-desk-proposals-write project-id (list :project-title title :items items))
                      (message "Claude: batch %d/%d done" n total))
                    (next (cdr rest) (1+ n))))))))
        (next batches 1)))))

;;;; The report

(defun thesis-desk--relevance-line (r claims)
  "The relevance entry R as text, the target named from CLAIMS when it is an ID."
  (format "%s %s %s: %s"
          (or (plist-get r :kind) "?")
          (or (plist-get r :strength) "?")
          (thesis-desk-claim-title (format "%s" (plist-get r :target)) claims)
          (or (plist-get r :nuance) "")))

(defun thesis-desk-litnotes-sections (items claims)
  "Report sections of the proposal ITEMS, one per group, with CLAIMS for names."
  (let (groups)
    (dolist (p items)
      (let ((cell (assoc (or (plist-get p :group) "Ungrouped") groups)))
        (if cell (setcdr cell (append (cdr cell) (list p)))
          (setq groups (append groups (list (list (or (plist-get p :group) "Ungrouped") p)))))))
    (mapcar (lambda (g)
              (list :title (car g)
                    :items (mapcar (lambda (p)
                                     (list :key (plist-get p :id) :file (plist-get p :file)
                                           :label (plist-get p :title)
                                           :text (or (plist-get p :summary) "")
                                           :children
                                           (append
                                            (and (plist-get p :role) (list (concat "role: " (plist-get p :role))))
                                            (mapcar (lambda (r) (concat "relevance: " (thesis-desk--relevance-line r claims)))
                                                    (plist-get p :relevance))
                                            (and (not (string-empty-p (or (plist-get p :missing) "")))
                                                 (list (concat "missing: " (plist-get p :missing)))))))
                                   (cdr g))))
            groups)))

;;;###autoload
(defun thesis-desk-litnotes-review (project-id)
  "Show Claude's proposals for the litnotes of PROJECT-ID; A writes the kept ones."
  (interactive (list (thesis-desk--read-project)))
  (let* ((data (or (thesis-desk-proposals-read project-id)
                   (user-error "No proposals yet: run thesis-desk-litnotes-propose")))
         (items (plist-get data :items)))
    (thesis-desk-report
     "*thesis-desk: litnote proposals*"
     (format "Proposed summaries: %s" (plist-get data :project-title))
     (thesis-desk-litnotes-sections items (thesis-desk-claims))
     :intro (format "%d litnotes in %d groups.  d drops a proposal; A writes the rest into the notes (backups first)."
                    (length items) (length (delete-dups (mapcar (lambda (p) (plist-get p :group)) items))))
     :refresh (lambda () (thesis-desk-litnotes-review project-id))
     :apply (lambda (excluded) (thesis-desk-litnotes-apply project-id excluded)))))

;;;; Writing into the litnotes

(defun thesis-desk-summary-heading (project-title)
  "The heading that holds the summary for PROJECT-TITLE in a litnote."
  (format "Summary for %s" project-title))

(defun thesis-desk-summary-text (p project-title claims)
  "The Org subtree written into a litnote for proposal P."
  (concat "* " (thesis-desk-summary-heading project-title) "\n"
          ":PROPERTIES:\n:THESIS_GROUP: " (or (plist-get p :group) "") "\n:END:\n"
          (or (plist-get p :summary) "") "\n\n"
          (and (plist-get p :role) (concat "- role :: " (plist-get p :role) "\n"))
          (mapconcat (lambda (r)
                       (let ((target (format "%s" (plist-get r :target))))
                         (format "- relevance :: %s %s %s: %s\n"
                                 (if (seq-find (lambda (c) (equal (plist-get c :id) target)) claims)
                                     (org-link-make-string (concat "id:" target)
                                                           (thesis-desk-claim-title target claims))
                                   target)
                                 (or (plist-get r :kind) "?") (or (plist-get r :strength) "?")
                                 (or (plist-get r :nuance) ""))))
                     (plist-get p :relevance) "")))

(defun thesis-desk-summary-write (file p project-title claims)
  "Write proposal P into FILE.
Its summary heading for PROJECT-TITLE is replaced, or added before the first
heading.  CLAIMS name the targets that are claim IDs."
  (with-current-buffer (find-file-noselect file)
    (when (buffer-modified-p) (user-error "%s has unsaved changes" file))
    (org-with-wide-buffer
     (goto-char (point-min))
     (let ((text (thesis-desk-summary-text p project-title claims))
           (re (format "^\\* %s[ \t]*$" (regexp-quote (thesis-desk-summary-heading project-title)))))
       (if (re-search-forward re nil t)
           (let ((beg (line-beginning-position)))
             (org-end-of-subtree t t)
             (delete-region beg (point))
             (insert text "\n"))
         (goto-char (point-min))
         (if (re-search-forward org-heading-regexp nil t)
             (goto-char (line-beginning-position))
           (goto-char (point-max))
           (unless (bolp) (insert "\n")))
         (insert text "\n"))))
    (save-buffer)))

(defun thesis-desk-litnotes-apply (project-id &optional excluded)
  "Write every proposal of PROJECT-ID not in EXCLUDED into its litnote."
  (let* ((data (thesis-desk-proposals-read project-id))
         (title (plist-get data :project-title))
         (claims (thesis-desk-claims))
         (backup (thesis-desk-file (format-time-string "backups/%Y%m%d-%H%M%S/")))
         (todo (seq-remove (lambda (p) (member (plist-get p :id) excluded)) (plist-get data :items)))
         (written 0))
    (when (y-or-n-p (format "Write %d summaries into their litnotes (backups in %s)? "
                            (length todo) backup))
      (make-directory backup t)
      (dolist (p todo)
        (let ((file (plist-get p :file)))
          (condition-case err
              (progn
                (copy-file file (expand-file-name (file-name-nondirectory file) backup) t)
                (thesis-desk-summary-write file p title claims)
                (setq written (1+ written)))
            (error (message "[thesis-desk] %s: %s" file (error-message-string err))))))
      (message "%d litnotes written; backups in %s" written backup))))

(provide 'thesis-desk-litnotes)
;;; thesis-desk-litnotes.el ends here
