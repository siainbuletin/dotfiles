;; -*- lexical-binding: t; -*-
;;; sp-splash.el --- An alternative splash screen

;;; Commentary:
;;
;;  An alternative splash screen:
;; this is also including the ascii art of the lambda sign, which will show up in the dashboard
;; I gotta test to see if it works with the dashboard

;; Note: The screen is not shown if there are opened file buffers. For
;;       example, if you start emacs with a filename on the command
;;       line, the splash is not shown.

;;; Code:
(require 'cl-lib)
;; Guarded require: without this, a sandbox boot with sp-load-extras
;; nil and no nerd-icons installed would crash module-load here.
;; Spec 02 caught the identical pattern in sp-dashboard.el.
(when (locate-library "nerd-icons")
  (require 'nerd-icons))

(defgroup sp-splash nil
  "Extensible splash screen."
  :group 'applications)

;;;; Splash Faces
(defface sp-splash-title-face nil
  "Face for splash title."
  :group 'faces)

(defface sp-splash-header-face nil
  "Face for splash header."
  :group 'faces)

(defface sp-splash-footer-face nil
  "Face for splash footer."
  :group 'faces)

(defface sp-splash-menu-face nil
  "Face for splash menus."
  :group 'faces)

(defface sp-splash-image-face nil
  "Face for splash image."
  :group 'faces)

;;;; Splash Variables

;; Init info
;; See https://github.com/emacs-dashboard/emacs-dashboard/blob/master/dashboard-widgets.el
;; https://github.com/hlissner/doom-emacs/blob/eddaae40e84b5eb1f0136aaba23d918f71b6a986/core/core.el#L479
(defcustom sp-splash-init-info
  (lambda ()
    (let ((package-count 0) (time (emacs-init-time)))
      (cond ((bound-and-true-p package-alist)
             (setq package-count (length package-activated-list)))
            ((boundp 'straight--profile-cache)
             (setq package-count (+ (hash-table-count straight--profile-cache) package-count))))
      (if (zerop package-count)
          (format "Emacs started in %s" time)
        (format "%d packages loaded in %s" package-count time))))
  "Init info with packages loaded and init time."
  :type '(function string)
  :group 'sp-splash)

;; Banner

;; Banner
(defcustom sp-splash-banner nil
  "Banner picture for splash-screen"
  :type '(string)
  :group 'sp-splash)

(defvar isep "   "
  "Separator for icon and title.")
(defvar ksep "   "
  "Separator for title and key.")

;;;; Lambda art
;; The lambda in `lambda-splash.txt' is drawn behind the menu: it only fills
;; blanks, so the title and the menu buttons stay on top of it.
(defface sp-splash-art-face
  '((((background dark))  :foreground "#454b5c")
    (((background light)) :foreground "#cfd3dc"))
  "Face for the lambda art behind the splash menu.
The colour follows the background of the current theme, so it changes
with `load-theme' the next time the splash is drawn."
  :group 'faces)

(defcustom sp-splash-art-file "lambda-splash.txt"
  "Text file with the art drawn behind the menu.
A relative name is looked up in `sp-library-dir'.  Nil draws the
lambda logo image instead."
  :type '(choice (const :tag "Use the logo image" nil) file)
  :group 'sp-splash)

(defcustom sp-splash-art-x-offset -50
  "Columns to move the art right (negative: left).
Zero centres the art on the menu."
  :type 'integer
  :group 'sp-splash)

(defcustom sp-splash-art-y-offset 10
  "Lines to move the art down (negative: up).
Zero centres the art on the menu."
  :type 'integer
  :group 'sp-splash)

(defcustom sp-splash-art-x-step 2
  "Columns `sp-splash-art-right' and `sp-splash-art-left' move the art."
  :type 'integer
  :group 'sp-splash)

(defcustom sp-splash-art-y-step 1
  "Lines `sp-splash-art-up' and `sp-splash-art-down' move the art."
  :type 'integer
  :group 'sp-splash)

(defun sp-splash--art-lines ()
  "Return the lines of `sp-splash-art-file', or nil when unavailable."
  (when sp-splash-art-file
    (let ((file (expand-file-name sp-splash-art-file sp-library-dir)))
      (when (file-readable-p file)
        (let ((lines (with-temp-buffer
                       (insert-file-contents file)
                       (split-string (buffer-string) "\n"))))
          ;; Drop blank lines at the end so they don't count as height.
          (while (and lines (string-blank-p (car (last lines))))
            (setq lines (butlast lines)))
          lines)))))

(defun sp-splash--draw-art (first-line last-line)
  "Draw the art behind the menu spanning FIRST-LINE to LAST-LINE.
Only plain blanks are replaced, so text, buttons and images are kept."
  (when-let* ((lines (sp-splash--art-lines)))
    (let* ((inhibit-read-only t)
           (indent-tabs-mode nil)
           (art-width (apply #'max (mapcar #'length lines)))
           (menu-middle (/ (+ first-line last-line) 2))
           (top (+ (- menu-middle (/ (length lines) 2))
                   sp-splash-art-y-offset))
           (menu-center (+ (max 0 (/ (- (window-width) (length "Welcome to λ-Emacs")) 2))
                           9))
           (left (+ (- menu-center (/ art-width 2))
                    sp-splash-art-x-offset))
           (max-line (window-body-height))
           (row 0))
      (dolist (text lines)
        (let ((line (+ top row)))
          (when (and (>= line 1) (<= line max-line))
            ;; Grow the buffer when the art runs past its last line.
            (goto-char (point-max))
            (while (< (line-number-at-pos) line)
              (insert-char ?\n 1))
            (goto-char (point-min))
            (forward-line (1- line))
            (dotimes (i (length text))
              (let ((ch (aref text i))
                    (col (+ left i)))
                (when (and (/= ch ?\s) (>= col 0))
                  (sp-splash--put-art-char col ch)
                  (forward-line 0)))))
          (setq row (1+ row)))))))

(defun sp-splash--put-art-char (col ch)
  "Put CH in the art face at column COL of the current line if it is blank."
  (move-to-column col)
  (cond ((and (eolp) (<= (current-column) col))
         (insert-char ?\s (- col (current-column)))
         (insert (propertize (string ch) 'face 'sp-splash-art-face)))
        ((and (= (current-column) col)
              (eq (char-after) ?\s)
              (not (get-text-property (point) 'face))
              (not (get-text-property (point) 'button))
              (not (get-text-property (point) 'display)))
         (delete-char 1)
         (insert (propertize (string ch) 'face 'sp-splash-art-face)))))

;;;; Move the art
(defun sp-splash-art-nudge (dx dy)
  "Move the art DX columns right and DY lines down, and redraw the splash."
  (setq sp-splash-art-x-offset (+ sp-splash-art-x-offset dx)
        sp-splash-art-y-offset (+ sp-splash-art-y-offset dy))
  (message "Splash art offset: x %d, y %d" sp-splash-art-x-offset sp-splash-art-y-offset)
  (sp-splash-refresh))

(defun sp-splash-art-left ()
  "Move the splash art left."
  (interactive)
  (sp-splash-art-nudge (- sp-splash-art-x-step) 0))

(defun sp-splash-art-right ()
  "Move the splash art right."
  (interactive)
  (sp-splash-art-nudge sp-splash-art-x-step 0))

(defun sp-splash-art-up ()
  "Move the splash art up."
  (interactive)
  (sp-splash-art-nudge 0 (- sp-splash-art-y-step)))

(defun sp-splash-art-down ()
  "Move the splash art down."
  (interactive)
  (sp-splash-art-nudge 0 sp-splash-art-y-step))

(defun sp-splash-art-reset ()
  "Put the splash art back at the default position."
  (interactive)
  (setq sp-splash-art-x-offset (eval (car (get 'sp-splash-art-x-offset 'standard-value)))
        sp-splash-art-y-offset (eval (car (get 'sp-splash-art-y-offset 'standard-value))))
  (sp-splash-refresh))

(defun sp-splash-art-show-position ()
  "Show the current art offsets as a form to paste into the config.
The form is also copied to the kill ring."
  (interactive)
  (let ((form (format "(setq sp-splash-art-x-offset %d\n      sp-splash-art-y-offset %d)"
                      sp-splash-art-x-offset sp-splash-art-y-offset)))
    (kill-new form)
    (message "%s" form)))

;;;; Define Splash

(defun sp-splash--erase ()
  ;; check if splash exists and switch if so
  (when (get-buffer "*splash*")
    (switch-to-buffer "*splash*")
    (let ((inhibit-read-only t))
      (erase-buffer))))

(defun sp-splash-terminal ()
  "A custom splash screen for terminal Emacs"
  (interactive)
  ;; Switch to or create splash buffer
  (or (when (get-buffer "*splash*")
        (switch-to-buffer "*splash*"))
      ;; Hide modeline before window-body-height is computed
      (let* ((splash-buffer (get-buffer-create "*splash*")))
        (with-current-buffer splash-buffer
          (setq header-line-format nil)
          (setq mode-line-format nil)
          (erase-buffer))

        (let* ((buffer-read-only t)
               (midp  (/ (point-max) 2))
               (padding-top 3)
               (height (/ (window-height) 2))
	           (width (/ (window-width) 2))
               ;; Original ascii image from here:
               ;; https://github.com/Triagle/emax/blob/master/boot.txt
               (banner (sp-get-string-from-file (concat sp-library-dir "lambda-splash.txt"))))

          (with-current-buffer splash-buffer
            ;; Buffer local settings
            (if (one-window-p)
                (setq mode-line-format nil))
            (setq-local cursor-type nil)
            (setq vertical-scroll-bar nil)
            (setq horizontal-scroll-bar nil)
            (setq fill-column width)
            (face-remap-add-relative 'link :underline nil)
            (unless (and (display-graphic-p) sys-mac) (menu-bar-mode 0))
            ;; Set margin padding locally
            (setq-local left-margin-width (/ width 6)
                        right-margin-width (/ width 6))
            (set-window-buffer nil (current-buffer))
            ;; Add padding at top
            (insert-char ?\n 1)
            (unless sp-splash-banner
              ;; Insert text banner
              (insert banner))
            ;; Position point
            (goto-char (point-min))
            (forward-line (- (/ (window-height) 2) 10))
            (end-of-line)
            ;; Insert header text
            (insert-rectangle `(,(propertize "           Welcome to 𝛌-Emacs"  'face 'sp-splash-title-face)
                                ,(concat (propertize "         GNU Emacs version" 'face 'sp-splash-header-face)
                                         " "
                                         (propertize (format "%d.%d" emacs-major-version emacs-minor-version) 'face 'sp-splash-header-face))
                                ,(let ((init-info (funcall sp-splash-init-info)))
                                   (concat " " (propertize init-info 'face 'sp-splash-header-face)))))
            ;; ;; Vertical padding to bottom
            (goto-char (point-max))
            ;; Footer text
            (defvar sp-splash-footer "   " "Footer text.")
            (save-excursion (insert-char ?\s (- (/ (window-width) 4) 10))
                            (insert
                             (propertize sp-splash-footer 'face 'sp-splash-footer-face)))
            (goto-char (point-min))
            (display-buffer-same-window splash-buffer nil))
          (switch-to-buffer "*splash*"))
        (sp-splash-mode))))

(defun sp-splash-screen ()
  "A custom splash screen for Emacs.
Called interactively, it drops an existing *splash* buffer first so the
splash is drawn again with the current settings."
  (interactive)
  (when (and (called-interactively-p 'any) (get-buffer "*splash*"))
    (kill-buffer "*splash*"))
  ;; Switch to or create splash buffer
  (or (when (get-buffer "*splash*")
        (switch-to-buffer "*splash*"))
      ;; Hide modeline before window-body-height is computed
      (let* ((splash-buffer (get-buffer-create "*splash*")))
        (with-current-buffer splash-buffer
          (setq header-line-format nil)
          (setq mode-line-format nil)
          (erase-buffer))

        (let* ((buffer-read-only t)
               (midp  (/ (point-max) 2))
               (padding-top 3)
               (height (/ (window-height) 2))
	           (width (/ (window-width) 2))
               (image-scaling-factor 2.2)
               (menu-first-line 1)
               (menu-last-line 1)
               ;; scale icons
               (nerd-icons-scale-factor 1.10)
               (nerd-icons-default-adjust -0.02))

          (with-current-buffer splash-buffer
            ;; Buffer local settings
            (if (one-window-p)
                (setq mode-line-format nil))
            (setq-local cursor-type nil)
            (setq vertical-scroll-bar nil)
            (setq horizontal-scroll-bar nil)
            (setq fill-column width)
            (face-remap-add-relative 'link :underline nil)
            (unless (and (display-graphic-p) sys-mac) (menu-bar-mode 0))

            ;; Set margin padding locally
            (setq-local left-margin-width 0
                        right-margin-width (/ width 6))
            (set-window-buffer nil (current-buffer))

            ;; Add padding at top
            (insert-char ?\n padding-top)
            
            ;; Simple centered layout
            (let* ((center-col (max 0 (/ (- (window-width) 60) 2))))
              
              ;; Add the lambda image, centered and reasonably sized
              (when (and (> (window-width) 80) (> (window-height) 20)
                         (null (sp-splash--art-lines)))
                (let* ((image-file (if (eq (car custom-enabled-themes) 'lambda-dark)
                                       (concat sp-library-dir "lambda-logo-white.png")
                                     (concat sp-library-dir "lambda-logo-black.png")))
                       (image (create-image image-file 'png nil :width 175 :height 175)))
                  (insert-char ?\s (+ center-col 19))
                  (insert-image image)
                  (insert-char ?\n 2)))
              
              (let ((welcome-text "Welcome to λ-Emacs")
                    (version-text (format "GNU Emacs version %d.%d" emacs-major-version emacs-minor-version))
                    (init-info (funcall sp-splash-init-info)))
                
                ;; Welcome text
                (let ((welcome-center (max 0 (/ (- (window-width) (length welcome-text)) 2))))
                  (insert-char ?\s welcome-center)
                  (insert (propertize welcome-text 'face 'sp-splash-title-face))
                  (insert-char ?\n 2))
                
                ;; Version text
                (let ((version-center (max 0 (/ (- (window-width) (length version-text)) 2))))
                  (insert-char ?\s version-center)
                  (insert (propertize version-text 'face 'sp-splash-header-face))
                  (insert-char ?\n 1))
                
                ;; Init info
                (let ((init-center (max 0 (/ (- (window-width) (length init-info)) 2))))
                  (insert-char ?\s init-center)
                  (insert (propertize init-info 'face 'sp-splash-header-face))
                  (insert-char ?\n 2))))

            ;; Insert menu buttons - left-aligned as a group, group is centered
            (goto-char (point-max))
            (setq menu-first-line (line-number-at-pos))
            (let* ((button-indent (max 0 (/ (- (window-width) (length "Welcome to λ-Emacs")) 2)))
                   (button-labels '(("nf-fa-calendar" "Agenda" "a" sp-open-agenda-in-workspace "Open Agenda")
                                    ("nf-fa-code" "Config" "c" sp-open-emacsd-in-workspace "Visit config directory")
                                    ("nf-fa-envelope_o" "Mail" "m" sp-open-email-in-workspace "Open Email in Mu4e")
                                    ("nf-fa-book" "Notes" "n" sp-open-notes-in-workspace "Open notes directory")
                                    ("nf-fa-folder" "Projects" "p" tabspaces-open-or-create-project-and-workspace "Open project & workspace")))
                   (max-label-width (apply 'max (mapcar (lambda (item) (length (nth 1 item))) button-labels))))
            
              (dolist (button button-labels)
                (let* ((icon (nth 0 button))
                       (label (nth 1 button))
                       (key (nth 2 button))
                       (action (nth 3 button))
                       (help (nth 4 button))
                       (padded-label (format (format "%%-%ds" max-label-width) label)))
                  (insert-char ?\s button-indent)
                  (insert-text-button (concat (nerd-icons-faicon icon)
                                              isep 
                                              padded-label 
                                              ksep 
                                              "(" key ")")
                                      'action (lambda (_) (sp-splash--workspace-dispatch action))
                                      'help-echo help
                                      'face 'sp-splash-menu-face
                                      'follow-link t)
                  (insert-char ?\n 1))))
            (setq menu-last-line (1- (line-number-at-pos)))


            ;; Add footer with some space above bottom
            (goto-char (point-max))
            (let* ((current-line (line-number-at-pos))
                   (window-height (window-height))
                   (footer-padding (max 1 (- window-height current-line 15))))
              (insert-char ?\n footer-padding))
            
            ;; Footer text centered
            (defvar sp-splash-footer "   " "Footer text.")
            (let ((footer-center (max 0 (/ (- (window-width) (length sp-splash-footer)) 2))))
              (insert-char ?\s footer-center)
              (insert (propertize sp-splash-footer 'face 'sp-splash-footer-face)))

            ;; Lambda art behind the menu (a no-op when the art is off)
            (sp-splash--draw-art menu-first-line menu-last-line)

            (goto-char (point-min))
            (display-buffer-same-window splash-buffer nil))
          (switch-to-buffer "*splash*"))
        (sp-splash-mode))))

;;;;; Set Splash Footer
;; Set a footer for the splash screen
(setq sp-splash-footer  "wawawewa")

(defun sp-splash-screen-bury ()
  "Bury the splash screen buffer (immediately)."
  (interactive)
  (when (get-buffer "*splash*")
    (bury-buffer)))

(defun sp-splash-screen-kill ()
  "Kill the splash screen buffer (immediately)."
  (interactive)
  (when (get-buffer "*splash*")
    (kill-buffer)))

;;;; Workspace Dispatch
(defun sp-splash--workspace-dispatch (fn)
  "Call FN when it is defined, otherwise prompt to enable the workspaces module."
  (if (fboundp fn)
      (funcall fn)
    (message "Enable the workspaces module (sp-workspaces) for this action")))

(defun sp-splash-open-agenda ()
  "Open the agenda workspace from the splash screen."
  (interactive)
  (sp-splash--workspace-dispatch 'sp-open-agenda-in-workspace))

(defun sp-splash-open-config ()
  "Open the emacs.d workspace from the splash screen."
  (interactive)
  (sp-splash--workspace-dispatch 'sp-open-emacsd-in-workspace))

(defun sp-splash-open-email ()
  "Open the email workspace from the splash screen."
  (interactive)
  (sp-splash--workspace-dispatch 'sp-open-email-in-workspace))

(defun sp-splash-open-notes ()
  "Open the notes workspace from the splash screen."
  (interactive)
  (sp-splash--workspace-dispatch 'sp-open-notes-in-workspace))

(defun sp-splash-open-project ()
  "Open a project workspace from the splash screen."
  (interactive)
  (sp-splash--workspace-dispatch 'sp-open-existing-project-and-workspace))

;;;; Define Minor Mode
;; Custom splash screen
(defvar sp-splash-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") 'sp-splash-open-agenda)
    (define-key map (kbd "c") 'sp-splash-open-config)
    (define-key map (kbd "m") 'sp-splash-open-email)
    (define-key map (kbd "n") 'sp-splash-open-notes)
    (define-key map (kbd "p") 'sp-splash-open-project)
    (define-key map (kbd "S-<left>") 'sp-splash-art-left)
    (define-key map (kbd "S-<right>") 'sp-splash-art-right)
    (define-key map (kbd "S-<up>") 'sp-splash-art-up)
    (define-key map (kbd "S-<down>") 'sp-splash-art-down)
    (define-key map (kbd "0") 'sp-splash-art-reset)
    (define-key map (kbd "s") 'sp-splash-art-show-position)
    (define-key map (kbd "q") 'sp-splash-screen-kill)
    (define-key map (kbd "<escape>") 'sp-splash-screen-bury)
    (define-key map (kbd "k") 'sp-splash-screen-kill)
    map)
  "Keymap for sp-splash-mode.")

(define-minor-mode sp-splash-mode
  "Emacs minor mode for splash screen."
  :global nil
  :keymap sp-splash-mode-map
  :group 'sp-splash
  
  :require 'sp-splash
  (buffer-disable-undo)
  (auto-revert-mode -1)
  (whitespace-mode -1)
  (when (fboundp 'linum-mode)
    (linum-mode -1))
  (when (>= emacs-major-version 26)
    (display-line-numbers-mode -1))
  
  (setq-local buffer-read-only t)
  (setq-local cursor-type nil)
  (setq-local hl-line-mode -1)
  (setq-local mode-line-format nil)
  (setq-local header-line-format nil)
  
  ;; No margin or fringe in splash buffer
  (setq-local left-margin-width nil
              right-margin-width nil)
  (set-window-fringes (selected-window) 0 0 nil)
  (setq inhibit-startup-screen t
        truncate-lines nil
        inhibit-startup-message t
        inhibit-startup-echo-area-message t)
  
  ;; Use Emacs state if Evil is active so single-key bindings work
  (when (bound-and-true-p evil-mode)
    (evil-emacs-state))
  (goto-char (point-min)))

;;;; Splash Setup & Refresh Functions
(defun sp-splash-refresh ()
  "Refresh & recenter splash after window switch."
  (interactive)
  (when (string= (buffer-name) "*splash*")
    (progn
      (ignore-errors
        (sp-splash-screen-kill)
        (sp-splash-screen)))))

(defun sp-splash--setup-splash-hooks ()
  "Initialize splash and setup hooks."
  (progn
    (if (display-graphic-p)
        (sp-splash-screen)
      (sp-splash-terminal))
    (add-hook 'window-state-change-hook #'sp-splash-refresh)
    (add-hook 'window-configuration-change-hook  #'sp-splash-refresh)
    (add-hook 'sp-switch-buffer-hook #'sp-splash-refresh)))

;; Install hook after frame parameters have been applied and only if
;; no option on the command line
(when (and (not (member "--no-splash" command-line-args))
           (not (member "--file"      command-line-args))
           (not (member "--insert"    command-line-args))
           (not (member "--find-file" command-line-args)))
  (add-hook 'window-setup-hook #'sp-splash--setup-splash-hooks))

;;; Provide:

(provide 'sp-splash)
;;; sp-splash.el ends here