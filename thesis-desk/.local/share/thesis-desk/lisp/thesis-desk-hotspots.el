;;; thesis-desk-hotspots.el --- Concepts your see-also notes keep calling for -*- lexical-binding: t; -*-

;;; Commentary:

;; A /hotspot/ is a concept that many see-also notes point at (footnotes,
;; "See also" sections, `seealso ::' lines, as `sp-see-also' reads them).
;; Each of those notes is a small call to come back to the concept; when many
;; pile up, the concept needs a /synthesis/: a note of its own on the state of
;; research on that problem, written by you.
;;
;; `thesis-desk-hotspots' ranks the concepts by the calls that no synthesis
;; has addressed yet.  RET visits the synthesis (or the concept, when there is
;; none); A creates a synthesis note for every entry not dropped.  In a
;; synthesis note, `thesis-desk-synthesis-mark-addressed' records that the
;; calls listed now are answered, so only newer ones count afterwards.
;;
;; The mentions come from `thesis-desk-mentions-function' (set by
;; `thesis-desk-sp' to the `sp-see-also' index).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)
(require 'thesis-desk-views)

(declare-function thesis-desk-file "thesis-desk")

(defcustom thesis-desk-mentions-function nil
  "Function of no arguments returning a hash table: concept ID to its mentions.
A mention is a plist with at least :file and :snippet, and may have
:litnote-id, :litnote-title, :desc, :where (prose, quote, section) and
:open (non-nil under an open question)."
  :type '(choice (const nil) function) :group 'thesis-desk)

(defcustom thesis-desk-concept-title-function nil
  "Function of (ID MENTIONS) giving a concept's title; nil uses the link text."
  :type '(choice (const nil) function) :group 'thesis-desk)

(defcustom thesis-desk-hotspot-min-calls 3
  "Unaddressed calls a concept needs to be listed as a hotspot."
  :type 'integer :group 'thesis-desk)

(defcustom thesis-desk-hotspot-where-weights '((prose . 1.0) (quote . 2.0) (section . 1.5))
  "Weight of a call by where it was written.
Quotes count more: the concept is not yet in your own words."
  :type '(alist :key-type symbol :value-type number) :group 'thesis-desk)

(defcustom thesis-desk-hotspot-open-weight 1.0
  "Added to the weight of a call written under an open research question."
  :type 'number :group 'thesis-desk)

(defcustom thesis-desk-synthesis-directory "~/notes/synthesis/"
  "Folder of the synthesis notes, one per concept."
  :type 'directory :group 'thesis-desk)

(defcustom thesis-desk-synthesis-tags '("synthesis" "thesis")
  "File tags of a new synthesis note."
  :type '(repeat string) :group 'thesis-desk)

;;;; Which calls are addressed

(defun thesis-desk--state-file ()
  "File that remembers the calls each synthesis addressed."
  (thesis-desk-file "synthesis-state.eld"))

(defun thesis-desk--state-read ()
  "The addressed calls: an alist of (CONCEPT-ID . KEYS)."
  (let ((file (thesis-desk--state-file)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (condition-case nil (read (current-buffer)) (error nil))))))

(defun thesis-desk--state-write (state)
  "Save STATE, an alist of (CONCEPT-ID . KEYS)."
  (let ((file (thesis-desk--state-file)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert ";; Calls (see-also mentions) that a synthesis note has addressed.\n"
              ";; Written by thesis-desk-synthesis-mark-addressed.  -*- mode: lisp-data -*-\n")
      (pp state (current-buffer)))))

(defun thesis-desk-mention-key (mention)
  "A stable key for MENTION: the note it is in and a hash of its text."
  (format "%s|%s"
          (or (plist-get mention :litnote-id) (plist-get mention :file))
          (substring (sha1 (or (plist-get mention :snippet) "")) 0 12)))

;;;; Ranking

(defun thesis-desk-mention-weight (mention)
  "Weight of MENTION: where it was written, plus its open question."
  (+ (or (alist-get (plist-get mention :where) thesis-desk-hotspot-where-weights) 1.0)
     (if (plist-get mention :open) thesis-desk-hotspot-open-weight 0)))

(defun thesis-desk--concept-title (id mentions)
  "Title of concept ID, from the title function or the commonest link text."
  (or (and thesis-desk-concept-title-function
           (ignore-errors (funcall thesis-desk-concept-title-function id mentions)))
      (car (car (sort (let (counts)
                        (dolist (m mentions)
                          (when-let* ((d (plist-get m :desc)))
                            (let ((cell (assoc d counts)))
                              (if cell (setcdr cell (1+ (cdr cell))) (push (cons d 1) counts)))))
                        counts)
                      (lambda (a b) (> (cdr a) (cdr b))))))
      id))

(defun thesis-desk-hotspots-rank (table state &optional min)
  "Rank the concepts of TABLE (ID to mentions) by calls not in STATE.
STATE is an alist (ID . addressed keys).  Keep concepts with at least MIN
unaddressed calls (default `thesis-desk-hotspot-min-calls').  Return plists
with :id :title :mentions :new :total :litnotes :open :quotes :score."
  (let ((min (or min thesis-desk-hotspot-min-calls))
        result)
    (maphash
     (lambda (id mentions)
       (let* ((done (cdr (assoc id state)))
              (new (seq-remove (lambda (m) (member (thesis-desk-mention-key m) done)) mentions))
              (litnotes (length (delete-dups
                                 (mapcar (lambda (m) (or (plist-get m :litnote-id) (plist-get m :file)))
                                         new)))))
         (when (>= (length new) min)
           (push (list :id id
                       :title (thesis-desk--concept-title id mentions)
                       :mentions mentions :new new
                       :total (length mentions)
                       :litnotes litnotes
                       :open (seq-count (lambda (m) (plist-get m :open)) new)
                       :quotes (seq-count (lambda (m) (eq (plist-get m :where) 'quote)) new)
                       :addressed (and done t)
                       :score (* (apply #'+ (mapcar #'thesis-desk-mention-weight new))
                                 (1+ (log (1+ litnotes)))))
                 result))))
     table)
    (sort result (lambda (a b) (> (plist-get a :score) (plist-get b :score))))))

;;;; Synthesis notes

(defun thesis-desk-synthesis-file (concept-id)
  "The synthesis note of CONCEPT-ID, or nil."
  (let ((dir (expand-file-name thesis-desk-synthesis-directory))
        (needle (format ":THESIS_SYNTHESIS_OF: %s" concept-id)))
    (when (file-directory-p dir)
      (seq-find (lambda (file)
                  (with-temp-buffer
                    (insert-file-contents file nil 0 2000)
                    (search-forward needle nil t)))
                (directory-files dir t "\\`[^.].*\\.org\\'")))))

(defun thesis-desk--slug (title)
  "A file name part made from TITLE."
  (let ((s (downcase (replace-regexp-in-string "[^[:alnum:]]+" "-" (string-trim title)))))
    (string-trim (truncate-string-to-width s 60) "-" "-")))

(defun thesis-desk-synthesis-text (concept-id title id)
  "The text of a new synthesis note with ID on CONCEPT-ID called TITLE."
  (concat ":PROPERTIES:\n:ID:       " id "\n:THESIS_SYNTHESIS_OF: " concept-id "\n:END:\n"
          "#+title: State of research: " title "\n"
          "#+filetags: :" (string-join thesis-desk-synthesis-tags ":") ":\n\n"
          "- parents :: " (org-link-make-string (concat "id:" concept-id) title) "\n\n"
          "* The calls\n"
          "Every see-also note that points at the concept (refresh with C-c C-c).\n"
          "When this note answers them, run thesis-desk-synthesis-mark-addressed.\n\n"
          "#+BEGIN: concept-usage :id \"" concept-id "\"\n#+END:\n\n"
          "* Positions\n\n* My account\n\n* Open problems\n"))

(defun thesis-desk-synthesis-create (concept-id title)
  "Create the synthesis note of CONCEPT-ID called TITLE unless it exists.
Return its file."
  (or (thesis-desk-synthesis-file concept-id)
      (let* ((dir (expand-file-name thesis-desk-synthesis-directory))
             (file (expand-file-name (concat "state-of-research-" (thesis-desk--slug title) ".org") dir))
             (n 1))
        (make-directory dir t)
        (while (file-exists-p file)
          (setq n (1+ n)
                file (expand-file-name (format "state-of-research-%s-%d.org" (thesis-desk--slug title) n) dir)))
        (with-temp-file file
          (insert (thesis-desk-synthesis-text concept-id title (org-id-new))))
        file)))

(defun thesis-desk--mentions-table ()
  "The concept to mentions table, or an error saying how to get one."
  (unless thesis-desk-mentions-function
    (user-error "No see-also index: load thesis-desk-sp with sp-see-also, or set `thesis-desk-mentions-function'"))
  (funcall thesis-desk-mentions-function))

;;;###autoload
(defun thesis-desk-synthesis-mark-addressed (&optional concept-id)
  "Record that the synthesis of CONCEPT-ID answers every call there is now.
In a synthesis note, CONCEPT-ID is read from its THESIS_SYNTHESIS_OF."
  (interactive)
  (let* ((id (or concept-id
                 (save-excursion
                   (goto-char (point-min))
                   (and (re-search-forward "^:THESIS_SYNTHESIS_OF:[ \t]+\\(\\S-+\\)" nil t)
                        (match-string-no-properties 1)))
                 (user-error "Not in a synthesis note")))
         (mentions (gethash id (thesis-desk--mentions-table)))
         (state (thesis-desk--state-read))
         (keys (delete-dups (append (cdr (assoc id state))
                                    (mapcar #'thesis-desk-mention-key mentions)))))
    (setf (alist-get id state nil nil #'equal) keys)
    (thesis-desk--state-write state)
    (message "%d calls marked as addressed" (length mentions))))

;;;; The report

(defun thesis-desk-hotspot-item (spot)
  "A report item for the hotspot SPOT."
  (let* ((id (plist-get spot :id))
         (synthesis (thesis-desk-synthesis-file id)))
    (list :key id
          :file (or synthesis (ignore-errors (org-id-find-id-file id)))
          :label (plist-get spot :title)
          :text (format "%d new calls of %d, in %d notes; %d under open questions, %d in quotes%s"
                        (length (plist-get spot :new)) (plist-get spot :total)
                        (plist-get spot :litnotes) (plist-get spot :open) (plist-get spot :quotes)
                        (if synthesis "" "; no synthesis yet"))
          :children (mapcar (lambda (m)
                              (format "%s: %s" (or (plist-get m :litnote-title)
                                                   (file-name-base (plist-get m :file)))
                                      (truncate-string-to-width
                                       (or (plist-get m :snippet) "") 100 nil nil "…")))
                            (seq-take (sort (copy-sequence (plist-get spot :new))
                                            (lambda (a b) (> (thesis-desk-mention-weight a)
                                                             (thesis-desk-mention-weight b))))
                                      3)))))

(defun thesis-desk-hotspot-sections (spots)
  "Report sections for SPOTS.
Concepts with no synthesis come first, then those with new calls."
  (let (none stale)
    (dolist (spot spots)
      (if (thesis-desk-synthesis-file (plist-get spot :id))
          (push (thesis-desk-hotspot-item spot) stale)
        (push (thesis-desk-hotspot-item spot) none)))
    (list (list :title "No synthesis yet" :items (nreverse none)
                :empty "every hotspot has a synthesis note")
          (list :title "New calls since the synthesis" :items (nreverse stale)
                :empty "no synthesis is behind"))))

(defvar thesis-desk--hotspots nil
  "The hotspots last listed, for the apply step.")

;;;###autoload
(defun thesis-desk-hotspots ()
  "List the concepts that many see-also notes call for, most pressing first.
RET visits the synthesis note (or the concept); d drops an entry; A creates
a synthesis note for every entry left."
  (interactive)
  (let ((spots (thesis-desk-hotspots-rank (thesis-desk--mentions-table)
                                          (thesis-desk--state-read))))
    (setq thesis-desk--hotspots spots)
    (thesis-desk-report
     "*thesis-desk: hotspots*" "Concepts that need a synthesis"
     (thesis-desk-hotspot-sections spots)
     :intro (format "%d concepts with at least %d see-also calls that no synthesis addresses yet."
                    (length spots) thesis-desk-hotspot-min-calls)
     :refresh #'thesis-desk-hotspots
     :apply #'thesis-desk-hotspots-apply)))

(defun thesis-desk-hotspots-apply (&optional excluded)
  "Create a synthesis note for every listed hotspot whose ID is not in EXCLUDED."
  (let ((made 0))
    (dolist (spot thesis-desk--hotspots)
      (unless (or (member (plist-get spot :id) excluded)
                  (thesis-desk-synthesis-file (plist-get spot :id)))
        (thesis-desk-synthesis-create (plist-get spot :id) (plist-get spot :title))
        (setq made (1+ made))))
    (message "%d synthesis notes created in %s" made thesis-desk-synthesis-directory)
    (thesis-desk-hotspots)))

(provide 'thesis-desk-hotspots)
;;; thesis-desk-hotspots.el ends here
