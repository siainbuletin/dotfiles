;;; sp-vulpea-convert-properties.el --- Convert Org drawer properties to Vulpea meta lines -*- lexical-binding: t; -*-

;;; Commentary:

;; This module migrates note metadata out of Org property drawers and into
;; Vulpea-style meta lines, i.e. description-list items of the form `- key ::
;; value' placed just below a node's drawer. It works on one node at point, on
;; a whole buffer, or across every note Vulpea knows about, with a dry-run
;; preview and a non-blocking batch runner that shows progress and an ETA.

;;; Code:

(require 'org)
(require 'vulpea)
(require 'cl-lib)
(require 'subr-x)

(defvar sia-vulpea-convert-property-blocklist
  '("ID" "CUSTOM_ID" "CATEGORY" "ARCHIVE" "ROAM_REFS" "ROAM_ALIASES"
    "ROAM_EXCLUDE" "ROAM_PLANNING" "BLOCKER" "TRIGGER" "ORDERED"
    "COOKIE_DATA" "LOG_INTO_DRAWER" "LOGGING" "VISIBILITY"
    "EXPORT_FILE_NAME" "EXPORT_TITLE" "DIR" "UNNUMBERED" ;; by ai
    "CREATED" ;; necessary for org-node to work well
    )
  "Property names never converted to meta lines (case-insensitive).
These are properties Org, org-roam, or Vulpea itself read
directly out of the property drawer -- converting them to meta
lines would break that machinery (most importantly ID: Vulpea's
whole notion of \"a node\" depends on it staying a real
property). Add to this list before running a conversion if your
notes use other drawer properties something else depends on.")

;;; Low-level: one node at a time ---------------------------------------

(defun sia-vulpea--after-property-drawer-pos ()
  "Return the position right after the property drawer of the node at point.
\"Node at point\" is the heading at or above point, or the
file-level node if point is before the first heading.

For a heading, this is simply right after its own drawer (or
right after the heading line, if it has none).

For the file-level node, this additionally skips past any
leading #+KEYWORD: lines (#+title:, #+date:, #+filetags:, etc.)
in whatever order they appear relative to the property drawer.
Without this, meta lines inserted \"right after the drawer\"
would land *above* #+title:/#+date: whenever the drawer happens
to come first in the file -- which is exactly the bug this
guards against."
  (save-excursion
    (if (org-before-first-heading-p)
        (progn
          (goto-char (point-min))
          (let (moved)
            (setq moved t)
            (while moved
              (setq moved nil)
              (cond
               ((looking-at "^[ \t]*:PROPERTIES:[ \t]*$")
                (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                (forward-line 1)
                (setq moved t))
               ((looking-at "^[ \t]*#\\+[a-zA-Z_-]+:.*$")
                (forward-line 1)
                (setq moved t)))))
          (point))
      (org-back-to-heading t)
      (forward-line 1)
      (if (looking-at "^[ \t]*:PROPERTIES:[ \t]*$")
          (progn (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                 (forward-line 1)
                 (point))
        (point)))))

(defun sia-vulpea--insert-or-update-meta-line (key value)
  "Insert or update a \"- KEY :: VALUE\" meta line for the node at point.
Placed right after that node's property drawer. If a meta line
for KEY already exists between the drawer and the next heading
(or end of file, for the file-level node), its value is replaced
instead of adding a duplicate -- so re-running a conversion is
safe and idempotent."
  (let* ((start (sia-vulpea--after-property-drawer-pos))
         (end (save-excursion
                (goto-char start)
                (if (re-search-forward "^\\*" nil t) (line-beginning-position) (point-max))))
         (re (format "^\\(-[ \t]+%s[ \t]+::[ \t]*\\).*$" (regexp-quote key))))
    (save-excursion
      (goto-char start)
      (if (re-search-forward re end t)
          (replace-match (concat "\\1" value) t)
        (goto-char start)
        (insert (format "- %s :: %s\n" key value))))))

(defun sia-vulpea--ensure-blank-line-before-meta ()
  "Ensure a blank line separates the node at point's property
drawer (and, for the file-level node, its #+KEYWORD: lines) from
the meta block that begins right after them -- see
`sia-vulpea--after-property-drawer-pos'. Only inserts a newline
if the line immediately before that position isn't already
blank, so re-running a conversion never piles up extra blank
lines."
  (save-excursion
    (goto-char (sia-vulpea--after-property-drawer-pos))
    (unless (or (bobp)
                (save-excursion (forward-line -1) (looking-at "^[ \t]*$")))
      (insert "\n"))))

