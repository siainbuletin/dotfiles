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

;; An emoji is not drawn as wide as its `string-width' says: the width of the glyph
;; comes from the emoji font, and a variation selector (U+FE0F) or a ZWJ sequence changes
;; it again.  So each emoji is put in a cell whose width is measured in pixels, in the
;; font in use, and padded to a whole number of character cells with a `display' space.
;; The pad is relative, so it does not depend on where the line starts on the screen.
(defvar sp-citations--cell-cache (make-hash-table :test 'equal)
  "Cells made by `sp-citations--emoji-cell', by emoji, columns, character width and font.")

(defun sp-citations--pixel-cells-p ()
  "Non-nil when widths can be measured in pixels: a graphical frame."
  (and (display-graphic-p) (fboundp 'string-pixel-width)))

(defun sp-citations--build-cell (emoji cells)
  "Return EMOJI shown in CELLS character cells, measured in pixels.
The string is CELLS spaces, so its `string-width' is CELLS whatever the emoji is; its
`display' property is the emoji, made smaller if it is wider than the cells, then a
space that takes the pixels left.  `citar' therefore never pads or cuts it."
  (let* ((target (* cells (frame-char-width)))
         (glyph emoji)
         (factor 1.0)
         (width (string-pixel-width glyph)))
    (dotimes (_ 2)
      (when (> width target)
        (setq factor (* factor 0.98 (/ (float target) width))
              glyph (propertize emoji 'face `(:height ,factor))
              width (string-pixel-width glyph))))
    (propertize (make-string cells ?\s)
                'display (concat glyph (propertize " " 'display
                                                   `(space :width (,(max 0 (- target width)))))))))

(defun sp-citations--emoji-cell (emoji cells)
  "Return EMOJI in a cell of CELLS columns, exact in pixels on a graphical display.
On a terminal it is the emoji and spaces up to CELLS columns."
  (if (not (sp-citations--pixel-cells-p))
      (concat emoji (make-string (max 1 (- cells (string-width emoji))) ?\s))
    (let ((key (list emoji cells (frame-char-width)
                     (face-attribute 'default :family nil t)
                     (face-attribute 'default :height nil t))))
      (or (gethash key sp-citations--cell-cache)
          (puthash key (sp-citations--build-cell emoji cells) sp-citations--cell-cache)))))

(defun sp-citations--blank-cell (cells)
  "Return a blank of CELLS character cells, exact in pixels on a graphical display."
  (if (sp-citations--pixel-cells-p)
      (propertize (make-string cells ?\s)
                  'display `(space :width (,(* cells (frame-char-width)))))
    (make-string cells ?\s)))

