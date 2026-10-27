;;; sp-themes-test.el --- Tests for sp-themes  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-themes-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar sp-themes-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))
  "The folder of init.el.")

(defvar sp-library-dir (expand-file-name "libraries/" sp-themes-test--root))

(defmacro use-package (&rest _) nil)

(add-to-list 'load-path (expand-file-name "libraries/modules/ui/" sp-themes-test--root))
(load (expand-file-name "libraries/modules/ui/sp-themes.el" sp-themes-test--root) nil t)

(defmacro sp-themes-test--clean (&rest body)
  "Run BODY with no theme enabled, and none left enabled after it."
  `(unwind-protect
       (progn (mapc #'disable-theme custom-enabled-themes) ,@body)
     (mapc #'disable-theme custom-enabled-themes)))

(ert-deftest sp-themes-test-registry ()
  (let ((registry (sp-theme-registry t)))
    (should (> (length registry) 50))
    (dolist (entry registry)
      (should (plist-get entry :name))
      (should (plist-get entry :background))
      (should (file-exists-p (plist-get entry :file))))
    (dolist (family sp-theme-families)
      (dolist (theme (cdr family))
        (should (sp-theme-info theme))
        (should (eq (plist-get (sp-theme-info theme) :family) (car family)))))))

(ert-deftest sp-themes-test-registry-backgrounds ()
  (dolist (pair '((ef-dream . dark) (ef-day . light) (doric-fire . dark)
                  (lambda-light-faded . light) (lambda-dark . dark)
                  (sp-dark . dark) (sp-light . light) (sp-wandavision . dark)))
    (should (eq (plist-get (sp-theme-info (car pair)) :background) (cdr pair)))))

(ert-deftest sp-themes-test-registry-folders ()
  (should (equal (plist-get (sp-theme-info 'ef-dream) :folder) "active"))
  (should (equal (plist-get (sp-theme-info 'sp-dark) :folder) "sp"))
  (should (equal (plist-get (sp-theme-info 'ef-bio) :folder) "library"))
  (should (equal (plist-get (sp-theme-info 'ef-bio) :package) "ef-themes"))
  (should-not (sp-theme-info 'ef-deuteranopia-dark))
  (should-not (sp-theme-info 'modus-vivendi-tritanopia)))

(ert-deftest sp-themes-test-candidates ()
  (let ((cands (sp-theme--candidates)))
    (should (equal (car cands) '("lambda-light" . "hard-light")))
    (should (equal (alist-get "ef-dream" cands nil nil #'equal) "hard-dark"))
    (should (equal (alist-get "ef-bio" cands nil nil #'equal) "library: ef-themes"))
    (should (= (length cands) (length (delete-dups (mapcar #'car cands)))))))

(ert-deftest sp-themes-test-load-leaves-one ()
  (sp-themes-test--clean
   (sp-load-theme 'ef-day)
   (sp-load-theme 'lambda-light)
   (should (equal custom-enabled-themes '(lambda-light)))
   (let ((sp-theme-disable-others nil))
     (sp-load-theme 'ef-day)
     (should (equal custom-enabled-themes '(ef-day lambda-light))))))

(ert-deftest sp-themes-test-no-confirmation ()
  (sp-themes-test--clean
   (let ((custom-safe-themes nil))
     (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) (error "Asked")))
               ((symbol-function 'y-or-n-p) (lambda (&rest _) (error "Asked"))))
       (load-theme 'ef-day)
       (should (equal custom-enabled-themes '(ef-day)))))))

(ert-deftest sp-themes-test-dark-p ()
  (sp-themes-test--clean
   (sp-load-theme 'doric-fire)
   (should (sp-theme-dark-p))
   (sp-load-theme 'ef-day)
   (should-not (sp-theme-dark-p))))

(ert-deftest sp-themes-test-time-appearance ()
  (let ((sp-theme-auto-source 'time))
    (let ((sp-theme-day-hours '(0 . 24)))
      (should (eq (sp-theme-appearance) 'light)))
    (let ((sp-theme-day-hours '(0 . 0)))
      (should (eq (sp-theme-appearance) 'dark)))))

(ert-deftest sp-themes-test-platform-providers ()
  (let ((sp-theme-auto-source 'system)
        (sp-theme-day-hours '(0 . 24)))
    (cl-letf (((symbol-function 'sp-theme-platform) (lambda () 'linux))
              ((symbol-function 'sp-test-provider) (lambda () 'dark)))
      (let ((sp-theme-system-providers '((linux . sp-test-provider))))
        (should (eq (sp-theme-appearance) 'dark)))
      ;; No provider for this platform, an error, or nonsense: the time.
      (let ((sp-theme-system-providers '((macos . sp-test-provider))))
        (should (eq (sp-theme-appearance) 'light)))
      (let ((sp-theme-system-providers '((linux . sp-test-provider))))
        (cl-letf (((symbol-function 'sp-test-provider) (lambda () (error "boom"))))
          (should (eq (sp-theme-appearance) 'light)))
        (cl-letf (((symbol-function 'sp-test-provider) (lambda () 'purple)))
          (should (eq (sp-theme-appearance) 'light)))))))

(ert-deftest sp-themes-test-ambient-source ()
  (sp-themes-test--clean
   (let ((sp-theme-auto-source 'ambient)
         (sp-theme-appearance-themes '((light . ef-day) (dark . ef-dream)))
         (sp-theme-day-hours '(0 . 24))
         (family 'hard-dark))
     (cl-letf (((symbol-function 'sp-theme-platform) (lambda () 'macos))
               ((symbol-function 'sp-test-ambient) (lambda () family)))
       (let ((sp-theme-ambient-providers '((macos . sp-test-ambient))))
         (sp-theme-sync)
         (should (equal custom-enabled-themes '(ef-dream)))
         (setq family 'faded-dark)
         (sp-theme-sync)
         (should (equal custom-enabled-themes '(lambda-dark-faded)))
         (setq family 'hard-light)
         (sp-theme-sync)
         (should (equal custom-enabled-themes '(lambda-light)))
         ;; An unknown family counts as no reading: the time of day.
         (setq family 'purple)
         (sp-theme-sync)
         (should (equal custom-enabled-themes '(ef-day))))))))

(ert-deftest sp-themes-test-watcher ()
  (sp-themes-test--clean
   (let ((sp-theme-appearance-themes '((light . ef-day) (dark . ef-dream)))
         (sp-theme-auto-source 'system)
         (sp-theme-day-hours '(0 . 24))
         (stopped nil)
         (callback nil))
     (cl-letf (((symbol-function 'sp-theme-platform) (lambda () 'linux))
               ((symbol-function 'sp-test-watch)
                (lambda (cb) (setq callback cb) (lambda () (setq stopped t)))))
       (let ((sp-theme-system-providers nil)
             (sp-theme-system-watchers '((linux . sp-test-watch))))
         (sp-theme-auto-mode 1)
         (unwind-protect
             (progn
               ;; A watcher replaces the timer.
               (should-not sp-theme--auto-timer)
               (funcall callback 'dark)
               (should (equal custom-enabled-themes '(ef-dream))))
           (sp-theme-auto-mode -1))
         (should stopped))))))

(ert-deftest sp-themes-test-load-appearance ()
  (sp-themes-test--clean
   (let ((sp-theme-appearance-themes '((light . ef-day) (dark . ef-dream)))
         (loaded nil))
     (cl-letf (((symbol-function 'sp-load-theme) (lambda (theme) (push theme loaded))))
       (sp-theme-load-appearance 'dark)
       (should (equal loaded '(ef-dream))))
     (load-theme 'ef-dream t)
     (setq loaded nil)
     (cl-letf (((symbol-function 'sp-load-theme) (lambda (theme) (push theme loaded))))
       (sp-theme-load-appearance 'dark)
       (should-not loaded)
       (sp-theme-load-appearance 'light)
       (should (equal loaded '(ef-day)))))))

(ert-deftest sp-themes-test-auto-mode ()
  (sp-themes-test--clean
   (let ((sp-theme-appearance-themes '((light . ef-day) (dark . ef-dream)))
         (sp-theme-auto-source 'time)
         (sp-theme-day-hours '(0 . 24)))
     (sp-theme-auto-mode 1)
     (unwind-protect
         (progn
           (should (equal custom-enabled-themes '(ef-day)))
           (should (timerp sp-theme--auto-timer))
           (should (memq #'sp-theme-sync server-after-make-frame-hook))
           (setq sp-theme-day-hours '(0 . 0))
           (sp-theme-sync)
           (should (equal custom-enabled-themes '(ef-dream))))
       (sp-theme-auto-mode -1))
     (should-not sp-theme--auto-timer)
     (should-not (memq #'sp-theme-sync server-after-make-frame-hook)))))

(provide 'sp-themes-test)
;;; sp-themes-test.el ends here
