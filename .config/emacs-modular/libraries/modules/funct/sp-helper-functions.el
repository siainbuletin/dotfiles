;;; sp-other-functions.el --- summary -*- lexical-binding: t -*-

;; Useful functions

;;;;; Call an emacs instance
;; Call an emacs instance for testing

(defun lem-call-emacs ()
  (interactive)
  (start-process "Emacs" nil
                 ;; (executable-find "/usr/local/bin/emacs")))
                 (executable-find "/Applications/Emacs.app/Contents/MacOS/Emacs")
;; (executable-find "Emacs")
))

;;; Exiting without confirmation
(setq confirm-kill-processes nil)

;;;;; Archive region to setup-archive
(defun sp-kill-and-archive-region ()
  "Delete & append region to end of setup-archive.el"
  (interactive)
  (append-to-file (region-beginning) (region-end) (concat sp-setup-dir "sp-archived-configs.el"))
  (delete-region (region-beginning) (region-end)))

;;;;; Config Helper Functions

(defvar lem-files-sources-data
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

(defun lem-find-lambda-file ()
  "Find a file from list of λ-Emacs configuration files."
  (interactive)
  (require 'consult)
  (consult--multi (mapcar #'(lambda (s) (apply 'sp--files-make-source s))
			              lem-files-sources-data)
		          :prompt "λ-files: "
		          :history 'file-name-history))

(defun lem-search-lambda-files ()
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
(defun lem-load-init-file ()
  "Load the base init file."
  (interactive)
  (load-file (concat user-emacs-directory "init.el")))

(defun lem-load-config-file ()
  "Load the user config file."
  (interactive)
  (load-file lem-config-file))

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

;;;; CRUX
;; A Collection of Ridiculously Useful eXtensions for Emacs. Crux bundles many
;; useful interactive commands to enhance your overall Emacs experience. Most of
;; the crux commands are related to the editing experience, but there are also a
;; bunch of utility commands that are just very useful to have (e.g.
;; crux-open-with and crux-reopen-as-root). Originally part of Emacs Prelude.
(use-package crux
  :if (and sp-load-extras (locate-library "crux"))
  :defer 1
  :bind
  ("C-k"   . crux-smart-kill-line)
  ("C-a"   . crux-move-beginning-of-line))

;;;; Frame Functions
;;;;; Delete Frame or Quit
(defun lem-delete-frame-or-quit ()
  "Delete the selected frame & kill terminal buffers. If the last frame, kill Emacs."
  (interactive)
  (kill-matching-buffers "*vterm" nil t)
  (when (condition-case nil (delete-frame)
          (error (save-buffers-kill-emacs))))
  (select-frame-set-input-focus (selected-frame)))

;;;;; Create Capture Frame
;; have these functions available for server
(defun lem-activate-capture-frame ()
  "run org-capture in capture frame"
  (progn
    (require 'org)
    (select-frame-by-name "capture")
    (switch-to-buffer (get-buffer-create "new"))
    (org-capture)))

;;;;; Weather Capture Frame
(defun lem-weather-journal-capture ()
  (interactive)
  (progn
    (require 'org)
    (select-frame-by-name "capture")
    (switch-to-buffer (get-buffer-create "new"))
    (lem-org-journal)
    (lem-insert-weather)))

;;;; Window Functions
;;;;; Toggle Dedicated Window
(defun lem-toggle-window-dedicated ()
  "Toggle whether the current active window is dedicated or not"
  (interactive)
  (message
   (if (let ((window (get-buffer-window (current-buffer))))
         (set-window-dedicated-p window (not (window-dedicated-p window))))
       "Window '%s' is dedicated"
     "Window '%s' is normal")
   (current-buffer)))

;;;;; Exchange Windows
;; Swap buffers in windows and leave the cursor in the original window. Courtesy of
;; Mike Zamansky's video.
;; http://cestlaz.github.io/posts/using-emacs-36-touch-of-elisp/#.WX5Wg0czpcx

(defun lem-window-exchange-buffer ()
  "Swap buffer in windows and leave focus in original window"
  (interactive)
  (ace-swap-window)
  (aw-flip-window))

;;;;; Rotate Windows
;; from magnars modified by ffevotte for dedicated windows support
(defun lem-rotate-windows (count)
  "Rotate your windows.
  Dedicated windows are left untouched. Giving a negative prefix
  argument takes the kindows rotate backwards."
  (interactive "p")
  (let* ((non-dedicated-windows (cl-remove-if 'window-dedicated-p (window-list)))
         (num-windows (length non-dedicated-windows))
         (i 0)
         (step (+ num-windows count)))
    (cond ((not (> num-windows 1))
           (message "You can't rotate a single window!"))
          (t
           (dotimes (counter (- num-windows 1))
             (let* ((next-i (% (+ step i) num-windows))

                    (w1 (elt non-dedicated-windows i))
                    (w2 (elt non-dedicated-windows next-i))

                    (b1 (window-buffer w1))
                    (b2 (window-buffer w2))

                    (s1 (window-start w1))
                    (s2 (window-start w2)))
               (set-window-buffer w1 b2)
               (set-window-buffer w2 b1)
               (set-window-start w1 s2)
               (set-window-start w2 s1)
               (setq i next-i)))))))

(defun lem-rotate-windows-backward (count)
  "Rotate your windows backward."
  (interactive "p")
  (lem-rotate-windows (* -1 count)))

;;;;; Focus Window Split
;; Easy split and move functions
(defun lem-split-window-right-and-focus ()
  "Split the window horizontally and focus the new window."
  (interactive)
  (require 'windmove)
  (split-window-right)
  (windmove-right))

(defun lem-split-window-below-and-focus ()
  "Split the window vertically and focus the new window."
  (interactive)
  (require 'windmove)
  (split-window-below)
  (windmove-down))

;;;;; Toggle Window Split
(defun lem-toggle-window-split ()
  "Move from a horizontal to a vertical split and vice versa."
  (interactive)
  (if (= (count-windows) 2)
      (let* ((this-win-buffer (window-buffer))
             (next-win-buffer (window-buffer (next-window)))
             (this-win-edges (window-edges (selected-window)))
             (next-win-edges (window-edges (next-window)))
             (this-win-2nd (not (and (<= (car this-win-edges)
                                         (car next-win-edges))
                                     (<= (cadr this-win-edges)
                                         (cadr next-win-edges)))))
             (splitter
              (if (= (car this-win-edges)
                     (car (window-edges (next-window))))
                  'split-window-horizontally
                'split-window-vertically)))
        (delete-other-windows)
        (let ((first-win (selected-window)))
          (funcall splitter)
          (if this-win-2nd (other-window 1))
          (set-window-buffer (selected-window) this-win-buffer)
          (set-window-buffer (next-window) next-win-buffer)
          (select-window first-win)
          (if this-win-2nd (other-window 1))))))

;;;;; Jump to Minibuffer Window
(defun sp-goto-minibuffer-window ()
  "locate point to minibuffer window if it is active."
  (interactive)
  (if (active-minibuffer-window)
      (select-window (active-minibuffer-window))
    (error "Minibuffer is not active")))

(bind-key "C-c m" #'sp-goto-minibuffer-window)

;;;; Buffer Functions
;;;;; Blank Buffer New Frame
;; Make a blank buffer when opening a new frame. From
;; https://stackoverflow.com/a/25792276.

(defun lem-new-buffer-new-frame ()
  "Create a new frame with a new empty buffer."
  (interactive)
  (let ((buffer (generate-new-buffer "untitled")))
    (set-buffer-major-mode buffer)
    (display-buffer buffer '(display-buffer-pop-up-frame . nil))))


;;;;; Create new buffer
(defun lem-create-new-buffer ()
  "Create a new buffer in the default major mode."
  (interactive)
  (let ((buffer (generate-new-buffer "*new*")))
    (set-window-buffer nil buffer)
    (with-current-buffer buffer
      (funcall (default-value 'major-mode)))))

;;;;; Create New Elisp Buffer
(defun lem-create-new-elisp-buffer ()
  "Create a new buffer in `'emacs-lisp-mode'."
  (interactive)
  (let ((buffer (generate-new-buffer "*elisp*")))
    (set-window-buffer nil buffer)
    (with-current-buffer buffer
      (emacs-lisp-mode))))

;;;;; Make Temp Buffer
(defun lem-tmp-buffer()
  "Make a temporary buffer and switch to it."
  (interactive)
  (switch-to-buffer (get-buffer-create (concat "tmp-" (format-time-string "%m.%dT%H.%M.%S"))))
  (delete-other-windows))

;;;;; Revert all buffers
;;
(defun lem-revert-all-file-buffers ()
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
(defun lem-copy-whole-buffer-to-clipboard ()
  "Copy entire buffer to clipboard"
  (interactive)
  (clipboard-kill-ring-save (point-min) (point-max)))

(defun lem-copy-clipboard-to-whole-buffer ()
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

(defun lem-next-user-buffer ()
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

(defun lem-previous-user-buffer ()
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

(defun lem-eval-buffer-until-error ()
  "Evaluate emacs buffer until error occured."
  (interactive)
  (goto-char (point-min))
  (while t (eval (read (current-buffer)))))

;;;;; Kill Current Buffer
;; (kill-this-buffer) is unreliable when not invoked from the menubar. So here's a
;; wrapper on (kill-buffer) to kill the current buffer. This is sometimes better
;; than (evil-delete-buffer) since it keeps the window.

(defun lem-kill-this-buffer ()
  (interactive)
  (kill-buffer))

;;;;; Show Filename of Buffer

;; http://camdez.com/blog/2013/11/14/emacs-show-buffer-file-name/
(defun lem-show-and-copy-buffer-full-filename ()
  "Show the full path to the current file in the minibuffer and copy to clipboard."
  (interactive)
  (let ((file-name (buffer-file-name)))
    (if file-name
        (progn
          (message file-name)
          (kill-new file-name))
      (error "Buffer not visiting a file"))))

(defun lem-show-and-copy-buffer-filename ()
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

(defun lem-delete-current-buffer-file ()
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
(defun lem-get-string-from-file (filePath)
  "Read a file and return the contents as a string"
  (with-temp-buffer
    (insert-file-contents filePath)
    (buffer-string)))


;;;;; Duplicate file
;; Duplicate a file in dired or deer
(defun lem-duplicate-file ()
  (interactive)
  (dired-do-copy-regexp "\\(.*\\)\\.\\(.*\\)" "\\1 (copy).\\2"))

;;;;; Move File
(defun lem-move-file ()
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

(defun lem-insert-time-string ()
  "Insert year, day, hour, month, and second as a single string
      with no seperation"
  (interactive)
  (insert (format-time-string "%Y%d%H%M%S")))

(defun lem-insert-time-seconds-epoch ()
  "Insert the integer number of seconds since the epoch."
  (interactive)
  (insert (format-time-string "%s")))
;; (keymap-global-set "C-c e") 'lem-insert-time-seconds-epoch)

;;;;; Insert Comment Seperator
;; ======================================================
;; Insert commented seperator like this line
;; ======================================================
;; https://github.com/kuanyui/writing-utils.el/blob/db29d30e11b6d6d96c0d351b642af97631f3365f/writing-utils.el#L85

(defun lem-insert-commented-separator()
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
(defun lem-insert-weather ()
  "Insert `'wttr.in' weather forecast in buffer."
  (interactive)
  (let ((w (shell-command-to-string "curl -s 'wttr.in/?0qT' | head -n10")))
    (insert (mapconcat (function (lambda (x) (format ": %s" x)))
                       (split-string w "\n")
                       "\n")))
  (newline))

;;;;; Clipboard Transforms Using Pandoc
(defun lem-org-to-markdown ()
  "convert clipboard contents from org to markdown and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t markdown"))
  (yank))

(defun lem-markdown-to-org ()
  "convert clipboard contents from markdown to org and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f markdown -t org"))
  (yank))

(defun lem-tex-to-org ()
  "convert clipboard contents from markdown to org and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f latex -t org"))
  (yank))

(defun lem-org-to-tex ()
  "convert clipboard contents from org to tex and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t latex"))
  (yank))

(defun lem-tex-to-markdown ()
  "convert clipboard contents from markdown to org and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f latex -t markdown --markdown-headings=atx"))
  (yank))

(defun lem-markdown-to-tex ()
  "convert clipboard contents from markdown to org and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f markdown -t latex"))
  (yank))

(defun lem-cite-to-org ()
  "convert clipboard contents from markdown to org with citations and paste"
  (interactive)
  (kill-new (shell-command-to-string (concat "pbpaste | pandoc --bibliography=" lem-bibliography " -s -t markdown-native_divs-raw_html-citations | pandoc -f markdown -t org")))
  (yank))

(defun lem-cite-to-markdown ()
  "convert clipboard contents to markdown with citations and paste"
  (interactive)
  (kill-new (shell-command-to-string (concat "pbpaste | pandoc --bibliography=" lem-bibliography " -s -t markdown-native_divs-raw_html-citations --markdown-headings=atx")))
  (yank))

(defun lem-bibtex-to-yaml-reference ()
  "convert clipboard bibtex contents to yaml and paste"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc-citeproc -y -f bibtex | pbcopy"))
  (yank))

(defun lem-md-to-rtf ()
  "convert md to rtf and send to clipboard"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f markdown -t rtf | pbcopy"))
  (yank))


;; NOTE: piping to pbcopy doesn't seem to work but it is ready to paste as is
(defun lem-org-to-rtf ()
  "convert org to rtf and send to clipboard"
  (interactive)
  (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t html | /usr/bin/textutil -stdin -stdout -format html -convert rtf -fontsize 14 -font Helvetica | pbcopy")))

(defun lem-org-to-mail-rtf ()
  "copy buffer, convert clipboard contents from org to rtf, and send to mail message"
  (interactive)
  (lem-copy-whole-buffer-to-clipboard)
  ;; (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t rtf"))
  (kill-new (shell-command-to-string "pbpaste | pandoc -f org -t html | /usr/bin/textutil -stdin -stdout -format html -convert rtf -fontsize 14 | pbcopy"))
  (kill-buffer)
  (delete-frame)
  (do-applescript "if application \"Mail\" is running then
      tell application \"Mail\"
      activate
      delay 0.35
      tell application \"System Events\"
      keystroke \"v\" using {command down}
      end tell
      end tell
      end if"))

;;;;; Smart Yanking
;;Courtesy of Marcin Borkowski http://mbork.pl/2018-07-02_Smart_yanking

(defun has-space-at-boundary-p (string)
  "Check whether STRING has any whitespace on the boundary.
      Return 'left, 'right, 'both or nil."
  (let ((result nil))
    (when (string-match-p "^[[:space:]]+" string)
      (setq result 'left))
    (when (string-match-p "[[:space:]]+$" string)
      (if (eq result 'left)
          (setq result 'both)
        (setq result 'right)))
    result))

(defun is-there-space-around-point-p ()
  "Check whether there is whitespace around point.
      Return 'left, 'right, 'both or nil."
  (let ((result nil))
    (when (< (save-excursion
               (skip-chars-backward "[:space:]"))
             0)
      (setq result 'left))
    (when (> (save-excursion
               (skip-chars-forward "[:space:]"))
             0)
      (if (eq result 'left)
          (setq result 'both)
        (setq result 'right)))
    result))

(defun set-point-before-yanking (string)
  "Put point in the appropriate place before yanking STRING."
  (let ((space-in-yanked-string (has-space-at-boundary-p string))
        (space-at-point (is-there-space-around-point-p)))
    (cond ((and (eq space-in-yanked-string 'left)
                (eq space-at-point 'left))
           (skip-chars-backward "[:space:]"))
          ((and (eq space-in-yanked-string 'right)
                (eq space-at-point 'right))
           (skip-chars-forward "[:space:]")))))

(defun set-point-before-yanking-if-in-text-mode (string)
  "Invoke `set-point-before-yanking' in text modes."
  (when (derived-mode-p 'text-mode)
    (set-point-before-yanking string)))

(advice-add
 'insert-for-yank
 :before
 #'set-point-before-yanking-if-in-text-mode)
;; http://lists.gnu.org/archive/html/help-gnu-emacs/2007-05/msg00975.html

;;;;; Wrap in Yaml block
(defun lem-yaml-wrap ()
  "wrap region in --- for a yaml block"
  (interactive)
  (let ((start (region-beginning))
        (end (region-end)))
    (goto-char end)
    (insert "---" "\n")
    (goto-char start)
    (insert "---" "\n")))

;;;;; Jump to sexp

(defun lem-forward-or-backward-sexp (&optional arg)
  "Go to the matching parenthesis character if one is adjacent to point."
  (interactive "^p")
  (cond ((looking-at "\\s(") (forward-sexp arg))
        ((looking-back "\\s)" 1) (backward-sexp arg))
        ;; Now, try to succeed from inside of a bracket
        ((looking-at "\\s)") (forward-char) (backward-sexp arg))
        ((looking-back "\\s(" 1) (backward-char) (forward-sexp arg))))

;;;; UI Functions
;;;;; Toggle markup
(defun lem-toggle-display-markup ()
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

;;;;; Quit Message Function
(defun sp--quit-p (&optional prompt)
  "Return t if this session should be killed. Prompts the user for
      confirmation."
  (or (yes-or-no-p (format "››› %s" (or prompt "Quit Emacs?")))
      (ignore (message "Aborted"))))
(setq confirm-kill-emacs nil)
(add-hook 'kill-emacs-query-functions #'sp--quit-p)
(defvar lem-quit-messages
  '(;; from Doom
    "Let's beat it -- This is turning into a bloodbath!"
    "I wouldn't leave if I were you. DOS is much worse."
    "Ya know, next time you come in here I'm gonna toast ya."
    "Go ahead and leave. See if I care."
    "Are you sure you want to quit this great editor?"
    ;; Custom
    "Emacs! Emacs!! Emacs!!!"
    "The King is dead, long live the King!"
    "Like you have somewhere better to be..."
    "Don't worry, I won't tell everyone you're a failure"
    "Aus so krummem Holze, als woraus der Mensch gemacht ist, kann nichts ganz Gerades gezimmert werden"
    "Sed omnia praeclara tam difficilia, quam rara sunt"
    "(setq nothing t everything 'permitted)"
    "Emacs will remember that."
    "Emacs, Emacs never changes."
    "Hey! Hey, M-x listen!"
    "Okay, look. We've both said a lot of things you're going to regret..."
    "You are *not* prepared!")
  "A list of quit messages, picked randomly by `lem-quit'. Taken from
      http://doom.wikia.com/wiki/Quit_messages and elsewhere.")

(defun sp--quit (&rest _)
  (sp--quit-p
   (format "%s  Quit?"
           (nth (random (length lem-quit-messages))
                lem-quit-messages))))

(remove-hook 'kill-emacs-query-functions #'sp--quit-p)
(add-hook 'kill-emacs-query-functions #'sp--quit)

;; Other functions to look through (this is an archive)
;; Emacs Writing Studio Customisation

(defcustom sia-org-heading-level-capitalise nil
  "Minimum level of Org headings to be capitalised
Nil implies all levels are capitalised."
  :group 'ews
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

;;; BIBLIOGRAPHY
(defvar sp-bibtex-files
  (when (file-exists-p sp-bibtex-dir)
    (directory-files sp-bibtex-dir t "^[A-Z|a-z|0-9].+.bib$"))
  "List of BibTeX files. Use `sia-bibtex-register' to configure.")

;;;###autoload
(defun sia-bibtex-register ()
  "Register the contents of the `sp-bibtex-dir' with `sp-bibtex-files`.
Use when adding or removing a BibTeX file from or to `sp-bibtex-dir'."
  (interactive)
  (when (file-exists-p sp-bibtex-dir)
    (let ((bib-files (directory-files sp-bibtex-dir t
				      "^[A-Z|a-z|0-9].+.bib$")))
      (setq sp-bibtex-files bib-files
  	    org-cite-global-bibliography bib-files
	    citar-bibliography bib-files)))
  (message "Registered:\n%s" (mapconcat #'identity sp-bibtex-files "\n")))

(defun sp--bibtex-combined-biblio-lookup ()
  "Combines `biblio-lookup' and `biblio-doi-insert-bibtex'."
  (require 'biblio)
  (let* ((dbs (biblio--named-backends))
         (db-list (append dbs '(("DOI" . biblio-doi-backend))))
         (db-selected (biblio-completing-read-alist
                       "Backend:"
                       db-list)))
    (if (eq db-selected 'biblio-doi-backend)
        (let ((doi (read-string "DOI: ")))
          (biblio-doi-insert-bibtex doi))
      (biblio-lookup db-selected))))

;;;###autoload
(defun sia-bibtex-biblio-lookup ()
  "Insert Biblio search results into current buffer or select BibTeX file."
  (interactive)
  (if-let ((current-mode major-mode)
	   sp-bibtex-files
	   (bibfiles (length sp-bibtex-files))
	   (bibfile (cond ((eq bibfiles 1) (car sp-bibtex-files))
			  ((equal major-mode 'bibtex-mode)
			   (buffer-file-name))
			  (t (completing-read
			      "Select BibTeX file:" sp-bibtex-files)))))
      (progn (find-file bibfile)
	     (goto-char (point-max))
	     (sp--bibtex-combined-biblio-lookup)
	     (save-buffer))
    (message "No BibTeX file(s) defined.")))

;; Search for missing BibTeX attachments and filenames
(defun sp--bibtex-extract-attachments ()
  "Extract attachment file names from BibTeX files in `sp-bibtex-dir'."
  (sia-bibtex-register)
  (let ((attachments '()))
    (dolist (bibtex-file sp-bibtex-files)
      (with-temp-buffer
        (insert-file-contents bibtex-file)
        (goto-char (point-min))
        (while (re-search-forward "file.*=.*{\\([^}]+\\)}" nil t)
          (let ((file-paths (split-string (match-string 1)
                                          "[[:space:]]*;[[:space:]]*")))
            (dolist (file-path file-paths)
              (push (expand-file-name (string-trim file-path)
                                      sp-bibtex-dir)
                    attachments))))))
    attachments))

(defun sp--bibtex-extract-files ()
  "List files recursively in `sp-bibtex-dir', excluding `.bib' and `.csl'."
  (seq-remove (lambda (file)
                (or (string-suffix-p ".bib" file)
                    (string-suffix-p ".csl" file)))
              (mapcar 'expand-file-name
                      (directory-files-recursively sp-bibtex-dir ""))))

;;;###autoload
(defun sia-bibtex-missing-files ()
  "List BibTeX attachments not listed in a BibTeX file entry."
  (interactive)
  (let* ((files (sp--bibtex-extract-files))
         (attachments (sp--bibtex-extract-attachments))
         (missing (cl-remove-if
                   (lambda (f) (member f attachments)) files)))
    (message "%s files not registered in bibliography" (length missing))
    (dolist (file missing)
      (message file))))

;;;###autoload
(defun sia-bibtex-missing-attachments ()
  "List BibTeX file entries with missing attachment(s)."
  (interactive)
  (let* ((files (sp--bibtex-extract-files))
         (attachments (sp--bibtex-extract-attachments))
         (missing (cl-remove-if
                   (lambda (f) (member f files)) attachments)))
    (message "%s BibTeX files without matching attachment." (length missing))
    (dolist (file missing)
      (message file))))

;; Denote
;; Distraction-free writing
(defvar sia-olivetti-point nil
  "Stores the point position before enabling Olivetti mode.")

;;;###autoload
(defun sia-olivetti ()
  "Distraction-free writing environment enhancing Olivetti mode.

Stores the window configuration when enabling Olivetti mode.
Restores the previous configuration when existing Olivetti mode
and moves point to the last location."
  (interactive)
  (if olivetti-mode
      (progn
        (if (eq (length (window-list)) 1)
            (progn
              (jump-to-register 1)
              (goto-char sia-olivetti-point)))
        (olivetti-mode 0)
        (text-scale-set 0))
    (progn
      (setq sia-olivetti-point (point))
      (window-configuration-to-register 1)
      (delete-other-windows)
      (text-scale-set 1)
      (olivetti-mode t))))

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

;;; Provide
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(provide 'sp-other-functions)
;;; sp-other-functions.el ends here
