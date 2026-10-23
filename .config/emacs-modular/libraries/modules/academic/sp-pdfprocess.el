;; -*- lexical-binding: t; -*-
;; sp-pdfprocess.el

;;; Commentary:

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

;;; Provide:

(provide 'sp-pdfprocess)
;; sp-pdfprocess.el ends here.
