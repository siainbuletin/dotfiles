;;; sp-org-custom-highlight.el --- Org emphasis helpers -*- lexical-binding: t; -*-

;;; Commentary:

;; Small function which creates a bespoke org-mode comment which is supposed
;; to mimic the behavior of comments in Obsidian, making them stand out in the
;; text as tasks I need to take care of.

;;; Code:

(defface my-org-inline-comment
  '((t :inherit lazy-highlight))
  "Face for @@comment:...@@ inline comments.
Inherits `lazy-highlight', which `sp-themes' tints from the theme in use.")

(add-hook 'org-mode-hook
          (lambda ()
            (font-lock-add-keywords
             nil
             '(("\\(@@comment:\\)\\(\\(?:[^@\n]\\|@[^@\n]\\)*\\)\\(@@\\)"
                (1 'shadow prepend)
                (2 'my-org-inline-comment prepend)
                (3 'shadow prepend)))
             'append)))

(defun sp-org--comment-lines (text)
  "Return TEXT with each non-blank line wrapped as an inline comment.
Leading and trailing whitespace of a line stays outside the markers."
  (mapconcat
   (lambda (line)
     (if (string-blank-p line)
         line
       (string-match "\\`\\([ \t]*\\)\\(.*?\\)\\([ \t]*\\)\\'" line)
       (concat (match-string 1 line)
               "@@comment:" (match-string 2 line) "@@"
               (match-string 3 line))))
   (split-string text "\n")
   "\n"))

(defun sp-org-insert-inline-comment ()
  "Wrap the active region in `@@comment:...@@', or insert an empty one.
With a region, each non-blank line becomes its own comment, so the
highlighting (one line only) matches the export.  Without a region,
insert `@@comment:@@' and put point inside it."
  (interactive)
  (let ((beg (and (use-region-p) (region-beginning)))
        (end (and (use-region-p) (region-end))))
    (if (not (and beg (string-match-p "[^ \t\n]" (buffer-substring-no-properties beg end))))
        (progn
          (deactivate-mark)
          (insert "@@comment:@@")
          (backward-char 2))
      (let ((text (buffer-substring beg end)))
        (when (string-search "@@" text)
          (user-error "The region contains @@, which would end the comment early"))
        (atomic-change-group
          (goto-char beg)
          (delete-region beg end)
          (insert (sp-org--comment-lines text)))
        (deactivate-mark)))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c h") #'sp-org-insert-inline-comment))

(defun sp-org--comment-inner-bounds (&optional context)
  "Bounds (BEG . END) of the text of the `@@comment:@@' snippet CONTEXT, or nil.
CONTEXT is the snippet at point, by default as `org-element-context' gives it.
Point must be inside the text."
  (let ((ctx (or context (org-element-context))))
    (when (and (eq (org-element-type ctx) 'export-snippet)
               (equal (org-element-property :back-end ctx) "comment"))
      (let ((beg (+ (org-element-property :begin ctx) (length "@@comment:")))
            (end (- (org-element-property :end ctx)
                    (org-element-property :post-blank ctx)
                    (length "@@"))))
        (and (<= beg (point) end) (cons beg end))))))

(defun sp-org--shift-positions (tree delta)
  "Add DELTA to the position properties of the links and citations of TREE.
The nodes are changed in place."
  (org-element-map tree '(link citation citation-reference)
    (lambda (node)
      (dolist (prop '(:begin :end :contents-begin :contents-end))
        (when-let* ((value (org-element-property prop node)))
          (org-element-put-property node prop (+ value delta)))))))

(defun sp-org--comment-object-at-point (context)
  "Link, citation or citation reference at point inside snippet CONTEXT, or nil.
The result has real buffer positions, like what `org-element-context' returns."
  (when-let* ((bounds (sp-org--comment-inner-bounds context)))
    (let ((tree (org-element-parse-secondary-string
                 (buffer-substring-no-properties (car bounds) (cdr bounds))
                 '(link citation)))
          (delta (1- (car bounds)))
          best)
      (sp-org--shift-positions tree delta)
      (org-element-map tree '(link citation citation-reference)
        (lambda (node)
          (let ((beg (org-element-property :begin node))
                (end (org-element-property :end node)))
            (when (and (<= beg (point)) (< (point) end)
                       (or (null best)
                           (< (- end beg)
                              (- (org-element-property :end best)
                                 (org-element-property :begin best)))))
              (setq best node)))))
      best)))

(define-advice org-element-context (:around (orig &optional element) sp-org-comment-objects)
  "Look inside `@@comment:@@' snippets for links and citations."
  (let ((context (funcall orig element)))
    (or (and (null element) (sp-org--comment-object-at-point context))
        context)))

(define-advice org-cite--allowed-p (:around (orig context) sp-org-comment-text)
  "Allow a citation in the running text of a `@@comment:@@'."
  (or (and (sp-org--comment-inner-bounds context) t)
      (funcall orig context)))

(provide 'sp-org-custom-highlight)
