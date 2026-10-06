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
  :group 'lambda-splash)

;; Banner

;; Banner
(defcustom sp-splash-banner nil
  "Banner picture for splash-screen"
  :type '(string)
  :group 'lambda-splash)

(defvar isep "   "
  "Separator for icon and title.")
(defvar ksep "   "
  "Separator for title and key.")

;;;; Define Splash

(defun sp-splash--erase ()
  ;; check if splash exists and switch if so
  (when-let* ((inhibit-read-only t))
    (get-buffer "*splash*")
    (switch-to-buffer "*splash*")
    (erase-buffer)))

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
  "A custom splash screen for Emacs"
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
               (image-scaling-factor 2.2)
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
              (when (and (> (window-width) 80) (> (window-height) 20))
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

            (goto-char (point-min))
            (display-buffer-same-window splash-buffer nil))
          (switch-to-buffer "*splash*"))
        (sp-splash-mode))))

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
    (define-key map (kbd "q") 'sp-splash-screen-kill)
    (define-key map (kbd "<escape>") 'sp-splash-screen-bury)
    (define-key map (kbd "k") 'sp-splash-screen-kill)
    map)
  "Keymap for sp-splash-mode.")

(define-minor-mode sp-splash-mode
  "Emacs minor mode for splash screen."
  :global nil
  :keymap sp-splash-mode-map
  :group 'lambda-emacs
  
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

(provide 'sp-splash)
;;; sp-splash.el ends here