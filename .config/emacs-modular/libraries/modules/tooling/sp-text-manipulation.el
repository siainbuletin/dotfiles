;;; sp-text-manipulation.el --- Text editing helpers and whitespace cleanup -*- lexical-binding: t; -*-

;;; Commentary:

;; This creates useful functions for moving around text a lot easier.

;;; Code:

;;;; Enabling CUA mode by default.
(cua-mode)

;; Cleaning up unnecessary whitespace
(defun sp-clean-whitespace (&optional Begin End)
  "Delete trailing whitespace, and replace repeated blank lines to just 1.
Only space and tab is considered whitespace here.
Works on whole buffer or selection, respects `narrow-to-region'."
  (interactive)
  (let (xbeg xend)
    (seq-setq (xbeg xend)
              (if (and Begin End)
                  (list Begin End)
                (if (region-active-p)
                    (list (region-beginning) (region-end))
                  (list (point-min) (point-max)))))
    (save-excursion
      (save-restriction
        (narrow-to-region xbeg xend)
        (progn
          (goto-char (point-min))
          (while (re-search-forward "[ \t]+\n" nil t) (replace-match "\n")))
        (progn
          (goto-char (point-min))
          (while (re-search-forward "\n\n\n+" nil t) (replace-match "\n\n")))
        (progn
          (goto-char (point-max))
          (while (eq (char-before) 32) (delete-char -1))))))
  (message "done sp-clean-whitespace"))

(add-hook 'before-save-hook 'sp-clean-whitespace)

;;;; Add whitespace before and after heading
;;
;; Ensure that blank lines exist between headings and between headings and their contents. 
;; With prefix, operate on whole buffer. Ensures that blank lines exist after each headings’s
;; drawers. Works on a subtree or a whole buffer. It also adds blank lines after drawers. 
;; Works well with *~org-return-dwim~.
;;
;; source: https://github.com/alphapapa/unpackaged.el#agenda-for-subtree-or-region

;;;###autoload
(defun sp-org-fix-blank-lines (&optional prefix)
  "Ensure that blank lines exist between headings and between headings and their contents.
With prefix, operate on whole buffer. Ensures that blank lines
exist after each headings's drawers."
  (interactive "P")
  (org-map-entries (lambda ()
                     (org-with-wide-buffer
                      ;; `org-map-entries' narrows the buffer, which prevents us from seeing
                      ;; newlines before the current heading, so we do this part widened.
                      (while (not (looking-back "\n\n" nil))
                        ;; Insert blank lines before heading.
                        (insert "\n")))
                     (let ((end (org-entry-end-position)))
                       ;; Insert blank lines before entry content
                       (forward-line)
                       (while (and (org-at-planning-p)
                                   (< (point) (point-max)))
                         ;; Skip planning lines
                         (forward-line))
                       (while (re-search-forward org-drawer-regexp end t)
                         ;; Skip drawers. You might think that `org-at-drawer-p' would suffice, but
                         ;; for some reason it doesn't work correctly when operating on hidden text.
                         ;; This works, taken from `org-agenda-get-some-entry-text'.
                         (re-search-forward "^[ \t]*:END:.*\n?" end t)
                         (goto-char (match-end 0)))
                       (unless (or (= (point) (point-max))
                                   (org-at-heading-p)
                                   (looking-at-p "\n"))
                         (insert "\n"))))
                   t (if prefix
                         nil
                       'tree)))

;;;;; Fill Paragraph
(defun sp-fill-paragraph ()
  "if in an org buffer use org-fill-paragraph; else use fill-paragraph"
  (interactive)
  (if (derived-mode-p 'org-mode)
      (call-interactively #'org-fill-paragraph)
    (call-interactively #'fill-paragraph)))

;; TODO --- this isn't the proper settings - I should workshop ways to
;; do the fill-paragraph properly
;; (keymap-global-set [remap fill-paragraph]
;;                #'sp-fill-paragraph)

;;;;; Unfill Paragraph
;; Stefan Monnier <foo at acm.org>. It is the opposite of fill-paragraph
(defun sp-unfill-paragraph (&optional region)
  "Takes a multi-line paragraph and makes it into a single line of text."
  (interactive (progn (barf-if-buffer-read-only) '(t)))
  (let ((fill-column (point-max))
        ;; This would override `fill-column' if it's an integer.
        (emacs-lisp-docstring-fill-column t))
    (fill-paragraph nil region)))
(keymap-global-set "M-Q" #'sp-unfill-paragraph)

;;;;; Formatted Copy
(defun formatted-copy ()
  "Export region to HTML, and copy it to the clipboard."
  (interactive)
  (save-window-excursion
    (let* ((buf (org-export-to-buffer 'html "*Formatted Copy*" nil nil t t))
           (html (with-current-buffer buf (buffer-string))))
      (with-current-buffer buf
        (shell-command-on-region
         (point-min)
         (point-max)
         "textutil -stdin -format html -convert rtf -stdout | pbcopy"))
      (kill-buffer buf))))

(keymap-global-set "H-w" 'formatted-copy)

;; Abbreviation

(use-package abbrev
  :ensure nil
  :defer 2
  :config
  ;; (add-hook 'text-mode-hook #'abbrev-mode)
  (setq abbrev-file-name (concat sp-var-dir "abbrev/.abbrev_defs")
        save-abbrevs 'nil)
  (if (file-exists-p abbrev-file-name)
      (quietly-read-abbrev-file)))

;;;; Capitalization
;; From https://karthinks.com/software/batteries-included-with-emacs/
(keymap-global-set "M-u" 'upcase-dwim)
(keymap-global-set "M-l" 'downcase-dwim)
(keymap-global-set "M-c" 'capitalize-dwim)

;;;;; Smart Yanking
;;Courtesy of Marcin Borkowski http://mbork.pl/2018-07-02_Smart_yanking

(defun has-space-at-boundary-p (string)
  "Check whether STRING has any whitespace on the boundary.
      Return 'left, 'right, 'both or nil."
  (let ((result nil))
    (when (string-match-p "^[[:space:]]+" string)
      (setq result 'left))
    (when (string-match-p "[[:space:]]+$" string)
      (if (eq result 'left)
          (setq result 'both)
        (setq result 'right)))
    result))

(defun is-there-space-around-point-p ()
  "Check whether there is whitespace around point.
      Return 'left, 'right, 'both or nil."
  (let ((result nil))
    (when (< (save-excursion
               (skip-chars-backward "[:space:]"))
             0)
      (setq result 'left))
    (when (> (save-excursion
               (skip-chars-forward "[:space:]"))
             0)
      (if (eq result 'left)
          (setq result 'both)
        (setq result 'right)))
    result))

(defun set-point-before-yanking (string)
  "Put point in the appropriate place before yanking STRING."
  (let ((space-in-yanked-string (has-space-at-boundary-p string))
        (space-at-point (is-there-space-around-point-p)))
    (cond ((and (eq space-in-yanked-string 'left)
                (eq space-at-point 'left))
           (skip-chars-backward "[:space:]"))
          ((and (eq space-in-yanked-string 'right)
                (eq space-at-point 'right))
           (skip-chars-forward "[:space:]")))))

(defun set-point-before-yanking-if-in-text-mode (string)
  "Invoke `set-point-before-yanking' in text modes."
  (when (derived-mode-p 'text-mode)
    (set-point-before-yanking string)))

(advice-add
 'insert-for-yank
 :before
 #'set-point-before-yanking-if-in-text-mode)
;; http://lists.gnu.org/archive/html/help-gnu-emacs/2007-05/msg00975.html

(provide 'sp-text-manipulation)
;; sp-text-manipulation.el ends here.
