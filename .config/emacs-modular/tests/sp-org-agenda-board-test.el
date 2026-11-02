;;; sp-org-agenda-board-test.el --- Tests for the org-other-agenda colours  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'color)

;; Evaluate only the board section of the module: the rest of it needs
;; Elpaca and the other Org modules.
(defvar sp-org-agenda-board-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(with-temp-buffer
  (insert-file-contents
   (expand-file-name "libraries/modules/text/sp-org-agenda.el"
                     sp-org-agenda-board-test--root))
  (search-forward ";;;; Org other agenda: colours from the theme")
  (beginning-of-line)
  (let ((end (save-excursion (search-forward "(with-eval-after-load 'org-other-agenda"))))
    (while (< (point) end)
      (let ((form (read (current-buffer))))
        (unless (eq (car-safe form) 'with-eval-after-load)
          (eval form t))
        (skip-chars-forward " \t\n;")
        (when (looking-at ";") (forward-line 1))))))

(defun sp-org-agenda-board-test--define-faces ()
  "Define the faces of the board, as the package does, with hex colours."
  (dolist (entry sp-org-agenda-board-roles)
    (eval `(defface ,(car entry) '((t :foreground "#123456")) "Test.") t)))

(ert-deftest sp-org-agenda-board-test-every-role-has-an-accent ()
  (dolist (entry sp-org-agenda-board-roles)
    (should (assq (nth 1 entry) sp-org-agenda-board-accents))))

(ert-deftest sp-org-agenda-board-test-fixed-colours-are-gone ()
  (sp-org-agenda-board-test--define-faces)
  (sp-org-agenda-board-apply)
  (dolist (entry sp-org-agenda-board-roles)
    (should-not (equal (face-attribute (car entry) :foreground nil) "#123456"))))

(ert-deftest sp-org-agenda-board-test-follows-theme-faces ()
  (sp-org-agenda-board-test--define-faces)
  (defface sp-urgent nil "Test.")
  (face-spec-set 'sp-urgent '((t :foreground "#ff0000")))
  (face-spec-set 'default '((t :foreground "#202020" :background "#ffffff")))
  (sp-org-agenda-board-apply)
  (should (equal (face-attribute 'org-other-agenda-a :foreground nil t) "#ff0000"))
  (should (eq (face-attribute 'org-other-agenda-a :weight nil t) 'bold))
  ;; The semantic face is empty (a non-sp theme): the standard face is used.
  (face-spec-set 'sp-urgent '((t)))
  (face-spec-set 'error '((t :foreground "#aa0000")))
  (should (equal (face-attribute 'org-other-agenda-a :foreground nil t) "#aa0000")))

(ert-deftest sp-org-agenda-board-test-reorder-by-role ()
  (sp-org-agenda-board-test--define-faces)
  (face-spec-set 'warning '((t :foreground "#bb8800")))
  (face-spec-set 'error '((t :foreground "#aa0000")))
  (let ((sp-org-agenda-board-roles
         '((org-other-agenda-a crucial bold))))
    (sp-org-agenda-board-apply))
  (should (equal (face-attribute 'org-other-agenda-a :foreground nil t)
                 (sp-org-agenda-board--colour 'crucial))))

(ert-deftest sp-org-agenda-board-test-blocks-and-tab ()
  (sp-org-agenda-board-test--define-faces)
  (face-spec-set 'default '((t :foreground "#202020" :background "#ffffff")))
  (face-spec-set 'link '((t :foreground "#0000ff")))
  (face-spec-set 'sp-focus '((t)))
  (sp-org-agenda-board-apply)
  (should (equal (face-attribute 'org-other-agenda-active-tab :background nil t) "#0000ff"))
  (should (equal (face-attribute 'org-other-agenda-active-tab :foreground nil t) "#ffffff"))
  (let ((bg (face-attribute 'org-other-agenda-blk-a :background nil t)))
    (should (string-match-p "\\`#[0-9a-f]\\{6\\}\\'" bg))
    (should-not (equal bg "#ffffff")))
  (should (equal (face-attribute 'org-other-agenda-blk-a :foreground nil t) "#202020")))

(ert-deftest sp-org-agenda-board-test-mix ()
  (should (equal (sp-org-agenda-board--mix "#000000" "#ffffff" 0) "#000000"))
  (should (equal (sp-org-agenda-board--mix "#000000" "#ffffff" 1) "#ffffff")))

(provide 'sp-org-agenda-board-test)
;;; sp-org-agenda-board-test.el ends here
