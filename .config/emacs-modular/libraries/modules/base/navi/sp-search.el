;;; sp-search.el --- Search tools: Consult, grep front-ends and Recoll -*- lexical-binding: t; -*-

;;; Commentary:

;; This file is part of the category for /Navigation/ and should be treated as such.
;;
;; dired-x is necessary for making counsel-fd work
;; This module includes packages that help with search within the buffer, in a directory
;; or more complicated grep-like searches.
;;
;; It should also be somewhat integrated with sp-browsing.el, as it should pull in
;; omni-search and similar packages, for bringing in as much information as possible, and perhaps
;; acting on it in the future. The possibility of acting on this information is created through
;; the embark package.
;;
;; See also possibilities for the vulpea ecosystem for this.

;;; Code:

(use-package counsel
  :ensure t
)

(use-package consult
  :ensure t
  )

(keymap-global-set "C-c s l" #'consult-line)
(keymap-global-set "C-c s r" #'consult-ripgrep)

;; Global search

(use-package ag
  :ensure (:wait t))

(use-package rg
  :ensure (:wait t)
  )

(use-package deadgrep
  :ensure (:wait t)
  )

(use-package p-search
  :ensure (:host github :repo "zkry/p-search"))
 
;; Personal functions for better searching

;; Acting on searches

;; Functions written for searches
;;;; Search given directory
(defun sp-search-in-input-dir ()
  "Grep for a string in the input directory using completing read function"
  (interactive)
  (let ((current-prefix-arg '(4))) (call-interactively #'consult-ripgrep)))

;; More advanced searching

(defun counsel-recoll-function (string &rest _unused)
  "Issue recallq for STRING."
  (if (< (length string) 3)
      (counsel-more-chars 3)
    (counsel--async-command
     (format "recollq -b '%s'" string))
    nil))

(defun counsel-recoll (&optional initial-input)
  "Search for a string in the recoll database.
You'll be given a list of files that match.
Selecting a file will launch `swiper' for that file.
INITIAL-INPUT can be given as the initial minibuffer input."
  (interactive)
  (ivy-read "recoll: " 'counsel-recoll-function
            :initial-input initial-input
            :dynamic-collection t
            :history 'counsel-git-grep-history
            :action (lambda (x)
                      (when (string-match "file://\\(.*\\)\\'" x)
                        (let ((file-name (match-string 1 x)))
                          (find-file file-name)
                          (unless (string-match "pdf$" x)
                            (swiper ivy-text)))))))

;;;; Search buffer and saved views
;; `sp-search' opens a Magit-style results buffer with the transient menu on
;; top. Results of the ripgrep runner can be marked and exported to an Org
;; file that keeps the search parameters, a "saved view" that needs no Lisp.
(require 'transient)
(require 'seq)
(require 'subr-x)

(defvar sp-notes-dir)

(defgroup sp-search nil
  "One interface for all searches."
  :group 'convenience)

(defcustom sp-search-views-dir nil
  "Directory of the saved search views (Org files).
When nil, a `search-views' folder in `sp-notes-dir' is used."
  :type '(choice (const :tag "In the notes directory" nil) directory)
  :group 'sp-search)

(defcustom sp-search-max-results 2000
  "Most results one search keeps in the results buffer."
  :type 'integer
  :group 'sp-search)

(defcustom sp-search-menu-display-action
  '(display-buffer-in-side-window
    (side . top) (slot . 0) (dedicated . t)
    (window-height . fit-window-to-buffer)
    (window-parameters (mode-line-format . none)))
  "How `sp-search-menu' is displayed: a window at the top of the frame."
  :type 'sexp
  :group 'sp-search)

(defun sp-search--views-dir ()
  "Return the directory of the saved search views."
  (file-name-as-directory
   (or sp-search-views-dir
       (expand-file-name "search-views"
                         (if (boundp 'sp-notes-dir) sp-notes-dir user-emacs-directory)))))

(defun sp-search--header ()
  "Return the dashboard-style header lines of the search buffer and menu."
  (let ((on (lambda (name active)
              (propertize name 'face (if active 'success 'shadow)))))
    (concat
     (propertize "Searching in " 'face 'transient-heading)
     (propertize (abbreviate-file-name default-directory) 'face 'bold)
     (when-let* ((proj (and (fboundp 'project-current) (project-current))))
       (concat "  (project "
               (propertize (file-name-nondirectory
                            (directory-file-name (project-root proj)))
                           'face 'bold)
               ")"))
     "\n"
     (propertize "Completion: " 'face 'transient-heading)
     (funcall on "vertico" (bound-and-true-p vertico-mode)) " "
     (funcall on "marginalia" (bound-and-true-p marginalia-mode)) " "
     (funcall on "orderless" (featurep 'orderless)) " "
     (funcall on "embark" (featurep 'embark))
     (unless (executable-find "rg")
       (concat "  " (propertize "rg not found" 'face 'error))))))

(defun sp-search-in-notes ()
  "Grep through the notes directory with `consult-ripgrep'."
  (interactive)
  (consult-ripgrep (and (boundp 'sp-notes-dir) sp-notes-dir)))

(defvar-local sp-search--params nil
  "Parameters of the search shown in this buffer.")
(defvar-local sp-search--results nil
  "Matches of the search shown in this buffer, one plist each.")

(defun sp-search--rg (params)
  "Run ripgrep as described by PARAMS and return its matches."
  (let ((rg (or (executable-find "rg") (user-error "Ripgrep (rg) is not installed")))
        (dir (expand-file-name (plist-get params :dir)))
        (glob (plist-get params :glob))
        results)
    (with-temp-buffer
      (apply #'call-process rg nil '(t nil) nil
             "--line-number" "--no-heading" "--with-filename"
             "--color" "never" "--max-columns" "500"
             (append (pcase (plist-get params :case)
                       ("sensitive" '("--case-sensitive"))
                       ("ignore" '("--ignore-case"))
                       (_ '("--smart-case")))
                     (unless (plist-get params :regexp) '("--fixed-strings"))
                     (when (and glob (not (string-empty-p glob)))
                       (list "--glob" glob))
                     (list "-e" (plist-get params :query) "--" dir)))
      (goto-char (point-min))
      (while (and (< (length results) sp-search-max-results)
                  (re-search-forward "^\\(.+?\\):\\([0-9]+\\):\\(.*\\)$" nil t))
        (push (list :file (match-string 1)
                    :line (string-to-number (match-string 2))
                    :text (string-trim (match-string 3))
                    :marked nil)
              results)))
    (nreverse results)))

(defun sp-search--slug (text)
  "Return TEXT as a short file name part."
  (let ((s (string-trim (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase text)) "-" "-")))
    (if (string-empty-p s) "search" (substring s 0 (min 40 (length s))))))

(defun sp-search--write-view (name params items)
  "Write the saved view NAME for the search PARAMS with the matches ITEMS.
Return the file written, which is also opened."
  (require 'org)
  (let* ((dir (sp-search--views-dir))
         (base (format "%s-%s" (format-time-string "%Y%m%d") (sp-search--slug name)))
         (file (expand-file-name (concat base ".org") dir))
         (n 1)
         (one-line (lambda (s) (replace-regexp-in-string "[\n\r]+" " " (or s "")))))
    (make-directory dir t)
    (while (file-exists-p file)
      (setq n (1+ n)
            file (expand-file-name (format "%s-%d.org" base n) dir)))
    (with-temp-file file
      (insert (format "#+title: Search: %s\n#+filetags: :search_view:\n#+date: %s\n\n"
                      (funcall one-line (plist-get params :query))
                      (format-time-string "[%Y-%m-%d %a %H:%M]"))
              "* Parameters\n:PROPERTIES:\n"
              (format ":SEARCH_TOOL: %s\n" (or (plist-get params :tool) "rg"))
              (format ":SEARCH_QUERY: %s\n" (funcall one-line (plist-get params :query)))
              (format ":SEARCH_DIR: %s\n" (plist-get params :dir))
              (format ":SEARCH_GLOB: %s\n" (or (plist-get params :glob) ""))
              (format ":SEARCH_CASE: %s\n" (or (plist-get params :case) "smart"))
              (format ":SEARCH_REGEXP: %s\n" (if (plist-get params :regexp) "t" "nil"))
              ":END:\n\nRe-run this search with =M-x sp-search-run-view=.\n\n"
              (format "* Results (%d)\n" (length items)))
      (dolist (r items)
        (insert (format "- [[file:%s::%d][%s:%d]] :: %s\n"
                        (org-link-escape (plist-get r :file)) (plist-get r :line)
                        (file-name-nondirectory (plist-get r :file)) (plist-get r :line)
                        (plist-get r :text)))))
    (message "Saved view: %s" file)
    (find-file-other-window file)
    file))

(defun sp-search--read-view (file)
  "Return the SEARCH_* properties of the saved view FILE as a plist."
  (with-temp-buffer
    (insert-file-contents file)
    (let (plist)
      (while (re-search-forward "^:SEARCH_\\([A-Z]+\\): ?\\(.*\\)$" nil t)
        (setq plist (plist-put plist (intern (concat ":" (downcase (match-string 1))))
                               (match-string 2))))
      plist)))

(defun sp-search--view-params (file)
  "Return the search parameters stored in the saved view FILE."
  (let ((p (sp-search--read-view file)))
    (list :tool (plist-get p :tool)
          :query (plist-get p :query)
          :dir (plist-get p :dir)
          :glob (plist-get p :glob)
          :case (or (plist-get p :case) "smart")
          :regexp (equal (plist-get p :regexp) "t"))))

(defun sp-search--view-files ()
  "Return the saved view files, newest first."
  (let ((dir (sp-search--views-dir)))
    (and (file-directory-p dir)
         (sort (directory-files dir t "\\.org\\'") #'file-newer-than-file-p))))

(defun sp-search--insert-views ()
  "Insert the list of saved views."
  (insert "\n" (propertize "Saved views" 'face 'bold)
          (format " (%s)\n" (abbreviate-file-name (sp-search--views-dir))))
  (if-let* ((files (sp-search--view-files)))
      (dolist (f files)
        (insert (propertize (format "  %s  %s\n" (file-name-base f)
                                    (or (plist-get (sp-search--read-view f) :query) ""))
                            'sp-search-view f)))
    (insert "  none yet: select results and press x\n")))

(defun sp-search--render ()
  "Redraw the results buffer."
  (let ((inhibit-read-only t)
        (line (line-number-at-pos))
        (params sp-search--params)
        (results sp-search--results))
    (erase-buffer)
    (insert (sp-search--header) "\n\n")
    (if (not params)
        (insert (propertize "No search yet." 'face 'bold)
                " Press s to search, ? for the menu.\n")
      (let ((glob (plist-get params :glob)))
        (insert (propertize "Search" 'face 'bold) "\n"
                "  " (propertize (plist-get params :query) 'face 'font-lock-string-face)
                " in " (abbreviate-file-name (plist-get params :dir)) "\n"
                (format "  glob: %s, case: %s, %s\n"
                        (if (member glob '(nil "")) "all files" glob)
                        (plist-get params :case)
                        (if (plist-get params :regexp) "regexp" "fixed string"))
                (format "\nResults: %d, marked %d\n" (length results)
                        (length (seq-filter (lambda (r) (plist-get r :marked)) results)))))
      (let ((i 0) last)
        (dolist (r results)
          (unless (equal last (plist-get r :file))
            (setq last (plist-get r :file))
            (insert (propertize (file-relative-name last (plist-get params :dir))
                                'face 'font-lock-function-name-face)
                    "\n"))
          (insert (propertize (format "%s %5d  %s\n"
                                      (if (plist-get r :marked) "*" " ")
                                      (plist-get r :line) (plist-get r :text))
                              'sp-search-index i))
          (setq i (1+ i)))))
    (sp-search--insert-views)
    (goto-char (point-min))
    (forward-line (1- line))))

(defvar-keymap sp-search-mode-map
  :parent special-mode-map
  "?" #'sp-search-menu
  "s" #'sp-search-grep
  "g" #'sp-search-rerun
  "m" #'sp-search-mark
  "u" #'sp-search-unmark
  "M" #'sp-search-mark-all
  "U" #'sp-search-unmark-all
  "x" #'sp-search-export
  "V" #'sp-search-run-view
  "O" #'sp-search-open-view
  "RET" #'sp-search-visit)

(define-derived-mode sp-search-mode special-mode "Search"
  "Major mode of the search buffer: results with marks and saved views."
  (setq-local truncate-lines t))

(defun sp-search--show (params)
  "Run the search PARAMS and show its results in the search buffer."
  (let ((results (sp-search--rg params))
        (buf (get-buffer-create "*sp-search*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'sp-search-mode) (sp-search-mode))
      (setq sp-search--params params
            sp-search--results results)
      (goto-char (point-min))
      (sp-search--render))
    (pop-to-buffer-same-window buf)
    (message "%d results" (length results))))

(defun sp-search-grep (query &optional dir glob case-mode regexp)
  "Search for QUERY with ripgrep and show the results in the search buffer.
DIR, GLOB, CASE-MODE and REGEXP are asked for with a prefix argument."
  (interactive
   (let ((prefix current-prefix-arg))
     (list (read-string "Search for: "
                        (when (use-region-p)
                          (buffer-substring-no-properties (region-beginning) (region-end))))
           (if prefix (read-directory-name "In directory: ")
             (if-let* ((p (and (fboundp 'project-current) (project-current))))
                 (project-root p)
               default-directory))
           (when prefix (read-string "Glob (empty for all files): "))
           (if prefix (completing-read "Case: " '("smart" "sensitive" "ignore") nil t nil nil "smart")
             "smart")
           (if prefix (y-or-n-p "Regexp (no: fixed string)? ") t))))
  (sp-search--show (list :tool "rg" :query query
                         :dir (expand-file-name (or dir default-directory))
                         :glob glob :case (or case-mode "smart") :regexp regexp)))

(defun sp-search-rerun ()
  "Run the search of this buffer again."
  (interactive)
  (unless sp-search--params (user-error "No search to repeat"))
  (sp-search--show sp-search--params))

(defun sp-search-visit ()
  "Visit the match at point, or run the saved view at point."
  (interactive)
  (if-let* ((view (get-text-property (point) 'sp-search-view)))
      (sp-search-run-view view)
    (if-let* ((i (get-text-property (point) 'sp-search-index))
              (r (nth i sp-search--results)))
        (progn (find-file-other-window (plist-get r :file))
               (goto-char (point-min))
               (forward-line (1- (plist-get r :line))))
      (user-error "Nothing to open here"))))

(defun sp-search--set-mark (flag)
  "Set the mark of the match at point to FLAG, then go to the next line."
  (if-let* ((i (get-text-property (line-beginning-position) 'sp-search-index)))
      (progn (plist-put (nth i sp-search--results) :marked flag)
             (sp-search--render)
             (forward-line 1))
    (user-error "No match on this line")))

(defun sp-search-mark () "Mark the match at point for export." (interactive) (sp-search--set-mark t))
(defun sp-search-unmark () "Unmark the match at point." (interactive) (sp-search--set-mark nil))

(defun sp-search-mark-all (&optional unmark)
  "Mark every match for export; with UNMARK non-nil unmark them all."
  (interactive)
  (dolist (r sp-search--results) (plist-put r :marked (not unmark)))
  (sp-search--render))

(defun sp-search-unmark-all () "Unmark every match." (interactive) (sp-search-mark-all t))

(defun sp-search-export (name)
  "Export the marked matches (all if none) to the saved view NAME."
  (interactive
   (list (read-string "View name: " (sp-search--slug (or (plist-get sp-search--params :query) "")))))
  (unless sp-search--params (user-error "No search to export"))
  (let ((items (or (seq-filter (lambda (r) (plist-get r :marked)) sp-search--results)
                   sp-search--results)))
    (unless items (user-error "Nothing to export"))
    (sp-search--write-view name sp-search--params items)
    (sp-search--render)))

(defun sp-search--pick-view-file ()
  "Ask for a saved view file."
  (let* ((files (or (sp-search--view-files)
                    (user-error "No saved views in %s" (sp-search--views-dir))))
         (alist (mapcar (lambda (f) (cons (file-name-base f) f)) files)))
    (cdr (assoc (completing-read "Saved view: " alist nil t) alist))))

(defun sp-search-run-view (file)
  "Run the search stored in the saved view FILE and show it in the search buffer."
  (interactive
   (list (or (and buffer-file-name
                  (plist-get (sp-search--read-view buffer-file-name) :query)
                  buffer-file-name)
             (sp-search--pick-view-file))))
  (let ((params (sp-search--view-params file)))
    (unless (plist-get params :query) (user-error "%s has no search parameters" file))
    (sp-search--show params)))

(defun sp-search-open-view (file)
  "Open the saved view FILE."
  (interactive (list (sp-search--pick-view-file)))
  (find-file file))

(defun sp-search-export-grep-buffer (query name)
  "Export the grep lines of this buffer (or the region) to the saved view NAME.
QUERY is the search that produced them; it is stored in the view."
  (interactive
   (let* ((q (read-string "Query that produced these results: "
                          (car (bound-and-true-p grep-history))))
          (n (read-string "View name: " (sp-search--slug q))))
     (list q n)))
  (let ((beg (if (use-region-p) (region-beginning) (point-min)))
        (end (if (use-region-p) (region-end) (point-max)))
        items)
    (save-excursion
      (goto-char beg)
      (while (re-search-forward "^\\([^ \n:][^\n]*?\\):\\([0-9]+\\):\\(.*\\)$" end t)
        (push (list :file (expand-file-name (match-string 1))
                    :line (string-to-number (match-string 2))
                    :text (string-trim (match-string 3)))
              items)))
    (unless items (user-error "No grep lines found"))
    (sp-search--write-view name
                           (list :tool "rg" :query query
                                 :dir (expand-file-name default-directory)
                                 :glob "" :case "smart" :regexp t)
                           (nreverse items))))

(with-eval-after-load 'grep
  (keymap-set grep-mode-map "E" #'sp-search-export-grep-buffer))

(defun sp-search ()
  "Open the search buffer, with the search menu on top."
  (interactive)
  (let ((buf (get-buffer-create "*sp-search*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'sp-search-mode) (sp-search-mode))
      (sp-search--render))
    (pop-to-buffer-same-window buf)
    (sp-search-menu)))

(transient-define-prefix sp-search-menu ()
  "All the search commands of the configuration in one place."
  [:description sp-search--header
   ["Here: buffer and directory"
    ("l" "Lines in this buffer (consult-line)" consult-line)
    ("i" "Headings and symbols (consult-imenu)" consult-imenu)
    ("r" "Ripgrep in the project (consult-ripgrep)" consult-ripgrep)
    ("d" "Ripgrep in a chosen directory" sp-search-in-input-dir)
    ("f" "Fast file names (consult-snapfile)" consult-snapfile
     :if (lambda () (fboundp 'consult-snapfile)))
    ("T" "TODO/FIXME comments (consult-todo)" consult-todo
     :if (lambda () (fboundp 'consult-todo)))]
   ["Grep buffers (editable results)"
    ("g" "rg: ripgrep with a menu" rg-menu
     :if (lambda () (fboundp 'rg-menu)))
    ("D" "deadgrep: interactive ripgrep" deadgrep
     :if (lambda () (fboundp 'deadgrep)))
    ("a" "ag: the silver searcher" ag
     :if (lambda () (fboundp 'ag)))
    ("R" "Recoll: full-text index (Ivy)" counsel-recoll
     :if (lambda () (and (fboundp 'counsel-recoll) (executable-find "recollq"))))]
   ["Results buffer and saved views"
    ("/" "Ripgrep into the results buffer" sp-search-grep)
    ("V" "Run a saved view" sp-search-run-view)
    ("O" "Open a saved view file" sp-search-open-view)]]
  [["Notes: plain text"
    ("n" "Grep the notes (consult-ripgrep)" sp-search-in-notes)
    ("N" "Grep org-node notes" org-node-grep
     :if (lambda () (fboundp 'org-node-grep)))
    ("v" "Grep vulpea notes" vulpea-grep
     :if (lambda () (fboundp 'vulpea-grep)))
    ("c" "Pick a note, then search all (consult-notes)" consult-notes
     :if (lambda () (fboundp 'consult-notes)))
    ("C" "Search in all notes (consult-notes)" consult-notes-search-in-all-notes
     :if (lambda () (fboundp 'consult-notes-search-in-all-notes)))]
   ["Semantic: by meaning"
    ("s" "Semantic search (org-semantic)" org-semantic-find
     :if (lambda () (fboundp 'org-semantic-find)))
    ("S" "Semantic search in a directory" org-semantic-find-in-directory
     :if (lambda () (fboundp 'org-semantic-find-in-directory)))
    ("." "Semantic search from point" org-semantic-find-at-point
     :if (lambda () (fboundp 'org-semantic-find-at-point)))
    ("p" "p-search: combine evidence" p-search
     :if (lambda () (fboundp 'p-search)))
    ("t" "Semantic search of the tab inbox" sp-tab-psearch
     :if (lambda () (fboundp 'sp-tab-psearch)))
    ("P" "Tab inbox p-search (search box)" sp-tab-psearch-engine
     :if (lambda () (fboundp 'sp-tab-psearch-engine)))
    ("X" "Rebuild the semantic index" org-semantic-reindex
     :if (lambda () (fboundp 'org-semantic-reindex)))]
   ["Web and more"
    ("o" "Omni search (consult-omni)" consult-omni
     :if (lambda () (fboundp 'consult-omni)))
    ("b" "litdb: my article database" consult-omni-litdb
     :if (lambda () (fboundp 'consult-omni-litdb)))
    ("B" "litdb: by meaning" consult-omni-litdb-semantic
     :if (lambda () (fboundp 'consult-omni-litdb-semantic)))]]
  [("q" "Quit" transient-quit-one)])

(define-advice transient--show (:around (fn &rest args) sp-search-top)
  "Show `sp-search-menu' at the top of the frame."
  (let ((transient-display-buffer-action
         (if (eq transient-current-command 'sp-search-menu)
             sp-search-menu-display-action
           transient-display-buffer-action)))
    (apply fn args)))

(keymap-global-set "C-c s m" #'sp-search)

(provide 'sp-search)
;; sp-search.el ends here
