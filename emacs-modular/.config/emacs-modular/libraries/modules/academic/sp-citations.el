;;; sp-citations.el --- Citations with org-cite, CSL and Citar -*- lexical-binding: t; -*-

;;; Commentary:

;; This module configures citation handling: Org's built-in `oc' citation
;; framework, CSL-based export through `oc-csl' and the `citeproc' library, and
;; `citar' as the interactive front end for inserting, following and acting on
;; citations. It is required from `sp-academic'.

;;; Code:

(require 'oc-natbib)
;; (require 'oc-csl) -- this is already declared with use-package and all the settings

;;;; Org-Cite
;; built-in package -- set up proper configuration
(use-package oc
  :ensure nil
  :after org

  :custom
  (org-cite-export-processors
        '((beamer csl)
          (latex csl)
          (t csl)))
  (org-cite-global-bibliography sp-bibtex-files)
  (org-cite-insert-processor 'citar)
  (org-cite-follow-processor 'citar)
  (org-cite-activate-processor 'citar)
)

;; Use csl
;; needs to have CSL installed on the system
(use-package oc-csl
  :ensure nil
  :defer t  ;; Defer loading until actually needed
  :commands (org-cite-csl-activate
             org-cite-csl-render-bibliography
             org-cite-csl-render-item)
  :init
  ;; Set these variables early so they're available when needed
  (with-eval-after-load 'oc
    (setq org-cite-csl-styles-dir (sp-path sp-data-home "csl/styles"))
    (setq org-cite-csl-locales-dir (sp-path sp-data-home "csl/locales"))))

;;;; Citeproc
(use-package citeproc
  :ensure t
  :defer t  ;; Defer loading until oc-csl needs it
  :after oc)

;;;; Citar library lookup
;; A `file' field names the PDF where BibDesk, or an earlier layout, put it.
;; When it is not there, look it up by name below the library.
(require 'ucs-normalize)

(defcustom sp-citations-library-index-ttl 60
  "Seconds the index of `sp-literature-dir' is kept before a missing file rebuilds it."
  :type 'integer
  :group 'sp)

(defvar sp-citations--library-index nil
  "Cons of the time and a table of file name to the paths below `sp-literature-dir'.")

(defun sp-citations--library-index (&optional rebuild)
  "Return the table of file names below `sp-literature-dir', built when REBUILD or nil.
Keys are the lower-case file names; values are lists of absolute paths.
Hidden folders and the backup folder are skipped."
  (when (or rebuild (null sp-citations--library-index))
    (let ((table (make-hash-table :test #'equal))
          (backup (and (boundp 'sia-citar-library-backup-path)
                       (file-name-as-directory
                        (expand-file-name sia-citar-library-backup-path)))))
      (when (and (stringp sp-literature-dir) (file-directory-p sp-literature-dir))
        (dolist (file (directory-files-recursively
                       sp-literature-dir "" nil
                       (lambda (dir)
                         (not (or (string-prefix-p "." (file-name-nondirectory dir))
                                  (equal (file-name-as-directory dir) backup))))))
          (let ((base (file-name-nondirectory file)))
            (unless (string-prefix-p "." base)
              (push file (gethash (downcase (ucs-normalize-NFC-string base)) table))))))
      (setq sp-citations--library-index (cons (float-time) table))))
  (cdr sp-citations--library-index))

(defun sp-citations--find-in-library (name)
  "Return the files below `sp-literature-dir' named like the path NAME.
The folders of NAME are ignored; the index is rebuilt once when it is older
than `sp-citations-library-index-ttl' and has no match."
  (let ((key (downcase (ucs-normalize-NFC-string (file-name-nondirectory name)))))
    (or (gethash key (sp-citations--library-index))
        (when (> (- (float-time) (car sp-citations--library-index))
                 sp-citations-library-index-ttl)
          (gethash key (sp-citations--library-index t))))))

(defun sp-citations-parser-library (fieldvalue)
  "Parse the `file' field FIELDVALUE; find the files that are not where it says.
For `citar-file-parser-functions'.  Each name the default parsers give that
does not exist, as an absolute path or relative to `sp-literature-dir', is
searched by its file name below `sp-literature-dir'.  Names that exist are
left to the other parsers, so this returns only the files it found."
  (let (found)
    (dolist (parser '(citar-file--parser-default citar-file--parser-triplet))
      (when (fboundp parser)
        (dolist (name (funcall parser fieldvalue))
          (unless (file-exists-p (expand-file-name name sp-literature-dir))
            (setq found (append found (sp-citations--find-in-library name)))))))
    (delete-dups found)))

;;;; Citar faces
;; The citekey column of the candidates.
(defface sp-citar-key
  '((t :inherit shadow :slant italic))
  "Face of the citekey column in `citar' candidates."
  :group 'sp)

;;;; Citar indicators
;; The four marks before a candidate: link, file, note and cited.  Each is an emoji of
;; `sp-citations-indicator-cell' columns, with no padding between them; a mark that is
;; absent is a blank of the same width.
(defvar citar--entries)

(defconst sp-citations-indicator-cell 2
  "Columns of one indicator, the width of an emoji.")

(defun sp-citations--indicator-block-width ()
  "Columns taken by the indicators of `citar-indicators', and one more to separate them."
  (1+ (* sp-citations-indicator-cell (length citar-indicators))))

(defun sp-citations-setup-indicators ()
  "Set `citar-indicators' to the link, file, note and cited emoji."
  (cl-flet ((indicator (symbol function tag)
              (citar-indicator-create
               :symbol symbol :padding ""
               :emptysymbol (propertize (make-string sp-citations-indicator-cell ?\s)
                                        'display `(space :width ,sp-citations-indicator-cell))
               :function function :tag tag)))
    (setq citar-indicators
          (list (indicator "\U0001F33F️" #'citar-has-links "has:links")   ; link
                (indicator "\U0001F4C1️" #'citar-has-files "has:files")   ; file
                (indicator "\U0001F4DD️" #'citar-has-notes "has:notes")   ; note
                (indicator "\U0001F393️" #'citar-is-cited "is:cited")))))  ; cited

(defun sp-citations--indicator-symbols (candidate)
  "Return the indicators of CANDIDATE, ended by a space that reaches the block width.
Replaces `citar--make-indicator-symbols'.  Its padding is the last character of each
indicator, so it cannot be empty; here the one space after the last indicator is
stretched to a fixed column, whatever the width the emoji is drawn with."
  (concat (mapconcat
           (lambda (indicator)
             (if (string-match-p (citar-indicator-tag indicator) candidate)
                 (citar-indicator-symbol indicator)
               (citar-indicator-emptysymbol indicator)))
           citar-indicators "")
          (propertize " " 'display
                      `(space :align-to ,(sp-citations--indicator-block-width)))))

;;;; Citar candidate widths
;; `citar' gives every `*' column of the template an equal share of the frame width, so a
;; short column leaves blanks and a long one is cut.  Here the columns are sized from
;; the entries themselves, to the width of the posframe, not of the frame, and each
;; starts at a fixed column, so they line up whatever the font.
(defcustom sp-citations-candidate-margin 2
  "Columns kept free at the right of the `citar' candidates."
  :type 'integer
  :group 'sp)

(defcustom sp-citations-column-priorities '(2 2 1 1 3)
  "Priority of each `*' column of `citar-templates', in order: lower comes first.
The columns of one priority share what the lower priorities left.  The default
matches the template: title and authors 2, year and citekey 1, tags 3."
  :type '(repeat integer)
  :group 'sp)

(defun sp-citations--candidate-width ()
  "Return the columns a `citar' candidate may fill.
That is the share of the frame the posframe takes while `vertico-posframe-mode'
is on in a graphical frame, and the width of the frame otherwise."
  (if (and (bound-and-true-p vertico-posframe-mode)
           (boundp 'sp-posframe-width-fraction)
           (display-graphic-p))
      (round (* sp-posframe-width-fraction (frame-width)))
    (frame-width)))

(defun sp-citations--fit-widths (naturals room &optional priorities)
  "Return a list of column widths that fit ROOM, from the NATURALS widths.
The columns of the lowest PRIORITIES number are served first, and the next ones
get what is left.  In one priority, every column narrower than an equal share
keeps its full width, and the others share the rest equally, the widest taking
the remainder.  PRIORITIES is ignored unless it has one number per column."
  (let* ((count (length naturals))
         (priorities (if (= (length priorities) count) priorities (make-list count 1)))
         (widths (make-vector count 0))
         (left (max 0 room)))
    (dolist (tier (sort (delete-dups (copy-sequence priorities)) #'<))
      (let* ((members (cl-loop for index below count
                               when (= (nth index priorities) tier) collect index))
             (remaining (length members)))
        (dolist (index (sort members (lambda (a b) (< (nth a naturals) (nth b naturals)))))
          (let ((width (min (nth index naturals) (/ left remaining))))
            (aset widths index width)
            (setq left (- left width)
                  remaining (1- remaining))))))
    (append widths nil)))

(defun sp-citations--assemble (strings widths start)
  "Join the preformatted STRINGS of a candidate, giving each column its WIDTHS.
STRINGS alternates fixed text and column values, as `citar-format--preformat'
returns it.  The text before each column after the first is a space stretched
to the column where that column starts, counting from START, the column of the
first one; so the columns line up in any font.  A column of width 0 is left out
with the text before it."
  (let ((out (or (car strings) ""))
        (position (+ start (string-width (or (car strings) ""))))
        (previous nil))
    (cl-loop for (value following) on (cdr strings) by #'cddr
             for width in widths
             do (when (> width 0)
                  (when previous
                    (setq out (concat out (propertize previous 'display
                                                      `(space :align-to ,position)))))
                  (setq out (concat out (citar-format--string
                                         value :width (min width (string-width value))
                                         :hide-elided t :ellipsis citar-ellipsis))
                        position (+ position width (string-width (or following "")))))
                (setq previous following))
    (concat out previous)))

(defun sp-citations--format-candidates (original)
  "Format the `citar' candidates with widths fitted to their content.
Around advice of `citar--format-candidates', which is ORIGINAL; it is used
when the templates have no `*' column."
  (let* ((bibs (citar--bibliographies))
         (preformatted (and bibs (citar-cache--preformatted bibs)))
         (sample nil)
         (naturals nil))
    (when preformatted
      (maphash
       (lambda (_key preform)
         (let ((values (cl-loop for (value) on (cddr preform) by #'cddr
                                collect (string-width value))))
           (setq sample (or sample preform)
                 naturals (if naturals (cl-mapcar #'max naturals values) values))))
       preformatted))
    (if (null naturals)
        (funcall original)
      (let* ((citar--entries (citar-cache--entries bibs))
             (indicatorprocs (citar--make-indicator-processors citar-indicators))
             (base (sp-citations--indicator-block-width))
             (strings (cdr sample))
             ;; The text before an empty column is left out, but not before the first.
             (dropped (cl-loop for width in naturals
                               for (text) on strings by #'cddr
                               for first = t then nil
                               when (and (= width 0) (not first))
                               sum (string-width text)))
             (room (- (sp-citations--candidate-width) base
                      sp-citations-candidate-margin (- (car sample) dropped)))
             (widths (sp-citations--fit-widths naturals room sp-citations-column-priorities))
             (completions (make-hash-table :test 'equal
                                           :size (hash-table-count citar--entries))))
        (prog1 completions
          (maphash
           (lambda (citekey _entry)
             (let ((preform (or (gethash citekey preformatted)
                                (error "No preformatted candidate string: %s" citekey))))
               (puthash (concat (sp-citations--assemble (cdr preform) widths base)
                                (citar--make-indicator-tags citekey indicatorprocs))
                        citekey completions)))
           citar--entries))))))

;;;; Citar
;; Do you really need to make use of citar?
(use-package citar
  :ensure t
  :commands (citar-open-notes
             citar-insert-citation)
  
  :custom
  ;; Use with org citation
  (org-cite-global-bibliography sp-bibtex-files)
  (citar-bibliography sp-bibtex-files)

  ;; Library and notes
  (citar-library-paths (list sp-literature-dir))
  (citar-library-file-extensions '("pdf" "jpg"))
  (citar-file-additional-files-separator "-")
  (citar-notes-paths (list (or sp-bib-notes sp-notes-dir)))
  
  ;; Working at point
  (citar-at-point-function 'embark-act) ;; use embark with at-point

  (citar-additional-fields 
    '("doi"
      "url"))   ;; What exactly can you do with these additional fields?

  (citar-templates
        `((main . "${title:*}   ${author editor:*}   ${year issued date:*}")
          (suffix . ,(concat "   "
                             (propertize "${=key= id:*}" 'face 'sp-citar-key)
                             "   ${tags keywords:*}"))
          (preview . "${author editor} (${year issued date}) ${title}, ${journal journaltitle publisher container-title collection-title}.\n")
          (note . ,sp-citar-note)))

  :config
  ;; Find a PDF that is not where its `file' field says.
  (add-to-list 'citar-file-parser-functions #'sp-citations-parser-library t)
  (sp-citations-setup-indicators)
  (advice-add 'citar--make-indicator-symbols :override #'sp-citations--indicator-symbols)
  (advice-add 'citar--format-candidates :around #'sp-citations--format-candidates)

  :bind
         (("C-c w b o" . citar-open))
         (:map org-mode-map :package org ("C-c b" . #'org-cite-insert))
         
         :hook
         (LaTeX-mode . citar-capf-setup)
         (org-mode . citar-capf-setup)
         (markdown-mode . citar-capf-setup)
)

;; Acting on citations (and jumping across the files better)
(use-package citar-embark
  :ensure t
  :after (citar embark)
  :no-require
  :config (citar-embark-mode)
  )

;;;; Citation hover
;; Show the formatted reference of the citation under the mouse or point.
(defcustom sp-cite-hover-display '(tooltip echo)
  "Where to show the reference of the `[cite:@key]' link under the mouse or point.
`tooltip' sets the `help-echo' of the link, shown when the mouse hovers over
it.  `echo' adds an Eldoc function, which shows the reference in the echo area
when point is on the link.  Set it to nil to turn both off."
  :type '(set (const :tag "Tooltip on mouse hover" tooltip)
              (const :tag "Echo area when point is on the link" echo))
  :group 'sp)

(defconst sp-cite-hover--link-regexp
  "\\[cite\\(?:/[-_/[:alnum:]]*\\)?:[^]]*\\]"
  "Regexp matching an Org citation such as `[cite/t:see @key1; @key2 p. 3]'.")

(defconst sp-cite-hover--key-regexp
  "@\\([-.:?!`'/*@+|(){}<>&_^$#%~[:alnum:]]+\\)"
  "Regexp matching a citation key, with the key itself in group 1.")

(defun sp-cite-hover--key-at (pos)
  "Return the citation key at POS, or the first key of the citation around it.
Return nil when POS is not inside a `[cite:]' link."
  (save-excursion
    (goto-char pos)
    (let ((line-start (line-beginning-position))
          (line-end (line-end-position))
          found)
      (while (and (not found)
                  (re-search-backward "\\[cite" line-start t))
        (when (and (looking-at sp-cite-hover--link-regexp)
                   (<= pos (match-end 0)))
          (setq found (cons (match-beginning 0) (match-end 0)))))
      (when found
        (goto-char (car found))
        (let (first at-pos)
          (while (and (not at-pos)
                      (re-search-forward sp-cite-hover--key-regexp
                                         (min (cdr found) line-end) t))
            (unless first (setq first (match-string-no-properties 1)))
            (when (and (<= (match-beginning 0) pos) (<= pos (match-end 0)))
              (setq at-pos (match-string-no-properties 1))))
          (or at-pos first))))))

(defun sp-cite-hover--reference (key)
  "Return the formatted reference of KEY from the bibliography, or nil.
It uses `citar-format-reference', which applies the `preview' template of
`citar-templates'.  Any error from citar gives nil, so a hover never breaks."
  (when (and key (require 'citar nil t) (fboundp 'citar-format-reference))
    (and-let* ((entry (ignore-errors (citar-get-entry key)))
               (text (ignore-errors (citar-format-reference (list key))))
               ((stringp text))
               (text (string-trim (substring-no-properties text)))
               ((not (string-empty-p text))))
      text)))

(defun sp-cite-hover--help-echo (_window object pos)
  "Return the reference of the citation at POS in OBJECT for `help-echo'."
  (when (and (memq 'tooltip sp-cite-hover-display) (bufferp object))
    (with-current-buffer object
      (when-let* ((key (sp-cite-hover--key-at pos)))
        (or (sp-cite-hover--reference key)
            (format "@%s: not found in the bibliography" key))))))

(defun sp-cite-hover--fontify (limit)
  "Put the `help-echo' tooltip on the citations up to LIMIT.
It is a font-lock matcher: it adds the property and never fontifies."
  (while (re-search-forward sp-cite-hover--link-regexp limit t)
    (add-text-properties (match-beginning 0) (match-end 0)
                         '(help-echo sp-cite-hover--help-echo)))
  nil)

(defun sp-cite-hover--eldoc (callback &rest _)
  "Eldoc function: show the reference of the citation at point with CALLBACK."
  (when (memq 'echo sp-cite-hover-display)
    (when-let* ((key (sp-cite-hover--key-at (point)))
                (text (sp-cite-hover--reference key)))
      (funcall callback text :thing (concat "@" key) :face 'font-lock-doc-face))))

(defun sp-cite-hover-setup ()
  "Turn on the citation tooltip and echo area reference in this Org buffer."
  (add-hook 'eldoc-documentation-functions #'sp-cite-hover--eldoc nil t)
  (font-lock-add-keywords nil '((sp-cite-hover--fontify)) 'append)
  (font-lock-flush))

(add-hook 'org-mode-hook #'sp-cite-hover-setup)

(defvar sia-citar-library-backup-path (sp-path sp-literature-dir "backup"))

(provide 'sp-citations)
;; sp-citations.el ends here
