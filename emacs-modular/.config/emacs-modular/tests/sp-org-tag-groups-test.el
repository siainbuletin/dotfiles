;;; sp-org-tag-groups-test.el --- Tests for the tag colours  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-org-tag-groups-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(defvar sp-org-tag-groups-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(provide 'doric-themes)
(defgroup spcustom nil "Test group.")
(defvar sp-after-load-theme-hook nil)
(load (expand-file-name "libraries/modules/ui/sp-theme-engine.el" sp-org-tag-groups-test--root) nil t)
(load (expand-file-name "libraries/modules/custom/sp-org-tag-groups.el" sp-org-tag-groups-test--root) nil t)

(defmacro sp-org-tag-groups-test--with-theme (mode bg fg &rest body)
  "Run BODY with background MODE (`light' or `dark') and the default colours BG, FG."
  (declare (indent 3))
  `(let ((old-mode (frame-parameter nil 'background-mode))
         (old-bg (face-attribute 'default :background))
         (old-fg (face-attribute 'default :foreground)))
     (unwind-protect
         (progn (set-frame-parameter nil 'background-mode ,mode)
                (set-face-attribute 'default nil :background ,bg :foreground ,fg)
                (set-face-attribute 'error nil :foreground (if (eq ,mode 'dark) "#ff6f6f" "#ba2d2f"))
                ,@body)
       (set-frame-parameter nil 'background-mode old-mode)
       (set-face-attribute 'default nil :background old-bg :foreground old-fg))))

(ert-deftest sp-org-tag-groups-palette-legible-in-both-modes ()
  (dolist (spec '((light "#fff5ea" "#584141") (dark "#232025" "#efd5c5")))
    (apply (lambda (mode bg fg)
             (sp-org-tag-groups-test--with-theme mode bg fg
               (dolist (slot (mapcar #'car sp-org-tag-groups-palette))
                 (let ((entry (sp-org-tag-groups-palette-entry slot)))
                   (should (>= (sp-org-tag-groups--contrast (car entry) (cdr entry)) 4.5))))))
           spec)))

(ert-deftest sp-org-tag-groups-palette-follows-theme ()
  (let (light dark)
    (sp-org-tag-groups-test--with-theme 'light "#fff5ea" "#584141"
      (setq light (sp-org-tag-groups-palette-entry 'red)))
    (sp-org-tag-groups-test--with-theme 'dark "#232025" "#efd5c5"
      (setq dark (sp-org-tag-groups-palette-entry 'red)))
    (should-not (equal light dark))
    (should (< (sp-org-tag-groups--luminance (car light))
               (sp-org-tag-groups--luminance "#ffffff")))
    (should (< (sp-org-tag-groups--luminance (car dark)) 0.2))))

(ert-deftest sp-org-tag-groups-palette-unknown-slot-is-neutral ()
  (sp-org-tag-groups-test--with-theme 'light "#ffffff" "#000000"
    (should (equal (sp-org-tag-groups-palette-entry 'nonexistent)
                   (sp-org-tag-groups-palette-entry 'default)))))

(ert-deftest sp-org-tag-groups-theme-load-drops-memo ()
  (let ((before sp-org-tag-groups--theme-epoch))
    (run-hooks 'sp-after-load-theme-hook)
    (should (> sp-org-tag-groups--theme-epoch before))))

(ert-deftest sp-org-tag-groups-group-without-colour-is-neutral ()
  (let ((sp-org-tag-groups-alist '(("unsorted" "loose")))
        (sp-org-tag-groups-colors nil))
    (sp-org-tag-groups-test--with-theme 'light "#ffffff" "#000000"
      (should (equal (plist-get (sp-org-tag-groups--chip-face-1 "loose") :background)
                     (car (sp-org-tag-groups-palette-entry 'default)))))))

(defmacro sp-org-tag-groups-test--with-dirs (&rest body)
  "Run BODY with notes, a writing folder with two projects, and a config folder."
  (declare (indent 0))
  `(let ((sp-notes-dir "/tmp/t/notes/")
         (sp-writing-projects "/tmp/t/writing/")
         (user-emacs-directory "/tmp/t/config/")
         (projectile-known-projects '("/tmp/t/writing/book/" "/tmp/t/writing/paper"
                                      "/tmp/t/elsewhere/proj/"))
         (sp-note-origin--cache nil))
     ,@body))

(ert-deftest sp-org-tag-groups-origin-groups ()
  (sp-org-tag-groups-test--with-dirs
    (should (equal (sp-note-origin "/tmp/t/notes/a.org") '(0 . "Notes")))
    (should (equal (sp-note-origin "/tmp/t/writing/book/ch1/a.org") '(1 . "Writing: book")))
    (should (equal (sp-note-origin "/tmp/t/writing/paper/a.org") '(1 . "Writing: paper")))
    (should (equal (sp-note-origin "/tmp/t/writing/loose/a.org") '(2 . "Writing")))
    (should (equal (sp-note-origin "/tmp/t/config/docs/a.org") '(3 . "Config")))
    (should (equal (sp-note-origin "/tmp/t/elsewhere/proj/a.org") '(4 . "Other")))
    (should (equal (sp-note-origin nil) '(4 . "Other")))))

(ert-deftest sp-org-tag-groups-origin-without-projectile ()
  (sp-org-tag-groups-test--with-dirs
    (let ((projectile-known-projects nil))
      (should (equal (sp-note-origin "/tmp/t/writing/book/a.org") '(2 . "Writing"))))))

(ert-deftest sp-org-tag-groups-origin-sort-orders-groups ()
  (sp-org-tag-groups-test--with-dirs
    (cl-letf (((symbol-function 'vulpea-select-candidate-path)
               (lambda (c) (get-text-property 0 'path c))))
      (let* ((mk (lambda (title path) (propertize title 'path path)))
             (cands (list (funcall mk "zzz" "/tmp/t/config/a.org")
                          (funcall mk "bbb" "/tmp/t/writing/paper/a.org")
                          (funcall mk "ccc" "/tmp/t/writing/x/a.org")
                          (funcall mk "aaaa" "/tmp/t/notes/a.org")
                          (funcall mk "a" "/tmp/t/notes/b.org")
                          (funcall mk "bk" "/tmp/t/writing/book/a.org"))))
        (should (equal (mapcar #'substring-no-properties (sp-note-origin-sort cands))
                       '("a" "aaaa" "bk" "bbb" "ccc" "zzz")))
        (should (equal (sp-note-origin-group (nth 1 cands) nil) "Writing: paper"))
        (should (eq (sp-note-origin-group (nth 1 cands) t) (nth 1 cands)))))))

(provide 'sp-org-tag-groups-test)
;;; sp-org-tag-groups-test.el ends here
