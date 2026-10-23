;;; sp-canvas.el --- Experimental canvas and Excalidraw support -*- lexical-binding: t; -*-

;;; Commentary:

;; Canvas will be useful for Emacs reader more, but there's also
;; excalidraw and other functions that I'd like to try out in my
;; work around Emacs.

;;; Code:

(let ((excali-directory (expand-file-name "/path/to/excali-mode")))
  (when (and (>= emacs-major-version 32)
             (fboundp 'canvas-refresh)
             (image-type-available-p 'canvas)
             (file-exists-p
              (expand-file-name (concat "excali-module" module-file-suffix)
                                excali-directory)))
    (add-to-list 'load-path excali-directory)

    (use-package excali
      :defer t
      :commands (excali-open excali-new))

    ;; Text source files, NOT .excalidraw scene files.
    (autoload 'excali-dsl-mode "excali-dsl" nil t)
    (add-to-list 'auto-mode-alist
                 '("\\.excalidsl\\'" . excali-dsl-mode))))

;;; End:
(provide 'sp-canvas)
;; sp-canvas.el ends here.x
