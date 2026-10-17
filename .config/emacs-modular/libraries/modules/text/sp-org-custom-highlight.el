(defface my-org-inline-comment
  '((t :background "#fff3a3" :foreground "black"))
  "Face for @@comment:...@@ inline comments.")

(add-hook 'org-mode-hook
          (lambda ()
            (font-lock-add-keywords
             nil
             '(("\\(@@comment:\\)\\([^@\n]*\\)\\(@@\\)"
                (1 'shadow prepend)
                (2 'my-org-inline-comment prepend)
                (3 'shadow prepend)))
             'append)))
