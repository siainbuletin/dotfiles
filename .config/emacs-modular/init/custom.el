;; -*- lexical-binding: t; -*-

(let ((customization-file (expand-file-name "custom.el"
                                            (file-name-directory
                                             (directory-file-name
                                              (file-name-directory (or load-file-name
                                                                       buffer-file-name)))))))
  (if (file-exists-p customization-file)
      (progn
        (message "Using custom file: %s" customization-file)
        (setq custom-file customization-file)
        (load custom-file 'noerror))
    (progn
      (message "Using default custom file location: %s" custom-file))))

(defgroup siapip nil
  "Configuration options for siapip Emacs setup."
  :prefix "siapip/"
  :group 'convenience)

(custom-set-variables
 '(bibtex-aux-opt-alist
   '(("keywords" "Keywords to describe the entry" "")
     ("file" "Relative or absolute path to attachments" "")) nil nil "Customized with use-package bibtex")
 '(custom-safe-themes
   '("acd363510d3e4b638db178783bde3d4492574c0f5c889f845251949f43567d16"
     "f2f42f0b7c53736840fc3ff5751235e3b87cc535b04ddaf3423e2926548bfbb4"
     default)))