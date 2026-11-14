;;; sp-elpaca-melpa-fix-test.el --- Tests for sp-elpaca-melpa-fix -*- lexical-binding: t; -*-

(require 'ert)
(defgroup spcustom nil "Test group.")
(require 'sp-elpaca-melpa-fix)
(defvar elpaca-cache-directory)
(defvar elpaca-melpa-branch)

(defun sp-elpaca-melpa-fix-test--call (program &rest args)
  "Stand-in for `elpaca-process-call': run PROGRAM with ARGS, return (STATUS OUT ERR)."
  (with-temp-buffer
    (let ((status (apply #'call-process program nil t nil args)))
      (list status (buffer-string) ""))))

(defun sp-elpaca-melpa-fix-test--sh (dir &rest args)
  (let ((default-directory dir))
    (should (zerop (apply #'call-process "git" nil nil nil args)))))

(ert-deftest sp-elpaca-melpa-fix-clone-uses-branch ()
  "The clone names `sp-elpaca-melpa-branch' and never `master'."
  (let* ((calls nil)
         (tmp (make-temp-file "sp-melpa" t))
         (sp-elpaca-melpa-branch "main"))
    (unwind-protect
        (cl-letf (((symbol-function 'elpaca-process-call)
                   (lambda (&rest args) (push args calls) (list 0 "" ""))))
          (sp-elpaca-melpa-fix--clone #'ignore tmp)
          (let ((flat (apply #'append calls)))
            (should (member "main" flat))
            (should-not (member "master" flat))
            (should (member "origin/main" flat))))
      (delete-directory tmp t))))

(ert-deftest sp-elpaca-melpa-fix-inactive-calls-original ()
  (let ((sp-elpaca-melpa-fix nil) called)
    (sp-elpaca-melpa-fix--clone (lambda (_) (setq called t)) "/nonexistent")
    (should called))
  (let ((sp-elpaca-melpa-fix t) (elpaca-melpa-branch "main") called)
    (sp-elpaca-melpa-fix--update (lambda () (setq called t)))
    (should called)))

(ert-deftest sp-elpaca-melpa-fix-update-repairs-master-checkout ()
  "A checkout on `master' whose remote only has `main' is moved to `main'."
  (let* ((root (make-temp-file "sp-melpa" t))
         (remote (expand-file-name "remote.git" root))
         (seed (expand-file-name "seed" root))
         (elpaca-cache-directory (file-name-as-directory (expand-file-name "cache" root)))
         (clone (expand-file-name "melpa" elpaca-cache-directory)))
    (unwind-protect
        (progn
          (make-directory seed t)
          (make-directory clone t)
          (sp-elpaca-melpa-fix-test--sh seed "init" "-q" "-b" "master")
          (sp-elpaca-melpa-fix-test--sh seed "config" "user.email" "t@example.com")
          (sp-elpaca-melpa-fix-test--sh seed "config" "user.name" "t")
          (write-region "one" nil (expand-file-name "recipe" seed))
          (sp-elpaca-melpa-fix-test--sh seed "add" ".")
          (sp-elpaca-melpa-fix-test--sh seed "commit" "-q" "-m" "one")
          (sp-elpaca-melpa-fix-test--sh root "clone" "-q" "--bare" seed remote)
          (sp-elpaca-melpa-fix-test--sh clone "clone" "-q" remote ".")
          ;; MELPA renames master to main
          (sp-elpaca-melpa-fix-test--sh remote "branch" "-m" "master" "main")
          (sp-elpaca-melpa-fix-test--sh seed "commit" "-q" "--allow-empty" "-m" "two")
          (sp-elpaca-melpa-fix-test--sh seed "push" "-q" remote "master:main")
          (cl-letf (((symbol-function 'elpaca-process-call)
                     #'sp-elpaca-melpa-fix-test--call))
            (sp-elpaca-melpa-fix--update #'ignore))
          (let ((default-directory clone))
            (should (equal "main"
                           (string-trim (shell-command-to-string "git rev-parse --abbrev-ref HEAD"))))
            (should (string-match-p "two" (shell-command-to-string "git log --format=%s -1")))))
      (delete-directory root t))))
