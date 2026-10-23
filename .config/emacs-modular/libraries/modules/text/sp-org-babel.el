;;; -*- lexical-binding: t -*-
;; sp-org-babel.el

;;; Commentary:

;; This file deals with the tangling aspect of Emacs as well
;; this should, in the future, hold a reference to the functions
;; that are used for quickly tangling files.

;;; Code:

;;;; Different languages for org babel.
;; Avoid `org-babel-do-load-languages' since it does an eager require.
(use-package ob-python
  :ensure nil
  :defer t
  :commands (org-babel-execute:python)
  :config
  (progn
    (setq org-babel-python-command "python3"))) ;Default to python 3.x

(use-package ob-ditaa
  :ensure nil
  :defer t
  :config
  (progn
    ;; http://pages.sachachua.com/.emacs.d/Sacha.html
    (setq org-ditaa-jar-path (expand-file-name
                              "ditaa.jar"
                              (concat user-emacs-directory "software/")))))

(use-package ob-plantuml
  :ensure nil
  :defer t
  :config
  (progn
    (setq org-plantuml-jar-path (expand-file-name
                                 "plantuml.jar"
                                 (concat user-emacs-directory "software/")))

    (defun lem-advice-org-babel-execute:plantuml (orig-fun &rest args)
      "Force `shell-file-name' to be bash as the \">\" operator is used for redirection.

If this forcing is not done, and if `shell-file-name' is tcsh,
\">\" does not work.  When trying to overwrite files, we get a
\"File exists\" error, and \">!\" would need to be used instead.

Instead it's simpler to use bash."
      (let ((shell-file-name (executable-find "bash")))
        (apply orig-fun args)))
    (advice-add 'org-babel-execute:plantuml :around #'lem-advice-org-babel-execute:plantuml)))

(use-package ob-shell
  :ensure nil
  :defer t
  :commands
  (org-babel-execute:sh
   org-babel-expand-body:sh
   org-babel-execute:bash
   org-babel-expand-body:bash))

(use-package ob-lisp
  :ensure nil
  :defer t
  :commands (org-babel-execute:lisp))

(use-package ob-latex
  :ensure nil
  :defer t
  :commands
  (org-babel-execute:latex))

(use-package ob-gnuplot
  :ensure nil
  :defer t
  :commands (org-babel-execute:gnuplot))

;;:; Tangle settings
(use-package ob-tangle
  :ensure nil
  :defer t
  :config
  (progn
    ;; Trailing whitespace management
    ;; Delete trailing whitespace in tangled buffer and save it.
    (add-hook 'org-babel-post-tangle-hook #'delete-trailing-whitespace)
    (add-hook 'org-babel-post-tangle-hook #'save-buffer :append)))

(defun org-babel-nushell--list-includes (params)
  "Extract values from all :include keys in PARAMS alist."
  (let ((result nil))
    (dolist (pair params result)
      (when (and (consp pair)
                 (eq (car pair) :include))
        (push (cdr pair) result)))))

(defun org-babel-nushell--read-includes (params)
  "Read all includes"
  (let ((result '()))
    (dolist (name (org-babel-nushell--list-includes params))
      (let ((block-position (org-babel-find-named-block name)))
        (when block-position
          (save-excursion
            (goto-char block-position)
            (let ((data (org-babel-get-src-block-info)))
              (when data
                (push (nth 1 data) result)))))))
    (string-join (nreverse result) "\n")))

(defun org-babel-nushell-var-to-nushell (params)
  (format "let $%s = %s" (car params) (json-encode (cdr params))))

(defcustom org-babel-nushell-eval-shell-file-name "/bin/sh"
  "Shell executable used by `org-babel-eval' to execute Nushell source blocks.
This shell is used to execute the Nushell command."
  :type 'string
  :group 'spconfig)

(defun org-babel-execute:nushell (body params)
  "Execute a block of nushell code"
  (let* ((shell-file-name org-babel-nushell-eval-shell-file-name)
         (cmd (or (cdr (assoc :cmd params)) "nu"))
         (args (or (cdr (assoc :args params)) "-c"))
         (vars (mapcar
                'org-babel-nushell-var-to-nushell
                (org-babel--get-vars params)))
         (included-code (org-babel-nushell--read-includes params))
         (code (string-join (list (or included-code "") (org-babel-chomp body)) "\n"))
         (full-code (if vars
                        (concat (string-join vars "\n") "\n" code)
                      code))
         (command (format "%s %s %s" cmd args (shell-quote-argument full-code))))
    (org-babel-eval command "")))

(defun org-babel-execute:jinja (body params)
  "Execute a jinja2 template"
  (let* ((script (shell-quote-argument "import sys, jinja2 as j2; print(j2.Template(sys.argv[1]).render())"))
         (code (shell-quote-argument (org-babel-chomp body)))
         (command (format "python3 -c %s %s" script code)))
    (org-babel-eval command "")))

;;; Tangling all files at once from the literate configuration
(require 'ob-tangle)

(defvar sp-literate-org-dir (expand-file-name "docs/tangles/" user-emacs-directory))
(defvar sp-literate-files '("early.org" "core.org" "ui.org" "keys.org")
  "Org files to tangle, in order.")

(defun sp-tangle-all ()
  "Tangle every file in `sp-org-files' to its `:tangle' targets."
  (interactive)
  (let ((org-confirm-babel-evaluate nil)
        (tangled '()))
    (dolist (name sp-literate-files)
      (setq tangled
            (append tangled
                    (org-babel-tangle-file (expand-file-name name sp-literate-org-dir)))))
    (message "Tangled %d file(s): %s"
             (length tangled)
             (mapconcat #'file-name-nondirectory tangled ", "))
    tangled))

;;; Provide:

(provide 'sp-org-babel)
;; sp-org-babel.el ends here.