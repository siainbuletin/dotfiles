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
(defmacro use-package (&rest _) nil)
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

(provide 'sp-org-tag-groups-test)
;;; sp-org-tag-groups-test.el ends here

;;;; SVG tags

(ert-deftest sp-org-svg-tags-heading-tags-only ()
  (with-temp-buffer
    (org-mode)
    (insert "* Title: x :@writing:deep:\nbody a:b: here\n")
    (goto-char (point-min))
    (should (re-search-forward ":@writing" nil t))
    (should (sp-org-svg-tags--in-heading-tags-p (match-beginning 0)))
    (goto-char (point-min))
    (re-search-forward "Title:")
    (should-not (sp-org-svg-tags--in-heading-tags-p (1- (match-end 0))))
    (re-search-forward "a:b:")
    (should-not (sp-org-svg-tags--in-heading-tags-p (match-beginning 0)))))

(ert-deftest sp-org-svg-tags-keywords-match-consecutive-tags ()
  (let ((entries (sp-org-svg-tags--entries)) (s ":a:b_1:"))
    (let ((pos 0) names)
      (while (string-match (car (nth 1 entries)) s pos)
        (push (match-string 1 s) names)
        (setq pos (match-end 0)))
      (should (equal (nreverse names) '("a" "b_1"))))
    (let ((pos 0) n)
      (while (string-match (car (nth 0 entries)) s pos)
        (push (match-string 0 s) n)
        (setq pos (match-end 0)))
      (should (equal (nreverse n) '(":a" ":b_1"))))
    (should (string-match (car (nth 2 entries)) "x :a: "))))

(ert-deftest sp-org-svg-tags-nil-without-graphics ()
  (with-temp-buffer
    (org-mode)
    (insert "* T :project:\n")
    (goto-char (point-min))
    (re-search-forward "\\(project\\):")
    (cl-letf (((symbol-function 'sp-org-svg-tags-available-p) (lambda () nil)))
      (should-not (sp-org-svg-tags--chip "project"))
      (should-not (sp-org-svg-tags--leading-colon ":")))))

(ert-deftest sp-org-svg-tags-chip-and-emoji ()
  (let ((sp-org-tag-groups-alist '(("structure" "project")))
        (sp-org-tag-groups-rules '(("project" :emoji "R")))
        made)
    (with-temp-buffer
      (org-mode)
      (insert "* T :project:other:\n")
      (cl-letf (((symbol-function 'sp-org-svg-tags-available-p) (lambda () t))
                ((symbol-function 'svg-tag-make)
                 (lambda (tag &rest args) (setq made (cons tag args)) 'image)))
        (goto-char (point-min))
        (re-search-forward ":\\(project\\)")
        (should (eq 'image (sp-org-svg-tags--chip "project")))
        (should (equal "project" (car made)))
        (should (plist-get (plist-get (cdr made) :face) :background))
        (goto-char (point-min))
        (re-search-forward "\\(:\\)project")
        (should (equal "R " (substring-no-properties (sp-org-svg-tags--leading-colon ":"))))
        (goto-char (point-min))
        (re-search-forward "\\(:\\)other")
        (should (equal "" (sp-org-svg-tags--leading-colon ":")))
        (goto-char (point-min))
        (re-search-forward "\\(:\\)$")
        (should (equal "" (sp-org-svg-tags--trailing-colon ":")))))))
