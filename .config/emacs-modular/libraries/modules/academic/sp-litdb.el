;;; sp-litdb.el --- Search the litdb index of highlighted PDF pages -*- lexical-binding: t; -*-

;;; Commentary:

;; `tools/devonthink-to-litdb.py' indexes the highlighted pages of the PDFs in
;; DEVONthink in litdb.  This module searches that index from Emacs through
;; `tools/litdb-query.py', a process that keeps litdb's embedding model loaded,
;; and shows the hits as completion candidates of the category `sp-litdb' so that
;; Embark can act on them and collect them.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'org)

(defvar embark-keymap-alist)
(defvar embark-multitarget-actions)
(defvar embark-default-action-overrides)

(defgroup sp-litdb nil
  "Search the litdb index of highlighted PDF pages."
  :group 'spcustom)

(defcustom sp-litdb-python (expand-file-name "~/.local/share/uv/tools/litdb/bin/python")
  "Python of the litdb tool (it has litdb, PyMuPDF and the embedding model)."
  :type 'file)

(defcustom sp-litdb-query-script (expand-file-name "tools/litdb-query.py" user-emacs-directory)
  "The search process script."
  :type 'file)

(defcustom sp-litdb-index-script (expand-file-name "tools/devonthink-to-litdb.py" user-emacs-directory)
  "The script that indexes the highlighted pages of DEVONthink PDFs."
  :type 'file)

(defcustom sp-litdb-default-mode 'hybrid
  "How `sp-litdb-search' searches: `hybrid', `vector' (meaning) or `fulltext' (words)."
  :type '(choice (const hybrid) (const vector) (const fulltext)))

