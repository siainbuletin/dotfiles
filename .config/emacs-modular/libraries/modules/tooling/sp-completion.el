;;; sp-completion.el --- Minibuffer completion with Vertico, Marginalia and Orderless -*- lexical-binding: t; -*-

;;; Commentary:

;; These are the completion frameworks that I plan on using.

;;; Code:

;;;; Vertico (base)
(use-package vertico
  :ensure t
  :demand t

  :custom
  (vertico-count 13) ; Number of candidates to display
  (vertico-resize t)
  (vertico-cycle t) ; Once passing the last candidate in the list, it will loop back to the first
  (vertico-sort-function
           'vertico-sort-history-alpha)

  :config
  (vertico-mode))

;;;; Vertico extensions
;; Use vertico in buffer
(use-package vertico-buffer
  :ensure nil
  :after vertico
  :custom
  (vertico-buffer-hide-prompt t)
  :config
  ;; Set no headerline in vertico-buffer
  (cl-defmethod vertico--setup :after (&context (vertico-buffer-mode (eql t)))
    (add-hook 'pre-redisplay-functions 'vertico-buffer--redisplay nil 'local)
    (let* ((action vertico-buffer-display-action) tmp win old-buf
           (_ (unwind-protect
                  (progn
                    (with-current-buffer (setq tmp (generate-new-buffer "*vertico-buffer*"))
                      ;; Set a fake major mode such that `display-buffer-reuse-mode-window'
                      ;; does not take over!
                      (setq major-mode 'vertico-buffer-mode))
                    ;; Temporarily select the original window such
                    ;; that `display-buffer-same-window' works.
                    (setq old-buf (mapcar (lambda (win) (cons win (window-buffer win))) (window-list))
                          win (with-minibuffer-selected-window (display-buffer tmp action))
                          old-buf (alist-get win old-buf))
                    (set-window-buffer win (current-buffer)))
                (kill-buffer tmp)))
           (sym (make-symbol "vertico-buffer--destroy"))
           (depth (recursion-depth))
           (now (window-parameter win 'no-other-window))
           (ndow (window-parameter win 'no-delete-other-windows)))
      (fset sym (lambda ()
                  (when (= depth (recursion-depth))
                    (with-selected-window (active-minibuffer-window)
                      (if (not (and (window-live-p win) (buffer-live-p old-buf)))
                          (delete-window win)
                        (set-window-parameter win 'no-other-window now)
                        (set-window-parameter win 'no-delete-other-windows ndow)
                        (set-window-buffer win old-buf))
                      (when vertico-buffer-hide-prompt
                        (set-window-vscroll nil 0))
                      (remove-hook 'minibuffer-exit-hook sym)))))
      ;; NOTE: We cannot use a buffer-local minibuffer-exit-hook here.
      ;; The hook will not be called when abnormally exiting the minibuffer
      ;; from another buffer via `keyboard-escape-quit'.
      (add-hook 'minibuffer-exit-hook sym)
      (set-window-parameter win 'no-other-window t)
      (set-window-parameter win 'no-delete-other-windows t)
      (overlay-put vertico--candidates-ov 'window win)
      (when (and vertico-buffer-hide-prompt vertico--count-ov)
        (overlay-put vertico--count-ov 'window win))
      (setq-local show-trailing-whitespace nil
                  truncate-lines t
                  face-remapping-alist
                  (copy-tree `((mode-line-inactive mode-line)
                               ,@face-remapping-alist))
                  header-line-format nil
                  mode-line-format
                  (list (format " %s "
                                (propertize
                                 (format (if (< depth 2) "*%s*" "*%s [%s]*")
                                         (replace-regexp-in-string
                                          ":? *\\'" ""
                                          (minibuffer-prompt))
                                         depth)
                                 'face 'mode-line-buffer-id)))
                  cursor-in-non-selected-windows 'box
                  vertico-count (- (/ (window-pixel-height win)
                                      (default-line-height)) 1))))
  :config
  ;; put minibuffer at top -- this is the more natural place to be looking!
  (setq vertico-buffer-display-action
        '(display-buffer-in-side-window
          (window-height . 12)
          (side . right)))
  ;; (vertico-buffer-mode 1) ;; I don't want this enabled by default, because it just kind of looks wrong
  )

;;;; Marginalia
(use-package marginalia
  :ensure (:wait t)
  :init
  (marginalia-mode)
  (setf
    (alist-get 'elpaca-info marginalia-command-categories) 'elpaca))

;;;; Orderless
(use-package orderless
  :ensure (:wait t)
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides
   '((file (styles partial-completion)))))

;;;; Company
(use-package company
  :ensure (:wait t))

(provide 'sp-completion)
;; sp-completion.el ends here.
