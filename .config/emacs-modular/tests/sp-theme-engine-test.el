;;; sp-theme-engine-test.el --- Tests for sp-theme-engine  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run headless, from the folder of init.el, with
;;   emacs -Q --batch -l tests/sp-theme-engine-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar sp-theme-engine-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))
  "The folder of init.el.")

(let ((root sp-theme-engine-test--root))
  (add-to-list 'load-path (expand-file-name "libraries/themes/lib/" root))
  (add-to-list 'load-path (expand-file-name "libraries/modules/ui/" root))
  (add-to-list 'custom-theme-load-path (expand-file-name "libraries/themes/sp/" root))
  (setq custom-safe-themes t))

(require 'sp-theme-engine)

(ert-deftest sp-theme-engine-test-blend ()
  (should (equal (sp-theme-blend "#000000" "#ffffff" 0) "#000000"))
  (should (equal (sp-theme-blend "#000000" "#ffffff" 1) "#ffffff"))
  (should (equal (sp-theme-blend "#000000" "#fefefe" 0.5) "#7f7f7f")))

(ert-deftest sp-theme-engine-test-palette-keys ()
  (require 'doric-themes)
  (load (expand-file-name "libraries/themes/active/doric-fire-theme.el"
                          sp-theme-engine-test--root)
        nil t)
  (let ((doric-keys (sort (mapcar #'car (symbol-value 'doric-fire-palette))
                          (lambda (a b) (string< a b)))))
    (dolist (flavor '(dark light))
      (let ((palette (sp-theme-palette flavor)))
        (should (equal doric-keys (sort (mapcar #'car palette)
                                        (lambda (a b) (string< a b)))))
        (dolist (entry palette)
          (should (string-match-p "\\`#[[:xdigit:]]\\{6\\}\\'" (cadr entry))))))))

(ert-deftest sp-theme-engine-test-set-color ()
  (let ((sp-theme-flavors (copy-tree sp-theme-flavors)))
    (cl-letf (((symbol-function 'sp-theme-reload) #'ignore))
      (sp-theme-set-color 'bg-main "#101010" 'dark))
    (should (equal (sp-theme-color 'bg-main 'dark) "#101010"))
    (should (equal (cadr (assq 'bg-main (sp-theme-palette 'dark))) "#101010"))
    (should-not (equal (sp-theme-color 'bg-main 'light) "#101010"))))

(ert-deftest sp-theme-engine-test-role ()
  (should (equal (sp-theme-role 'bg-region 'dark)
                 (cadr (assq 'bg-accent-primary (sp-theme-palette 'dark)))))
  (should-not (equal (sp-theme-role 'bg-region 'dark) (sp-theme-role 'bg-region 'light)))
  (should-not (sp-theme-role 'no-such-role 'dark))
  (let ((sp-theme-mappings (append '((role-a . role-b) (role-b . fg-green)) sp-theme-mappings)))
    (should (equal (sp-theme-role 'role-a 'dark) (sp-theme-color 'green 'dark)))))

(ert-deftest sp-theme-engine-test-role-per-flavor ()
  (let ((sp-theme-flavors (copy-tree sp-theme-flavors)))
    (cl-letf (((symbol-function 'sp-theme-reload) #'ignore))
      (sp-theme-set-mapping 'fg-link 'fg-green 'dark))
    (should (equal (sp-theme-role 'fg-link 'dark) (sp-theme-color 'green 'dark)))
    (should (equal (sp-theme-role 'fg-link 'light) (sp-theme-color 'blue 'light)))))

(ert-deftest sp-theme-engine-test-face-attributes ()
  (should (equal (sp-theme--face-attributes
                  '(region :background bg-region :weight bold :underline t) 'dark)
                 (list :background (sp-theme-role 'bg-region 'dark)
                       :weight 'bold :underline t)))
  ;; An attribute whose role has no colour is left out.
  (should (equal (sp-theme--face-attributes '(x :foreground no-such-role :weight bold) 'dark)
                 '(:weight bold))))

(ert-deftest sp-theme-engine-test-merge-attrs ()
  (should (equal (sp-theme--merge-attrs '(:foreground "red" :inherit bold)
                                        '(:foreground "blue" :inherit fixed-pitch))
                 '(:foreground "blue" :inherit (bold fixed-pitch))))
  (should (equal (sp-theme--merge-attrs nil '(:height 1.2)) '(:height 1.2)))
  (should (equal (sp-theme--merge-attrs '((:weight bold)) '(:slant italic))
                 '(:weight bold :slant italic))))

(defconst sp-theme-engine-test--palette
  '("#2a3156" "#8f8280" "#4e5044" "#8a4160" "#8d2025"))

(ert-deftest sp-theme-engine-test-import-dark ()
  (let* ((flavor (sp-theme-flavor-from-palette sp-theme-engine-test--palette))
         (colors (plist-get flavor :colors))
         (bg (alist-get 'bg-main colors)))
    (should (eq (plist-get flavor :mode) 'dark))
    (should (< (sp-theme--luminance bg) 0.05))
    (should (>= (sp-theme-contrast (alist-get 'fg-main colors) bg) 10))
    (dolist (name '(accent-1 accent-2 red green yellow blue magenta cyan cursor))
      (should (>= (sp-theme-contrast (alist-get name colors) bg) 4.4)))
    ;; The most saturated colour is the first accent.
    (should (< (sp-theme-contrast "#8d2025" (alist-get 'accent-1 colors)) 3))
    (should (= 12 (length colors)))))

(ert-deftest sp-theme-engine-test-import-light ()
  (let* ((flavor (sp-theme-flavor-from-palette sp-theme-engine-test--palette
                                               :variant 'light))
         (colors (plist-get flavor :colors)))
    (should (eq (plist-get flavor :mode) 'light))
    (should (> (sp-theme--luminance (alist-get 'bg-main colors)) 0.7))
    (should (>= (sp-theme-contrast (alist-get 'fg-main colors)
                                   (alist-get 'bg-main colors))
                10))))

(ert-deftest sp-theme-engine-test-import-roles ()
  (let* ((flavor (sp-theme-flavor-from-palette sp-theme-engine-test--palette
                                               :roles '((red . 4) (blue . "#6fa8ff"))))
         (colors (plist-get flavor :colors)))
    (should (equal (alist-get 'blue colors) "#6fa8ff"))
    ;; red is the fifth colour, lifted only as far as readability needs.
    (should (> (sp-theme-contrast (alist-get 'red colors) (alist-get 'bg-main colors)) 4.4))
    (should-error (sp-theme-flavor-from-palette '("#112233")))
    (should-error (sp-theme-flavor-from-palette sp-theme-engine-test--palette
                                                :roles '((red . 9))))))

(ert-deftest sp-theme-engine-test-import-theme ()
  (let* ((dir (make-temp-file "sp-themes" t))
         (sp-theme-flavors (copy-tree sp-theme-flavors)))
    (cl-letf (((symbol-function 'sp-theme--themes-folder) (lambda () (file-name-as-directory dir))))
      (unwind-protect
          (let ((theme (sp-theme-import-palette "Wanda Vision"
                                                "#2a3156, #8f8280 #4e5044 #8a4160 #8d2025")))
            (should (eq theme 'sp-wanda-vision))
            (should (file-exists-p (expand-file-name "sp-wanda-vision-theme.el" dir)))
            (add-to-list 'custom-theme-load-path dir)
            (mapc #'disable-theme custom-enabled-themes)
            (load-theme theme t)
            (should (eq (car custom-enabled-themes) theme))
            (should (equal (face-attribute 'default :background)
                           (sp-theme-color 'bg-main 'wanda-vision))))
        (mapc #'disable-theme custom-enabled-themes)
        (delete-directory dir t)))))

(defun sp-theme-engine-test--setting (theme face)
  "Return the spec recorded for FACE in THEME, checking there is exactly one."
  (let ((records (seq-filter (lambda (s) (and (eq (car s) 'theme-face) (eq (cadr s) face)))
                             (get theme 'theme-settings))))
    (should (= 1 (length records)))
    (nth 3 (car records))))

(ert-deftest sp-theme-engine-test-theme-load ()
  (dolist (spec '((sp-dark . dark) (sp-light . light)))
    (let ((theme (car spec)) (flavor (cdr spec)))
      (load-theme theme t t)
      (should (eq (get theme 'sp-theme-flavor) flavor))
      (let ((region (cdar (sp-theme-engine-test--setting theme 'region))))
        (should (equal (plist-get region :background) (sp-theme-role 'bg-region flavor))))
      (let ((level (cdar (sp-theme-engine-test--setting theme 'org-level-1))))
        (should (equal (plist-get level :foreground) (sp-theme-role 'fg-heading-1 flavor)))
        (should (equal (plist-get level :height) 1.25)))
      (let ((code (cdar (sp-theme-engine-test--setting theme 'org-code))))
        (should (equal (plist-get code :foreground) (sp-theme-role 'fg-prose-code flavor)))
        (should (memq 'fixed-pitch (ensure-list (plist-get code :inherit)))))
      (let ((urgent (cdar (sp-theme-engine-test--setting theme 'sp-urgent))))
        (should (equal (plist-get urgent :foreground) (sp-theme-role 'err flavor)))))))

(ert-deftest sp-theme-engine-test-flavor-semantic-override ()
  (let ((sp-theme-flavors (copy-tree sp-theme-flavors)))
    (setf (plist-get (alist-get 'light sp-theme-flavors) :semantic)
          '((sp-crucial :foreground fg-green)))
    (load-theme 'sp-light t t)
    (let ((crucial (cdar (sp-theme-engine-test--setting 'sp-light 'sp-crucial))))
      (should (equal (plist-get crucial :foreground) (sp-theme-role 'fg-green 'light))))))

(provide 'sp-theme-engine-test)
;;; sp-theme-engine-test.el ends here
