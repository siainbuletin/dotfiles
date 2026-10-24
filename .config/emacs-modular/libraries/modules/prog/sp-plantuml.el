;;; sp-plantuml.el --- Minimal PlantUML mode with PNG preview -*- lexical-binding: t; -*-

;;; Commentary:

;; This module defines a small home-made major mode, `siapip/plantuml-mode',
;; for PlantUML diagram files (`.puml'). Every time such a file is saved it
;; runs the PlantUML jar through Java to render a PNG next to the source and
;; shows that image in a preview buffer.

;;; Code:

(defcustom siapip/plantuml:enable t
  "Whether the plantuml mode is enabled."
  :group 'spcustom
  :type 'boolean
  :set (lambda (sym val)
         (set-default sym val)
         (if val
             (add-to-list 'auto-mode-alist '("\\.puml\\'" . siapip/plantuml-mode))
           (setq auto-mode-alist
                 (delete '("\\.puml\\'" . siapip/plantuml-mode) auto-mode-alist)))))

(defcustom siapip/plantuml-jar-file "~/opt/plantuml/plantuml.jar"
  "The path to the plantuml jar file."
  :group 'spcustom
  :type 'file)

(defun siapip/plantuml-generate-png ()
  "Generate a PNG from the current plantuml file."
  (when (and siapip/plantuml-jar-file (file-exists-p siapip/plantuml-jar-file))
    (let ((cmd (format "java -jar %s -tpng %s"
                       (shell-quote-argument (expand-file-name siapip/plantuml-jar-file))
                       (shell-quote-argument buffer-file-name))))
      (shell-command cmd))))

(defun siapip/plantuml-preview ()
  "Display the PNG image for a plantuml file."
  (let* ((png-file (concat (file-name-sans-extension buffer-file-name) ".png"))
         (buf-name "*plantuml-preview*"))
    (when (file-exists-p png-file)
      (let ((preview-buffer (get-buffer-create buf-name)))
        (with-current-buffer preview-buffer
          (setq buffer-read-only nil)
          (erase-buffer)

          (use-local-map (make-sparse-keymap))
          (local-set-key (kbd "q") 'quit-window)
          
          (clear-image-cache png-file)
          (insert-image (create-image png-file))
          (setq header-line-format "Press 'q' to close.")
          (setq buffer-read-only t)
          (unless (get-buffer-window preview-buffer)
            (display-buffer preview-buffer)))))))

(defun siapip/plantuml-save-hook ()
  "Hook to run after saving a plantuml file."
  (when (string= (file-name-extension buffer-file-name) "puml")
    (siapip/plantuml-generate-png)
    (siapip/plantuml-preview)))

(define-derived-mode siapip/plantuml-mode prog-mode "PUML"
  "Major mode for editing plantuml files."
  :group 'siapip
  (add-hook 'after-save-hook 'siapip/plantuml-save-hook nil t))

(provide 'sp-plantuml)
