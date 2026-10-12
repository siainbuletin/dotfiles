;; -*- lexical-binding: t; -*-
;;; sp-dired.el --- summary

;;; Commentary:

;; Setup code for "navigating" Emacs, in the sense of outlines, goto functions,
;; saving place, recent files, etc.
;; this file is particularly concerned with good settings for dired.

;;; Code:

;; Configure dired to have casual bindings
  (use-package dired
    :ensure nil
    :after casual

    :bind
    (:map dired-mode-map
          ("C-o" . casual-dired-tmenu)))


;;;; Helpful functions
;; Make-dired-file-sizes-human-readable
;; Add file sizes in human-readable units (KB, MB, etc) to dired buffers.
(setq-default dired-listing-switches "-alh")    

;;;;; Dired Sidebar
(use-package dired-sidebar
  :when (and sp-load-extras (locate-library "dired-sidebar"))
  :commands (dired-sidebar-toggle-sidebar)
  
  :custom
  ;; Auto-fit width to content
  (dired-sidebar-resize-on-open t)
  (dired-sidebar-width 40)
  
  ;; Set horizontal fitting to only when needed
  (fit-window-to-buffer-horizontally 'only))

;;;; Personal function for sorting

(defun sia-dired-sort ()
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

;;;; Dirvish dired extension
(use-package dirvish
  :ensure t
  
  :init
  (dirvish-override-dired-mode)
  (dirvish-peek-mode)
  (dirvish-side-follow-mode)
  (dirvish-emerge-mode) ;; this will automatically start dirvish with the emerge mode (grouping for the file types)
)

(setq dirvish-attributes
      '(vc-state file-size git-msg subtree-state all-the-icons collapse file-time))

;;;;; UI settings for dirvish
(setq dirvish-mode-line-format '(:left (sort symlink) :right (vc-info yank index)))
(setq dirvish-header-line-height '(25 . 35))
(setq dirvish-side-width 38)
(setq dirvish-header-line-format '(:left (path) :right (free-space)))
(setq dired-listing-switches
      "-l --almost-all --human-readable --group-directories-first")

;;;; Open binary files externally
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

;;;; Grouping based on file type

(setq dirvish-emerge-groups
  ;; Header string |    Type    |    Criterias
  '(("Recent files"  (predicate . recent-files-2h))
  ("Documents"     (extensions "pdf" "tex" "bib" "epub"))
  ("Video"         (extensions "mp4" "mkv" "webm"))
  ("Pictures"      (extensions "jpg" "png" "svg" "gif"))
  ("Audio"         (extensions "mp3" "flac" "wav" "ape" "aac"))
  ("Archives"      (extensions "gz" "rar" "zip")))
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Provide
(provide 'sp-dired)

;;; sp-dired.el ends here