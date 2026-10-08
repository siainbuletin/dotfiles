;; -*- lexical-binding: t -*-

;;;;; Org Emphasis Functions
;; Adapted from https://emacs.stackexchange.com/a/14586
;; See https://emacstil.com/til/2021/11/29/org-emphasize-dwim/
(defun org-emphasize-dwim (&optional char)
  (interactive)
  (unless (region-active-p)
    (lem-maybe-mark-word))
  (org-emphasize char))

(defun org-emphasize-with-verbatim-dwim ()
  (interactive)
  (org-emphasize-dwim ?=))

(defun org-emphasize-with-code-dwim ()
  (interactive)
  (org-emphasize-dwim ?~))

(defun lem--cursor-outside-of-any-word ()
  (not (bounds-of-thing-at-point 'word)))

(defun lem--cursor-at-beginning-of-a-word ()
  (eq (point) (car (bounds-of-thing-at-point 'word))))

(defun lem-maybe-mark-word ()
  "Mark the current word. If cursor is outside of a word bounds, mark the empty position."
  (interactive)
  (unless (or (lem--cursor-outside-of-any-word) (lem--cursor-at-beginning-of-a-word))
    (backward-word))
  (unless (lem--cursor-outside-of-any-word)
    (mark-word)))

;;;; Proper highlighting of regions, like in Markdown with Obsidian
(use-package org-extra-emphasis
  :ensure (:type git :host github :repo "QiangF/org-extra-emphasis"))

(provide sp-org-emphasis)