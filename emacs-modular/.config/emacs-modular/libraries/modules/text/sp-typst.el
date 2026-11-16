;;; sp-typst.el --- PDF of the literate docs and of Org files, typeset with Typst -*- lexical-binding: t; -*-

;;; Commentary:

;; Exports the literate documentation (README.org, the architecture notes and
;; the doc of every module) to one PDF through ox-typst and the `typst' command,
;; and any single Org file the same way.  The assembly of the book, the template
;; (docs/typst/template.typ) and the batch driver (docs/typst/export.el) are
;; tangled from docs/tangles/text/sp-typst.org, which explains the design.

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'cl-lib)
(require 'sp-note-kinds)

(declare-function org-export-data "ox")
(declare-function org-export-get-footnote-definition "ox")
(declare-function org-element-property "org-element-ast")

(defvar org-typst-process)
(defvar org-typst-language-mapping)
(defvar org-export-use-babel)
(defvar org-export-filter-verbatim-functions)
(defvar org-export-filter-code-functions)
(defvar org-export-filter-inline-src-block-functions)
(defvar org-export-filter-footnote-reference-functions)
(defvar org-export-filter-link-functions)

(use-package ox-typst
  :ensure (:host github :repo "jmpunkt/ox-typst")
  :after ox)

(use-package typst-ts-mode
  :ensure t
  :mode ("\\.typ\\'" . typst-ts-mode)
  :config
  ;; tinymist is the language server (completion, diagnostics, live preview in
  ;; a browser).  Only start it when it is installed.
  (when (executable-find "tinymist")
    (with-eval-after-load 'eglot
      (add-to-list 'eglot-server-programs '(typst-ts-mode "tinymist")))
    (add-hook 'typst-ts-mode-hook #'eglot-ensure)))

(defgroup sp-typst nil
  "Typeset the literate docs and Org files with Typst."
  :group 'tools)

(defcustom sp-typst-root (expand-file-name user-emacs-directory)
  "Folder the doc paths are relative to: the Emacs configuration."
  :type 'directory
  :group 'sp-typst)

(defcustom sp-typst-executable "typst"
  "The Typst command."
  :type 'string
  :group 'sp-typst)

(defcustom sp-typst-font-paths nil
  "Extra folders with fonts, passed to Typst as `--font-path'."
  :type '(repeat directory)
  :group 'sp-typst)

