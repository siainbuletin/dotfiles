;;; sp-pdfprocess.el --- PDF metadata and the emacs-reader viewer -*- lexical-binding: t; -*-

;;; Commentary:

;; Utilities for working with PDF files in the academic setup. It has a command
;; that writes a reference's title and author from the Citar bibliography into
;; the PDF's metadata using the external `exiftool' program, and it installs
;; the `emacs-reader' document viewer from Codeberg.

;;; Code:

;;;; Working with PDF metadata from citar
(defun sia-citar-update-pdf-metadata (citekey)
  (interactive (list (citar-select-ref)))
  (citar--check-configuration 'citar-library-paths)
  (unless citar-library-paths
    (user-error "Make sure `citar-library-paths' is non-nil"))
  (let* ((files (gethash citekey (citar-get-files citekey))))
    (unless files
      (user-error (format "There are no PDF files associated with %s" citekey)))
    (let ((file (or (unless (cdr files) (car files)) (completing-read "Please select a PDF file: " files)))
          (title (citar-get-value 'title citekey))
          (author (cond ((citar-get-value 'author citekey)
                         (citar-get-value 'author citekey))
                        ((citar-get-value 'editor citekey)
                         (concat (citar-get-value 'editor citekey) " (ed.)")))))
      (progn
        (copy-file file sia-citar-library-backup-path 1)
        (call-process-shell-command
         (concat "exiftool -overwrite_original_in_place -Title='" title "' -Author='" author "' " file))))))

(provide 'sp-pdfprocess)
;; sp-pdfprocess.el ends here.
