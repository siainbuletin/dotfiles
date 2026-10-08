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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Provide
(provide 'sp-dired)

;;; sp-dired.el ends here