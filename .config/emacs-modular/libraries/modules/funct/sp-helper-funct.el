;;; sp-helper-funct.el --- summary -*- lexical-binding: t -*-

;; Useful functions

;;;;; Call an emacs instance
;; Call an emacs instance for testing

(defun sp-call-emacs ()
  (interactive)
  (start-process "Emacs" nil
                 ;; (executable-find "/usr/local/bin/emacs")))
                 (executable-find "/Applications/Emacs.app/Contents/MacOS/Emacs")
;; (executable-find "Emacs")
))

;;; Exiting without confirmation
(setq confirm-kill-processes nil)

;; Sounds
(setq ring-bell-function 'ignore) ;; Disable the bell sound

;; flash-screen-instead-of-ringing-bell
;; When you perform a problematic operation, flash the screen
;; instead of ringing the terminal bell
(setq visible-bell t)

;;;;; Archive region to setup-archive
(defun sp-kill-and-archive-region ()
  "Delete & append region to end of setup-archive.el"
  (interactive)
  (append-to-file (region-beginning) (region-end) (concat sp-setup-dir "sp-archived-configs.el"))
  (delete-region (region-beginning) (region-end)))

;;;;; Config Helper Functions

(defvar sp-files-sources-data
  `(("Init Files"      ?i ,sp-emacs-dir)
    ("Setup Files"     ?s ,sp-setup-dir)
    ("User Files"      ?u ,sp-user-dir))
  "Define titles, quick-keys, and directories to be searched for files.")

(defun sp--files-make-source (name char dir)
  "Return a source list suitable for `consult--multi'.
  NAME is the source name, CHAR is the narrowing character,
  and DIR is the directory to find files. "
  (let ((idir (propertize (file-name-as-directory dir) 'invisible t)))
    `(:name     ,name
      :narrow   ,char
      :category file
      :face     consult-file
      :items    ,(lambda () (mapcar (lambda (f) (concat idir f))
				               ;; filter files that glob *.*
				               (directory-files dir nil "[^.].*[.].+")))
      :action   ,(lambda (f) (find-file f)))))

(defun sp-find-lambda-file ()
  "Find a file from list of λ-Emacs configuration files."
  (interactive)
  (require 'consult)
  (consult--multi (mapcar #'(lambda (s) (apply 'sp--files-make-source s))
			              sp-files-sources-data)
		          :prompt "λ-files: "
		          :history 'file-name-history))

(defun sp-search-lambda-files ()
  "Search all configuration files in λ-Emacs with consult-ripgrep."
  (interactive)
  (require 'consult)
  (let ((consult-ripgrep-args
         "rg --null --line-buffered --max-columns=1000 --path-separator /\
   --smart-case --no-heading --line-number --hidden --glob=lambda-library/** --glob=!straight --glob=!var --glob=!.git/ ."))
    (if (executable-find "rg")
        (consult-ripgrep sp-emacs-dir)
      (message "Please install `rg' first."))))

;; Load init file
(defun sp-load-init-file ()
  "Load the base init file."
  (interactive)
  (load-file (concat user-emacs-directory "init.el")))

;;;; Built-in Functions
;; These are useful built-in functions, but you have to enable them
(put 'erase-buffer 'disabled nil)
(put 'downcase-region 'disabled nil)
(put 'upcase-region 'disabled nil)
(put 'narrow-to-region 'disabled nil)
(put 'dired-find-alternate-file 'disabled nil)

;; Not going to use these commands
(put 'ns-print-buffer 'disabled t)
(put 'suspend-frame 'disabled t)



;;;; Buffer Functions
;;;;; Blank Buffer New Frame
;; Make a blank buffer when opening a new frame. From
;; https://stackoverflow.com/a/25792276.

(defun sp-new-buffer-new-frame ()
  "Create a new frame with a new empty buffer."
  (interactive)
  (let ((buffer (generate-new-buffer "untitled")))
    (set-buffer-major-mode buffer)
    (display-buffer buffer '(display-buffer-pop-up-frame . nil))))


;;;;; Create new buffer
(defun sp-create-new-buffer ()
  "Create a new buffer in the default major mode."
  (interactive)
  (let ((buffer (generate-new-buffer "*new*")))
    (set-window-buffer nil buffer)
    (with-current-buffer buffer
      (funcall (default-value 'major-mode)))))

;;;;; Create New Elisp Buffer
(defun sp-create-new-elisp-buffer ()
  "Create a new buffer in `'emacs-lisp-mode'."
  (interactive)
  (let ((buffer (generate-new-buffer "*elisp*")))
    (set-window-buffer nil buffer)
    (with-current-buffer buffer
      (emacs-lisp-mode))))

;;;;; Make Temp Buffer
(defun sp-tmp-buffer()
  "Make a temporary buffer and switch to it."
  (interactive)
  (switch-to-buffer (get-buffer-create (concat "tmp-" (format-time-string "%m.%dT%H.%M.%S"))))
  (delete-other-windows))

;;;;; Revert all buffers
;;
(defun sp-revert-all-file-buffers ()
  "Refresh all open file buffers without confirmation.
Buffers in modified (not yet saved) state in emacs will not be reverted. They
will be reverted though if they were modified outside emacs.
Buffers visiting files which do not exist any more or are no longer readable
will be killed."
  (interactive)
  (dolist (buf (buffer-list))
    (let ((filename (buffer-file-name buf)))
      ;; Revert only buffers containing files, which are not modified;
      ;; do not try to revert non-file buffers like *Messages*.
      (when (and filename
                 (not (buffer-modified-p buf)))
        (if (file-readable-p filename)
            ;; If the file exists and is readable, revert the buffer.
            (with-current-buffer buf
              (revert-buffer :ignore-auto :noconfirm :preserve-modes))
          ;; Otherwise, kill the buffer.
          (let (kill-buffer-query-functions) ; No query done when killing buffer
            (kill-buffer buf)
            (message "Killed non-existing/unreadable file buffer: %s" filename))))))
  (message "Finished reverting buffers containing unmodified files."))

;;;;; Clipboard to/from Buffer
;; http://stackoverflow.com/a/10216338/4869
(defun sp-copy-whole-buffer-to-clipboard ()
  "Copy entire buffer to clipboard"
  (interactive)
  (clipboard-kill-ring-save (point-min) (point-max)))

(defun sp-copy-clipboard-to-whole-buffer ()
  "Copy clipboard and replace buffer"
  (interactive)
  (delete-region (point-min) (point-max))
  (clipboard-yank)
  (deactivate-mark))

;;;;; Useful Buffers
;; TODO: make this respect workspace buffers
(defun sp-user-buffer-q ()
  "Return t if current buffer is a user buffer, else nil.
  Typically, if buffer name starts with *, it's not considered a user buffer.
  This function is used by buffer switching command and close buffer command, so that next buffer shown is a user buffer.
  You can override this function to get your idea of “user buffer”.
  version 2016-06-18"
  (interactive)
  (if (string-equal "*" (substring (buffer-name) 0 1))
      nil
    (if (string-equal major-mode "dired-mode")
        nil
      t
      )))

(defun sp-next-user-buffer ()
  "Switch to the next user buffer.
  “user buffer” is determined by `sp-user-buffer-q'.
  URL `http://ergoemacs.org/emacs/elisp_next_prev_user_buffer.html'
  Version 2016-06-19"
  (interactive)
  (next-buffer)
  (let ((i 0))
    (while (< i 20)
      (if (not (sp-user-buffer-q))
          (progn (next-buffer)
                 (setq i (1+ i)))
        (progn (setq i 100))))))

(defun sp-previous-user-buffer ()
  "Switch to the previous user buffer.
  “user buffer” is determined by `sp-user-buffer-q'.
  URL `http://ergoemacs.org/emacs/elisp_next_prev_user_buffer.html'
  Version 2016-06-19"
  (interactive)
  (previous-buffer)
  (let ((i 0))
    (while (< i 20)
      (if (not (sp-user-buffer-q))
          (progn (previous-buffer)
                 (setq i (1+ i)))
        (progn (setq i 100))))))

;;;;; Eval emacs buffer until error

(defun sp-eval-buffer-until-error ()
  "Evaluate emacs buffer until error occured."
  (interactive)
  (goto-char (point-min))
  (while t (eval (read (current-buffer)))))

;;;;; Kill Current Buffer
;; (kill-this-buffer) is unreliable when not invoked from the menubar. So here's a
;; wrapper on (kill-buffer) to kill the current buffer. This is sometimes better
;; than (evil-delete-buffer) since it keeps the window.

(defun sp-kill-this-buffer ()
  (interactive)
  (kill-buffer))

;;;;; Show Filename of Buffer

;; http://camdez.com/blog/2013/11/14/emacs-show-buffer-file-name/
(defun sp-show-and-copy-buffer-full-filename ()
  "Show the full path to the current file in the minibuffer and copy to clipboard."
  (interactive)
  (let ((file-name (buffer-file-name)))
    (if file-name
        (progn
          (message file-name)
          (kill-new file-name))
      (error "Buffer not visiting a file"))))

(defun sp-show-and-copy-buffer-filename ()
  "Show the abbreviated path to the current file in the minibuffer and copy to clipboard."
  (interactive)
  (let ((file-name (buffer-file-name)))
    (if file-name
        (let ((abbrev-name (abbreviate-file-name file-name)))
          (message abbrev-name)
          (kill-new abbrev-name))
      (error "Buffer not visiting a file"))))

;;;;; Switch previous buffer

(defun switch-to-previous-buffer ()
  (interactive)
  (switch-to-buffer (other-buffer (current-buffer) 1)))

;;;; File Functions

;;;;; Delete Current File
;; from magnars

(defun sp-delete-current-buffer-file ()
  "Removes file connected to current buffer and kills buffer."
  (interactive)
  (let ((filename (buffer-file-name))
        (buffer (current-buffer))
        (name (buffer-name)))
    (if (not (and filename (file-exists-p filename)))
        (ido-kill-buffer)
      (when (yes-or-no-p "Are you sure you want to delete this file? ")
        (delete-file filename t)
        (kill-buffer buffer)
        (message "File '%s' successfully removed" filename)))))

;;;;; Get string from file
(defun sp-get-string-from-file (filePath)
  "Read a file and return the contents as a string"
  (with-temp-buffer
    (insert-file-contents filePath)
    (buffer-string)))


;;;;; Duplicate file
;; Duplicate a file in dired or deer
(defun sp-duplicate-file ()
  (interactive)
  (dired-do-copy-regexp "\\(.*\\)\\.\\(.*\\)" "\\1 (copy).\\2"))

;;;;; Move File
(defun sp-move-file ()
  "Write this file to a new location, and delete the old one."
  (interactive)
  (let ((old-location (buffer-file-name)))
    (call-interactively #'write-file)
    (when old-location
      (delete-file old-location))))

;;;; Directory Functions
;;;;; Make Parent Directory
;;  Create a directory – or a hierarchy of them – while finding a file in a
;;  nonexistent directory. From mbork
;;  http://mbork.pl/2016-07-25_Making_directories_on_the_fly

(defun make-parent-directory ()
  "Make sure the directory of `buffer-file-name' exists."
  (make-directory (file-name-directory buffer-file-name) t))

(add-hook 'find-file-not-found-functions #'make-parent-directory)

;;;;; Insert seconds
;; Functions for inserting times.

(defun sp-insert-time-string ()
  "Insert year, day, hour, month, and second as a single string
      with no seperation"
  (interactive)
  (insert (format-time-string "%Y%d%H%M%S")))

(defun sp-insert-time-seconds-epoch ()
  "Insert the integer number of seconds since the epoch."
  (interactive)
  (insert (format-time-string "%s")))
;; (keymap-global-set "C-c e") ''sp-insert-time-seconds-epoch)

;;;;; Insert Comment Seperator
;; ======================================================
;; Insert commented seperator like this line
;; ======================================================
;; https://github.com/kuanyui/writing-utils.el/blob/db29d30e11b6d6d96c0d351b642af97631f3365f/writing-utils.el#L85

(defun sp-insert-commented-separator()
  "Insert a commented separator in your code. Like this in
      ELisp:
      ;; ======================================================
      ;; Title
      ;; ======================================================
      Which makes code easier to read.
      "
  (interactive)
  (let* ((line (make-string 54 (string-to-char "=")))
	     (comment-start (if (member major-mode '(emacs-lisp-mode lisp-mode))
			                ";; " comment-start))
         (seperator (concat comment-start line)))
    (when (> (current-column) 0) (end-of-line) (newline))
    (insert (format "%s\n%s\n%s"
		            seperator comment-start seperator))
    (previous-line)
    ))

;;;;; Insert Weather
;; From [[https://www.baty.blog/2019/insert-weather-into-emacs-buffer][Jack Baty]] with some slight modifications for formatting. See also [[https://github.com/chubin/wttr.in][wttr.in]].
(defun sp-insert-weather ()
  "Insert `'wttr.in' weather forecast in buffer."
  (interactive)
  (let ((w (shell-command-to-string "curl -s 'wttr.in/?0qT' | head -n10")))
    (insert (mapconcat (function (lambda (x) (format ": %s" x)))
                       (split-string w "\n")
                       "\n")))
  (newline))

;;;;; Wrap in Yaml block
(defun sp-yaml-wrap ()
  "wrap region in --- for a yaml block"
  (interactive)
  (let ((start (region-beginning))
        (end (region-end)))
    (goto-char end)
    (insert "---" "\n")
    (goto-char start)
    (insert "---" "\n")))

;;;;; Jump to sexp

(defun sp-forward-or-backward-sexp (&optional arg)
  "Go to the matching parenthesis character if one is adjacent to point."
  (interactive "^p")
  (cond ((looking-at "\\s(") (forward-sexp arg))
        ((looking-back "\\s)" 1) (backward-sexp arg))
        ;; Now, try to succeed from inside of a bracket
        ((looking-at "\\s)") (forward-char) (backward-sexp arg))
        ((looking-back "\\s(" 1) (backward-char) (forward-sexp arg))))

;;;; UI Functions
;;;;; Toggle markup
(defun sp-toggle-display-markup ()
  "Toggle the display of markup in markdown and org modes"
  (interactive)
  (if (eq major-mode 'org-mode)
      (org-toggle-link-display)
    (if markdown-hide-markup
        (markdown-toggle-markup-hiding 0)
      (markdown-toggle-markup-hiding))))

;;;;; Quit All the Things!
;; From a great vim migration guide by Juanjo Álvarez
;; https://juanjoalvarez.net/en/detail/2014/sep/19/vim-emacsevil-chaotic-migration-guide/
;; (original code from davvil) https://github.com/davvil/.emacs.d/blob/master/init.el
;;
;; This should make operating with the minibuffer a little easier.
(defun minibuffer-keyboard-quit ()
  "Abort recursive edit.
      In Delete Selection mode, if the mark is active, just deactivate it;
      then it takes a second \\[keyboard-quit] to abort the minibuffer."
  (interactive)
  (if (and delete-selection-mode transient-mark-mode mark-active)
      (setq deactivate-mark  t)
    (when (get-buffer "*Completions*") (delete-windows-on "*Completions*"))
    (abort-recursive-edit)))
(with-eval-after-load 'evil
  (define-key evil-normal-state-map [escape] 'keyboard-quit)
  (define-key evil-visual-state-map [escape] 'keyboard-quit)
  (define-key minibuffer-local-map [escape] 'minibuffer-keyboard-quit)
  (define-key minibuffer-local-ns-map [escape] 'minibuffer-keyboard-quit)
  (define-key minibuffer-local-completion-map [escape] 'minibuffer-keyboard-quit)
  (define-key minibuffer-local-must-match-map [escape] 'minibuffer-keyboard-quit)
  (define-key minibuffer-local-isearch-map [escape] 'minibuffer-keyboard-quit)
  (global-set-key [escape] 'evil-exit-emacs-state))

;; Other functions to look through (this is an archive)
;; Emacs Writing Studio Customisation

(defcustom sia-org-heading-level-capitalise nil
  "Minimum level of Org headings to be capitalised
Nil implies all levels are capitalised."
  :group 'spconfig
  :type  '(choice (const :tag "All headings" nil)
		  (integer :tag "Highest level" 1)))

;; Check for missing external software
;;;###autoload
(defun sia-missing-executables (prog-list)
  "Identify missing executables in PROG-LIST.
Sublists indicate that one of the entries is required."
  (let ((missing '()))
    (dolist (exec prog-list)
      (if (listp exec)
          (unless (cl-some #'executable-find exec)
            (push (format "(%s)" (mapconcat 'identity exec " or ")) missing))
        (unless (executable-find exec)
          (push exec missing))))
    (if missing
        (message "Missing executable files(s): %s"
                 (mapconcat 'identity missing ", "))
      (message "No missing executable files."))))

;; Denote

;;;###autoload
(defun sia-org-insert-notes-drawer ()
  "Generate or open a NOTES drawer under the current heading.
If a drawer exists for this section, a new line is created at the end of the
current note."
  (interactive)
  (push-mark)
  (org-previous-visible-heading 1)
  (forward-line)
  (if (looking-at-p "^[ \t]*:NOTES:")
      (progn
        (org-fold-hide-drawer-toggle 'off)
        (re-search-forward "^[ \t]*:END:" nil t)
        (forward-line -1)
        (org-end-of-line)
        (org-return))
    (org-insert-drawer nil "NOTES"))
  (org-unlogged-message "Press <C-u C-SPACE> to return to the previous position."))

;;;###autoload
(defun sia-org-count-words ()
  "Add word count to each heading property drawer in an Org mode buffer."
  (interactive)
  (org-map-entries
   (lambda ()
     (let* ((start (point))
            (end (save-excursion (org-end-of-subtree)))
            (word-count (count-words start end)))
       (org-set-property "WORDCOUNT" (number-to-string word-count))))))

;;;###autoload
(defun sia-org-insert-screenshot ()
  "Take a screenshot with the maim program and insert as an Org mode link."
  (interactive)
  (let ((filename (read-file-name "Enter filename for screenshot: " default-directory)))
    (unless (string-equal "png" (file-name-extension filename))
      (setq filename (concat (file-name-sans-extension filename) ".png")))
    (call-process-shell-command (format "maim --select %s" filename))
    (insert (format "#+caption: %s\n" (read-from-minibuffer "Caption: ")))
    (insert (format "[[file:%s]]" filename))
    (org-redisplay-inline-images)))

;;;###autoload
(defun sia-org-headings-titlecase (&optional arg)
  "Cycle through all headings in an Org buffer and convert them to title case.
When used with universal argument (ARG) converts to sentence case.
Customise `titlecase-style' for styling."
  (interactive "P")
  (require 'titlecase)
  (let ((style (if arg 'sentence titlecase-style)))
    (message "Converting headings to '%s' style" style)
    (org-map-entries
     (lambda ()
       (let* ((heading (substring-no-properties (org-get-heading t t t t)))
	      (level (org-current-level))
	      (heading-lower (downcase heading))
              (new-heading (titlecase--string heading-lower style)))
	 (when (<= level (or sia-org-heading-level-capitalise 999))
	   (org-edit-headline new-heading)))))))

;; Fixed by Prot
(defun sia-denote-link-description-title-case (file)
  "Return link description for FILE.

If the region is active, use it as the description.
The title is formatted with the `titlecase' package.

This function is useful as the value of `denote-link-description-function' to
generate links in titlecase for attachments."
  (require 'titlecase)
  (let* ((file-type (denote-filetype-heuristics file))
         (title (denote-retrieve-title-or-filename file file-type)))
    (cond
     ((denote--get-active-region-content))
     ((or (null title) (string-blank-p title))
      "")
     ((string-match-p " " title)
      title)
     (t
      (let ((clean-title (replace-regexp-in-string "\\([a-zA-Z0-9]\\)-\\([a-zA-Z0-9]\\)" "\\1 \\2" title)))
        (format "%s" (titlecase--string clean-title titlecase-style)))))))

;;;; Sensible defaults library

;;; Code:

;; Utility functions:

(defun sp-comment-region-or-line ()
  "Comments or uncomments the region or the current line if
there's no active region."
  (interactive)
  (let (beg end)
    (if (region-active-p)
        (setq beg (region-beginning) end (region-end))
      (setq beg (line-beginning-position) end (line-end-position)))
    (comment-or-uncomment-region beg end)))

(defun sensible-defaults/increase-gc-threshold ()
  "Allow 20MB of memory (instead of 0.76MB) before calling
garbage collection. This means GC runs less often, which speeds
up some operations."
  (setq gc-cons-threshold 20000000))

(defun sp-offer-to-create-parent-directories-on-save ()
  "When saving a file in a directory that doesn't exist, offer
to (recursively) create the file's parent directories."
  (add-hook 'before-save-hook
            (lambda ()
              (when buffer-file-name
                (let ((dir (file-name-directory buffer-file-name)))
                  (when (and (not (file-exists-p dir))
                             (y-or-n-p (format "Directory %s does not exist. Create it?" dir)))
                    (make-directory dir t)))))))

(defun sensible-defaults/apply-changes-to-highlighted-region ()
  "Turn on transient-mark-mode."
  (transient-mark-mode t))

;; Ask if you're sure that you want to close Emacs.
(setq confirm-kill-emacs nil)

(defun sensible-defaults/quiet-startup ()
  "Don't present the usual startup message, and clear the scratch
buffer."
  (setq inhibit-startup-message t)
  (setq initial-scratch-message nil))

(defun sensible-defaults/shorten-yes-or-no ()
  "Don't ask `yes/no?', ask `y/n?'."
  (fset 'yes-or-no-p 'y-or-n-p))

(defun sensible-defaults/always-highlight-code ()
  "Turn on syntax highlighting whenever possible."
  (global-font-lock-mode t))

(defun sensible-defaults/refresh-buffers-when-files-change ()
  "When something changes a file, automatically refresh the
buffer containing that file so they can't get out of sync."
  (global-auto-revert-mode t))

(defun sensible-defaults/show-matching-parens ()
  "Visually indicate matching pairs of parentheses."
  (show-paren-mode t)
  (setq show-paren-delay 0.0))

(defun sensible-defaults/open-clicked-files-in-same-frame-on-mac ()
  "When you double-click on a file in the Mac Finder open it as a
buffer in the existing Emacs frame, rather than creating a new
frame just for that file."
  (setq ns-pop-up-frames nil))

(defun sensible-defaults/yank-to-point-on-mouse-click ()
  "When middle-clicking the mouse to yank from the clipboard,
insert the text where point is, not where the mouse cursor is."
  (setq mouse-yank-at-point t))

(defun sensible-defaults/use-all-settings ()
  "Use all of the sensible-defaults settings."
  (sp-open-from-home-dir)
  (sensible-defaults/increase-gc-threshold)
  (sp-camelcase-separate-words)
  (sp-auto-follow-symlinks)
  (sp-single-space-after-periods)
  (sp-offer-to-create-parent-directories-on-save)
  (sensible-defaults/apply-changes-to-highlighted-region)
  (sensible-defaults/quiet-startup)
  (sensible-defaults/shorten-yes-or-no)
  (sensible-defaults/always-highlight-code)
  (sensible-defaults/refresh-buffers-when-files-change)
  (sensible-defaults/show-matching-parens)


  (sensible-defaults/open-clicked-files-in-same-frame-on-mac)
  (sensible-defaults/yank-to-point-on-mouse-click))

;; Other functions
(use-package wizard
  :ensure (:type git :host github :repo "jamescherti/wizard.el" :rev :newest))

;;; Provide
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(provide 'sp-helper-funct)
;;; sp-helper-funct.el ends here
