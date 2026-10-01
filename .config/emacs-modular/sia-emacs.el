;; -*- lexical-binding: t; -*-

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
 '("./init/speedup"
   "./init/package"
   "./init/encoding" ;; text encoding
   "./init/essential" ;; this represents essential functions
   "./init/env"
   "./init/custom" ;; this is for the ~customize~ buffer
   "./init/gui"
   "./init/macos.el" ;; MacOS specific settings
   "./init/exwm" ;; see whether you're going to combine this with regular window management
   "./init/snippets" ;; snippet management
   ))

;; misc modules (utility)

(siapip/load
 '("./utils/exec-path-from-shell"
   "./utils/minibuffer"
   "./utils/indention"
   "./utils/replace-with-shell"
   "./utils/misc"
   ;; "./utils/modeline-choose"
   "./utils/lambda-line"
   ;; "./utils/extended-command"
   ))

;; package loading

(siapip/load
  '("./packages/search" ;; this represents full-text search packages
    "./packages/minibuffer-packs"
    "./packages/embark" 
    "./packages/counsel-recoll" 
    "./packages/consult-snapfile"
    "./packages/keys"
    "./packages/dired-conf"
    "./packages/bookmarks"
    "./packages/org-config"
    "./packages/sia-dashboard"
    "./packages/denote"
    "./packages/dgraphs"
    "./packages/org-node-mem"
    "./packages/academic"
    "./packages/reading"
    "./packages/projects"
    "./packages/help"
    "./packages/browsing"
    "./packages/vcontrol"
    "./packages/icon-config"
    "./packages/rss"
    "./packages/fonts"
    "./packages/taskman"
    "./packages/themes"
    "./packages/windows"
    "./packages/buffer-man"
    "./packages/multimedia"
    "./packages/terminal"
    "./packages/http"
    "./packages/ai"
    "./packages/vulpea-base"
  ))

;; functions I wrote

(siapip/load
  '("./functions/sia-move-region-to-heading.el"
    "./functions/sia-vulpea-convert-properties.el"
    "./functions/sia-vulpea-dblock.el"
    "./functions/sia-vulpea-grouped-backlinks.el"
    "./functions/sia-vulpea-table-views.el"
    "./functions/sia-vulpea-vui-table.el"))

;; Calling functions later on

(siapip/load
  '("./packages/vulpea-extensions" ;; needs the functions that I called earlier
  ))

;; language modules

(siapip/load
 '("./langs/common"
   ;; "./langs/plantuml"
   ;; "./langs/lisp"
   ;; "./langs/go"
   ;; "./langs/c"
   ;; "./langs/python"
   ;; "./langs/rust"
   ;; "./langs/xml"
   ;; "./langs/nix"
   ;; "./langs/misc" currently disabled, as there's several packages that conflict with something else that I have on the system
   "./langs/latex"
   ))

(siapip/load
 '("./ext/tex-switch-quotes/tex-switch-quotes"
   "./ext/misc/hl-line+"))

