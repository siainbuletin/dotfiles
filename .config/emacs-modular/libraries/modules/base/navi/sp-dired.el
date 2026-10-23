;;; sp-dired.el --- Dired and Dirvish file management -*- lexical-binding: t; -*-

;;; Commentary:

;; Setup code for "navigating" Emacs, in the sense of outlines, goto functions,
;; saving place, recent files, etc.
;; this file is particularly concerned with good settings for dired.

;;; Code:

;;;; Helpful functions
;; Make-dired-file-sizes-human-readable
;; Add file sizes in human-readable units (KB, MB, etc) to dired buffers.
(setq-default dired-listing-switches "-alh")

;;;;; Dired Sidebar
(use-package dired-sidebar
  :commands (dired-sidebar-toggle-sidebar)

  :custom
  ;; Auto-fit width to content
  (dired-sidebar-resize-on-open t)
  (dired-sidebar-width 40)

  ;; Set horizontal fitting to only when needed
  (fit-window-to-buffer-horizontally 'only))

;;;; Personal function for sorting

(defun sp-dired-sort ()
  "Sort dired dir listing in different ways.
Prompt for a choice.
Works in linux, MacOS, Microsoft Windows."
  (interactive)
  (let ((xmenu '(("date" . "-Al -t")
                 ("size" . "-Al -S")
                 ("name" . "-Al ")
                 ("dir" . "-Al --group-directories-first")))
        xsortBy)
    (setq xsortBy (completing-read "Sort by (default date):" xmenu nil t nil nil (caar xmenu)))
    (dired-sort-other (cdr (assoc xsortBy xmenu)))))

;; Set Dired listing switches for more minimalist output
(setq dired-listing-switches "-aghov --group-directories-first")

;; Additional syntax highlighting for dired
(use-package diredfl
  :ensure t
  :hook
  ((dired-mode . diredfl-mode)
   ;; highlight parent and directory preview as well
   (dirvish-directory-view-mode . diredfl-mode))

  :config
  (set-face-attribute 'diredfl-dir-name nil :bold t))

;;;; Dirvish dired extension
(use-package dirvish
  :ensure t
  :after dired

  :init
  (dirvish-override-dired-mode)          ; global mode, enable once
  :hook
  (dirvish-mode . dirvish-emerge-mode)   ; only inside Dirvish buffers

  :config
  (dirvish-peek-mode)
  (dirvish-side-follow-mode)

  :custom
  ;; attributes to show in the dirvish buffer
  (dirvish-attributes
  '(vc-state file-size git-msg subtree-state nerd-icons collapse file-time))

  ;; UI settings for dirvish
  (dirvish-mode-line-format
    '(:left (sort symlink)
      :right (vc-info yank index)))
  (dirvish-header-line-height '(25 . 35))
  (dirvish-header-line-format '(:left (path) :right (free-space)))
  (dirvish-side-width 38)

  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first")

  ;; showing the cursor
  ;; Dirvish by default hides the cursor in Dired buffers and highlights the current line.
  ;; It uses the dirvish-hl-line face for the active window and dirvish-hl-line-inactive for
  ;; inactive windows. To modify this behavior, customize the dirvish-hide-cursor variable.
  (dirvish-hide-cursor t)

  ;; Customizing the cache dir
  (dirvish-cache-dir (concat sp-cache-dir "dirvish/"))

  ;; groups
  (dirvish-emerge-groups
   '(("Recent files" (predicate . recent-files-2h))
     ("Documents"    (extensions "pdf" "tex" "bib" "epub"))
     ("Video"        (extensions "mp4" "mkv" "webm"))
     ("Pictures"     (extensions "jpg" "png" "svg" "gif"))
     ("Audio"        (extensions "mp3" "flac" "wav" "ape" "aac"))
     ("Archives"     (extensions "gz" "rar" "zip"))))

  ;; Keybindings to move through the buffer
  :bind
  (("C-c f" . dirvish)
   :map dirvish-mode-map               ; Dirvish inherits `dired-mode-map'
   (";"   . dired-up-directory)        ; So you can adjust `dired' bindings here
   ("?"   . dirvish-dispatch)          ; [?] a helpful cheatsheet
   ("a"   . dirvish-setup-menu)        ; [a]ttributes settings:`t' toggles mtime, `f' toggles fullframe, etc.
   ("f"   . dirvish-file-info-menu)    ; [f]ile info
   ("o"   . dirvish-quick-access)      ; [o]pen `dirvish-quick-access-entries'
   ("s"   . dirvish-quicksort)         ; [s]ort flie list
   ("r"   . dirvish-history-jump)      ; [r]ecent visited
   ("l"   . dirvish-ls-switches-menu)  ; [l]s command flags
   ("v"   . dirvish-vc-menu)           ; [v]ersion control commands
   ("*"   . dirvish-mark-menu)
   ("y"   . dirvish-yank-menu)
   ("N"   . dirvish-narrow)
   ("^"   . dirvish-history-last)
   ("TAB" . dirvish-subtree-toggle)
   ("M-f" . dirvish-history-go-forward)
   ("M-b" . dirvish-history-go-backward)
   ("M-e" . dirvish-emerge-menu)))

;;;; Windowing Layout for dirvish
;; this should make it work like yazi

;;;; Preview options
(setq dirvish-preview-buffers-max-count 2)
;; (dirvish-preview-environment) ;; I don't know how to set this up
;; (setq dirvish-preview-large-file-threshold) ;; anything above the default threshold is previewed partially

;; Custom preview for directories with 'eza'.  `dirvish-define-preview' is a
;; macro from Dirvish, which is loaded later, so define it once Dirvish is there.
(with-eval-after-load 'dirvish
  (dirvish-define-preview eza (file)
    "Use `eza' to generate directory preview."
    :require ("eza") ; tell Dirvish to check if we have the executable
    (when (file-directory-p file) ; we only interest in directories here
      `(shell . ("eza" "-al" "--color=always" "--icons=always"
                 "--group-directories-first" ,file))))

  (push 'eza dirvish-preview-dispatchers))

;;;;; Open binary files externally
(defun dirvish-open-binaries-externally (file fn)
  "When FN is not `dired', open binary FILE externally."
  (when-let* (((not (eq fn 'dired)))
              ((file-exists-p file))
              ((not (file-directory-p file)))
              ((member (downcase (or (file-name-extension file) ""))
                       dirvish-binary-exts)))
    ;; return t to terminate `dirvish--find-entry'.
    (prog1 t (dired-do-open))))

(add-hook 'dirvish-find-entry-hook #'dirvish-open-binaries-externally)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide 'sp-dired)

;;; sp-dired.el ends here