(defun sia-vulpea--convert-node-properties (&optional keep-original)
  "Convert the node at point's own drawer properties to meta lines.
\"Node at point\" is the heading at or above point, or the
file-level node if point is before the first heading. Only
properties not in `sia-vulpea-convert-property-blocklist', and
with a non-empty value, are converted; the property name is
downcased for the meta key. Unless KEEP-ORIGINAL is non-nil, each
converted property is then deleted from the drawer. If anything
was converted, a blank line is inserted before the meta block
(once, however many properties were converted) to separate it
from the drawer/front matter above -- see
`sia-vulpea--ensure-blank-line-before-meta'. Returns the list of
property names converted (empty if none)."
  (save-excursion
    (unless (org-before-first-heading-p) (org-back-to-heading t))
    (let ((converted nil))
      (dolist (prop (org-entry-properties (point) 'standard))
        (let ((name (car prop)) (value (cdr prop)))
          (unless (or (member (upcase name) sia-vulpea-convert-property-blocklist)
                      (null value)
                      (string-empty-p value))
            (sia-vulpea--insert-or-update-meta-line (downcase name) value)
            (push name converted)
            (unless keep-original (org-entry-delete (point) name)))))
      (when converted
        (sia-vulpea--ensure-blank-line-before-meta))
      (nreverse converted))))

(defun sp-vulpea-convert-properties-at-point (&optional keep-original)
  "Convert the drawer properties of the node at point to meta lines.
With KEEP-ORIGINAL (\\[universal-argument]), keep the properties
in the drawer too, instead of deleting each one as it's
converted."
  (interactive "P")
  (let ((converted (sia-vulpea--convert-node-properties keep-original)))
    (if converted
        (message "Converted: %s" (string-join converted ", "))
      (message "Nothing to convert here (all properties are blocklisted, or there are none)"))))

;;; Whole buffer, and every node in it -----------------------------------

(defun sia-vulpea--node-title ()
  "Return the title of the node at point.
The heading text if inside one, or the file's own #+title:
line (falling back to the filename) at file level -- mirrors
`sia-vulpea--after-property-drawer-pos''s notion of \"node at
point\"."
  (if (org-before-first-heading-p)
      (or (save-excursion
            (goto-char (point-min))
            (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" nil t)
              (string-trim (match-string 1))))
          (file-name-nondirectory (or (buffer-file-name) "")))
    (org-get-heading t t t t)))

(defun sia-vulpea--file-has-convertible-properties-p (file)
  "Non-nil if FILE's raw text contains at least one property-drawer
line whose name isn't in `sia-vulpea-convert-property-blocklist'
and whose value is non-empty.

This is a fast, structure-agnostic text scan -- no `org-mode', no
Vulpea db -- meant only as a pre-filter before the real,
buffer-based conversion. It doesn't require FILE to actually be
visited or parsed as Org, just read as text, which is what makes
it cheap. A false positive here (matching something that isn't
really inside a drawer) just means a file gets opened for
nothing during the real pass, which is harmless -- so the regex
doesn't need to be a perfect drawer parser, only a conservative
one that never produces a false *negative*."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (catch 'found
      (while (re-search-forward
              "^[ \t]*:\\([A-Za-z_][A-Za-z0-9_-]*\\):[ \t]+\\(.+\\)$" nil t)
        (let ((name (match-string 1)) (value (match-string 2)))
          (unless (or (member (upcase name) '("PROPERTIES" "END"))
                      (member (upcase name) sia-vulpea-convert-property-blocklist)
                      (string-empty-p (string-trim value)))
            (throw 'found t))))
      nil)))

(defun sia-vulpea--files-with-convertible-properties ()
  "Return the subset of all Vulpea note files with at least one
convertible property, found via a fast raw-text pre-scan of each
file (see `sia-vulpea--file-has-convertible-properties-p').

This deliberately does NOT go through Vulpea's db -- Vulpea
doesn't expose property-drawer contents through its own note
data, so filtering that way never actually worked (every note
came back with nothing convertible, regardless of what was
really in the file, and no amount of `vulpea-db-sync-full-scan'
would have changed that). This is a pre-filter only: the actual
conversion still re-reads each kept file's live buffer via
`org-entry-properties', which remains the source of truth for
what gets converted."
  (seq-filter #'sia-vulpea--file-has-convertible-properties-p
              (seq-uniq (mapcar #'vulpea-note-path (vulpea-db-query)))))

(defun sia-vulpea--insert-converted-report (nodes)
  "Insert one Org line per (ID . TITLE) in NODES, as a clickable
id: link: \"- [[id:ID][TITLE]]\". Meant for a buffer already in
`org-mode', so the links are actually clickable/`org-open-at-point'-able."
  (dolist (node nodes)
    (insert (format "- [[id:%s][%s]]\n" (car node) (cdr node)))))

(defun sia-vulpea-convert-buffer-properties-to-meta (&optional keep-original)
  "Convert drawer properties to meta lines for every recognized node
in the current buffer -- the file-level node (if it has an :ID:)
and every heading with an :ID:, i.e. every node Vulpea/org-roam
actually indexes here. Saves the buffer afterwards. Returns a
list of (ID . TITLE) for every node that had at least one
property converted (empty if none)."
  (interactive "P")
  (let (converted-nodes)
    (save-excursion
      (goto-char (point-min))
      (when (org-entry-get (point-min) "ID")
        (when (sia-vulpea--convert-node-properties keep-original)
          (push (cons (org-entry-get (point-min) "ID") (sia-vulpea--node-title))
                converted-nodes)))
      (org-map-entries
       (lambda ()
         (when (org-entry-get (point) "ID")
           (when (sia-vulpea--convert-node-properties keep-original)
             (push (cons (org-entry-get (point) "ID") (sia-vulpea--node-title))
                   converted-nodes))))))
    (when (called-interactively-p 'any)
      (message "Converted properties on %d node%s in this buffer"
               (length converted-nodes) (if (= (length converted-nodes) 1) "" "s")))
    (save-buffer)
    (nreverse converted-nodes)))

;;; Non-blocking batch processing, with progress + ETA --------------------

(defun sia-vulpea--format-duration (seconds)
  "Return SECONDS formatted as e.g. \"2m 13s\" or \"45s\"."
  (let* ((secs (max 0 (round seconds)))
         (m (/ secs 60))
         (s (% secs 60)))
    (if (> m 0) (format "%dm %ds" m s) (format "%ds" s))))

(defun sia-vulpea--process-files-async (files per-file-fn label on-done)
  "Call PER-FILE-FN once per file in FILES, one at a time, without
freezing Emacs for the whole run.

Each file is handled, then the *next* one is scheduled via a
fresh zero-second timer instead of just continuing a tight
`dolist' loop -- that gap is what hands control back to Emacs's
command loop between files, so redisplay happens, `C-g' still
works, and the UI doesn't lock up. To be fully transparent about
what this is and isn't: stock Emacs has no threads that run
Elisp concurrently, so nothing here runs \"in the background\"
while you keep typing in another buffer -- it's cooperative
yielding, not true parallelism. (Emacs 26+ built with
`--with-threads' does have `make-thread', but Elisp execution
under it is still serialized by a global lock, so it wouldn't
actually speed this up or free the UI thread the way OS threads
would -- it's not used here.) What you do get is a UI that stays
responsive and interruptible for the whole duration of a large
batch, which a plain loop over hundreds of files would not give
you.

PER-FILE-FN is called with one file path, current-buffer already
that file's buffer (via `find-file-noselect'); its return value
is collected. LABEL is shown alongside a live N/TOTAL count and
an ETA, estimated from the average time per file so far. ON-DONE
is called with the list of all per-file return values, in the
same order as FILES, once every file has been processed."
  (let* ((total (length files))
         (reporter (make-progress-reporter (format "%s " label) 0 total))
         (start-time (current-time))
         (i 0)
         (results nil))
    (cl-labels
        ((step ()
           (if (null files)
               (progn
                 (progress-reporter-done reporter)
                 (funcall on-done (nreverse results)))
             (let ((file (pop files)))
               (push (with-current-buffer (find-file-noselect file)
                       (funcall per-file-fn file))
                     results)
               (setq i (1+ i))
               (progress-reporter-update
                reporter i
                (format " (%d/%d, ETA %s)" i total
                        (sia-vulpea--format-duration
                         (if (zerop i)
                             0
                           (* (/ (float-time (time-subtract (current-time) start-time)) i)
                              (- total i))))))
               (run-with-timer 0 nil #'step)))))
      (step))))

;;; Preview + real run across every Vulpea note ---------------------------

(defun sia-vulpea-preview-convert-all-notes-properties ()
  "Report, without changing anything, what a full conversion would do.
Lists, per note file, which non-blocklisted properties were
found on its recognized nodes. Run this before
`sia-vulpea-convert-all-notes-properties-to-meta' to sanity-check
`sia-vulpea-convert-property-blocklist' first -- nothing here
writes to any file. Runs without freezing Emacs, with a live
progress count and ETA in the echo area -- see
`sia-vulpea--process-files-async'."
  (interactive)
  (let* ((all-files (seq-uniq (mapcar #'vulpea-note-path (vulpea-db-query))))
         (files (sia-vulpea--files-with-convertible-properties)))
    (if (null files)
        (message "Nothing would be converted -- no notes have any non-blocklisted properties.")
      (message "Pre-filter (raw-text scan): scanning %d of %d note file%s."
                (length files) (length all-files) (if (= (length all-files) 1) "" "s"))
      (sia-vulpea--process-files-async
       files
     (lambda (file)
       (save-excursion
         (let (found)
           (goto-char (point-min))
           (when (org-entry-get (point-min) "ID")
             (dolist (p (org-entry-properties (point-min) 'standard))
               (unless (member (upcase (car p)) sia-vulpea-convert-property-blocklist)
                 (push (car p) found))))
           (org-map-entries
            (lambda ()
              (when (org-entry-get (point) "ID")
                (dolist (p (org-entry-properties (point) 'standard))
                  (unless (member (upcase (car p)) sia-vulpea-convert-property-blocklist)
                    (push (car p) found))))))
           (when found
             (format "%s: %s" (file-name-nondirectory file)
                     (string-join (seq-uniq found) ", "))))))
     "Previewing property conversion"
     (lambda (results)
       (let ((report (delq nil results)))
         (if report
             (with-current-buffer (get-buffer-create "*vulpea property conversion preview*")
               (erase-buffer)
               (insert (string-join report "\n"))
               (goto-char (point-min))
               (display-buffer (current-buffer)))
           (message "Nothing would be converted -- every property found is blocklisted."))))))))

(defun sia-vulpea-convert-all-notes-properties-to-meta (&optional keep-original)
  "Convert drawer properties to meta lines across every Vulpea note.
Runs `sia-vulpea-convert-buffer-properties-to-meta' over every
file a fast raw-text pre-scan finds has something convertible
(see `sia-vulpea--files-with-convertible-properties' -- files
with nothing to do are never opened as Org buffers), saving each
one. This edits and saves potentially a large part of your note
collection -- run `sia-vulpea-preview-convert-all-notes-properties'
first, and back up your notes (or commit, if under version
control) before running this, especially with KEEP-ORIGINAL nil
(the default), which deletes each converted property from its
drawer as it goes. Runs without freezing Emacs, with a live
progress count and ETA in the echo area -- see
`sia-vulpea--process-files-async'.

When finished, opens a report buffer (in `org-mode', so the
links are clickable via `org-open-at-point') listing every
converted node as a \"- [[id:...][Title]]\" line -- see
`sia-vulpea--insert-converted-report'."
  (interactive "P")
  (unless (y-or-n-p "This will edit and save every Vulpea note. Continue? ")
    (user-error "Aborted"))
  (let* ((all-files (seq-uniq (mapcar #'vulpea-note-path (vulpea-db-query))))
         (files (sia-vulpea--files-with-convertible-properties)))
    (if (null files)
        (message "Nothing to convert -- no notes have any non-blocklisted properties.")
      (message "Pre-filter (raw-text scan): converting %d of %d note file%s."
                (length files) (length all-files) (if (= (length all-files) 1) "" "s"))
      (sia-vulpea--process-files-async
       files
       (lambda (_file) (sia-vulpea-convert-buffer-properties-to-meta keep-original))
       "Converting properties"
       (lambda (results)
         (let* ((converted-nodes (apply #'append results))
                (total (length converted-nodes))
                (file-count (length (seq-remove #'null results))))
           (message "Converted properties on %d node%s across %d note file%s"
                     total (if (= total 1) "" "s")
                     file-count (if (= file-count 1) "" "s"))
           (with-current-buffer (get-buffer-create "*vulpea property conversion report*")
             (erase-buffer)
             (org-mode)
             (insert (format "* Converted %d node%s\n\n"
                              total (if (= total 1) "" "s")))
             (sia-vulpea--insert-converted-report converted-nodes)
             (goto-char (point-min))
             (display-buffer (current-buffer)))))))))

(keymap-global-set "C-c w c" #'sp-vulpea-convert-properties-at-point)

(provide 'sp-vulpea-convert-properties)
;;; sp-vulpea-convert-properties.el ends here
