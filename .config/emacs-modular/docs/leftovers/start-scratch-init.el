;; Task management
(straight-use-package 'org-super-agenda)
(require 'org-inlinetask)

;; Reading packages
(straight-use-package 'calibredb)
(straight-use-package 'nov.el)

;; Configuration for calibredb
(use-package calibredb
  :defer t
  :config
  (setq calibredb-root-dir "~/Documents/calibre-library")
  (setq calibredb-db-dir "~/Documents/calibre-library/metadata.db")
  )

;; (straight-use-package 'phi-notes) ;; can't actually find the package (it has to be installed manually)

;; (straight-use-package
;; '(pdf-drop-mode :type git :host github :repo "rougier/pdf-drop-mode"))

;; SPACED REPETITION
(straight-use-package 'gnosis)

;; Definitions for built in packages
;; dired
;; org-attach
;; org-capture

;; CONFIGURING BIBTEX-CAPF
(use-package bibtex-capf
  :straight (:type git :host github :repo "mclear-tools/bibtex-capf")
  :hook ((org-mode markdown-mode tex-mode latex-mode reftex-mode). bibtex-capf-mode)
  :custom
  (bibtex-capf-bibliography
   '("~/Documents/bibliography/marx.bib")))

;; ORG-REF CONFIGURATION

(setq bibtex-completion-bibliography '("~/Documents/bib-files/master.bib"
					                   "~/Documents/bib-files/thesis.bib"
                                       "~/Documents/bib-files/marx.bib"
                                       "~/Documents/bib-files/hci.bib"
                                       "~/Documents/bib-files/aesthetics.bib")
	bibtex-completion-library-path '("~/Documents/literature/")
	bibtex-completion-notes-path "~/Documents/org-files/"
	bibtex-completion-notes-template-multiple-files "* ${author-or-editor}, ${title}, ${journal}, (${year}) :${=type=}: \n\nSee [[cite:&${=key=}]]\n"

    ;; this bit was copied directly from the GitHub page, I don't actually understand what it does
	bibtex-completion-additional-search-fields '(keywords)
	bibtex-completion-display-formats
	'((article       . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*} ${journal:40}")
	  (inbook        . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*} Chapter ${chapter:32}")
	  (incollection  . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*} ${booktitle:40}")
	  (inproceedings . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*} ${booktitle:40}")
	  (t             . "${=has-pdf=:1}${=has-note=:1} ${year:4} ${author:36} ${title:*}"))
	bibtex-completion-pdf-open-function
	(lambda (fpath)
	  (call-process "open" nil 0 nil fpath)))

;; Automatically generating BibTeX keys
(require 'bibtex)

(setq bibtex-autokey-year-length 4
      bibtex-autokey-name-year-separator "-"
      bibtex-autokey-year-title-separator "-"
      bibtex-autokey-titleword-separator "-"
      bibtex-autokey-titlewords 2
      bibtex-autokey-titlewords-stretch 1
      bibtex-autokey-titleword-length 5)

(define-key bibtex-mode-map (kbd "H-b") 'org-ref-bibtex-hydra/body)

;; Helm-bibtex for citation insertion
(require 'org-ref)
(require 'org-ref-helm)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CONFIGURING THE CASUAL SUITE ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(straight-use-package 'casual)

;; CASUAL AGENDA

;; CASUAL DIRED

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CONFIGURING THE MINIBUFFER ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Using emacs-mini-frame allows me to make the Emacs minibuffer basically behave like the Alfred launcher for computing several things.
;; it would be cool if I could integrate this with the eval section in StumpWM

(straight-use-package 'mini-frame)

;; Is this the command that you want to use if you're on a tiling window manager like Hyprland?
;; (setq mini-frame-detach-on-hide nil)
(setq mini-frame-standalone 't)
(setq mini-frame-resize-min-height 10)
;; (setq mini-frame-ignore-commands
;;      (append mini-frame-ignore-commands '(evil-window-split evil-window-vsplit evil-ex))
;;      )

;; Custom position for the mini frame

;; Making the miniframe scale better in the middle of the page
;; this has to use resize-mini-frames

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;
;; APPEARANCE ;;
;;;;;;;;;;;;;;;;

(straight-use-package
  '(nano :type git :host github :repo "rougier/nano-emacs"))

(require 'nano-layout)

(setq nano-font-family-monospaced "0xProto Nerd Font Mono")
(setq nano-font-family-proportional "Roboto Slab")
(setq nano-font-size 17)

(require 'nano-faces)
(nano-faces)

;; Load nano defaults
(require 'nano-defaults)

;; Enable the nano modeline
(require 'nano-modeline)

;; Defining the splash page for nano
(let ((inhibit-message t))
  (message "Welcome to GNU Emacs / N Λ N O edition")
  (message (format "Initialization time: %s" (emacs-init-time))))

(require 'nano-splash)

(require 'nano-help)

;; This is supposed to improve org-mode visually
(require 'nano-writer)
(add-to-list 'major-mode-remap-alist '(org-mode . writer-mode))

;; Define different themes for light and dark mode
;; (require 'nano-theme-light)
;; (require 'nano-theme-dark)

;; Loading NANO theme with better font file
;; (require 'nano-theme)
;; (setq nano-font-size 13) ;; font size has to be set BEFORE loading the NANO theme
;; (nano-toggle-theme)

;; THE FONT SIZE DECLARED HERE IS REDUNDANT, AS IT IS ALREADY DECLARED WITH THE FONT BEFORE. ALSO, I NEED TO DIRECTLY EDIT THE NANO-THEME.EL FILE IN ORDER TO MAKE THIS WORK.

;; Face settings
(set-face-attribute 'nano-face-strong nil
                    :foreground (face-foreground 'nano-face-default)
                    :weight 'bold)

;; By default, nano seems to disable a lot of bolding that is used,
;; so this function is supposed to fix it
(set-face-attribute 'bold nil :weight 'bold) ;; isn't this setting already redundant?

;;;;;;;;;;;;;;;;;;;;;;;
;; OTHER THEME FILES ;;
;;;;;;;;;;;;;;;;;;;;;;;

(straight-use-package 'dracula-theme)

;; this one is like an overall-warmer gruvbox
(straight-use-package 'suscolors-theme)

;; These are themes made by Protesilaos
(use-package ef-themes
  :ensure t
  :init
  ;; This makes the Modus commands listed below consider only the Ef
  ;; themes.  For an alternative that includes Modus and all
  ;; derivative themes (like Ef), enable the
  ;; `modus-themes-include-derivatives-mode' instead.
  (ef-themes-take-over-modus-themes-mode 1)
  :bind
  (
   ;; ("<f5>" . modus-themes-rotate)
   ;; ("C-<f5>" . modus-themes-select)
   ;; ("M-<f5>" . modus-themes-load-random)
   )
  :config
  ;; All customisations here.
  (setq modus-themes-mixed-fonts t)
  (setq modus-themes-italic-constructs t)

  ;; Finally, load your theme of choice (or a random one with
  ;; `modus-themes-load-random', `modus-themes-load-random-dark',
  ;; `modus-themes-load-random-light').

  ;; there are light themes (that I liked from the selection)
  ;; (modus-themes-load-theme 'ef-cyprus)
  ;; (modus-themes-load-theme 'ef-duo-light)
  ;; (modus-themes-load-theme 'ef-frost)
  ;; (modus-themes-load-theme 'ef-maris-light)
  ;; (modus-themes-load-theme 'ef-reverie)

  ;; these are some dark themes I liked
  ;; (modus-themes-load-theme 'ef-dark)
  ;; (modus-themes-load-theme 'ef-deuteranopia-dark)
  (modus-themes-load-theme 'ef-dream) ;; ABSOLUTELY GOATED LOOKING THEME
  )

;; Loading currennnt theme
;; (load-theme 'suscolors t)

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; NICETIES FOR BUFFERS ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Always enable the visual-line-mode when reading in a normal org buffer
(visual-line-mode)
; is this actually enabled just for org buffers or is it enabled globally?

;; visual-fill-column for a nice soft wrap
(use-package visual-fill-column
  :commands visual-fill-column-mode

  :custom
  (fill-column-enable-sensible-window-split t)

  :bind
  (("C-x p" . 'visual-fill-column-mode)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; OTHER ADJUSTMENTS AFTER PACKAGE MANAGEMENT

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ADJUSTMENTS FOR MACOS ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; this makes sure that the GUI version of Emacs on
;; MacOS picks up on the environment variables
(use-package exec-path-from-shell
  :ensure
  :init (exec-path-from-shell-initialize))

;; replace ls from coreutils with smth else so dired understands
(if (string-equal system-type "darwin")
    (setq dired-use-ls-dired nil))
