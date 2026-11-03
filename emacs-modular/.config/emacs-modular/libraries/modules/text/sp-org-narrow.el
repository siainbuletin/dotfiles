;;; sp-org-narrow.el --- Narrowing helpers for long Org buffers -*- lexical-binding: t; -*-

;;; Commentary:

;; This is a bunch of functions for better working with longer org-mode buffers,
;; which would need employing narrowing.
;;
;; In the future, they should be somehow correlated with vulpea-ui-sidebar so that
;; the sidebar actually follows the narrowing properly and doesn't show any other
;; kind of context.

;;; Code:

;;;; Narrow/Widen with buffers
;; this could definitely be made a lot better for more complicated work with narrowed buffers

(defun sp-narrow-or-widen-dwim (p)
  "Widen if buffer is narrowed, narrow-dwim otherwise.
  Dwim means: region, org-src-block, org-subtree, markdown
  subtree, or defun, whichever applies first. Narrowing to
  org-src-block actually calls `org-edit-src-code'.

  With prefix P, don't widen, just narrow even if buffer
  is already narrowed."
  (declare (interactive-only t))
  (interactive "P")
  (cond ((and (buffer-narrowed-p) (not p)) (widen))
        ((region-active-p)
         (narrow-to-region (region-beginning)
                           (region-end)))
        ((derived-mode-p 'org-mode)
         ;; `org-edit-src-code' is not a real narrowing
         ;; command. Remove this first conditional if
         ;; you don't want it.
         (cond ((ignore-errors (org-edit-src-code) t)
                (delete-other-windows))
               ((ignore-errors (org-narrow-to-block) t))
               (t (org-narrow-to-subtree))))
        ((derived-mode-p 'markdown-mode)
         (markdown-narrow-to-subtree))
        ((derived-mode-p 'latex-mode)
         (LaTeX-narrow-to-environment))
        (t (narrow-to-defun))))

;;bind this in the narrow keymap
(bind-key* "C-x n n" #'sp-narrow-or-widen-dwim narrow-map)

;;;;; Narrow & Advance/Retreat
;; Functions to advance forwards or backwards through narrowed tree
(defun sp-org-advance ()
  (interactive)
  (when (buffer-narrowed-p)
    (goto-char (point-min))
    (widen)
    (org-forward-heading-same-level 1))
  (org-narrow-to-subtree))

(defun sp-org-retreat ()
  (interactive)
  (when (buffer-narrowed-p)
    (goto-char (point-min))
    (widen)
    (org-backward-heading-same-level 1))
  (org-narrow-to-subtree))

;;;;; Clone and Narrow
(defun sp-clone-buffer-and-narrow ()
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
