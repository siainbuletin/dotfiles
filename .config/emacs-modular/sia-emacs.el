;; -*- lexical-binding: t; -*-
;; To enable put the following as your .emacs file assuming
;; all contents were installed into ~/.emacs/siapip/
;;
;; (load "/path/to/siapip-emacs-config/siapip-emacs")

;; SETTING UP THE LOAD PATH

(defvar siapip/load-path (file-name-directory (or load-file-name buffer-file-name))
  "Path of the siapip emacs config")
(when (not siapip/load-path)
  (error "Cannot determine configuration path of siapip emacs-config: both load-file-name and buffer-file-name are nil"))

(defun siapip/load (paths)
  "Load files relative to this emacs config."
  (when (not (listp paths))
    (setq paths (list paths)))
  (dolist (path paths)
    (condition-case err
        (load (expand-file-name path siapip/load-path))
      (error (message "Failed to load siapip-config sub-library at %S: %S" path err)))))

;; init files

(siapip/load
 '("./init/custom.el"
   "./init/speedup.el"
   "./init/package.el"
   "./init/encoding.el"
   "./init/gui.el"
   "./init/exwm.el"))

;; loading different modules

(siapip/load
 '("./utils/exec-path-from-shell"
   "./utils/minibuffer"
   "./utils/indention"
   "./utils/replace-with-shell"
   "./utils/misc"
   "./utils/vterm"
   "./utils/eat-terminal"
   "./utils/modeline"
   "./utils/multiple-cursors"
   "./utils/extended-command"))

;; language modules

(siapip/load
 '("./langs/common"
   "./langs/plantuml"
   "./langs/lisp"
   "./langs/go"
   "./langs/c"
   "./langs/python"
   "./langs/rust"
   "./langs/org"
   "./langs/xml"
   "./langs/nix"
   "./langs/misc"))

(siapip/load "./langs/latex")

(siapip/load
 '("./ext/tex-switch-quotes/tex-switch-quotes"
   "./ext/misc/hl-line+"))
