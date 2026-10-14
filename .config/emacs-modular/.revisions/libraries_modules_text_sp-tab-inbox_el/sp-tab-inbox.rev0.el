;;; sp-tab-inbox.el --- Link inbox widget for vulpea-ui -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (vulpea "2") (vulpea-ui "0") (vui "0"))

;;; Commentary:

;; A `vulpea-ui' sidebar widget that searches a directory of plain files
;; (the "link inbox") for mentions of the current note's title and aliases,
;; without adding those files to the vulpea database.
;;
;; - Each hit is shown on its own lines, with the body text word-wrapped.
;; - Hits whose only match sits inside an id: link into the current note's
;;   file (the note itself or any heading with an :ID:) are filtered out.
;; - `collect' moves a hit under a heading of the current note using
;;   `sp-move-region-to-heading', keeping the list bullet in both places and
;;   leaving a link behind.  `collect all' does this for every hit, asking for
;;   the heading once.
;; - `send' (or `sp-tab-inbox-send-elsewhere') sends a hit to another
;;   note you pick or create, for when the match is about something else.
;;   At that prompt, an embark action ("L", see `sp-tab-inbox-embark-map')
;;   also links that note from the note you searched from.
;; - Inbox files that were not already open are saved and killed afterwards.
;;
;; There's an entire section for the way that collecting should deal with
;; 'Resources' headings, as these contain the most complex logic. If there's
;; a top level 'Resources' in the file, everything should automatically be
;; placed there, instead of going through the minibuffer.
;;
;; Load it after vulpea-ui, e.g.:
;;
;;   (with-eval-after-load 'vulpea-ui
;;     (require 'sp-tab-inbox))
;;
;; and set `sp-tab-inbox-dir' to your inbox directory.  Press `g' in the
;; sidebar to refresh.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vulpea)
(require 'vulpea-ui)
(require 'vui)
(require 'sp-move-region-to-heading)

;;;; Configuration

(defcustom sp-tab-inbox-dir "~/link-inbox/"
  "Directory of plain files with unsorted links."
  :type 'directory
  :group 'vulpea)

(defcustom sp-tab-inbox-fill-column 40
  "Wrap width for link inbox results.
Tune to your sidebar width."
  :type 'integer
  :group 'vulpea)

(defcustom sp-tab-inbox-auto-resources t
  "When non-nil, collect under the note's \"Resources\" heading automatically.
The heading is matched like `sp--resources-heading-p' does, in any case,
and only inside the subtree the sidebar is scoped to (the whole file for
a file-level note, the narrowed heading otherwise).  If there is no such
heading, or the choice is ambiguous, you are prompted for one as usual.
See `sp-tab-inbox--resources-target' for how ties are handled."
  :type 'boolean
  :group 'vulpea)

(defcustom sp-tab-inbox-new-note-body "* Resources\n"
  "Body of a note created by `sp-tab-inbox-send-elsewhere'.
The default gives the new note a Resources heading, so the hit lands there
without another prompt.  Set to nil for an empty note."
  :type '(choice (const :tag "Empty note" nil) string)
  :group 'vulpea)

(defvar sp-tab-inbox-generation 0
  "Bumped after collecting, so the widget's memo recomputes.")

(defvar sp-tab-inbox--current nil
  "The (NOTE . HITS) the widget last rendered, for the interactive commands.")

(defvar sp-tab-inbox--pending nil
  "The (FILE LINE TEXT ORIGIN) hit waiting for an embark action.
Embark quits the minibuffer before running an action, so the hit being
sent has to live outside the command that is prompting.")

(defconst sp-tab-inbox-bullet-re
  "\\(?:[ \t]*[-+]\\|[ \t]*[0-9]+[.)]\\|[ \t]+\\*\\)[ \t]+\\(?:\\[[ xX-]\\][ \t]+\\)?"
  "Matches a list bullet (and optional checkbox) at the start of a line.
A column-0 `*' is an Org heading, so it is not treated as a bullet.")

;;;; Searching

(defun sp-tab-inbox--note-ids (note)
  "Return the ID of NOTE plus every :ID: property in NOTE's file."
  (let ((path (vulpea-note-path note))
        (ids (list (vulpea-note-id note))))
    (when (and path (file-readable-p path))
      (with-temp-buffer
        (if-let ((buf (find-buffer-visiting path)))
            (insert (with-current-buffer buf
                      (save-restriction
                        (widen)
                        (buffer-substring-no-properties (point-min) (point-max)))))
          (insert-file-contents path))
        (goto-char (point-min))
        (while (re-search-forward "^[ \t]*:ID:[ \t]+\\([^ \t\n]+\\)" nil t)
          (push (match-string 1) ids))))
    (delete-dups ids)))

(defun sp-tab-inbox--unlinked-p (text terms ids)
  "Non-nil if some term in TERMS occurs in TEXT outside links to any of IDS."
  (let* ((case-fold-search t)
         (link-re (concat "\\[\\[id:" (regexp-opt ids)
                          "\\]\\(?:\\[[^]]*\\]\\)?\\]"))
         (stripped (replace-regexp-in-string link-re "" text t t)))
    (seq-some (lambda (term) (string-match-p (regexp-quote term) stripped))
              terms)))

(defun sp-tab-inbox-search (note)
  "Return list of (FILE LINE TEXT) mentioning NOTE's title or aliases.
Matches that only sit inside id: links into NOTE's file are dropped."
  (when-let* ((rg (executable-find "rg"))
              (terms (seq-filter
                      (lambda (s) (>= (length s) 3))
                      (cons (vulpea-note-title note)
                            (vulpea-note-aliases note)))))
    (with-temp-buffer
      (apply #'call-process rg nil t nil
             "--line-number" "--no-heading" "--with-filename"
             "--ignore-case" "--fixed-strings" "--word-regexp"
             (append (mapcan (lambda (term) (list "-e" term)) terms)
                     (list (expand-file-name sp-tab-inbox-dir))))
      (goto-char (point-min))
      (let ((ids (sp-tab-inbox--note-ids note))
            result)
        (while (re-search-forward "^\\(.+?\\):\\([0-9]+\\):\\(.*\\)$" nil t)
          (let ((text (string-trim (match-string 3))))
            (when (sp-tab-inbox--unlinked-p text terms ids)
              (push (list (match-string 1)
                          (string-to-number (match-string 2))
                          text)
                    result))))
        (nreverse result)))))

;;;; Display helpers

(defun sp-tab-inbox-wrap (text)
  "Fill TEXT to `sp-tab-inbox-fill-column' and indent it by two spaces."
  (with-temp-buffer
    (insert text)
    (let ((fill-column sp-tab-inbox-fill-column))
      (fill-region (point-min) (point-max)))
    (goto-char (point-min))
    (while (not (eobp))
      (insert "  ")
      (forward-line 1))
    (buffer-string)))

(defun sp-tab-inbox-visit (file line)
  "Visit LINE of FILE in another window."
  (find-file-other-window file)
  (goto-char (point-min))
  (forward-line (1- line)))

;;;; Collecting

(defun sp-tab-inbox--heading-marker (note)
  "Return a marker at the heading NOTE refers to, or nil.
The position stored in NOTE is trusted only if the heading there carries
NOTE's ID; otherwise the heading is looked up by ID."
  (with-current-buffer (find-file-noselect (vulpea-note-path note))
    (org-with-wide-buffer
     (let ((id (vulpea-note-id note))
           (pos (vulpea-note-pos note)))
       (or (and pos (<= 1 pos (point-max))
                (progn (goto-char pos)
                       (and (org-at-heading-p)
                            (equal (org-entry-get nil "ID") id)
                            (point-marker))))
           (org-id-find id t))))))

(defun sp-tab-inbox--scope-root (note)
  "Return (MARKER . LEVEL) for the subtree the sidebar is scoped to.
For a heading-level NOTE (e.g. when the sidebar follows narrowing) this is
that heading.  For a file-level note, or if the heading can't be found, it
is the whole file: MARKER at the start of the file and LEVEL 0."
  (or (and (> (or (vulpea-note-level note) 0) 0)
           (when-let ((m (sp-tab-inbox--heading-marker note)))
             (cons m (with-current-buffer (marker-buffer m)
                       (org-with-wide-buffer
                        (goto-char m)
                        (org-current-level))))))
      (with-current-buffer (find-file-noselect (vulpea-note-path note))
        (cons (org-with-wide-buffer (copy-marker (point-min))) 0))))

(defun sp-tab-inbox--resources-candidates (root)
  "Return (MARKER LEVEL ID) for each Resources heading below ROOT.
ROOT is (MARKER . LEVEL) as returned by `sp-tab-inbox--scope-root'.
The root heading itself is not a candidate."
  (with-current-buffer (marker-buffer (car root))
    (org-with-wide-buffer
     (let (result)
       (goto-char (car root))
       (org-map-entries
        (lambda ()
          (when (and (> (org-current-level) (cdr root))
                     (sp--resources-heading-p (org-get-heading t t t t)))
            (push (list (point-marker)
                        (org-current-level)
                        (org-entry-get nil "ID"))
                  result)))
        nil
        (if (zerop (cdr root)) nil 'tree))
       (nreverse result)))))

(defun sp-tab-inbox--subtree-parts (marker)
  "Return (BEG END HEAD BODY CHILDREN) for the subtree at MARKER.
BEG and END delimit the whole subtree.  HEAD is the heading line plus its
planning line and property drawer, BODY is the text before the first
sub-heading, and CHILDREN is everything from the first sub-heading on."
  (save-excursion
    (goto-char marker)
    (let* ((beg (line-beginning-position))
           (end (progn (org-end-of-subtree t t) (point)))
           (meta-end (progn (goto-char beg)
                            (org-end-of-meta-data)
                            (min (point) end)))
           (next (progn (goto-char beg)
                        (end-of-line)
                        (if (outline-next-heading) (min (point) end) end)))
           (child-beg (max meta-end next)))
      (list beg end
            (buffer-substring-no-properties beg meta-end)
            (buffer-substring-no-properties meta-end child-beg)
            (buffer-substring-no-properties child-beg end)))))

(defun sp-tab-inbox--parent-marker (marker)
  "Return a marker at the parent heading of the heading at MARKER, or nil.
Nil means the heading sits directly under the file."
  (with-current-buffer (marker-buffer marker)
    (org-with-wide-buffer
     (goto-char marker)
     (when (org-up-heading-safe)
       (point-marker)))))

(defun sp-tab-inbox--merge-resources (tied parent)
  "Merge the TIED sibling Resources headings into a single one under PARENT.
TIED are (MARKER LEVEL ID) entries as returned by
`sp-tab-inbox--resources-candidates', all children of PARENT (a marker, or
nil for the file itself) at the same level.  The first heading's line and
properties are kept; the bodies of all headings are concatenated in file
order, followed by all their sub-headings.  The result is a single heading
at the same level, placed at the end of PARENT's subtree, as its last
child.  Return (MARKER . PATH) for the merged heading."
  (with-current-buffer (marker-buffer (car (car tied)))
    (org-with-wide-buffer
     (let* ((parts (mapcar (lambda (c) (sp-tab-inbox--subtree-parts (car c)))
                           (sort (copy-sequence tied)
                                 (lambda (a b) (< (car a) (car b))))))
            (nl (lambda (s)
                  (if (or (string-empty-p s) (string-suffix-p "\n" s))
                      s
                    (concat s "\n"))))
            ;; each part is (BEG END HEAD BODY CHILDREN)
            (text (concat (funcall nl (nth 2 (car parts)))
                          (mapconcat (lambda (p) (funcall nl (nth 3 p))) parts "")
                          (mapconcat (lambda (p) (funcall nl (nth 4 p))) parts ""))))
       ;; delete bottom-up so the earlier positions stay valid
       (dolist (p (reverse parts))
         (delete-region (nth 0 p) (nth 1 p)))
       (if parent
           (progn (goto-char parent) (org-end-of-subtree t t))
         (goto-char (point-max)))
       (unless (bolp) (insert "\n"))
       (let ((pos (point)))
         (insert text)
         (message "Merged %d Resources headings" (length parts))
         (cons (copy-marker pos) "Resources"))))))

(defun sp-tab-inbox--resources-target (note)
  "Return (MARKER . PATH) for the Resources heading to collect under, or nil.
Only the subtree NOTE is scoped to is searched, and the shallowest
Resources heading wins.  If several are tied at that depth:
- when they are siblings under the same parent, that is a formatting
  error: they are merged in place into a single Resources heading at the
  same level, last under that parent (see `sp-tab-inbox--merge-resources'),
  which is then used -- unless any of them has an ID, in which case nil is
  returned (the caller prompts), since merging would drop IDs that may be
  linked to;
- when they sit under different parents, the choice is ambiguous and nil
  is returned (the caller prompts); nothing is changed."
  (let* ((root (sp-tab-inbox--scope-root note))
         (cands (sp-tab-inbox--resources-candidates root)))
    (when cands
      (let* ((min-level (apply #'min (mapcar #'cadr cands)))
             (tied (seq-filter (lambda (c) (= (cadr c) min-level)) cands)))
        (if (null (cdr tied))
            (cons (car (car tied)) "Resources")
          (let* ((parents (mapcar (lambda (c) (sp-tab-inbox--parent-marker (car c)))
                                  tied))
                 (positions (mapcar (lambda (m) (and m (marker-position m)))
                                    parents)))
            (and (zerop (seq-count #'caddr tied))
                 (seq-every-p (lambda (pos) (equal pos (car positions)))
                              positions)
                 (sp-tab-inbox--merge-resources tied (car parents)))))))))

(defun sp-tab-inbox--target (note)
  "Return the (MARKER . PATH) heading target to collect into for NOTE.
Uses the Resources heading when `sp-tab-inbox-auto-resources' is set and
one exists, and otherwise prompts like `sp-move-region-to-heading' does."
  (or (and sp-tab-inbox-auto-resources
           (sp-tab-inbox--resources-target note))
      (sp--read-org-heading (vulpea-note-path note))))

(defun sp-tab-inbox-collect (file line text note &optional target)
  "Move LINE of FILE under a heading of NOTE with `sp-move-region-to-heading'.
The list bullet, if any, is moved with the text and also kept in FILE in
front of the link left behind.
TEXT is the hit text, checked against the file to catch stale line numbers.
TARGET is an optional (MARKER . PATH) to skip the heading prompt.
Return the target used."
  (let* ((target (or target (sp-tab-inbox--target note)))
         (existing (find-buffer-visiting file))
         (buf (or existing (find-file-noselect file))))
    (unwind-protect
        (with-current-buffer buf
          (save-excursion
            (goto-char (point-min))
            (forward-line (1- line))
            (let ((bol (line-beginning-position))
                  (end (line-end-position)))
              (unless (equal (string-trim (buffer-substring-no-properties bol end))
                             text)
                (user-error "Line %d of %s changed; refresh the sidebar"
                            line (file-name-nondirectory file)))
              (goto-char bol)
              (let* ((bullet-end (and (looking-at sp-tab-inbox-bullet-re)
                                      (match-end 0)))
                     ;; with a bullet, start at the bullet (skip indentation)
                     (beg (if bullet-end
                              (progn (skip-chars-forward " \t") (point))
                            bol))
                     (bullet (and bullet-end
                                  (buffer-substring-no-properties beg bullet-end))))
                (goto-char beg)
                (sp-move-region-to-heading beg end (car target) (cdr target))
                ;; the link now sits at BEG; put the bullet back before it
                (when bullet
                  (goto-char beg)
                  (insert bullet)))))
          (save-buffer))
      ;; only kill buffers this command opened
      (when (and (not existing) (buffer-live-p buf))
        (kill-buffer buf)))
    target))

(defun sp-tab-inbox-collect-one (file line text note)
  "Collect a single hit (FILE, LINE, TEXT) into NOTE and refresh the sidebar."
  (sp-tab-inbox-collect file line text note)
  (cl-incf sp-tab-inbox-generation)
  (vulpea-ui-sidebar-refresh))

(defun sp-tab-inbox-collect-all (hits note)
  "Collect every hit in HITS under one heading of NOTE."
  (when hits
    (let ((target (sp-tab-inbox--target note)))
      ;; Each moved line is replaced by a one-line link, so line numbers
      ;; in the inbox files stay valid between hits.
      (dolist (hit hits)
        (pcase-let ((`(,file ,line ,text) hit))
          (sp-tab-inbox-collect file line text note target)))
      (cl-incf sp-tab-inbox-generation)
      (message "Collected %d link inbox lines" (length hits))
      (vulpea-ui-sidebar-refresh))))

;;;; Sending to another note

(defvar embark-keymap-alist)

(defvar-keymap sp-tab-inbox-embark-map
  :doc "Embark actions available while choosing where to send a link inbox hit."
  "L" #'sp-tab-inbox-embark-send-and-link)

(defun sp-tab-inbox--embark-alist ()
  "Return `embark-keymap-alist' extended with `sp-tab-inbox-embark-map'.
The map is added in front of whatever is already registered for the
`vulpea-note' category, and is meant to be bound only while prompting,
so that the action exists nowhere else."
  (if (and (require 'embark nil t) (boundp 'embark-keymap-alist))
      (let ((existing (alist-get 'vulpea-note embark-keymap-alist)))
        (cons (cons 'vulpea-note
                    (cons 'sp-tab-inbox-embark-map
                          (if (listp existing) existing (list existing))))
              embark-keymap-alist))
    (bound-and-true-p embark-keymap-alist)))

(defun sp-tab-inbox--ensure-note (note-or-title)
  "Return a real note for NOTE-OR-TITLE, creating a file-level one if needed.
NOTE-OR-TITLE is a title string or a `vulpea-note'; a note without an ID
is what `vulpea-select' returns for a title that doesn't exist yet."
  (if (and (not (stringp note-or-title)) (vulpea-note-id note-or-title))
      note-or-title
    (let ((title (string-trim
                  (or (if (stringp note-or-title)
                          note-or-title
                        (vulpea-note-title note-or-title))
                      ""))))
      (when (string-empty-p title)
        (user-error "Empty note title"))
      (vulpea-create title nil :body sp-tab-inbox-new-note-body))))

(defun sp-tab-inbox--candidate-note (candidate)
  "Return the note CANDIDATE stands for, or its title if there is none.
The ID is read from the `vulpea-note-id' text property, or from the
trailing UUID vulpea appends to every candidate; embark can drop the
property but not the text.  Without an ID, an exact title match among
file-level notes is used if there is exactly one."
  (let* ((id (or (get-text-property 0 'vulpea-note-id candidate)
                 (and (string-match
                       (concat "\\([0-9A-Fa-f]\\{8\\}\\(?:-[0-9A-Fa-f]\\{4\\}\\)\\{3\\}"
                               "-[0-9A-Fa-f]\\{12\\}\\)[ \t]*\\'")
                       candidate)
                      (match-string 1 candidate))))
         (title (string-trim candidate)))
    (or (and id (vulpea-db-get-by-id id))
        (let ((exact (seq-filter
                      (lambda (n)
                        (and (zerop (vulpea-note-level n))
                             (string-equal-ignore-case (vulpea-note-title n) title)))
                      (vulpea-db-search-by-title title))))
          (if (= (length exact) 1) (car exact) title)))))

(defun sp-tab-inbox--insert-link (origin note)
  "Insert a list item linking to NOTE under ORIGIN's Resources heading.
The heading is chosen like when collecting.  Nothing is inserted if it
already links to NOTE, or if NOTE is ORIGIN."
  (unless (equal (vulpea-note-id note) (vulpea-note-id origin))
    (let ((target (sp-tab-inbox--target origin)))
      (with-current-buffer (marker-buffer (car target))
        (org-with-wide-buffer
         (goto-char (car target))
         (let ((end (save-excursion (org-end-of-subtree t t) (point))))
           (if (save-excursion
                 (re-search-forward
                  (regexp-quote (concat "[[id:" (vulpea-note-id note) "]"))
                  end t))
               (message "%s already links to %s"
                        (vulpea-note-title origin) (vulpea-note-title note))
             ;; end of the heading's own body, before any sub-heading
             (end-of-line)
             (outline-next-heading)
             (goto-char (min (point) end))
             (unless (bolp) (insert "\n"))
             (insert "- " (vulpea-utils-link-make-string note) "\n"))))
        (save-buffer)))))

(defun sp-tab-inbox--resolve-hit ()
  "Return (FILE LINE TEXT ORIGIN) for the hit to send, asking if needed.
In a file inside `sp-tab-inbox-dir' the line at point is the hit;
anywhere else you pick one of the sidebar's current hits.  ORIGIN is the
note the sidebar is showing."
  (let ((origin (car sp-tab-inbox--current))
        (file (buffer-file-name)))
    (unless origin
      (user-error "Open the vulpea-ui sidebar on a note first"))
    (if (and file (file-in-directory-p file (expand-file-name sp-tab-inbox-dir)))
        (list file
              (line-number-at-pos nil t)
              (string-trim (buffer-substring-no-properties
                            (line-beginning-position) (line-end-position)))
              origin)
      (let* ((hits (cdr sp-tab-inbox--current))
             (alist (mapcar (lambda (h)
                              (cons (format "%s:%d  %s"
                                            (file-name-nondirectory (nth 0 h))
                                            (nth 1 h) (nth 2 h))
                                    h))
                            hits)))
        (unless alist (user-error "No link inbox hits for %s"
                                  (vulpea-note-title origin)))
        (append (cdr (assoc (completing-read "Send hit: " alist nil t) alist))
                (list origin))))))

;;;###autoload
(defun sp-tab-inbox-send-elsewhere (&optional file line text origin)
  "Send a link inbox hit to another note, picked or created on the spot.
The hit is the line LINE of FILE with content TEXT, found from ORIGIN, the
note the sidebar is showing.  Interactively, these are the line at point
in an inbox file, or a hit you choose from the sidebar's current ones.

The note is chosen with `vulpea-select'; a title that doesn't exist yet
creates a new file-level note (see `sp-tab-inbox-new-note-body').  The
line then moves under the chosen note's Resources heading like `collect'
does.  No link back is added here; at the prompt, run the embark action
on `sp-tab-inbox-embark-map' to also link the note from ORIGIN."
  (interactive)
  (pcase-let ((`(,file ,line ,text ,origin)
               (if (and file line text origin)
                   (list file line text origin)
                 (sp-tab-inbox--resolve-hit))))
    (setq sp-tab-inbox--pending (list file line text origin))
    (when-let ((picked (let ((embark-keymap-alist (sp-tab-inbox--embark-alist)))
                         (vulpea-select
                          "Send to note"
                          :require-match nil
                          :filter-fn (lambda (n) (zerop (vulpea-note-level n)))))))
      (setq sp-tab-inbox--pending nil)
      (sp-tab-inbox-collect file line text (sp-tab-inbox--ensure-note picked))
      (cl-incf sp-tab-inbox-generation)
      (vulpea-ui-sidebar-refresh))))

(defun sp-tab-inbox-embark-send-and-link (candidate)
  "Embark action: send the pending hit to CANDIDATE and link it from its origin.
CANDIDATE is an existing note, or a title to create a note for.  Besides
moving the line like `sp-tab-inbox-send-elsewhere', this adds a link to
the note under the Resources heading of the note the search started from."
  (interactive "sNote: ")
  (pcase-let ((`(,file ,line ,text ,origin)
               (or sp-tab-inbox--pending
                   (user-error "No link inbox hit is waiting to be sent"))))
    (setq sp-tab-inbox--pending nil)
    (let ((note (sp-tab-inbox--ensure-note
                 (sp-tab-inbox--candidate-note candidate))))
      (sp-tab-inbox-collect file line text note)
      (sp-tab-inbox--insert-link origin note)
      (cl-incf sp-tab-inbox-generation)
      (vulpea-ui-sidebar-refresh))))

;;;; Widget

(vui-defcomponent sp-tab-inbox-widget ()
  "Plain-text mentions of the current note in the link inbox."
  :render
  (let ((note (use-vulpea-ui-note)))
    (when note
      (let ((hits (vui-use-memo (note sp-tab-inbox-generation)
                    (sp-tab-inbox-search note))))
        (setq sp-tab-inbox--current (cons note hits))
        (vui-component 'vulpea-ui-widget
          :title "Link inbox"
          :count (length hits)
          :children
          (lambda ()
            (if (null hits)
                (vui-text "No mentions")
              (apply #'vui-vstack
                     (vui-button "collect all"
                                 :on-click (lambda ()
                                             (sp-tab-inbox-collect-all hits note)))
                     (mapcar
                      (lambda (hit)
                        (pcase-let ((`(,file ,line ,text) hit))
                          (vui-vstack
                           (vui-hstack
                            (vui-button
                             (format "%s:%d" (file-name-nondirectory file) line)
                             :on-click (lambda () (sp-tab-inbox-visit file line)))
                            (vui-text " ")
                            (vui-button
                             "collect"
                             :on-click (lambda ()
                                         (sp-tab-inbox-collect-one
                                          file line text note)))
                            (vui-text " ")
                            (vui-button
                             "send"
                             :on-click (lambda ()
                                         (sp-tab-inbox-send-elsewhere
                                          file line text note))))
                           (vui-text
                            (propertize (sp-tab-inbox-wrap text)
                                        'face 'vulpea-ui-mention-context-face)))))
                      hits)))))))))

(vulpea-ui-register-widget 'link-inbox
  :component 'sp-tab-inbox-widget
  :order 360) ; right after unlinked-mentions (350)

;;; Provide

(provide 'sp-tab-inbox)
;;; sp-tab-inbox.el ends here
