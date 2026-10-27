;; Load up Org Mode and (now included) Org Babel for elisp embedded in Org Mode files
(setq dotfiles-dir (file-name-directory (or (buffer-file-name) load-file-name)))

;; load up all literate org-mode files in this directory
(mapc #'org-babel-load-file (directory-files dotfiles-dir t "\\.org$"))

(let* ((dotfile-dir (file-name-directory (or (buffer-file-name)
  				     load-file-name)))
     ;; disabled
     ;; (etc-dir   (expand-file-name "etc" dotfile-dir))
     ;; (etc-files (directory-files etc-dir t "\\.org$"))
     (config-org  (expand-file-name "README.org" dotfile-dir))
     (config-el   (expand-file-name "README.el"  dotfile-dir)))
(require 'org)
(require 'ob-tangle)

;;tangle and load if newer than compiled
(if (or (not (file-exists-p config-el))
        (file-newer-than-file-p config-org config-el))
    (org-babel-load-file config-org t)
  (load-file config-el)))