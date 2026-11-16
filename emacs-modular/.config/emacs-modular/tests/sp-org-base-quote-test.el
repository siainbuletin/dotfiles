;;; sp-org-base-quote-test.el --- Tests for sp-org-insert-quote-from-kill -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-org-base-quote-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org)
(require 'subr-x)

;; Load only the quote block command of sp-org-base, which needs no packages.
(let ((file (expand-file-name "../libraries/modules/text/sp-org-base.el"
                              (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (search-forward "(defun sp-org-insert-quote-from-kill")
    (beginning-of-line)
    (eval (read (current-buffer)) t)
    (goto-char (point-min))
    (search-forward "(defun sp-org-quote-join-lines")
    (beginning-of-line)
    (eval (read (current-buffer)) t)))

(defmacro sp-org-quote-test--with (kill &rest body)
  "Run BODY in an Org buffer with a kill ring holding KILL (a list, newest first)."
  (declare (indent 1))
  `(let ((kill-ring ,kill)
         (kill-ring-yank-pointer nil)
         (interprogram-paste-function nil)
         (interprogram-cut-function nil))
     (setq kill-ring-yank-pointer kill-ring)
     (with-temp-buffer
       (org-mode)
       ,@body)))

(ert-deftest sp-org-quote-uses-latest-kill ()
  (sp-org-quote-test--with '("newest" "older")
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string) "#+begin_quote\nnewest\n#+end_quote\n"))
    (should (eobp))))

(ert-deftest sp-org-quote-does-not-rotate-the-ring ()
  (sp-org-quote-test--with '("newest" "older")
    (sp-org-insert-quote-from-kill)
    (should (equal kill-ring '("newest" "older")))
    (should (equal (current-kill 0 t) "newest"))))

(ert-deftest sp-org-quote-empty-ring-gives-empty-block ()
  (sp-org-quote-test--with nil
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string) "#+begin_quote\n\n#+end_quote\n"))
    (should (equal (buffer-substring (line-beginning-position) (line-end-position)) ""))
    (should (equal (line-number-at-pos) 2))))

(ert-deftest sp-org-quote-prefix-leaves-kill-out ()
  (sp-org-quote-test--with '("newest")
    (sp-org-insert-quote-from-kill '(4))
    (should (equal (buffer-string) "#+begin_quote\n\n#+end_quote\n"))
    (should (equal kill-ring '("newest")))))

(ert-deftest sp-org-quote-drops-trailing-newlines ()
  (sp-org-quote-test--with '("one\n\ntwo\n\n\n")
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string) "#+begin_quote\none\n\ntwo\n#+end_quote\n"))))

(ert-deftest sp-org-quote-starts-on-its-own-line ()
  (sp-org-quote-test--with '("q")
    (insert "text before")
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string) "text before\n#+begin_quote\nq\n#+end_quote\n"))))

(ert-deftest sp-org-quote-keeps-text-after-point ()
  (sp-org-quote-test--with '("q")
    (insert "ab")
    (backward-char 1)
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string) "a\n#+begin_quote\nq\n#+end_quote\nb"))))

(ert-deftest sp-org-quote-escapes-headings-and-keywords ()
  (sp-org-quote-test--with '("* not a heading\n\n#+title: no")
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string)
                   "#+begin_quote\n,* not a heading\n\n,#+title: no\n#+end_quote\n"))))

(ert-deftest sp-org-quote-drops-text-properties ()
  (sp-org-quote-test--with (list (propertize "bold" 'face 'bold))
    (sp-org-insert-quote-from-kill)
    (should-not (text-properties-at 14))))

(ert-deftest sp-org-quote-wraps-the-region-and-keeps-the-ring ()
  (sp-org-quote-test--with '("killed")
    (insert "intro\nregion text\nafter")
    (goto-char (point-min))
    (forward-line 1)
    (set-mark (point))
    (end-of-line)
    (transient-mark-mode 1)
    (activate-mark)
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string)
                   "intro\n#+begin_quote\nregion text\n#+end_quote\n\nafter"))
    (should (equal kill-ring '("killed")))))

;; The helper sits before the command in the file, so load it first.
(ert-deftest sp-org-quote-joins-hard-wrapped-lines ()
  (sp-org-quote-test--with '("first line\n  second line \nthird")
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string)
                   "#+begin_quote\nfirst line second line third\n#+end_quote\n"))))

(ert-deftest sp-org-quote-keeps-paragraph-breaks ()
  (sp-org-quote-test--with '("a\nb\n\n\nc\nd\n")
    (sp-org-insert-quote-from-kill)
    (should (equal (buffer-string)
                   "#+begin_quote\na b\n\nc d\n#+end_quote\n"))))

(provide 'sp-org-base-quote-test)
;;; sp-org-base-quote-test.el ends here