(defcustom sp-typst-template-file "docs/typst/template.typ"
  "The Typst template of the book, relative to `sp-typst-root'."
  :type 'string
  :group 'sp-typst)

(defcustom sp-typst-build-directory "docs/typst/.build/"
  "Where the assembled Org, the Typst and the PDF are written.
Relative to `sp-typst-root'.  The template is copied into it."
  :type 'string
  :group 'sp-typst)

(defcustom sp-typst-doc-directories '("docs/architecture" "docs/justifications")
  "Folders of loose docs, relative to `sp-typst-root', one book part each."
  :type '(repeat string)
  :group 'sp-typst)

(defcustom sp-typst-see-also-style 'margin
  "How a see-also note (`[fn:see-1]') is typeset.
`margin' draws a Tufte sidenote with the Typst package marginalia, which Typst
downloads the first time (it needs the network once) and which widens the
outer margin of the page.  `footnote' draws an ordinary footnote and needs no
package."
  :type '(choice (const :tag "Sidenote in the margin (marginalia)" margin)
                 (const :tag "Ordinary footnote" footnote))
  :group 'sp-typst)

(defcustom sp-typst-include-old nil
  "When non-nil, also include the `-old.org' docs."
  :type 'boolean
  :group 'sp-typst)

(defcustom sp-typst-book-title "Sia's modular literate configuration for Emacs"
  "Title of the book."
  :type 'string
  :group 'sp-typst)

(defcustom sp-typst-book-author "Sia Piperea"
  "Author of the book."
  :type 'string
  :group 'sp-typst)

(defcustom sp-typst-book-name "emacs-modular"
  "Base name of the book's files in `sp-typst-build-directory'."
  :type 'string
  :group 'sp-typst)

(defun sp-typst--file (relative)
  "Absolute name of RELATIVE, a path under `sp-typst-root'."
  (expand-file-name relative sp-typst-root))

(defun sp-typst--org-files (directory)
  "The Org docs directly in DIRECTORY (relative to the root), as relative paths.
Backups, empty files and, unless `sp-typst-include-old', `-old.org' docs are left out."
  (let ((absolute (sp-typst--file directory)))
    (when (file-directory-p absolute)
      (seq-keep
       (lambda (name)
         (let ((file (expand-file-name name absolute)))
           (when (and (or sp-typst-include-old
                          (not (string-suffix-p "-old.org" name)))
                      (> (file-attribute-size (file-attributes file)) 0))
             (concat (file-name-as-directory directory) name))))
       (directory-files absolute nil "\\.org\\'")))))

(defun sp-typst--parts ()
  "The book as an alist of (PART-TITLE . FILES), FILES relative to the root."
  (let (parts)
    (push (cons "Overview"
                (seq-filter (lambda (f) (file-exists-p (sp-typst--file f)))
                            '("README.org")))
          parts)
    (dolist (directory sp-typst-doc-directories)
      (push (cons (capitalize (file-name-nondirectory directory))
                  (sp-typst--org-files directory))
            parts))
    (push (cons "Design notes"
                (sp-typst--org-files "docs"))
          parts)
    (dolist (sub (directory-files (sp-typst--file "docs/tangles") nil "\\`[^.]"))
      (let ((directory (concat "docs/tangles/" sub)))
        (when (file-directory-p (sp-typst--file directory))
          (push (cons (format "Modules: %s" sub)
                      (sp-typst--org-files directory))
                parts))))
    (seq-filter #'cdr (nreverse parts))))

(defun sp-typst--slug (file)
  "Heading id for the doc FILE (relative to the root)."
  (concat "doc-" (string-trim
                  (replace-regexp-in-string
                   "[^a-z0-9]+" "-" (downcase (file-name-sans-extension file)))
                  "-" "-")))

(defun sp-typst--title (file)
  "The `#+TITLE' of the absolute FILE, or its base name."
  (with-temp-buffer
    (insert-file-contents file nil 0 4000)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+title:[ \t]*\\(.+\\)$" nil t)
        (string-trim (match-string 1))
      (file-name-base file))))

(defun sp-typst--known (parts)
  "Hash table of the absolute name of every doc in PARTS to its relative path."
  (let ((known (make-hash-table :test #'equal)))
    (dolist (part parts)
      (dolist (file (cdr part))
        (puthash (sp-typst--file file) file known)))
    known))

(defconst sp-typst--dropped-keywords
  (concat "^#\\+\\(?:title\\|author\\|date\\|startup\\|property\\|options\\|"
          "filetags\\|setupfile\\|todo\\|seq_todo\\|typ_todo\\|tags\\|category\\|"
          "language\\|latex[a-z_]*\\|html[a-z_]*\\|export_[a-z_]+\\|link\\|"
          "constants\\|select_tags\\|exclude_tags\\|priorities\\|columns\\):.*\n?")
  "File-level keywords of a doc that mean nothing in the book.")

(defun sp-typst--drop-keywords ()
  "Delete the file-level keywords that mean nothing in the book."
  (goto-char (point-min))
  (let ((case-fold-search t))
    (while (re-search-forward sp-typst--dropped-keywords nil t)
      (replace-match ""))))

(defun sp-typst--fix-includes (directory)
  "Make `#+INCLUDE:' paths absolute (from DIRECTORY); drop missing files."
  (goto-char (point-min))
  (let ((case-fold-search t))
    (while (re-search-forward "^#\\+include:[ \t]*\"?\\([^\" \n]+\\)\"?\\(.*\\)\n?" nil t)
      (let ((file (expand-file-name (match-string 1) directory))
            (rest (match-string 2)))
        (replace-match (if (file-exists-p file)
                           (format "#+INCLUDE: \"%s\"%s\n" file rest)
                         "")
                       t t)))))

(defun sp-typst--shift-headings (levels)
  "Move every heading down by LEVELS levels."
  (goto-char (point-min))
  (while (re-search-forward "^\\*+ " nil t)
    (goto-char (line-beginning-position))
    (insert (make-string levels ?*))
    (forward-line 1)))

(defun sp-typst--block-ranges ()
  "Markers around each source, example, export and comment block of the buffer.
Org does not read links or footnotes inside them, so they are left alone."
  (let (ranges (case-fold-search t))
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*#\\+begin_\\(src\\|example\\|export\\|comment\\)\\_>" nil t)
      (let ((beg (copy-marker (match-beginning 0)))
            (kind (match-string 1)))
        (if (re-search-forward (format "^[ \t]*#\\+end_%s" kind) nil t)
            (push (cons beg (copy-marker (point))) ranges)
          (goto-char (point-max)))))
    ranges))

(defun sp-typst--in-block-p (ranges position)
  "Non-nil when POSITION is inside one of RANGES."
  (seq-some (lambda (range) (and (>= position (car range)) (<= position (cdr range))))
            ranges))

(defun sp-typst--fix-links (directory known)
  "Rewrite the `file:' links of a doc in DIRECTORY.
KNOWN is the table made by `sp-typst--known'."
  (let ((ranges (sp-typst--block-ranges)))
    (goto-char (point-min))
    (while (re-search-forward
            "\\[\\[file:\\([^]\n]+?\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]" nil t)
      (unless (sp-typst--in-block-p ranges (match-beginning 0))
        ;; The helper calls below use regexps, so take the match first.
        (let* ((beg (match-beginning 0))
               (end (match-end 0))
               (path (car (split-string (match-string 1) "::")))
               (description (match-string 2))
               (absolute (expand-file-name path directory))
               (doc (gethash absolute known))
               (text
                (save-match-data
                  (cond
                   ((string-match-p "\\.\\(?:svg\\|png\\|jpe?g\\|gif\\)\\'" path)
                    (if (file-exists-p absolute)
                        (format "[[file:%s]]" absolute)
                      (format "/figure %s is not built (run make docs)/"
                              (file-name-nondirectory path))))
                   (doc
                    (format "[[#%s][%s]]" (sp-typst--slug doc)
                            (or description (sp-typst--title absolute))))
                   (t (format "=%s=" (or description path)))))))
          (goto-char beg)
          (delete-region beg end)
          (insert text))))))

(defun sp-typst--note-label (slug label)
  "The footnote LABEL made unique with SLUG.
The prefix of a see-also note or an endnote stays at the front, so the label
still tells the kind (`see-1' becomes `see-SLUG-1', `3' becomes `SLUG-3')."
  (if-let* ((prefix (sp-note-prefix (sp-note-kind label))))
      (format "%s%s-%s" prefix slug (substring label (length prefix)))
    (format "%s-%s" slug label)))

(defun sp-typst--prefix-footnotes (slug)
  "Prefix every footnote label with SLUG, so labels do not repeat across docs.
A reference whose definition is not in the doc (usually text that
quotes the syntax) would stop the export, so it is kept as plain text."
  (let ((ranges (sp-typst--block-ranges))
        (defined nil))
    (goto-char (point-min))
    (while (re-search-forward "^\\[fn:\\([^]: \n]+\\)\\]" nil t)
      (push (match-string 1) defined))
    (goto-char (point-min))
    (while (re-search-forward "\\[fn:\\([^]: \n]+\\)\\(\\]\\|:\\)" nil t)
      (unless (sp-typst--in-block-p ranges (match-beginning 0))
        (let ((label (match-string 1))
              (inline (equal (match-string 2) ":"))
              (beg (match-beginning 0)))
          (cond
           ((or inline (member label defined))
            (replace-match (format "[fn:%s%s" (sp-typst--note-label slug label)
                                   (match-string 2))
                           t t))
           ;; A zero-width space after "fn" stops Org reading it as a footnote.
           (t (replace-match (format "[fn\u200b:%s]" label) t t))))))))

(defun sp-typst--has-notes-p (kind)
  "Non-nil when this buffer holds a note of KIND outside source and example blocks.
Docs that only quote the syntax in a block do not count."
  (let ((prefix (sp-note-prefix kind))
        (ranges (sp-typst--block-ranges))
        (case-fold-search nil)
        found)
    (when (and prefix (not (string-empty-p prefix)))
      (save-excursion
        (goto-char (point-min))
        (while (and (not found)
                    (re-search-forward (format "\\[fn:%s" (regexp-quote prefix)) nil t))
          (unless (sp-typst--in-block-p ranges (match-beginning 0))
            (setq found t)))))
    found))

(defun sp-typst--add-endnotes-section (level)
  "Add a Notes heading under heading LEVEL at the end of the doc, when it needs one.
A doc that has endnotes and no `#endnotes()' of its own (the template made by
`sp-note-insert-endnotes-section') gets the section here."
  (when (and (sp-typst--has-notes-p 'endnote)
             (not (save-excursion
                    (goto-char (point-min))
                    (search-forward "#endnotes()" nil t))))
    (goto-char (point-max))
    (insert "\n" (make-string (1+ level) ?*) " " sp-note-endnotes-title "\n"
            sp-note--endnotes-block)))

(defun sp-typst--prepare (file level known)
  "Text of the doc FILE (relative to the root), ready to sit under a heading.
The doc gets a heading of LEVEL; its own headings move below it.  KNOWN
is the table made by `sp-typst--known'."
  (let* ((absolute (sp-typst--file file))
         (slug (sp-typst--slug file))
         (title (sp-typst--title absolute)))
    (with-temp-buffer
      (insert-file-contents absolute)
      (sp-typst--drop-keywords)
      (sp-typst--fix-includes (file-name-directory absolute))
      (sp-typst--shift-headings level)
      (sp-typst--fix-links (file-name-directory absolute) known)
      (sp-typst--prefix-footnotes slug)
      (sp-typst--add-endnotes-section level)
      (concat (make-string level ?*) " " title "\n"
              ":PROPERTIES:\n:CUSTOM_ID: " slug "\n:END:\n\n"
              (string-trim-right (buffer-string)) "\n\n"))))

(defun sp-typst--build-directory ()
  "Absolute name of the build folder."
  (file-name-as-directory (sp-typst--file sp-typst-build-directory)))

(defun sp-typst--features (text)
  "The features of the Org TEXT that need more of Typst: a list of symbols.
`see-also' when TEXT has see-also notes and they are drawn in the margin."
  (and (eq sp-typst-see-also-style 'margin)
       (with-temp-buffer
         (insert text)
         (sp-typst--has-notes-p 'see-also))
       '(see-also)))

(defun sp-typst--preamble (title &optional features)
  "Org keywords for a document called TITLE; FEATURES is from `sp-typst--features'."
  (progn
    (string-join
     (delq nil
      (list (format "#+title: %s" title)
           (format "#+author: %s" sp-typst-book-author)
           (format-time-string "#+date: [%Y-%m-%d %a]")
           "#+language: en"
           "#+options: toc:t num:t H:9 ^:{} d:nil broken-links:t"
           "#+macro: latest-export-date (eval (format-time-string \"%Y-%m-%d\"))"
           "#+macro: word-count (eval (format \"%d\" (count-words (point-min) (point-max))))"
           "#+typst_header: #import \"template.typ\": book, endnote, endnotes, see-also"
           "#+typst_header: #show: book"
           (when (memq 'see-also features)
             "#+typst_header: #import \"sidenotes.typ\": see-also, sidenote-layout")
           (when (memq 'see-also features)
             "#+typst_header: #show: sidenote-layout")
           "\n"))
     "\n")))

(defun sp-typst-book-source ()
  "The Org text of the whole book."
  (let* ((parts (sp-typst--parts))
         (known (sp-typst--known parts)))
    (let ((body (with-temp-buffer
                  (dolist (part parts)
                    (insert "* " (car part) "\n\n")
                    (dolist (file (cdr part))
                      (insert (sp-typst--prepare file 2 known))))
                  (buffer-string))))
      (concat (sp-typst--preamble sp-typst-book-title (sp-typst--features body))
              body))))

(defun sp-typst--process ()
  "The value of `org-typst-process' for `sp-typst-executable' and the fonts."
  (concat (shell-quote-argument sp-typst-executable) " c \"%s\""
          (mapconcat (lambda (path)
                       (format " --font-path %s"
                               (shell-quote-argument (expand-file-name path))))
                     sp-typst-font-paths "")))

(defun sp-typst--end-expression (text _backend _info)
  "End the Typst expression TEXT with a semicolon when it ends in a call.
Typst reads a `[' straight after `#raw(\"x\")' as trailing content of the
call, so Org text such as `=a=[b]' would not compile; `ox-typst' has no
guard for this."
  (if (and (stringp text) (string-suffix-p ")" text))
      (concat text ";")
    text))

(defun sp-typst--note-markup (kind body)
  "The Typst markup of a note of KIND with the Typst text BODY."
  (pcase kind
    ('see-also (format "#see-also[%s]" body))
    ('endnote (format "#endnote[%s]" body))))

(defun sp-typst--footnote-reference (original reference contents info)
  "Export the footnote REFERENCE by its kind; ORIGINAL is `org-typst-footnote-reference'.
A see-also note and an endnote put their text in the text, where the Typst
function `see-also' or `endnote' (docs/typst/template.typ) takes it.  A note
cited twice is drawn twice."
  (let ((kind (sp-note-kind (org-element-property :label reference))))
    (if (eq kind 'footnote)
        (funcall original reference contents info)
      (sp-typst--note-markup
       kind
       (string-trim
        (if (eq (org-element-property :type reference) 'inline)
            (or contents "")
          (org-export-data
           (org-export-get-footnote-definition reference info) info)))))))

(defun sp-typst--footnote-definition (original definition contents info)
  "Export the footnote DEFINITION; those of see-also notes and endnotes are empty.
ORIGINAL is `org-typst-footnote-definition'."
  (if (eq (sp-note-kind (org-element-property :label definition)) 'footnote)
      (funcall original definition contents info)
    ""))

(defun sp-typst--with-notes (function)
  "Call FUNCTION with ox-typst exporting see-also notes and endnotes by kind."
  (let ((reference (symbol-function 'org-typst-footnote-reference))
        (definition (symbol-function 'org-typst-footnote-definition)))
    (cl-letf (((symbol-function 'org-typst-footnote-reference)
               (lambda (&rest args)
                 (apply #'sp-typst--footnote-reference reference args)))
              ((symbol-function 'org-typst-footnote-definition)
               (lambda (&rest args)
                 (apply #'sp-typst--footnote-definition definition args))))
      (funcall function))))

(defun sp-typst--export (text name)
  "Export the Org TEXT to a PDF called NAME in the build folder; return its path."
  (require 'org)
  (require 'ox-typst)
  (let ((build (sp-typst--build-directory))
        (coding-system-for-write 'utf-8-unix))
    (make-directory build t)
    (copy-file (sp-typst--file sp-typst-template-file)
               (expand-file-name "template.typ" build) t)
    ;; The other Typst files that sit beside the template (sidenotes.typ).
    (dolist (file (directory-files
                   (file-name-directory (sp-typst--file sp-typst-template-file))
                   t "\\.typ\\'"))
      (copy-file file (expand-file-name (file-name-nondirectory file) build) t))
    (let* ((org-file (expand-file-name (concat name ".org") build))
           (buffer (progn (with-temp-file org-file (insert text))
                          (find-file-noselect org-file t t))))
      (unwind-protect
          (with-current-buffer buffer
            (delay-mode-hooks (org-mode))
            (let ((org-export-use-babel nil)
                  (org-export-filter-verbatim-functions
                   (cons #'sp-typst--end-expression org-export-filter-verbatim-functions))
                  (org-export-filter-code-functions
                   (cons #'sp-typst--end-expression org-export-filter-code-functions))
                  (org-export-filter-inline-src-block-functions
                   (cons #'sp-typst--end-expression org-export-filter-inline-src-block-functions))
                  (org-export-filter-footnote-reference-functions
                   (cons #'sp-typst--end-expression org-export-filter-footnote-reference-functions))
                  (org-export-filter-link-functions
                   (cons #'sp-typst--end-expression org-export-filter-link-functions))
                  (org-typst-process (sp-typst--process))
                  (org-typst-language-mapping
                   (append '(("emacs-lisp" . "lisp") ("elisp" . "lisp")
                             ("sh" . "bash") ("shell" . "bash"))
                           org-typst-language-mapping)))
              (sp-typst--with-notes #'org-typst-export-to-pdf)))
        (kill-buffer buffer)))))

;;;###autoload
(defun sp-typst-export-book (&optional open)
  "Export every doc to one PDF; with prefix argument OPEN, open it.
Return the name of the PDF."
  (interactive "P")
  (let ((pdf (sp-typst--export (sp-typst-book-source) sp-typst-book-name)))
    (message "Typst: wrote %s" pdf)
    (when open (org-open-file pdf))
    pdf))

;;;###autoload
(defun sp-typst-export-file (file &optional open)
  "Export the Org FILE alone, with the book template; with prefix OPEN, open it.
Links to other docs become inline code, since they are not in this PDF."
  (interactive (list (or buffer-file-name (read-file-name "Org file: "))
                     current-prefix-arg))
  (let* ((relative (file-relative-name (expand-file-name file) sp-typst-root))
         (body (sp-typst--prepare relative 1 (make-hash-table :test #'equal)))
         (text (concat (sp-typst--preamble (sp-typst--title (expand-file-name file))
                                           (sp-typst--features body))
                       body))
         (pdf (sp-typst--export text (file-name-base file))))
    (message "Typst: wrote %s" pdf)
    (when open (org-open-file pdf))
    pdf))

(defun sp-typst-batch-book ()
  "Export the book from a batch Emacs (see docs/typst/Makefile)."
  (princ (sp-typst-export-book))
  (terpri))

(defun sp-typst-batch-file ()
  "Export the file named by the environment variable FILE from a batch Emacs."
  (princ (sp-typst-export-file (or (getenv "FILE") (error "Set FILE"))))
  (terpri))

(provide 'sp-typst)
;;; sp-typst.el ends here
