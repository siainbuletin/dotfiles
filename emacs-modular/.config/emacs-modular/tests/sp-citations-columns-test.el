;;; sp-citations-columns-test.el --- Citar column alignment -*- lexical-binding: t; -*-
;; Loads only the width functions of sp-citations.el, with a stub for citar-format--string,
;; and checks where each column starts once `display' spaces are resolved.
(require 'ert)
(require 'cl-lib)
(defvar citar-indicators '(a b c d))
(defvar citar-ellipsis "…")
(defun citar-format--string (value &rest args)
  (let ((width (plist-get args :width)))
    (if (> (string-width value) width) (truncate-string-to-width value width) value)))
(let ((file (expand-file-name "../libraries/modules/academic/sp-citations.el"
                              (file-name-directory (or load-file-name buffer-file-name)))))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (let ((form (read (current-buffer))))
            (when (and (memq (car-safe form) '(defcustom defconst defun))
                       (string-match-p
                        "\\`sp-citations-\\(prefix-width\\|indicator-cell\\|column\\|candidate-margin\\)\\|--\\(assemble\\|fit-widths\\|indicator-block-width\\)\\'"
                        (symbol-name (cadr form))))
              (eval form t))))
      (end-of-file nil))))

(defun sp-citations-test--render (string)
  "Return STRING's columns resolved: a list of (TEXT . START) for the words, as drawn."
  (let ((pos 0) (out nil) (i 0) (len (length string)))
    (while (< i len)
      (let ((disp (get-text-property i 'display string)))
        (if (and (consp disp) (eq (car disp) 'space))
            (progn (setq pos (max pos (plist-get (cdr disp) :align-to)))
                   (while (and (< i len) (get-text-property i 'display string)) (cl-incf i)))
          (let ((c (aref string i)))
            (when (and (/= c ?\s) (or (= i 0) (= (aref string (1- i)) ?\s)))
              (push (cons (substring string i (or (string-match " " string i) len)) pos) out))
            (cl-incf pos (char-width c)) (cl-incf i)))))
    (nreverse out)))

(ert-deftest sp-citations-columns-line-up-after-the-ui-prefix ()
  "A value that fills its column does not push the next column to the right."
  (let* ((prefix "  ")                      ; the two columns Vertico draws first
         (base (sp-citations--indicator-block-width))
         (widths '(2 8 4 12 10))
         (rows '(("T " "Alpha" "1999" "Short" "key1")
                 ("T " "Bravoooo" "2023" "Titlefillsall" "longkey123")))
         (starts (mapcar
                  (lambda (row)
                    (let* ((strings (append (list "")
                                            (cl-loop for v in row for sep in '(" " "   " "   " "   " "   ")
                                                     append (list v sep))))
                           (drawn (concat prefix (make-string (- base 2 (length prefix)) ?x) ;; indicator stand-in
                                          (sp-citations--assemble strings widths base))))
                      (mapcar #'cdr (sp-citations-test--render drawn))))
                  rows)))
    (should (equal (cdr (car starts)) (cdr (cadr starts))))))

(ert-deftest sp-citations-order-and-widths ()
  "Year and the 45-column citekey fit first; the default order is fixed."
  (should (equal sp-citations-column-priorities '(1 2 1 2 1 3)))
  (should (= (nth 4 sp-citations-column-max-widths) 45))
  (should (equal (sp-citations--fit-widths '(3 40 4 80 45 20) 90 '(1 2 1 2 1 3))
                 '(3 19 4 19 45 0))))

(provide 'sp-citations-columns-test)