(defcustom sp-litdb-results 25
  "Number of hits `sp-litdb-search' asks for."
  :type 'integer)

(defcustom sp-litdb-timeout 180
  "Seconds to wait for the search process (the first search loads the model)."
  :type 'number)

;;;; The search process

(defvar sp-litdb--process nil "The search process, started on first use.")
(defvar sp-litdb--ready nil "Non-nil once the process has loaded its model.")
(defvar sp-litdb--partial "" "Output of the process not yet ended by a newline.")
(defvar sp-litdb--pending nil "Answers received, as an alist of id to answer.")
(defvar sp-litdb--id 0 "Number of the last request.")

(defun sp-litdb--parse-line (line)
  "Store the answer in LINE, a JSON object the process printed."
  (unless (string-empty-p line)
    (when-let* ((obj (ignore-errors
                       (json-parse-string line :object-type 'alist :array-type 'list
                                               :null-object nil :false-object nil))))
      (if (alist-get 'ready obj)
          (setq sp-litdb--ready t)
        (push (cons (alist-get 'id obj) obj) sp-litdb--pending)))))

(defun sp-litdb--filter (_process string)
  "Collect STRING, and parse each complete line."
  (setq sp-litdb--partial (concat sp-litdb--partial string))
  (while (string-match "\n" sp-litdb--partial)
    (let ((line (substring sp-litdb--partial 0 (match-beginning 0))))
      (setq sp-litdb--partial (substring sp-litdb--partial (match-end 0)))
      (sp-litdb--parse-line line))))

(defun sp-litdb--ensure ()
  "Start the search process when it is not running, and wait until it is ready."
  (unless (process-live-p sp-litdb--process)
    (dolist (file (list sp-litdb-python sp-litdb-query-script))
      (unless (file-exists-p file)
        (user-error "sp-litdb: %s is missing (see the sp-litdb doc)" file)))
    (setq sp-litdb--ready nil sp-litdb--partial "" sp-litdb--pending nil
          sp-litdb--process
          (make-process :name "litdb" :noquery t :connection-type 'pipe
                        :coding 'utf-8
                        :command (list sp-litdb-python sp-litdb-query-script)
                        :filter #'sp-litdb--filter
                        :stderr (get-buffer-create " *litdb stderr*"))))
  (unless sp-litdb--ready
    (message "litdb: loading the embedding model (first search only)...")
    (let ((deadline (+ (float-time) sp-litdb-timeout)))
      (while (and (not sp-litdb--ready) (process-live-p sp-litdb--process)
                  (< (float-time) deadline))
        (accept-process-output sp-litdb--process 0.2)))
    (unless sp-litdb--ready
      (user-error "sp-litdb: the search process did not start (see ` *litdb stderr*')"))))

(defun sp-litdb--request (mode query n)
  "Ask the process for N hits for QUERY in MODE; return the list of results."
  (sp-litdb--ensure)
  (let* ((id (cl-incf sp-litdb--id))
         (deadline (+ (float-time) sp-litdb-timeout))
         answer)
    (process-send-string
     sp-litdb--process
     (concat (json-serialize `((id . ,id) (mode . ,(symbol-name mode))
                               (query . ,query) (n . ,n)))
             "\n"))
    (while (and (not (setq answer (assq id sp-litdb--pending)))
                (process-live-p sp-litdb--process)
                (< (float-time) deadline))
      (accept-process-output sp-litdb--process 0.2))
    (setq sp-litdb--pending (assq-delete-all id sp-litdb--pending))
    (unless answer (user-error "sp-litdb: no answer from litdb"))
    (when-let* ((error-text (alist-get 'error (cdr answer))))
      (user-error "litdb: %s" error-text))
    (alist-get 'results (cdr answer))))

;;;###autoload
(defun sp-litdb-stop ()
  "Stop the search process (it starts again on the next search)."
  (interactive)
  (when (process-live-p sp-litdb--process)
    (delete-process sp-litdb--process))
  (setq sp-litdb--process nil sp-litdb--ready nil))

;;;; Hits

(cl-defstruct (sp-litdb-hit (:constructor sp-litdb-hit--make) (:copier nil))
  source citekey page uuid score snippet highlights query)

(defvar sp-litdb--hits (make-hash-table :test 'equal)
  "Candidate string to `sp-litdb-hit', for the hits of every search so far.")

(defun sp-litdb--hit (result query)
  "Make a `sp-litdb-hit' from one RESULT of the process, found for QUERY."
  (let ((extra (alist-get 'extra result)))
    (sp-litdb-hit--make
     :source (alist-get 'source result)
     :citekey (alist-get 'citekey extra)
     :page (alist-get 'page extra)
     :uuid (alist-get 'uuid extra)
     :score (alist-get 'score result)
     :snippet (or (alist-get 'snippet result) "")
     :highlights (alist-get 'highlights extra)
     :query query)))

(defun sp-litdb--label (hit)
  "The text of HIT in a candidate list: key, page and the start of the page."
  (format "%s%s  %s"
          (or (sp-litdb-hit-citekey hit)
              (file-name-nondirectory (sp-litdb-hit-source hit)))
          (if (sp-litdb-hit-page hit) (format " p. %s" (sp-litdb-hit-page hit)) "")
          (truncate-string-to-width
           (replace-regexp-in-string "[\n\t ]+" " " (sp-litdb-hit-snippet hit)) 100)))

(defun sp-litdb--candidates (hits)
  "Candidate strings for HITS, made unique, and remembered in `sp-litdb--hits'."
  (let (seen)
    (mapcar (lambda (hit)
              (let* ((label (sp-litdb--label hit))
                     (cand (if (member label seen)
                               (format "%s [%s]" label (sp-litdb-hit-source hit))
                             label)))
                (push cand seen)
                (puthash cand hit sp-litdb--hits)
                cand))
            hits)))

(defun sp-litdb--annotate (candidate)
  "Score and highlight count of CANDIDATE."
  (when-let* ((hit (gethash candidate sp-litdb--hits)))
    (format "  %.2f%s" (or (sp-litdb-hit-score hit) 0.0)
            (if-let* ((n (length (sp-litdb-hit-highlights hit))) ((> n 0)))
                (format "  %d highlight%s" n (if (= n 1) "" "s"))
              ""))))

(defun sp-litdb--table (candidates)
  "A completion table for CANDIDATES, in rank order, of category `sp-litdb'."
  (lambda (string pred action)
    (if (eq action 'metadata)
        '(metadata (category . sp-litdb)
                   (display-sort-function . identity)
                   (cycle-sort-function . identity)
                   (annotation-function . sp-litdb--annotate))
      (complete-with-action action candidates string pred))))

(defun sp-litdb--hit-for (candidate)
  "The hit of CANDIDATE, or an error when the search was not made in this session."
  (or (gethash (substring-no-properties candidate) sp-litdb--hits)
      (user-error "Unknown litdb hit; search again")))

;;;; Searching

;;;###autoload
(defun sp-litdb-search (query &optional choose-mode)
  "Search the litdb index for QUERY and open the hit you choose in DEVONthink.
With a prefix argument, choose how to search (words, meaning or both).  The hits
are completion candidates of the category `sp-litdb': run `embark-collect' on
them to keep the list, and `embark-act' or `embark-act-all' for the actions."
  (interactive (list (read-string "litdb: " (when (use-region-p)
                                              (buffer-substring-no-properties
                                               (region-beginning) (region-end))))
                     current-prefix-arg))
  (let* ((mode (if choose-mode
                   (intern (completing-read "Search: " '("hybrid" "vector" "fulltext") nil t))
                 sp-litdb-default-mode))
         (hits (mapcar (lambda (result) (sp-litdb--hit result query))
                       (sp-litdb--request mode query sp-litdb-results))))
    (unless hits (user-error "No hits for %s" query))
    (sp-litdb-open
     (completing-read (format "litdb (%s) %s: " mode query)
                      (sp-litdb--table (sp-litdb--candidates hits)) nil t))))

;;;; Actions

(defun sp-litdb--url (hit)
  "The address of HIT's source."
  (sp-litdb-hit-source hit))

;;;###autoload
(defun sp-litdb-open (candidate)
  "Open CANDIDATE: in DEVONthink at its page, or with `browse-url' for a web page."
  (interactive (list (completing-read "Hit: " (hash-table-keys sp-litdb--hits) nil t)))
  (let ((url (sp-litdb--url (sp-litdb--hit-for candidate))))
    (if (string-prefix-p "x-devonthink-item:" url)
        (call-process "open" nil 0 nil url)
      (browse-url url))))

(defun sp-litdb--description (hit)
  "Link text for HIT: the key and the page."
  (concat (or (sp-litdb-hit-citekey hit) (sp-litdb-hit-source hit))
          (if (sp-litdb-hit-page hit) (format " p. %s" (sp-litdb-hit-page hit)) "")))

(defun sp-litdb-insert-link (candidate)
  "Insert an Org link to CANDIDATE's page in DEVONthink."
  (interactive (list (completing-read "Hit: " (hash-table-keys sp-litdb--hits) nil t)))
  (let ((hit (sp-litdb--hit-for candidate)))
    (insert (org-link-make-string (sp-litdb--url hit) (sp-litdb--description hit)))))

(defun sp-litdb-insert-cite (candidate)
  "Insert an Org citation of CANDIDATE with its page, such as [cite:@key p. 6]."
  (interactive (list (completing-read "Hit: " (hash-table-keys sp-litdb--hits) nil t)))
  (let ((hit (sp-litdb--hit-for candidate)))
    (unless (sp-litdb-hit-citekey hit) (user-error "This hit has no citation key"))
    (insert (format "[cite:@%s%s]" (sp-litdb-hit-citekey hit)
                    (if (sp-litdb-hit-page hit) (format " p. %s" (sp-litdb-hit-page hit)) "")))))

(defun sp-litdb--entry (hit)
  "An Org list item for HIT: the link, its highlights and the start of the page."
  (concat "- " (org-link-make-string (sp-litdb--url hit) (sp-litdb--description hit))
          (when (sp-litdb-hit-citekey hit) (format " [cite:@%s]" (sp-litdb-hit-citekey hit)))
          "\n"
          (mapconcat (lambda (h) (format "  - %s\n" h)) (sp-litdb-hit-highlights hit) "")))

(defun sp-litdb-collect-to-note (candidates)
  "Append CANDIDATES (a list of hits) to a note you choose, under one heading.
The heading names the search; each hit is a link to its page in DEVONthink, its
citation and its highlights.  The note is left unsaved so you can read it."
  (interactive (list (completing-read-multiple "Hits: " (hash-table-keys sp-litdb--hits) nil t)))
  (let* ((hits (mapcar #'sp-litdb--hit-for candidates))
         (note (vulpea-select "Collect into note" :require-match t))
         (query (sp-litdb-hit-query (car hits))))
    (find-file (vulpea-note-path note))
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert (format "\n* litdb: %s\n" query) (mapconcat #'sp-litdb--entry hits ""))
    (message "Collected %d hits into %s" (length hits) (vulpea-note-title note))))

;;;; DEVONthink links in Org

;; DEVONthink's own item links, such as [[x-devonthink-item://UUID?page=5][key p. 6]],
;; open in DEVONthink when followed in Org.
(org-link-set-parameters
 "x-devonthink-item"
 :follow (lambda (path _arg) (call-process "open" nil 0 nil (concat "x-devonthink-item:" path))))

;;;; Embark

(defvar-keymap sp-litdb-embark-map
  :doc "Embark actions for hits of `sp-litdb-search'."
  "o" #'sp-litdb-open
  "l" #'sp-litdb-insert-link
  "c" #'sp-litdb-insert-cite
  "n" #'sp-litdb-collect-to-note)

(with-eval-after-load 'embark
  (add-to-list 'embark-keymap-alist '(sp-litdb . sp-litdb-embark-map))
  (add-to-list 'embark-multitarget-actions 'sp-litdb-collect-to-note)
  (add-to-list 'embark-default-action-overrides '(sp-litdb . sp-litdb-open)))

;;;; Indexing

;;;###autoload
(defun sp-litdb-index ()
  "Index the highlighted pages of DEVONthink PDFs in litdb, in a buffer.
Only new and changed records are done; see `tools/devonthink-to-litdb.py'."
  (interactive)
  (sp-litdb-stop)
  (let ((buffer (get-buffer-create "*litdb index*")))
    (with-current-buffer buffer (erase-buffer))
    (make-process :name "litdb-index" :buffer buffer :noquery t
                  :command (list sp-litdb-python sp-litdb-index-script))
    (display-buffer buffer)))

;;;; Keys

(keymap-global-set "C-c k l" #'sp-litdb-search)
(keymap-global-set "C-c k I" #'sp-litdb-index)

(provide 'sp-litdb)
;; sp-litdb.el ends here
