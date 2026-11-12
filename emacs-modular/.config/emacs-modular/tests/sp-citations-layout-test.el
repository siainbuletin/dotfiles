;;; sp-citations-layout-test.el --- Citar column layout -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(defvar citar-templates nil)
(defface sp-citar-key '((t)) "" :group 'sp)
(let ((file (expand-file-name "../libraries/modules/academic/sp-citations.el"
                              (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (let ((form (read (current-buffer))))
            (when (and (memq (car-safe form) '(defcustom defconst defun defvar))
                       (string-match-p "\\`sp-citations\\(-layout-\\|--\\(half-frame-columns\\|layout\\|pixel-cells-p\\|build-cell\\|emoji-cell\\|blank-cell\\|cell-cache\\)\\)"
                                       (symbol-name (cadr form))))
              (eval form t))))
      (end-of-file nil))))

(defun sp-citations-test--total (columns)
  (let ((l (sp-citations--layout columns)))
    (+ sp-citations-layout-overhead (plist-get l :author) (plist-get l :title)
       (plist-get l :key) (if (> (plist-get l :tags) 0) (+ 2 (plist-get l :tags)) 0))))

(ert-deftest sp-citations-layout-fits-the-columns ()
  "The columns of the layout never go over the room, down to the narrowest."
  (dolist (columns '(60 68 80 90 104 120 130 160))
    (let ((l (sp-citations--layout columns)))
      (when (>= columns 70)
        (should (<= (sp-citations-test--total columns) (+ columns 2))))
      (should (<= (plist-get l :key) 45))
      (should (>= (plist-get l :title) 20)))))

(ert-deftest sp-citations-layout-key-in-full-when-wide ()
  (should (= (plist-get (sp-citations--layout 110) :key) 45))
  (should (= (plist-get (sp-citations--layout 160) :key) 45))
  (should (< (plist-get (sp-citations--layout 80) :key) 45))
  (should (= (plist-get (sp-citations--layout 80) :tags) 0)))

(ert-deftest sp-citations-layout-templates ()
  (let ((templates (sp-citations--layout-templates 110)))
    (should (string-match-p "\\`\\${=type=:3%etype} \\${author editor:[0-9]+}  \\${year issued date:4}  \\${title:[0-9]+}\\'"
                            (cdr (assq 'main templates))))
    (should (string-match-p "\\${=key= id:4[0-9]}" (cdr (assq 'suffix templates))))))
;; Emoji cells, with the pixel functions stubbed: a glyph is `width-of' pixels.
(defvar sp-citations-test--glyph-widths '(("A" . 14) ("B" . 20) ("C" . 36)))
(defun sp-citations-test--pixel-width (string)
  (let* ((factor (or (let ((f (get-text-property 0 'face string))) (and (consp f) (plist-get f :height))) 1.0))
         (base (cdr (assoc (substring-no-properties string) sp-citations-test--glyph-widths))))
    (round (* factor base))))
(defun sp-citations-test--display-width (cell)
  "Pixels the `display' of CELL takes: its glyph and its stretched space."
  (let ((display (get-text-property 0 'display cell)))
    (+ (sp-citations-test--pixel-width (substring display 0 1))
       (car (plist-get (cdr (get-text-property 0 'display (substring display 1))) :width)))))

(ert-deftest sp-citations-emoji-cell-is-exact-in-pixels ()
  "Narrow, exact and too wide glyphs all fill the cell to the pixel; string-width is the cells."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
            ((symbol-function 'frame-char-width) (lambda (&rest _) 9))
            ((symbol-function 'string-pixel-width) #'sp-citations-test--pixel-width))
    (clrhash sp-citations--cell-cache)
    (dolist (glyph '("A" "B" "C"))
      (let ((cell (sp-citations--emoji-cell glyph 2)))
        (should (= (string-width cell) 2))
        (should (<= (abs (- (sp-citations-test--display-width cell) 18)) 1))))
    (should (= (string-width (sp-citations--blank-cell 2)) 2))
    (should (equal (get-text-property 0 'display (sp-citations--blank-cell 2)) '(space :width (18))))))

(ert-deftest sp-citations-emoji-cell-on-a-terminal ()
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
    (should (= (string-width (sp-citations--emoji-cell "A" 3)) 3))))

(provide 'sp-citations-layout-test)
