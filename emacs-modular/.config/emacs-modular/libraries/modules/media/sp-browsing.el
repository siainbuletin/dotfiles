;;; sp-browsing.el --- Web browsing inside Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; Good, focused browsing should happen as much as possible within
;; Emacs. This means that some of the workflows that have me context-
;; switching between Emacs and the browser is eliminated.

;;; Code:

;;;; Defining variables

;;;; EWW (built-in)

;;;;; Helper functions for eww

;; Open link in eww or browser
(defun open-link-at-point-or-minibuffer-with-choice ()
  "Use `consult` to select a link at point, in the buffer, from `consult-omni` results, or prompt for a URL.
  Then choose to open it in macOS default browser or eww.
  If 'eww' is chosen, the link is opened in a window that occupies 80% of the frame height below the current one."
  (interactive)
  (let* ((url (or (thing-at-point 'url)                             ;; Check if there's a URL at point
                (consult--read (thing-at-point--list 'url))       ;; Use consult to select a URL from the buffer
                (consult-omni)                                    ;; Use consult-omni results to select a link
                (read-string "Enter URL: "))))                    ;; Fall back to manual URL entry
    (if url
      (let ((choice (completing-read "Open link in: " '("macOS Browser" "eww"))))
        (cond
         ((string-equal choice "macOS Browser")
          (shell-command (concat "open " (shell-quote-argument url))))
         ((string-equal choice "eww")
          ;; Calculate the height for the top window (20% of the frame height)
          (let ((window (selected-window))
                (top-window-height (floor (* 0.2 (window-total-height)))))
            ;; Split window with 20% height on top and 80% height for eww on the bottom
            (select-window (split-window window top-window-height))
            (eww url)))))
      (message "No URL provided."))))

;;;; Elpher

;;;; consult-omni

;; A copy of consult-omni (GPL-3.0-or-later, Armin Darvish) lives in
;; `libraries/modules/cloned/consult-omni/'; see VENDORED.org there for the
;; version and the local patches.

(defconst sp-consult-omni-dir
  (expand-file-name "libraries/modules/cloned/consult-omni/" sp-emacs-dir)
  "Folder with the vendored copy of consult-omni.")

(defconst sp-consult-omni-sources-dir
  (expand-file-name "sources/" sp-consult-omni-dir)
  "Folder with the source modules (Google, OpenAlex, ...) of consult-omni.")

(defcustom sp-consult-omni-secrets-file
  (expand-file-name "consult-omni-secrets.el" sp-var-dir)
  "File with the API keys of the consult-omni sources.
It is loaded when consult-omni starts and is not tracked by Git (`var/' is
ignored).  Put plain `setq' forms in it, for example
\(setq consult-omni-brave-api-key \"...\")."
  :group 'spcustom
  :type 'file)

;; `:load-path' reads a list as a list of paths and evaluates each symbol in it
;; as a variable, so the paths go through variables.
(use-package browser-hist
  :ensure (browser-hist :host github :repo "agzam/browser-hist.el")
  :demand t) ; `consult-omni-browser-history' requires it

(defun sp-consult-omni-load-module (symbol)
  "Load the consult-omni source SYMBOL; skip it when a package it needs is missing."
  (condition-case err
      (require symbol nil t)
    (error
     (message "consult-omni: source `%s' skipped: %s" symbol (error-message-string err))
     nil)))

(use-package consult-omni
  :ensure nil
  :load-path (sp-consult-omni-dir sp-consult-omni-sources-dir)
  :after (consult browser-hist)

  :custom
  (consult-omni-show-preview t) ;;; show previews
  (consult-omni-preview-key "C-o") ;;; set the preview key to C-o
  (consult-omni-highlight-matches-in-minibuffer t) ;;; highlight matches in minibuffer
  (consult-omni-highlight-matches-in-file t) ;;; highlight matches in files
  (consult-omni-default-count 5) ;;; set default count
  (consult-omni-default-page 0) ;;; set the default page (default is 0 for the first page)

  (consult-omni-default-format-candidate 'consult-omni--higlight-format-candidate) ;; show annotations for the results

  ;; Adjust these (e.g. increase to avoid hitting a source such as an API too frequently)
  (consult-omni-dynamic-input-debounce 0.8)
  (consult-omni-dynamic-input-throttle 1.6)
  (consult-omni-dynamic-refresh-delay 0.8)
  ;; Optionally set backend for http request (either 'url, 'request, or 'plz)
  ;; (consult-omni-http-retrieve-backend 'plz)

  :config
  ;; API keys first: a source is only enabled once its key is set.
  (load sp-consult-omni-secrets-file t t)
  ;; `(require 'consult-omni-sources)' only defines the loader; the sources
  ;; themselves are defined when the loader runs.  Without this call the list
  ;; of sources stays empty and any search fails with "Args out of range: [], 0".
  (require 'consult-omni-sources)
  ;; A source requires the package it searches (`elfeed', `notmuch', `consult-gh'...).
  ;; `require' with NOERROR only covers the source file itself, so one missing
  ;; package aborted this whole `:config'.  Skip that source and say so.
  (advice-add 'consult-omni-sources--load-module :override #'sp-consult-omni-load-module)
  (consult-omni-sources-load-modules)
  ;; Embark actions on the results
  (with-eval-after-load 'embark-consult
    (require 'consult-omni-embark)))

(setq consult-omni-multi-sources '("Apps"
                                   "buffers text search"
                                   "Dictionary"
                                   "doiorg"
                                   "elfeed"
                                   "Google"
                                   "litdb"
                                   "Notes Search"
                                   "Org Agenda"
                                   "GitHub"
                                   "YouTube"
                                   "Wikipedia"))

(setq consult-omni-default-browse-function 'browse-url)
(setq consult-omni-alternate-browse-function 'eww-browse-url)
(setq consult-omni-default-preview-function #'xwidget-webkit-browse-url)

;; A search whose input matches no result must not leave Emacs: the default
;; (`consult-omni-external-search') sends it to a web search engine in the
;; browser when RET is pressed before the results have arrived.
(defun sp-consult-omni-ignore-new (cand)
  "Do nothing with the input CAND that is not one of the results."
  (message "consult-omni: \"%s\" is not a result, nothing was opened; wait for the results, or use `consult-omni-external-search' to search the web"
           (if (stringp cand) (substring-no-properties cand) cand))
  nil)

(setq consult-omni-default-new-function #'sp-consult-omni-ignore-new)

(defun sp--consult-omni-scoped (label default-sources initial prompt sources no-callback args)
  "Run `consult-omni-multi' on SOURCES, or on DEFAULT-SOURCES when nil.
LABEL names the search in the prompt unless PROMPT is given.  INITIAL,
NO-CALLBACK and ARGS are passed on; the minimum input length is left unset."
  (let ((prompt (or prompt
                    (concat "[" (propertize label 'face 'consult-omni-prompt-face) "]" " Search:  "))))
    (apply #'consult-omni-multi initial prompt (or sources default-sources) no-callback nil args)))

(defvar consult-omni-web-sources (list "gptel"
                                       "Brave"
                                       "elfeed"
                                       "mu4e"
                                       "Wikipedia"
                                       "GitHub"
                                       "Invidious"))

(defun consult-omni-web (&optional initial prompt sources no-callback &rest args)
  "Interactive web search.

This is similar to `consult-omni-multi', but runs the search on
web sources defined in `consult-omni-web-sources'.
See `consult-omni-multi' for more details."
  (interactive)
  (sp--consult-omni-scoped "consult-omni-web" consult-omni-web-sources
                           initial prompt sources no-callback args))

;;;;; A litdb source for the local article database

(defcustom sp-consult-omni-litdb-command "litdb"
  "Name or path of the litdb command line program."
  :group 'spcustom
  :type 'string)

(defcustom sp-consult-omni-litdb-timeout 60
  "Seconds to wait for litdb before the search is given up.
The first call after a start can take long: litdb imports its
libraries (and, for the semantic search, loads the embedding model)."
  :group 'spcustom
  :type 'integer)

(defvar sp--consult-omni-litdb-process nil
  "The litdb process of the search in progress, if any.")

(defconst sp--consult-omni-litdb-field-separator "␟"
  "Printable character between the fields of a litdb result.")

(defconst sp--consult-omni-litdb-record-separator "␞"
  "Printable character after each litdb result.")

(defun sp--consult-omni-litdb-format (field)
  "Return the jinja template for the litdb result column FIELD.
Newlines and square brackets are replaced: litdb prints through rich,
which reads brackets as markup, and one result must stay on one line."
  (format "%s|replace('\\n',' ')|replace('[','(')|replace(']',')')"
          field))

(defun sp--consult-omni-litdb-template (kind)
  "Return the `--fmt' template of litdb for KIND, `fulltext' or `semantic'."
  (let ((sep sp--consult-omni-litdb-field-separator))
    (concat "{{ source }}" sep "{{ score|round(3) }}" sep "{{ "
            (sp--consult-omni-litdb-format
             (if (eq kind 'fulltext) "snippet" "text[:200]"))
            " }}" sp--consult-omni-litdb-record-separator)))

(defun sp--consult-omni-litdb-arguments (kind query count)
  "Return the litdb arguments that search for QUERY.
KIND is `fulltext' or `semantic'; COUNT is the number of results."
  (if (eq kind 'fulltext)
      ;; Quote each word: the full text index reads `-' and `:' as operators.
      (append (list "fulltext" "-n" (number-to-string count)
                    "-f" (sp--consult-omni-litdb-template kind))
              (mapcar (lambda (word) (format "\"%s\"" (replace-regexp-in-string "\"" "" word)))
                      (split-string query "[ \t]+" t)))
    (append (list "vsearch" "-n" (number-to-string count)
                  "-f" (sp--consult-omni-litdb-template kind))
            (split-string query "[ \t]+" t))))

(defun sp--consult-omni-litdb-address (source)
  "Return the web address of the litdb SOURCE, or nil.
A DOI is turned into a doi.org address."
  (cond ((string-match-p "\\`https?://" source) source)
        ((string-match-p "\\`10\\.[0-9]+/" source) (concat "https://doi.org/" source))
        ((string-match-p "\\`doi:" source)
         (concat "https://doi.org/" (substring source 4)))))

(defun sp--consult-omni-litdb-candidate (record query name)
  "Return the consult-omni candidate for the litdb RECORD found with QUERY.
RECORD is the text of one result; NAME is the name of the source."
  (let* ((fields (split-string record sp--consult-omni-litdb-field-separator))
         (source (string-trim (or (nth 0 fields) "")))
         (score (string-trim (or (nth 1 fields) "")))
         (text (string-trim (or (nth 2 fields) "")))
         (title (if (string-empty-p text) source text)))
    (unless (string-empty-p source)
      (consult-omni-propertize-by-plist
       (copy-sequence title)
       `(:title ,title :source ,name :url ,(sp--consult-omni-litdb-address source)
         :search-url nil :query ,query :litdb-source ,source :score ,score)
       0 1))))

(defun sp--consult-omni-litdb-parse (output query name)
  "Return the candidates of the litdb OUTPUT for QUERY, found by source NAME."
  (delq nil
        (mapcar (lambda (record) (sp--consult-omni-litdb-candidate record query name))
                (split-string output sp--consult-omni-litdb-record-separator t "[ \t\n]+"))))

(defun sp--consult-omni-litdb-run (kind name input callback args)
  "Search litdb for INPUT without blocking Emacs and pass the results to CALLBACK.
KIND is `fulltext' or `semantic'; NAME is the name of the consult-omni
source; ARGS are the arguments consult-omni received."
  (pcase-let* ((`(,query . _) (consult-omni--split-command
                               input (seq-difference args (list :callback callback))))
               (program (executable-find sp-consult-omni-litdb-command)))
    (when (process-live-p sp--consult-omni-litdb-process)
      (delete-process sp--consult-omni-litdb-process))
    (when (and program query (not (string-blank-p query)))
      (let* ((buffer (generate-new-buffer " *consult-omni-litdb*"))
             ;; rich wraps lines at 80 columns when it does not print to a terminal;
             ;; sh below drops standard error so warnings do not mix into the results
             (process-environment (cons "COLUMNS=100000" process-environment))
             (timer nil)
             (process
              (make-process
               :name "consult-omni-litdb" :buffer buffer :noquery t
               :command (append (list "sh" "-c" "exec \"$@\" 2>/dev/null" "sh" program)
                               (sp--consult-omni-litdb-arguments
                                kind query (max 1 (or consult-omni-default-count 5))))
               :sentinel
               (lambda (proc _event)
                 (when (memq (process-status proc) '(exit signal))
                   (when timer (cancel-timer timer))
                   (let ((results (and (eq proc sp--consult-omni-litdb-process)
                                       (zerop (process-exit-status proc))
                                       (with-current-buffer buffer
                                         (sp--consult-omni-litdb-parse (buffer-string) query name)))))
                     (when (and (not (zerop (process-exit-status proc)))
                                (eq proc sp--consult-omni-litdb-process))
                       (message "litdb: search failed (exit %s); see `M-x list-processes'"
                                (process-exit-status proc)))
                     (when (and results (functionp callback))
                       (funcall callback results)))
                   (kill-buffer buffer))))))
        (setq sp--consult-omni-litdb-process process)
        (setq timer (run-at-time sp-consult-omni-litdb-timeout nil
                                 (lambda () (when (process-live-p process)
                                              (delete-process process)))))))
    nil))

(cl-defun sp-consult-omni-litdb-fetch-results (input &rest args &key callback &allow-other-keys)
  "Run the litdb full text search for INPUT and pass the results to CALLBACK."
  (apply #'sp--consult-omni-litdb-run 'fulltext "litdb" input callback args))

(cl-defun sp-consult-omni-litdb-semantic-fetch-results (input &rest args &key callback &allow-other-keys)
  "Run the litdb vector search for INPUT and pass the results to CALLBACK."
  (apply #'sp--consult-omni-litdb-run 'semantic "litdb semantic" input callback args))

(defun sp-consult-omni-litdb-callback (cand)
  "Open the litdb result CAND: its web address in the browser, or its file."
  (when (listp cand) (setq cand (car-safe cand)))
  (let ((url (get-text-property 0 :url cand))
        (source (get-text-property 0 :litdb-source cand)))
    (cond ((and (stringp url) (not (string-empty-p url)))
           (funcall consult-omni-default-browse-function url))
          ((and (stringp source) (file-exists-p source))
           (find-file source))
          (t (message "litdb: nothing to open for \"%s\"" (or source cand))))))

(defun sp--consult-omni-litdb-enabled ()
  "Return non-nil when the litdb program can be run."
  (and (executable-find sp-consult-omni-litdb-command) t))

(with-eval-after-load 'consult-omni
  ;; The full text search is quick.  The vector search loads the embedding
  ;; model on every call, so it is only a command, not in the multi sources.
  (dolist (spec `(("litdb" ?l sp-consult-omni-litdb-fetch-results)
                  ("litdb semantic" ?L sp-consult-omni-litdb-semantic-fetch-results)))
    (pcase-let ((`(,name ,char ,fetch) spec))
      (eval
       `(consult-omni-define-source ,name
                                    :narrow-char ,char
                                    :category 'consult-omni-litdb
                                    :type 'dynamic
                                    :require-match nil
                                    :min-input 3
                                    :request #',fetch
                                    :on-return #'identity
                                    :on-callback #'sp-consult-omni-litdb-callback
                                    :preview-key consult-omni-preview-key
                                    :search-hist 'consult-omni--search-history
                                    :select-hist 'consult-omni--selection-history
                                    :enabled #'sp--consult-omni-litdb-enabled
                                    :group #'consult-omni--group-function
                                    :sort t
                                    :interactive consult-omni-intereactive-commands-type)
       t))))

;;;;; A Vulpea source for the local search

(defun sp--consult-omni-vulpea-items (query)
  "Return the Vulpea notes whose title contains every word of QUERY."
  (let ((case-fold-search t)
        (words (mapcar #'regexp-quote (split-string query "[ \t]+" t))))
    (when words
      (vulpea-db-query
       (lambda (note)
         (let ((title (vulpea-note-title note)))
           (and (stringp title)
                (cl-every (lambda (word) (string-match-p word title)) words))))))))

(defun sp--consult-omni-vulpea-candidate (note query)
  "Return the consult-omni candidate for the Vulpea NOTE found with QUERY."
  (consult-omni-propertize-by-plist
   (copy-sequence (vulpea-note-title note))
   `(:title ,(vulpea-note-title note) :source "Vulpea" :url nil :search-url nil
     :query ,query :note ,note)
   0 1))

(defun sp-consult-omni-vulpea-callback (cand)
  "Visit the Vulpea note of the consult-omni candidate CAND."
  (when-let* ((note (get-text-property 0 :note cand)))
    (if (fboundp 'vulpea-visit)
        (vulpea-visit note)
      (find-file (vulpea-note-path note)))))

(cl-defun sp-consult-omni-vulpea-fetch-results (input &rest args &key callback &allow-other-keys)
  "Find the Vulpea notes whose title matches INPUT and pass them to CALLBACK."
  (pcase-let* ((`(,query . _) (consult-omni--split-command input (seq-difference args (list :callback callback))))
               (results (mapcar (lambda (note) (sp--consult-omni-vulpea-candidate note query))
                                (seq-take (sp--consult-omni-vulpea-items query)
                                          (max 1 (or consult-omni-default-count 5))))))
    (when (and results (functionp callback))
      (funcall callback results))
    results))

(with-eval-after-load 'consult-omni
  (consult-omni-define-source "Vulpea"
                              :narrow-char ?v
                              :category 'consult-omni-vulpea
                              :type 'dynamic
                              :require-match nil
                              :request #'sp-consult-omni-vulpea-fetch-results
                              :on-return #'identity
                              :on-callback #'sp-consult-omni-vulpea-callback
                              :preview-key consult-omni-preview-key
                              :search-hist 'consult-omni--search-history
                              :select-hist 'consult-omni--selection-history
                              :enabled (lambda () (fboundp 'vulpea-db-query))
                              :group #'consult-omni--group-function
                              :sort t
                              :interactive consult-omni-intereactive-commands-type))

(defvar consult-omni-local-sources (list "Vulpea"
                                         "ripgrep"
                                         "Org Agenda"))

(defun consult-omni-local (&optional initial prompt sources no-callback &rest args)
  "Interactive local search.

This is similar to `consult-omni-multi', but runs the search on
local sources defined in `consult-omni-local-sources'.
See `consult-omni-multi' for more details."
  (interactive)
  (sp--consult-omni-scoped "consult-omni-local" consult-omni-local-sources
                           initial prompt sources no-callback args))

(defvar consult-omni-scholar-sources (list "OpenAlex"
                                           "PubMed"
                                           "Scopus"
                                           "doiorg"
                                           "Notes Search"
                                           "gptel"))

(defun consult-omni-scholar (&optional initial prompt sources no-callback &rest args)
  "Interactive multi-source academic literature search.

This is similar to `consult-omni-multi', but runs the search on
academic literature sources defined in `consult-omni-scholar-sources'.
See `consult-omni-multi' for more details."
  (interactive)
  (sp--consult-omni-scoped "consult-omni-scholar" consult-omni-scholar-sources
                           initial prompt sources no-callback args))

(provide 'sp-browsing)
;;; sp-browsing.el ends here
