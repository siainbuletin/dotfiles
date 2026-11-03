;;; sp-org-babel.el --- Org Babel languages and tangling -*- lexical-binding: t; -*-

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
  :group 'spcustom)

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

;;;; Tangling all files at once from the literate configuration
(require 'ob-tangle)

(require 'cl-lib)

(defvar sp-literate-org-dir (expand-file-name "docs/tangles/" user-emacs-directory)
  "Folder with the literate Org documents of the modules.")

(defun sp-tangle--module-doc-p (file)
  "Non-nil if FILE has a `:tangle' path into `libraries/modules/'."
  (with-temp-buffer
    (insert-file-contents file)
    (re-search-forward ":tangle [./]*libraries/modules/" nil t)))

(defun sp-tangle-docs ()
  "Return the absolute names of all module documents below `sp-literate-org-dir'."
  (cl-remove-if-not #'sp-tangle--module-doc-p
                    (directory-files-recursively sp-literate-org-dir "^sp-.*[.]org\\'")))

(defcustom sp-tangle-cache-file
  (expand-file-name "tangle-hashes.eld"
                    (if (boundp 'sp-cache-dir) sp-cache-dir user-emacs-directory))
  "File remembering the hash and output files of each tangled document."
  :type 'file
  :group 'org-babel)

(defun sp-tangle--read-cache ()
  "Return the alist stored in `sp-tangle-cache-file', or nil."
  (when (file-readable-p sp-tangle-cache-file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents sp-tangle-cache-file)
          (read (current-buffer)))
      (error nil))))

(defun sp-tangle--write-cache (cache)
  "Store the alist CACHE in `sp-tangle-cache-file'."
  (make-directory (file-name-directory sp-tangle-cache-file) t)
  (with-temp-file sp-tangle-cache-file
    (let ((print-length nil) (print-level nil))
      (prin1 cache (current-buffer)))))

(defun sp-tangle--rel (file)
  "Return FILE relative to `sp-literate-org-dir'."
  (file-relative-name file sp-literate-org-dir))

(defun sp-tangle--hash (file)
  "Return the SHA-1 of the text of FILE."
  (with-temp-buffer
    (insert-file-contents-literally file)
    (secure-hash 'sha1 (current-buffer))))

(defun sp-tangle--stale-p (doc entry)
  "Non-nil if DOC must be tangled, given its cache ENTRY (hash and outputs)."
  (or (null entry)
      (not (equal (plist-get entry :hash) (sp-tangle--hash doc)))
      (cl-some (lambda (out)
                 (not (file-exists-p (expand-file-name out sp-literate-org-dir))))
               (plist-get entry :outputs))))

(defun sp-tangle--run (docs force)
  "Tangle the stale ones among DOCS (all of them if FORCE) and update the cache.
Return the list of `.el' files written."
  (let* ((org-confirm-babel-evaluate nil)
         (revert-without-query '(".*")) ; a document pulled in by git is re-read silently
         (cache (sp-tangle--read-cache))
         (written '()) (failed '()) (skipped 0))
    (dolist (doc docs)
      (let* ((key (sp-tangle--rel doc))
             (entry (cdr (assoc key cache))))
        (if (not (or force (sp-tangle--stale-p doc entry)))
            (cl-incf skipped)
          (condition-case err
              (let* ((hash (sp-tangle--hash doc))
                     (outputs (org-babel-tangle-file doc))
                     (rel (mapcar #'sp-tangle--rel outputs))
                     (orphans (cl-set-difference (plist-get entry :outputs) rel
                                                 :test #'equal)))
                (setf (alist-get key cache nil nil #'equal)
                      (list :hash hash :outputs rel))
                (setq written (append written outputs))
                (dolist (o orphans)
                  (when (file-exists-p (expand-file-name o sp-literate-org-dir))
                    (message "sp-tangle: %s no longer writes %s (left in place)"
                             key (file-name-nondirectory o)))))
            (error (push (format "%s (%s)" key (error-message-string err)) failed))))))
    ;; Forget documents that were deleted or no longer tangle into the modules.
    (when (equal docs (sp-tangle-docs))
      (let ((live (mapcar #'sp-tangle--rel docs)))
        (setq cache (cl-remove-if-not (lambda (e) (member (car e) live)) cache))))
    (sp-tangle--write-cache cache)
    (message "sp-tangle: tangled %d file(s) from %d document(s), %d up to date%s"
             (length written) (- (length docs) skipped (length failed)) skipped
             (if failed (format "; FAILED: %s" (string-join failed ", ")) ""))
    written))

;;;###autoload
(defun sp-tangle-changed (&optional force)
  "Tangle the module documents whose text changed since they were last tangled.
With prefix argument FORCE, tangle all of them.  Return the files written."
  (interactive "P")
  (sp-tangle--run (sp-tangle-docs) force))

;;;###autoload
(defun sp-tangle-all ()
  "Tangle every module document, changed or not.  Return the files written."
  (interactive)
  (sp-tangle-changed t))

(defun sp-tangle-changed-and-reload (&optional force)
  "Tangle the changed module documents, then reload the modules they wrote.
With prefix argument FORCE, tangle (and reload) all of them."
  (interactive "P")
  (let ((files (sp-tangle-changed force)))
    (cond ((null files))
          ((fboundp 'sp-reload--run) (sp-reload--run files))
          (t (dolist (f files)
               (when (featurep (intern (file-name-base f)))
                 (load f nil t t)))))
    files))

(defun sp-tangle--after-save ()
  "Tangle the visited file if it is a changed module document."
  (when (and buffer-file-name
             (file-in-directory-p buffer-file-name sp-literate-org-dir)
             (string-match-p "\\`sp-.*[.]org\\'" (file-name-nondirectory buffer-file-name))
             (sp-tangle--module-doc-p buffer-file-name))
    (sp-tangle--run (list buffer-file-name) nil)))

(define-minor-mode sp-tangle-on-save-mode
  "Tangle a module document when it is saved, if its text changed."
  :lighter " Tgl"
  (if sp-tangle-on-save-mode
      (add-hook 'after-save-hook #'sp-tangle--after-save nil t)
    (remove-hook 'after-save-hook #'sp-tangle--after-save t)))

(provide 'sp-org-babel)
;; sp-org-babel.el ends here.
