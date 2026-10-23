;;; sp-org-export.el --- Org export, Pandoc and clipboard conversion -*- lexical-binding: t; -*-

;;; Commentary:

;; This should be correlated with the typesetting that I currently have running.

;;; Code:

;;;; Org Export
;; Useful base export settings
(use-package ox
  :ensure nil
  :after org
  
  :custom
  ;; Don't use bad hyperref value
  ;; https://emacs.stackexchange.com/a/46226/11934
  (org-latex-hyperref-template nil)
  
  ;; Export settings
  (org-table-export-default-format "orgtbl-to-csv") ;; export for org-tables to csv
  (org-export-with-smart-quotes t)
  (org-export-with-broken-links t)
  (org-export-async-debug t)
  (org-html-postamble nil) ;; dont export postamble
  (org-export-async-init-file nil)
  ;; (org-export-backends '(ascii beamer html icalendar latex odt pandoc hugo md))
  ;; org v8 bundled with Emacs 24.4
  (org-odt-preferred-output-format "docx")
  
  :config
  ;; Only OSX need below setup
  (defun sp-odt-org-convert-process ()
    (interactive)
    (let ((cmd "/Applications/LibreOffice.app/Contents/MacOS/soffice"))
      (when (and (eq system-type 'darwin) (file-exists-p cmd))
        ;; org v8
        (setq org-odt-convert-processes '(("LibreOffice" "/Applications/LibreOffice.app/Contents/MacOS/soffice --headless --convert-to %f%x --outdir %d %i"))))))
  (sp-odt-org-convert-process))

;;;; Org Export Extensions
;;;;; Ox-Pandoc
;; Export w/pandoc
(use-package ox-pandoc
  :ensure t
  ;; :if (executable-find "pandoc")
  :defer t  ;; Defer loading until needed for export
  :commands (org-pandoc-export-to-html5
             org-pandoc-export-to-html5-and-open
             org-pandoc-export-to-markdown
             org-pandoc-export-to-pdf
             org-pandoc-export-to-latex
             org-pandoc-export-to-docx)
  :custom
  (org-pandoc-command (executable-find "pandoc"))
  (org-pandoc-options '((standalone .  t)))
  (org-pandoc-options-for-docx '((standalone . nil)))
  (org-pandoc-options-for-beamer-pdf '((pdf-engine . "xelatex")))
  (org-pandoc-options-for-latex-pdf '((pdf-engine . "xelatex")))
  (org-pandoc-format-extensions '(org+smart)))

;;;;; Ox-Pandoc Export Menu Options
;; Set pandoc export options
(setq org-pandoc-menu-entry
      '(
        ;;(?0 "to jats." org-pandoc-export-to-jats)
        ;;(?0 "to jats and open." org-pandoc-export-to-jats-and-open)
        ;;(?  "as jats." org-pandoc-export-as-jats)
        ;;(?1 "to epub2 and open." org-pandoc-export-to-epub2-and-open)
        ;;(?! "to epub2." org-pandoc-export-to-epub2)
        ;;(?2 "to tei." org-pandoc-export-to-tei)
        ;;(?2 "to tei and open." org-pandoc-export-to-tei-and-open)
        ;;(?" "as tei." org-pandoc-export-as-tei)
        ;;(?3 "to markdown_mmd." org-pandoc-export-to-markdown_mmd)
        ;;(?3 "to markdown_mmd and open." org-pandoc-export-to-markdown_mmd-and-open)
        ;;(?# "as markdown_mmd." org-pandoc-export-as-markdown_mmd)
        ;;(?4 "to html5." org-pandoc-export-to-html5)
        (?4 "to html5 and open." org-pandoc-export-to-html5-and-open)
        (?$ "as html5." org-pandoc-export-as-html5)
        (?5 "to html5-pdf and open." org-pandoc-export-to-html5-pdf-and-open)
        (?% "to html5-pdf." org-pandoc-export-to-html5-pdf)
        ;;(?6 "to markdown_phpextra." org-pandoc-export-to-markdown_phpextra)
        ;;(?6 "to markdown_phpextra and open." org-pandoc-export-to-markdown_phpextra-and-open)
        ;;(?& "as markdown_phpextra." org-pandoc-export-as-markdown_phpextra)
        ;;(?7 "to markdown_strict." org-pandoc-export-to-markdown_strict)
        ;;(?7 "to markdown_strict and open." org-pandoc-export-to-markdown_strict-and-open)
        ;;(?' "as markdown_strict." org-pandoc-export-as-markdown_strict)
        ;; (?8 "to opendocument." org-pandoc-export-to-opendocument)
        ;; (?8 "to opendocument and open." org-pandoc-export-to-opendocument-and-open)
        ;; (?( "as opendocument." org-pandoc-export-as-opendocument)
        (?8 "to opml." org-pandoc-export-to-opml)
        (?9 "to opml and open." org-pandoc-export-to-opml-and-open)
        ;; (?* "as opml." org-pandoc-export-as-opml)
        ;;(?: "to rst." org-pandoc-export-to-rst)
        ;;(?: "to rst and open." org-pandoc-export-to-rst-and-open)
        ;;(?* "as rst." org-pandoc-export-as-rst)
        ;;(?< "to slideous." org-pandoc-export-to-slideous)
        (?< "to slideous and open." org-pandoc-export-to-slideous-and-open)
        (?, "as slideous." org-pandoc-export-as-slideous)
        (?= "to ms-pdf and open." org-pandoc-export-to-ms-pdf-and-open)
        (?- "to ms-pdf." org-pandoc-export-to-ms-pdf)
        ;;(?> "to textile." org-pandoc-export-to-textile)
        ;;(?> "to textile and open." org-pandoc-export-to-textile-and-open)
        ;;(?. "as textile." org-pandoc-export-as-textile)
        ;;(?a "to asciidoc." org-pandoc-export-to-asciidoc)
        ;;(?a "to asciidoc and open." org-pandoc-export-to-asciidoc-and-open)
        ;;(?A "as asciidoc." org-pandoc-export-as-asciidoc)
        (?b "to beamer-pdf and open." org-pandoc-export-to-beamer-pdf-and-open)
        (?B "to beamer-pdf." org-pandoc-export-to-beamer-pdf)
        (?c "to context-pdf and open." org-pandoc-export-to-context-pdf-and-open)
        (?C "to context-pdf." org-pandoc-export-to-context-pdf)
        ;;(?d "to docbook5." org-pandoc-export-to-docbook5)
        (?d "to docbook5 and open." org-pandoc-export-to-docbook5-and-open)
        (?D "as docbook5." org-pandoc-export-as-docbook5)
        (?e "to epub3 and open." org-pandoc-export-to-epub3-and-open)
        (?E "to epub3." org-pandoc-export-to-epub3)
        ;;(?f "to fb2." org-pandoc-export-to-fb2)
        ;;(?f "to fb2 and open." org-pandoc-export-to-fb2-and-open)
        ;;(?F "as fb2." org-pandoc-export-as-fb2)
        ;;(?g "to gfm." org-pandoc-export-to-gfm)
        (?g "to gfm and open." org-pandoc-export-to-gfm-and-open)
        (?G "as gfm." org-pandoc-export-as-gfm)
        ;;(?h "to html4." org-pandoc-export-to-html4)
        (?h "to html4 and open." org-pandoc-export-to-html4-and-open)
        (?H "as html4." org-pandoc-export-as-html4)
        ;;(?i "to icml." org-pandoc-export-to-icml)
        (?i "to icml and open." org-pandoc-export-to-icml-and-open)
        (?I "as icml." org-pandoc-export-as-icml)
        ;;(?j "to json." org-pandoc-export-to-json)
        (?j "to json and open." org-pandoc-export-to-json-and-open)
        (?J "as json." org-pandoc-export-as-json)
        ;; (?k "to markdown." org-pandoc-export-to-markdown)
        (?k "to markdown and open." org-pandoc-export-to-markdown-and-open)
        (?K "as markdown." org-pandoc-export-as-markdown)
        (?l "to latex-pdf and open." org-pandoc-export-to-latex-pdf-and-open)
        (?L "to latex-pdf." org-pandoc-export-to-latex-pdf)
        ;;(?m "to man." org-pandoc-export-to-man)
        (?m "to man and open." org-pandoc-export-to-man-and-open)
        (?M "as man." org-pandoc-export-as-man)
        ;;(?n "to native." org-pandoc-export-to-native)
        (?n "to native and open." org-pandoc-export-to-native-and-open)
        (?N "as native." org-pandoc-export-as-native)
        (?o "to odt and open." org-pandoc-export-to-odt-and-open)
        (?O "to odt." org-pandoc-export-to-odt)
        (?p "to pptx and open." org-pandoc-export-to-pptx-and-open)
        (?P "to pptx." org-pandoc-export-to-pptx)
        ;;(?q "to commonmark." org-pandoc-export-to-commonmark)
        ;;(?q "to commonmark and open." org-pandoc-export-to-commonmark-and-open)
        ;;(?Q "as commonmark." org-pandoc-export-as-commonmark)
        ;;(?r "to rtf." org-pandoc-export-to-rtf)
        (?r "to rtf and open." org-pandoc-export-to-rtf-and-open)
        (?R "as rtf." org-pandoc-export-as-rtf)
        ;;(?s "to s5." org-pandoc-export-to-s5)
        ;;(?s "to s5 and open." org-pandoc-export-to-s5-and-open)
        ;;(?S "as s5." org-pandoc-export-as-s5)
        ;;(?t "to texinfo." org-pandoc-export-to-texinfo)
        ;;(?t "to texinfo and open." org-pandoc-export-to-texinfo-and-open)
        ;;(?T "as texinfo." org-pandoc-export-as-texinfo)
        ;;(?u "to dokuwiki." org-pandoc-export-to-dokuwiki)
        (?u "to dokuwiki and open." org-pandoc-export-to-dokuwiki-and-open)
        (?U "as dokuwiki." org-pandoc-export-as-dokuwiki)
        ;; (?v "to revealjs." org-pandoc-export-to-revealjs)
        (?v "to revealjs and open." org-pandoc-export-to-revealjs-and-open)
        (?V "as revealjs." org-pandoc-export-as-revealjs)
        ;;(?w "to mediawiki." org-pandoc-export-to-mediawiki)
        (?w "to mediawiki and open." org-pandoc-export-to-mediawiki-and-open)
        (?W "as mediawiki." org-pandoc-export-as-mediawiki)
        (?x "to docx and open." org-pandoc-export-to-docx-and-open)
        (?X "to docx." org-pandoc-export-to-docx)
        ;;(?y "to slidy." org-pandoc-export-to-slidy)
        (?y "to slidy and open." org-pandoc-export-to-slidy-and-open)
        (?Y "as slidy." org-pandoc-export-as-slidy)
        ;;(?z "to dzslides." org-pandoc-export-to-dzslides)
        (?z "to dzslides and open." org-pandoc-export-to-dzslides-and-open)
        (?Z "as dzslides." org-pandoc-export-as-dzslides)
        ;;(?{ "to muse." org-pandoc-export-to-muse)
        ;;(?{ "to muse and open." org-pandoc-export-to-muse-and-open)
        ;;(?[ "as muse." org-pandoc-export-as-muse)
        ;;(?} "to zimwiki." org-pandoc-export-to-zimwiki)
        ;;(?} "to zimwiki and open." org-pandoc-export-to-zimwiki-and-open)
        ;;(?] "as zimwiki." org-pandoc-export-as-zimwiki)
        ;;(?~ "to haddock." org-pandoc-export-to-haddock)
        ;;(?~ "to haddock and open." org-pandoc-export-to-haddock-and-open)
        ;;(?^ "as haddock." org-pandoc-export-as-haddock)
        ))

;; Exporting different regions
;;;;;; Export Headings as Seperate Files
;; export headlines to separate files
;; http://pragmaticemacs.com/emacs/export-org-mode-headlines-to-separate-files/ ; see also:
;; http://emacs.stackexchange.com/questions/2259/how-to-export-top-level-headings-of-org-mode-buffer-to-separate-files

;; FIXME: neither of these functions work right now for some reason.
(defun lem-org-export-headlines-to-docx ()
  "Export all subtrees that are *not* tagged with :noexport: to
    separate docx files.

    Subtrees that do not have the :EXPORT_FILE_NAME: property set
    are exported to a filename derived from the headline text."
  (interactive)
  (save-buffer)
  (let ((modifiedp (buffer-modified-p)))
    (save-excursion
      (goto-char (point-min))
      (goto-char (re-search-forward "^*"))
      (set-mark (line-beginning-position))
      (goto-char (point-max))
      (org-map-entries
       (lambda ()
         (let ((export-file (org-entry-get (point) "EXPORT_FILE_NAME")))
           (unless export-file
             (org-set-property
              "EXPORT_FILE_NAME"
              (replace-regexp-in-string " " "_" (nth 4 (org-heading-components)))))
           (deactivate-mark)
           (org-pandoc-export-to-docx nil t)
           (unless export-file (org-delete-property "EXPORT_FILE_NAME"))
           (set-buffer-modified-p modifiedp)))
       "-noexport" 'region-start-level)))
  (shell-command-to-string "open ~/Dropbox/Work/Comments/Referee-Reports/ref-report.docx"))

(defun lem-org-export-headlines-to-pdf ()
  "Export all subtrees that are *not* tagged with :noexport: to
    separate pdf files.

    Subtrees that do not have the :EXPORT_FILE_NAME: property set
    are exported to a filename derived from the headline text."
  (interactive)
  ;; (require 'ox-pandoc)
  (save-buffer)
  (let ((modifiedp (buffer-modified-p)))
    (save-excursion
      (goto-char (point-min))
      (goto-char (re-search-forward "^*"))
      (set-mark (line-beginning-position))
      (goto-char (point-max))
      (org-map-entries
       (lambda ()
         (let ((export-file (org-entry-get (point) "EXPORT_FILE_NAME")))
           (unless export-file
             (org-set-property
              "EXPORT_FILE_NAME"
              (replace-regexp-in-string " " "_" (nth 4 (org-heading-components)))))
           (deactivate-mark)
           (org-latex-export-to-pdf nil t nil nil '(:latex-class "org-notes"))
           ;; (org-pandoc-export-to-latex-pdf nil t)
           (unless export-file (org-delete-property "EXPORT_FILE_NAME"))
           (set-buffer-modified-p modifiedp)))
       "-noexport" 'region-start-level))))

;;;;;; Export Top Level Trees to File
;; From a useful [[https://emacs.stackexchange.com/questions/27226/how-to-export-top-level-trees-in-an-org-file-to-corresponding-files][stack exchange]] post
(defun lem-org-map-entries (org-file in-tags func)
  (let ((tags (if (stringp in-tags)
                  (list in-tags)
                in-tags)))

    (with-temp-buffer
      (org-mode)
      (insert-file-contents org-file)

      ;; Execute func at each heading that matches tags.
      (while (< (point) (point-max))

        ;; If find a heading...
        (and (search-forward-regexp "^\* " nil "end")

             ;; ...that matches the given tags...
             (seq-reduce
              (lambda(a b) (and a b))
              (mapcar
               (lambda (tag)
                 (beginning-of-line)
                 (search-forward-regexp
                  (concat ":" tag ":") (line-end-position) "end"))
               tags)
              t)

             ;; ... then execute given function with cursor at beginning of
             ;; heading.
             (progn
               (beginning-of-line)
               (save-excursion
                 (funcall func))
               (end-of-line)))))))

;;;;;; Org Export Last Subtree
;; bind f5 to keyboard macro of export-last-subtree
(fset 'export-last-subtree
      "\C-u\C-c\C-e")

(eval-after-load "org"
  '(progn
     (define-key org-mode-map (kbd "<f5>") 'export-last-subtree)))

;; Exporting to HTML

;;;;;; Org Export Body to HTML Buffer
(defun lem-org-export-to-buffer-html-as-body (&optional async body-only ext-plist)
  "Export org buffer body to html"
  (interactive)
  (org-export-to-buffer 'html "*Org HTML Export*"
    async nil nil body-only ext-plist
    (lambda ()
      (html-mode)
      (lem-copy-whole-buffer-to-clipboard)))
  (delete-windows-on "*Org HTML Export*")
  (message "HTML copied!"))
;; (lem-previous-user-buffer))

;;;;; Ox-Hugo
;; Export to Hugo with Org
;; https://github.com/kaushalmodi/ox-hugo
(use-package ox-hugo
  :ensure t
  :defer t  ;; Defer loading until needed for Hugo export
  :commands (org-hugo-export-as-md
             org-hugo-export-to-md
             org-hugo-export-wim-to-md
             org-hugo-export-subtree-to-md)
  :config
  ;; https://ox-hugo.scripter.co/doc/org-cite-citations/
  ;; Modify this to have a different header for references
  (plist-put org-hugo-citations-plist :bibliography-section-heading "References"))

;;;;;; Org-Hugo Links
;; New link type for Org-Hugo internal links
(defun org-hugo-link-complete ()
  "Create link with Hugo ref shortcode"
  (concat "{{% ref " (file-relative-name (read-file-name "File: ")) " %}}"))

(defun org-hugo-follow (link)
  (find-file (expand-file-name link)))

(with-eval-after-load 'org
  (org-link-set-parameters "hugo"
                           :complete 'org-hugo-link-complete
                           :follow 'org-hugo-follow))

;;;; Org Html Conversion
(use-package htmlize
  :ensure t
  :commands (htmlize-buffer))

;;;; Clipboard conversion through Pandoc 
;; (initially lived in the file for functions in Lambda Emacs)
(defun sp-org-to-markdown ()
  "convert clipboard contents from org to markdown and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t markdown"))
  (yank))

(defun sp-markdown-to-org ()
  "convert clipboard contents from markdown to org and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f markdown -t org"))
  (yank))

(defun sp-tex-to-org ()
  "convert clipboard contents from markdown to org and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f latex -t org"))
  (yank))

(defun sp-org-to-tex ()
  "convert clipboard contents from org to tex and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t latex"))
  (yank))

(defun sp-tex-to-markdown ()
  "convert clipboard contents from markdown to org and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f latex -t markdown --markdown-headings=atx"))
  (yank))

(defun sp-markdown-to-tex ()
  "convert clipboard contents from markdown to org and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f markdown -t latex"))
  (yank))

(defun sp-cite-to-org ()
  "convert clipboard contents from markdown to org with citations and paste"
  (interactive)
  (kill-new (shell-command-to-string (concat "pbpaste | pandoc --bibliography=" sp-bibliography " -s -t markdown-native_divs-raw_html-citations | pandoc -f markdown -t org")))
  (yank))

(defun sp-cite-to-markdown ()
  "convert clipboard contents to markdown with citations and paste"
  (interactive)
  (kill-new (shell-command-to-string (concat "pbpaste | pandoc --bibliography=" sp-bibliography " -s -t markdown-native_divs-raw_html-citations --markdown-headings=atx")))
  (yank))

(defun sp-bibtex-to-yaml-reference ()
  "convert clipboard bibtex contents to yaml and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc-citeproc -y -f bibtex | pbcopy"))
  (yank))

(defun sp-md-to-rtf ()
  "convert md to rtf and send to clipboard"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f markdown -t rtf | pbcopy"))
  (yank))


;; NOTE: piping to pbcopy doesn't seem to work but it is ready to paste as is
(defun sp-org-to-rtf ()
  "convert org to rtf and send to clipboard"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t html | /usr/bin/textutil -stdin -stdout -format html -convert rtf -fontsize 14 -font Helvetica | pbcopy")))

(defun sp-org-to-mail-rtf ()
  "copy buffer, convert clipboard contents from org to rtf, and send to mail message"
  (interactive)
  (sp-copy-whole-buffer-to-clipboard)
  ;; (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t rtf"))
  (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t html | /usr/bin/textutil -stdin -stdout -format html -convert rtf -fontsize 14 | pbcopy"))
  (kill-buffer)
  (delete-frame)
  (do-applescript "if application \"Mail\" is running then
      tell application \"Mail\"
      activate
      delay 0.35
      tell application \"System Events\"
      keystroke \"v\" using {command down}
      end tell
      end tell
      end if"))

(provide 'sp-org-export)