(defun sp-citations-setup-indicators ()
  "Set `citar-indicators' to the link, file, note and cited emoji."
  (cl-flet ((indicator (symbol function tag)
              (citar-indicator-create
               :symbol symbol :padding ""
               :emptysymbol (make-string sp-citations-indicator-cell ?\s)
               :function function :tag tag)))
    (setq citar-indicators
          (list (indicator "\U0001F33F️" #'citar-has-links "has:links")   ; link
                (indicator "\U0001F4C1️" #'citar-has-files "has:files")   ; file
                (indicator "\U0001F4DD️" #'citar-has-notes "has:notes")   ; note
                (indicator "\U0001F393️" #'citar-is-cited "is:cited")))))  ; cited

(defun sp-citations--indicator-symbols (candidate)
  "Return the indicators of CANDIDATE, ended by one space.
Replaces `citar--make-indicator-symbols'.  Its padding is the last character of each
indicator, so it cannot be empty.  Each indicator is a cell of
`sp-citations-indicator-cell' columns, measured in pixels."
  (concat (mapconcat
           (lambda (indicator)
             (if (string-match-p (citar-indicator-tag indicator) candidate)
                 (sp-citations--emoji-cell (citar-indicator-symbol indicator)
                                           sp-citations-indicator-cell)
               (sp-citations--blank-cell sp-citations-indicator-cell)))
           citar-indicators "")
          " "))

;;;; Citar entry types
(defvar sp-org-tag-groups-bibtex-types)
(defvar sp-org-tag-groups-bibtex-type-fallback)

(defun sp-citations--type-emoji (type)
  "Return the emoji of the BibTeX entry TYPE in a cell of 3 columns, for the type column.
The emoji come from `sp-org-tag-groups-bibtex-types'; a type that is not in it,
or the module not being loaded, gives the fallback emoji.  The cell is measured in
pixels (`sp-citations--emoji-cell').  Used as the `etype' transform of
`citar-display-transform-functions'."
  (sp-citations--emoji-cell
   (or (and (boundp 'sp-org-tag-groups-bibtex-types)
            (nth 1 (assoc (downcase (or type "")) sp-org-tag-groups-bibtex-types)))
       (and (boundp 'sp-org-tag-groups-bibtex-type-fallback)
            sp-org-tag-groups-bibtex-type-fallback)
       "\U0001F4C4\uFE0F")
   3))

;;;; Citar layout
;; The widths in `citar-templates' are numbers, so they are worked out here from the
;; columns of the frame Emacs has on the screen, as the posframe takes them, at the size
;; of the `default' face.  They are worked out again when the frame has changed size
;; since the last time (a tile of AeroSpace, then a maximized frame), each time a
;; command asks for a reference.  The citekey is shown in full (45) when it fits; the
;; authors and the title share what is left, and the tags only come back on a wide frame.
(defvar sp-posframe-width-fraction)

(defcustom sp-citations-layout-columns nil
  "Columns the `citar' candidates may take, or nil to work them out from the frame.
Nil means the columns of the posframe: see `sp-citations--frame-columns'."
  :type '(choice (const :tag "From the frame" nil) integer)
  :group 'sp)

(defconst sp-citations-layout-overhead 27
  "Columns the template spends besides authors, title, citekey and tags.
That is 2 for the margin, 11 for the Vertico mark and the four indicators, 3 for the
type emoji, 1 after it, 4 for the year and 6 for the separators (two columns each).")

(defun sp-citations--frame-columns ()
  "Return the columns the `citar' candidates have, from the frame on the screen.
It is the text width of the selected frame (the parent when a child frame is selected)
in pixels, divided by the pixel width of a character of the `default' face, so a change
of font size shows at once, before the frame has been resized.  While the posframe is on in a graphical frame it takes
`sp-posframe-width-fraction' of that, as `sp-posframe-get-size' does; otherwise the
whole width."
  (let* ((frame (or (frame-parameter nil 'parent-frame) (selected-frame)))
         (width (floor (frame-text-width frame) (frame-char-width frame))))
    (if (and (bound-and-true-p vertico-posframe-mode) (display-graphic-p frame)
             (boundp 'sp-posframe-width-fraction))
        (round (* sp-posframe-width-fraction width))
      width)))

(defun sp-citations--layout (&optional columns)
  "Return the widths of the `citar' columns for COLUMNS as a plist.
The keys are :author, :title, :key and :tags.  The citekey takes up to 45 columns, but
never leaves the title under 20 and the authors under 10, and not under 16 itself;
the title takes what is left after the authors, a fifth of the room (10 to 30).  Tags
get 20 columns once the room is 110 columns or more."
  (let* ((columns (or columns sp-citations-layout-columns (sp-citations--frame-columns)))
         (room (max 0 (- columns sp-citations-layout-overhead)))
         (tags (if (>= room 110) 22 0))
         (room (- room tags))
         (author (max 10 (min 30 (round (* 0.2 room)))))
         (key (max 16 (min 45 (- room author 20))))
         (title (max 20 (- room author key))))
    (list :author author :title title :key key :tags (max 0 (- tags 2)))))

(defun sp-citations--layout-templates (&optional columns)
  "Return the `main' and `suffix' entries of `citar-templates' for COLUMNS."
  (let* ((layout (sp-citations--layout columns))
         (tags (plist-get layout :tags)))
    `((main . ,(format "${=type=:3%%etype} ${author editor:%d}  ${year issued date:4}  ${title:%d}"
                       (plist-get layout :author) (plist-get layout :title)))
      (suffix . ,(concat "  "
                         (propertize (format "${=key= id:%d}" (plist-get layout :key))
                                     'face 'sp-citar-key)
                         (if (> tags 0) (format "  ${tags keywords:%d}" tags) ""))))))

(defvar sp-citations--applied-state nil
  "What the widths of `citar-templates' were last worked out for.
A list of the columns, the width of a character, and the family and height of the
`default' face: the emoji cells depend on the font as well as on the columns.")

(defun sp-citations--repreformat ()
  "Format the cached `citar' candidates again.
`citar' keeps each candidate as a pre-formatted string, made when the bibliography is
read or when the format string changes, and the emoji cells of the type column are in
it.  When only the font changed, nothing makes `citar' do it again, so it is done here."
  (when (and (boundp 'citar-cache--bibliographies)
             (fboundp 'citar-cache--preformat-bibliography))
    (maphash (lambda (_file bib) (citar-cache--preformat-bibliography bib))
             citar-cache--bibliographies)))

(defun sp-citations--apply-layout (&optional force)
  "Work the `citar' widths out for the frame and font as they are now, if they changed.
With FORCE the widths are always worked out again.  `citar' formats the candidates
again by itself when the templates change; when only the font changed (the emoji cells)
the cached candidates are formatted again here."
  (let* ((columns (or sp-citations-layout-columns (sp-citations--frame-columns)))
         (state (list columns (frame-char-width)
                      (face-attribute 'default :family nil t)
                      (face-attribute 'default :height nil t))))
    (when (or force (not (equal state sp-citations--applied-state)))
      (setq sp-citations--applied-state state)
      (clrhash sp-citations--cell-cache)
      (let* ((templates (sp-citations--layout-templates columns))
             (same (and (equal-including-properties (cdr (assq 'main templates))
                                                    (cdr (assq 'main citar-templates)))
                        (equal-including-properties (cdr (assq 'suffix templates))
                                                    (cdr (assq 'suffix citar-templates))))))
        (setq citar-templates (append templates
                                      (assq-delete-all 'suffix (assq-delete-all 'main citar-templates))))
        (when same (sp-citations--repreformat))))))

(defun sp-citations--before-select (&rest _)
  "Advice before the commands that ask for a reference: fit the widths to the frame."
  (sp-citations--apply-layout))

(defun sp-citations-fit-layout ()
  "Work the `citar' column widths out again from the frame and the font.
This is done on its own, before a command that asks for a reference, when the frame
or the font changed; this command forces it, and the cached candidates are formatted
again."
  (interactive)
  (sp-citations--apply-layout t)
  (message "citar layout: %S columns" (car sp-citations--applied-state)))

;;;; Citation with a page
;; `org-cite-insert' (C-c b) stays as it is.  `sp-citations-insert-with-page' (C-c B)
;; is a second command for a citation that needs a locator: it asks for the page of
;; every key it inserts and writes it as the suffix, `[cite:@key p. 12]'.

(defun sp-citations-first-page (pages)
  "The first page in PAGES, a BibTeX `pages' value, or nil.
`12--30' and `12, 15' give `12'; `S12--S20' gives `S12'."
  (when (and (stringp pages)
             (string-match "\\`[ \t{]*\\([[:alnum:]]+\\)" pages))
    (match-string 1 pages)))

(defun sp-citations-format-locator (answer)
  "The locator text for ANSWER, as typed at the page prompt, or nil when it is empty.
A single number gives `p. 12', a range gives `pp. 12-14', anything else
\(`p. 12', `ch. 3', `fig. 2') is kept as typed."
  (let ((text (string-trim (or answer ""))))
    (cond
     ((string-empty-p text) nil)
     ((string-match-p "\\`[[:alnum:]]+\\'" text) (concat "p. " text))
     ((string-match-p "\\`[[:alnum:]]+[ \t]*\\(?:-+\\|\u2013\\|\u2014\\)[ \t]*[[:alnum:]]+\\'" text)
      (concat "pp. " (replace-regexp-in-string "[ \t]*\\(?:-+\\|\u2013\\|\u2014\\)[ \t]*" "-" text)))
     (t text))))

(defun sp-citations--cite-text (key locator)
  "The text of the reference to KEY in a citation, with LOCATOR after it when non-nil."
  (if locator (format "@%s %s" key locator) (format "@%s" key)))

(defun sp-citations--citation-end ()
  "The position of the closing bracket of the `[cite:]' link point is in, or nil.
Only the current line is searched."
  (save-excursion
    (let ((pos (point))
          (line-start (line-beginning-position))
          found)
      (while (and (not found)
                  (re-search-backward "\\[cite\\(?:/[-_/[:alnum:]]*\\)?:" line-start t))
        (when (and (looking-at "\\[cite[^]\n]*\\]")
                   (< pos (match-end 0)))
          (setq found (1- (match-end 0)))))
      found)))

(defun sp-citations--ask-page (key)
  "Ask for the page of KEY and return its locator text, or nil for no page.
The first page of the `pages' field of the entry is the initial input; delete it
to cite the whole work."
  (let ((first (sp-citations-first-page (citar-get-value "pages" key))))
    (sp-citations-format-locator
     (read-string (format "Page for %s (empty for none): " key) first))))

(defun sp-citations-insert-with-page ()
  "Insert a citation with `citar' and ask for the page of each key.
The page is written as the suffix of the key, `[cite:@key p. 12]'.  Point inside an
existing citation adds the keys to it, separated by `;'.  This is a separate command
from `org-cite-insert', which does not ask."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Citations with a page are for Org buffers"))
  (let* ((keys (or (citar-select-refs) (user-error "No reference chosen")))
         (text (mapconcat (lambda (key)
                            (sp-citations--cite-text key (sp-citations--ask-page key)))
                          keys "; ")))
    (if-let* ((end (sp-citations--citation-end)))
        (progn (goto-char end) (insert "; " text))
      (insert "[cite:" text "]"))))

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
        `(,@(sp-citations--layout-templates)
          (preview . "${author editor} (${year issued date}) ${title}, ${journal journaltitle publisher container-title collection-title}.\n")
          (note . ,sp-citar-note)))

  :config
  ;; Find a PDF that is not where its `file' field says.
  (add-to-list 'citar-file-parser-functions #'sp-citations-parser-library t)
  (sp-citations-setup-indicators)
  (add-to-list 'citar-display-transform-functions '(etype . (sp-citations--type-emoji)))
  (advice-add 'citar--make-indicator-symbols :override #'sp-citations--indicator-symbols)
    (advice-add 'citar-select-ref :before #'sp-citations--before-select)
  (advice-add 'citar-select-refs :before #'sp-citations--before-select)

  :bind
         (("C-c w b o" . citar-open))
         (:map org-mode-map :package org
               ("C-c b" . #'org-cite-insert)
               ("C-c B" . #'sp-citations-insert-with-page))
         
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
