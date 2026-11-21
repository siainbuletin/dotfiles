;;; thesis-desk-map.el --- The thesis map: claims and questions -*- lexical-binding: t; -*-

;;; Commentary:

;; The map is the spine everything else points at: headings with an :ID: and
;; a :DG_TYPE: of claim or question (the names the relationship annotator
;; reads).  Claims can also live in your notes; `thesis-desk-claim-sources'
;; lists the functions that collect them, and `thesis-desk-sp' adds the
;; Vulpea notes with a DG_TYPE.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)

(declare-function thesis-desk-file "thesis-desk")
(defvar thesis-desk-map-file)

(defcustom thesis-desk-claim-types '("claim" "question")
  "DG_TYPE values that count as something a reading can be for."
  :type '(repeat string) :group 'thesis-desk)

(defcustom thesis-desk-claim-sources (list #'thesis-desk-map-claims)
  "Functions of no arguments, each returning claims as plists.
A claim plist has :id, :title and :type.  The lists are joined and
duplicates (same :id) dropped, first source first."
  :type '(repeat function) :group 'thesis-desk)

(defconst thesis-desk-map--skeleton
  "#+title: Thesis map
#+todo: CLAIM QUESTION | ARGUED ANSWERED DROPPED

# One heading per claim (a sentence you would defend in the text) or open
# question, each with an :ID: and a :DG_TYPE:.  Order the headings in the
# order of the argument.  Notes elsewhere with a DG_TYPE count too.

* Chapter 1
"
  "Contents of a new map file.")

(defun thesis-desk-map-path ()
  "The map file."
  (thesis-desk-file thesis-desk-map-file))

(defun thesis-desk-map-claims-in-buffer ()
  "The claims of the current Org buffer: headings with an ID and a claim DG_TYPE."
  (let (claims)
    (org-with-wide-buffer
     (goto-char (point-min))
     (while (re-search-forward org-heading-regexp nil t)
       (let ((id (org-entry-get (point) "ID"))
             (type (org-entry-get (point) "DG_TYPE")))
         (when (and id type (member (downcase type) thesis-desk-claim-types))
           (push (list :id id
                       :title (org-get-heading t t t t)
                       :type (downcase type)
                       :file (buffer-file-name))
                 claims)))))
    (nreverse claims)))

(defun thesis-desk-map-claims ()
  "The claims of the map file, or nil when it does not exist yet."
  (let ((file (thesis-desk-map-path)))
    (when (file-exists-p file)
      (with-current-buffer (find-file-noselect file)
        (thesis-desk-map-claims-in-buffer)))))

(defun thesis-desk-claims ()
  "All claims, from every function in `thesis-desk-claim-sources'."
  (let ((seen (make-hash-table :test #'equal))
        claims)
    (dolist (source thesis-desk-claim-sources)
      (dolist (claim (condition-case err
                         (funcall source)
                       (error (message "[thesis-desk] %s failed: %s"
                                       source (error-message-string err))
                              nil)))
        (unless (gethash (plist-get claim :id) seen)
          (puthash (plist-get claim :id) t seen)
          (push claim claims))))
    (nreverse claims)))

(defun thesis-desk-claim-title (id &optional claims)
  "The title of claim ID among CLAIMS (default all), or ID itself."
  (or (plist-get (seq-find (lambda (c) (equal (plist-get c :id) id))
                           (or claims (thesis-desk-claims)))
                 :title)
      id))

(defun thesis-desk-claim-candidates (claims)
  "An alist of (LABEL . ID) for completing over CLAIMS; labels are unique."
  (let ((seen (make-hash-table :test #'equal))
        result)
    (dolist (claim claims)
      (let* ((base (format "%s [%s]" (plist-get claim :title)
                           (substring (plist-get claim :type) 0 1)))
             (label base)
             (n 1))
        (while (gethash label seen)
          (setq n (1+ n) label (format "%s <%d>" base n)))
        (puthash label t seen)
        (push (cons label (plist-get claim :id)) result)))
    (nreverse result)))

(defun thesis-desk-read-claims (&optional prompt initial-ids)
  "Ask for any number of claims with PROMPT; return their IDs.
INITIAL-IDS are offered as the default.  An empty answer means none."
  (let* ((claims (thesis-desk-claims))
         (cands (thesis-desk-claim-candidates claims))
         (default (string-join
                   (delq nil (mapcar (lambda (id) (car (rassoc id cands))) initial-ids))
                   ","))
         (answer (completing-read-multiple
                  (or prompt "Claims (comma separated, empty for none): ")
                  cands nil t nil nil (unless (string-empty-p default) default))))
    (delq nil (mapcar (lambda (label) (cdr (assoc label cands))) answer))))

;;;###autoload
(defun thesis-desk-map-visit ()
  "Open the thesis map, creating it from a skeleton when missing."
  (interactive)
  (let ((file (thesis-desk-map-path)))
    (unless (file-exists-p file)
      (make-directory (file-name-directory file) t)
      (with-temp-file file (insert thesis-desk-map--skeleton)))
    (find-file file)))

(provide 'thesis-desk-map)
;;; thesis-desk-map.el ends here
