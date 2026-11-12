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
;; The three indicator columns and the citekey column of the candidates.
(defface sp-citar-indicator-link
  '((t :inherit (bold font-lock-function-name-face)))
  "Face of the link indicator (L) in `citar' candidates."
  :group 'sp)

(defface sp-citar-indicator-file
  '((t :inherit (bold error)))
  "Face of the file indicator (F) in `citar' candidates."
  :group 'sp)

(defface sp-citar-indicator-note
  '((t :inherit (bold success)))
  "Face of the note indicator (N) in `citar' candidates."
  :group 'sp)

(defface sp-citar-key
  '((t :inherit shadow :slant italic))
  "Face of the citekey column in `citar' candidates."
  :group 'sp)

(defconst sp-citations-indicator-colors
  '((sp-citar-indicator-link . blue)
    (sp-citar-indicator-file . red)
    (sp-citar-indicator-note . green))
  "Alist of indicator face and the `modus-themes' palette colour it takes.")

(defun sp-citations-update-indicator-faces (&rest _)
  "Take the foreground of the indicator faces from the active Modus theme.
Without a Modus theme the faces keep the colours they inherit."
  (when (and (fboundp 'modus-themes-get-current-theme)
             (modus-themes-get-current-theme))
    (pcase-dolist (`(,face . ,color) sp-citations-indicator-colors)
      (let ((value (modus-themes-get-color-value color)))
        (when (stringp value)
          (set-face-attribute face nil :foreground value))))))

(sp-citations-update-indicator-faces)
(add-hook 'enable-theme-functions #'sp-citations-update-indicator-faces)

(defun sp-citations--indicator-symbol (kind)
  "Return the symbol string of the indicator KIND, `link', `file' or `note'.
A nerd-icons glyph on a graphical display, the letter L, F or N otherwise,
in both cases in the bold face of KIND."
  (let ((face (intern (format "sp-citar-indicator-%s" kind))))
    (or (and (display-graphic-p)
             (require 'nerd-icons nil t)
             ;; nerd-icons has no octicon PDF/text glyph, so those two use
             ;; FontAwesome; link-external maps to the octicon directly.
             (pcase kind
               ('file (nerd-icons-faicon "nf-fa-file_pdf_o" :face face))
               ('note (nerd-icons-faicon "nf-fa-file_text_o" :face face))
               ('link (nerd-icons-octicon "nf-oct-link_external" :face face))))
        (propertize (upcase (substring (symbol-name kind) 0 1)) 'face face))))

(defun sp-citations-setup-indicators ()
  "Set `citar-indicators' to the coloured link, file and note columns.
The cited column keeps the default of `citar'."
  (setq citar-indicators
        (list (citar-indicator-create :symbol (sp-citations--indicator-symbol 'link)
                                      :padding "  "
                                      :function #'citar-has-links
                                      :tag "has:links")
              (citar-indicator-create :symbol (sp-citations--indicator-symbol 'file)
                                      :padding "  "
                                      :function #'citar-has-files
                                      :tag "has:files")
              (citar-indicator-create :symbol (sp-citations--indicator-symbol 'note)
                                      :padding "  "
                                      :function #'citar-has-notes
                                      :tag "has:notes")
              citar-indicator-cited)))

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
        `((main . " ${title:48}   ${author editor:30}")
          (suffix . ,(concat "   "
                             (propertize "${=key= id:15}" 'face 'sp-citar-key)
                             "   ${=type=:12}   ${=beref=:12}   ${tags keywords:*}"))
          (preview . "${author editor} (${year issued date}) ${title}, ${journal journaltitle publisher container-title collection-title}.\n")
          (note . ,sp-citar-note)))

  :config
  ;; Find a PDF that is not where its `file' field says.
  (add-to-list 'citar-file-parser-functions #'sp-citations-parser-library t)
  (sp-citations-setup-indicators)
  (sp-citations-update-indicator-faces)

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
