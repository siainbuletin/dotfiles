;; -*- lexical-binding: t; -*-
;; sp-org-narrow.el

;;; Commentary:

;; This is a bunch of functions for better working with longer org-mode buffers,
;; which would need employing narrowing.
;;
;; In the future, they should be somehow correlated with vulpea-ui-sidebar so that
;; the sidebar actually follows the narrowing properly and doesn't show any other
;; kind of context.

;;; Code:

;;;;; Narrow & Advance/Retreat
;; Functions to advance forwards or backwards through narrowed tree
(defun lem-org-advance ()
  (interactive)
  (when (buffer-narrowed-p)
    (goto-char (point-min))
    (widen)
    (org-forward-heading-same-level 1))
  (org-narrow-to-subtree))

(defun lem-org-retreat ()
  (interactive)
  (when (buffer-narrowed-p)
    (goto-char (point-min))
    (widen)
    (org-backward-heading-same-level 1))
  (org-narrow-to-subtree))

;;;;; Clone and Narrow
(defun lem-clone-buffer-and-narrow ()
  "Clone buffer and narrow outline tree"
  (interactive)
  (let ((buf (clone-indirect-buffer-other-window nil nil)))
    (with-current-buffer buf
      (cond ((derived-mode-p 'org-mode)
             (org-narrow-to-element))
            ((derived-mode-p 'markdown-mode)
             (markdown-narrow-to-subtree))))
    (switch-to-buffer-other-window buf)))

(provide 'sp-org-narrow)
;; sp-org-narrow.el ends here.