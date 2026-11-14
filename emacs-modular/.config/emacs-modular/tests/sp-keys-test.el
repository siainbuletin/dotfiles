;;; sp-keys-test.el --- Tests for the academic and lint groups of sp-keys -*- lexical-binding: t; -*-

(require 'ert)
(require 'bind-key)
(require 'cl-lib)
(require 'subr-x)

(defconst sp-keys-test--file
  (expand-file-name "../libraries/modules/base/sp-keys.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The module under test.")

(defvar sp-prefix)
(defvar lem+leader-map)

(defun sp-keys-test--forms ()
  "The top-level forms of `sp-keys-test--file'."
  (with-temp-buffer
    (insert-file-contents sp-keys-test--file)
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun sp-keys-test--prefix (form)
  "The key string of the :prefix of a `bind-keys' FORM, with `sp-prefix' bound."
  (eval (plist-get (cdr form) :prefix) t))

(defun sp-keys-test--setup ()
  "Evaluate the groups B, k and L, the shim table and the shim function."
  (setq sp-prefix "C-;"
        lem+leader-map (make-sparse-keymap))
  (bind-keys :prefix-map lem+leader-map :prefix sp-prefix)
  (let (maps)
    (dolist (form (sp-keys-test--forms))
      (pcase form
        (`(bind-keys . ,_)
         (when (string-match-p "\\`C-; [BkL]\\(?: \\|\\'\\)" (sp-keys-test--prefix form))
           (eval form t)
           (push (plist-get (cdr form) :prefix-map) maps)))
        (`(defconst sp-keys-moved . ,_) (eval form t))
        (`(defun sp-keys--shim . ,_) (eval form t))))
    (nreverse maps)))

(defun sp-keys-test--command (map key)
  "The command KEY runs in the keymap variable MAP."
  (let ((binding (keymap-lookup (symbol-value map) key)))
    (and (symbolp binding) binding)))

(ert-deftest sp-keys-lint-verbs-are-the-same-everywhere ()
  (let ((maps (sp-keys-test--setup)) (groups 0))
    (dolist (map maps)
      (when (string-prefix-p "lem+lint-" (symbol-name map))
        (let ((list-cmd (sp-keys-test--command map "l"))
              (apply-cmd (sp-keys-test--command map "a")))
          (when apply-cmd
            (cl-incf groups)
            (should list-cmd)
            (should (string-suffix-p "-dryrun" (symbol-name list-cmd)))
            (should (string-suffix-p "-convert" (symbol-name apply-cmd)))
            (should (equal (string-remove-suffix "-dryrun" (symbol-name list-cmd))
                           (string-remove-suffix "-convert" (symbol-name apply-cmd))))))))
    (should (>= groups 8))))

(ert-deftest sp-keys-bibtex-key-fix-has-a-key ()
  (sp-keys-test--setup)
  (should (eq (sp-keys-test--command 'lem+lint-bibtex-fix-keys "k")
              'sp-bibtex-lint-fix-keys))
  (should (eq (key-binding (kbd "C-; L b f k")) 'sp-bibtex-lint-fix-keys)))

(ert-deftest sp-keys-moved-keys-are-consistent ()
  (sp-keys-test--setup)
  (let ((olds (mapcar #'car sp-keys-moved)))
    (should (= (length olds) (length (delete-dups (copy-sequence olds)))))
    (dolist (entry sp-keys-moved)
      (pcase-let ((`(,old ,new ,command) entry))
        (should (key-valid-p old))
        (should-not (string-prefix-p sp-prefix old))
        ;; Only the groups this test loads; a map is mounted by its own module, later.
        (when (and (string-match-p "\\`[BkL] " new)
                   (not (string-suffix-p "-map" (symbol-name command))))
          (should (eq (key-binding (kbd (concat sp-prefix " " new))) command)))))))

(ert-deftest sp-keys-academic-old-keys-all-move ()
  (sp-keys-test--setup)
  (dolist (old '("C-c w b r" "C-c w b l" "C-c w b L" "C-c w b k" "C-c w b a"
                 "C-c k l" "C-c k s" "C-c k d"))
    (should (assoc old sp-keys-moved))))

(ert-deftest sp-keys-shim-of-a-keymap-waits-for-the-next-key ()
  (sp-keys-test--setup)
  (defvar sp-keys-test--map (make-sparse-keymap))
  (let (waited)
    (cl-letf (((symbol-function 'set-transient-map)
               (lambda (map &rest _) (setq waited map)))
              ((symbol-function 'message) #'ignore))
      (funcall (sp-keys--shim "C-c k d" "k d" 'sp-keys-test--map)))
    (should (eq waited sp-keys-test--map))))

(provide 'sp-keys-test)
;;; sp-keys-test.el ends here
