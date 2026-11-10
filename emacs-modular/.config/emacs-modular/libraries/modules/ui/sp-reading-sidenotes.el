;;; sp-reading-sidenotes.el --- See-also footnotes as sidenotes in reading mode -*- lexical-binding: t; -*-

;;; Commentary:

;; In `sp-reading-mode', inline footnotes that hold an id link are shown as a
;; small number in the text and as a sidenote in the right margin.  The footnote
;; stays in the file.  `sp-reading-sidenotes-export' exports the note with ox-tufte.
;; Literate source: docs/tangles/ui/sp-reading-sidenotes.org.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(require 'sp-see-also)

(defvar sp-reading-mode)
(defvar sp-reading-mode-hook)
(defvar sp-reading-right-margin)
(declare-function sp-reading--refresh "sp-writedesk")
(declare-function org-open-file "org")
(declare-function org-tufte-export-to-html "ox-tufte")

;; ox-tufte is the export backend; it is only loaded when exporting.
(use-package ox-tufte
  :ensure t
  :defer t)

(defgroup sp-reading-sidenotes nil
  "See-also footnotes as sidenotes in `sp-reading-mode'."
  :group 'sp-reading)

(defcustom sp-reading-sidenotes t
  "Non-nil turns the sidenotes on with `sp-reading-mode' in Org buffers."
  :type 'boolean :group 'sp-reading-sidenotes)

(defcustom sp-reading-sidenote-margin 30
  "Width in characters of the right margin while the sidenotes are shown."
  :type 'integer :group 'sp-reading-sidenotes)

(defcustom sp-reading-sidenote-min-text 40
  "Narrowest text area, in columns, that still gets sidenotes."
  :type 'integer :group 'sp-reading-sidenotes)

(defcustom sp-reading-sidenote-delay 0.4
  "Idle seconds after an edit before the sidenotes are laid out again."
  :type 'number :group 'sp-reading-sidenotes)

(defface sp-reading-sidenote
  '((t :inherit shadow))
  "Face of the sidenote text in the margin."
  :group 'sp-reading-sidenotes)

(defface sp-reading-sidenote-number
  '((t :inherit font-lock-constant-face :weight bold))
  "Face of the number that stands for a footnote in the text."
  :group 'sp-reading-sidenotes)

(defun sp-reading-sidenotes--plain (text)
  "TEXT with links shown as their description and white space squeezed."
  (string-trim
   (replace-regexp-in-string
    "[ \t\n]+" " "
    (replace-regexp-in-string
     "\\[\\[\\([^]]*\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\]" "\\2"
     (replace-regexp-in-string
      "\\[\\[\\([^]]*\\)\\]\\]" "\\1" text)))))

(defun sp-reading-sidenotes--scan ()
  "The see-also footnotes of the buffer, as a list of (BEG END LABEL TEXT).
LABEL is nil for an anonymous footnote."
  (mapcar (lambda (note)
            (list (plist-get note :beg) (plist-get note :end)
                  (plist-get note :label)
                  (sp-reading-sidenotes--plain (plist-get note :text))))
          (sp-see-also-parse-buffer)))

(defvar-local sp-reading-sidenotes--timer nil
  "Idle timer that lays the sidenotes out again after an edit.")

(defun sp-reading-sidenotes--clear ()
  "Remove every sidenote overlay of the current buffer."
  (remove-overlays (point-min) (point-max) 'sp-reading-sidenote t))

(defun sp-reading-sidenotes--lines (number text)
  "The margin lines of the note NUMBER with TEXT, wrapped to the margin."
  (let ((width (max 8 (1- sp-reading-sidenote-margin))))
    (mapcar
     (lambda (line) (truncate-string-to-width line width nil nil "…"))
     (with-temp-buffer
       (insert (format "%d %s" number text))
       (let ((fill-column width)
             (sentence-end-double-space nil))
         (fill-region (point-min) (point-max)))
       (split-string (buffer-string) "\n" t)))))

(defun sp-reading-sidenotes--margin-string (line)
  "A string that displays LINE in the right margin."
  (propertize " " 'display
              (list '(margin right-margin)
                    (propertize line 'face 'sp-reading-sidenote))))

(defun sp-reading-sidenotes--overlay (pos string)
  "A sidenote overlay at POS whose before-string is STRING."
  (let ((ov (make-overlay pos pos nil t)))
    (overlay-put ov 'sp-reading-sidenote t)
    (overlay-put ov 'before-string string)
    ov))

(defun sp-reading-sidenotes--number-overlay (note number)
  "Replace the footnote NOTE on screen by its NUMBER."
  (let ((ov (make-overlay (nth 0 note) (nth 1 note) nil t)))
    (overlay-put ov 'sp-reading-sidenote t)
    (overlay-put ov 'display
                 (propertize (number-to-string number)
                             'face 'sp-reading-sidenote-number
                             'display '(raise 0.3)))
    (overlay-put ov 'help-echo (nth 3 note))
    ov))

(defun sp-reading-sidenotes--place (window notes)
  "Put the margin lines of NOTES (a list of (BEG END LABEL TEXT)) in WINDOW."
  (let ((last nil)
        (number 0))
    (save-excursion
      (dolist (note notes)
        (setq number (1+ number))
        (goto-char (nth 0 note))
        (vertical-motion 0 window)
        (let ((pos (point)))
          (when (and last (<= pos last))
            (goto-char last)
            (vertical-motion 1 window)
            (setq pos (point)))
          (catch 'done
            (let ((first t))
              (dolist (line (sp-reading-sidenotes--lines number (nth 3 note)))
                (unless first
                  (goto-char pos)
                  (when (< (vertical-motion 1 window) 1) (throw 'done nil))
                  (setq pos (point)))
                (setq first nil
                      last pos)
                (sp-reading-sidenotes--overlay
                 pos (sp-reading-sidenotes--margin-string line))))))))))

(defun sp-reading-sidenotes--render ()
  "Draw the sidenotes of the current buffer, replacing the old ones."
  (sp-reading-sidenotes--clear)
  (let ((window (get-buffer-window (current-buffer))))
    (when (and window
               (>= (window-body-width window) sp-reading-sidenote-min-text))
      (let ((notes (sp-reading-sidenotes--scan))
            (number 0))
        (dolist (note notes)
          (sp-reading-sidenotes--number-overlay note (setq number (1+ number))))
        (sp-reading-sidenotes--place window notes)))))

(defun sp-reading-sidenotes--schedule (&rest _)
  "Lay the sidenotes out again after a short idle time."
  (when (timerp sp-reading-sidenotes--timer)
    (cancel-timer sp-reading-sidenotes--timer))
  (let ((buffer (current-buffer)))
    (setq sp-reading-sidenotes--timer
          (run-with-idle-timer
           sp-reading-sidenote-delay nil
           (lambda ()
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (setq sp-reading-sidenotes--timer nil)
                 (when (bound-and-true-p sp-reading-sidenotes-mode)
                   (sp-reading-sidenotes--render)))))))))

;;;###autoload
(define-minor-mode sp-reading-sidenotes-mode
  "Show the see-also footnotes of this Org buffer as sidenotes.
The footnote becomes a number in the text and its content is drawn in the
right margin.  Works inside `sp-reading-mode'."
  :lighter nil
  (if sp-reading-sidenotes-mode
      (progn
        (unless (and (derived-mode-p 'org-mode)
                     (bound-and-true-p sp-reading-mode))
          (setq sp-reading-sidenotes-mode nil)
          (user-error "Sidenotes need an Org buffer in `sp-reading-mode'"))
        (setq-local sp-reading-right-margin sp-reading-sidenote-margin
                    right-margin-width sp-reading-sidenote-margin)
        (add-hook 'window-configuration-change-hook
                  #'sp-reading-sidenotes--schedule nil t)
        (add-hook 'after-change-functions #'sp-reading-sidenotes--schedule nil t)
        (add-hook 'text-scale-mode-hook #'sp-reading-sidenotes--schedule nil t)
        (when (fboundp 'sp-reading--refresh) (sp-reading--refresh))
        (sp-reading-sidenotes--schedule))
    (remove-hook 'window-configuration-change-hook
                 #'sp-reading-sidenotes--schedule t)
    (remove-hook 'after-change-functions #'sp-reading-sidenotes--schedule t)
    (remove-hook 'text-scale-mode-hook #'sp-reading-sidenotes--schedule t)
    (when (timerp sp-reading-sidenotes--timer)
      (cancel-timer sp-reading-sidenotes--timer)
      (setq sp-reading-sidenotes--timer nil))
    (sp-reading-sidenotes--clear)
    (when (local-variable-p 'sp-reading-right-margin)
      (kill-local-variable 'sp-reading-right-margin)
      (when (bound-and-true-p sp-reading-mode)
        (setq-local right-margin-width sp-reading-right-margin)
        (when (fboundp 'sp-reading--refresh) (sp-reading--refresh))))))

(defun sp-reading-sidenotes--follow ()
  "Turn the sidenotes on and off together with `sp-reading-mode'."
  (cond ((and (bound-and-true-p sp-reading-mode)
              sp-reading-sidenotes
              (derived-mode-p 'org-mode))
         (sp-reading-sidenotes-mode 1))
        ((and (not (bound-and-true-p sp-reading-mode))
              sp-reading-sidenotes-mode)
         (sp-reading-sidenotes-mode -1))))

(add-hook 'sp-reading-mode-hook #'sp-reading-sidenotes--follow)

(global-set-key (kbd "C-c w s") #'sp-reading-sidenotes-mode)

;;;###autoload
(defun sp-reading-sidenotes-export ()
  "Export this Org buffer to Tufte HTML with `ox-tufte' and open the result."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer"))
  (unless (require 'ox-tufte nil t)
    (user-error "The package ox-tufte is not installed"))
  (let ((org-tufte-include-footnotes-at-bottom nil))
    (org-open-file (org-tufte-export-to-html))))

(provide 'sp-reading-sidenotes)
;;; sp-reading-sidenotes.el ends here
