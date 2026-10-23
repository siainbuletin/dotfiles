;; -*- lexical-binding: t; -*-
;;; sp-tabs.el

;;; Commentary:

;; Tabs -- in some ways tabs are not very Emacsy, but tab-bar is great for
;; window & buffer management. The setup for tabs here is focused on tabs for
;; window configurations related to a "workspace" -- i.e. a project or other set
;; of windows. A workspace or "tabspace" (see the package below) is just a tab
;; with an isolated set of buffers (see also the consult function). 𝛌-Emacs (and
;; 𝛌-Themes) sets things up so that these tabs/workspaces are nicely displayed.

;;;; Tab Bar
;; Use tab-bar for window grouping and configuration within a project (replaces eyebrowse)

;; https://christiantietze.de/posts/2022/02/emacs-tab-bar-numbered-tabs/
(defvar lem-tab-bar--circle-numbers-alist
  '((0 . "⓪")
    (1 . "①")
    (2 . "②")
    (3 . "③")
    (4 . "④")
    (5 . "⑤")
    (6 . "⑥")
    (7 . "⑦")
    (8 . "⑧")
    (9 . "⑨")
    (10 . "⑩")
    (11 . "⑪")
    (12 . "⑫")
    (13 . "⑬")
    (14 . "⑭")
    (15 . "⑮"))

  "Alist of integers to strings of circled unicode numbers.")
(defun lem--tab-bar-tab-name-format (tab i)
  (let ((current-p (eq (car tab) 'current-tab))
        (tab-num (if (and tab-bar-tab-hints (< i 16))
                     (alist-get i lem-tab-bar--circle-numbers-alist) "")))
    (propertize
     (concat
      " "
      tab-num
      (propertize " " 'display '(space :width (4)))
      (alist-get 'name tab)
      (or (and tab-bar-close-button-show
               (not (eq tab-bar-close-button-show
                        (if current-p 'non-selected 'selected)))
               tab-bar-close-button)
          "")
      (propertize " " 'display '(space :width (4))))
     'face (funcall tab-bar-tab-face-function tab))))

;; See https://github.com/rougier/nano-modeline/issues/33
(defun lem--tab-bar-suffix ()
  "Add empty space.
This ensures that the last tab's face does not extend to the end
of the tab bar."
  " ")

(use-package tab-bar
  :ensure nil
  :after (project)
  :commands (tab-bar-new-tab
             tab-bar-switch-to-tab
             tab-bar-switch-to-next-tab
             tab-bar-switch-to-prev-tab)
  :custom
  ;; Set this to nil unless tab bar is in use
  (tab-bar-show nil)
  (tab-bar-tab-hints t) ;; show numbers in tabs
  ;; Unless another file/buffer is designated, start from workspace scratch buffer
  (tab-bar-new-tab-choice "*scratch*")
  (tab-bar-select-tab-modifiers '(super))
  (tab-bar-close-tab-select 'recent)
  (tab-bar-new-tab-to 'rightmost)
  (tab-bar-close-last-tab-choice 'tab-bar-mode-disable)
  (tab-bar-tab-name-format-function #'lem--tab-bar-tab-name-format)
  (tab-bar-new-button nil)
  (tab-bar-close-button nil)
  (tab-bar-close-button-show nil)
  (tab-bar-new-button nil)
  (tab-bar-auto-width nil)
  (tab-bar-format '(tab-bar-format-history
                    tab-bar-format-tabs
                    lem--tab-bar-suffix
                    tab-bar-format-add-tab))
  :config

  ;; https://protesilaos.com/codelog/2020-08-03-emacs-custom-functions-galore/
  (defun lem-tab-bar-select-tab-dwim ()
    "Do-What-I-Mean function for getting to a `tab-bar-mode' tab.
If no other tab exists, create one and switch to it.  If there is
one other tab (so two in total) switch to it without further
questions.  Otherwise use completion to select the tab."
    (interactive)
    (let ((tabs (mapcar (lambda (tab)
                          (alist-get 'name tab))
                        (tab-bar--tabs-recent))))
      (cond ((eq tabs nil)
             (tab-new))
            ((eq (length tabs) 1)
             (tab-next))
            (t
             (tab-bar-switch-to-tab
              (completing-read "Select tab: " tabs nil t)))))))

;;;; Tab Workspaces
(use-package tabspaces
  :ensure t
  ;; The session is only saved and restored while `tabspaces-mode' is on.
  :hook (after-init . tabspaces-mode)
  :commands (tabspaces-switch-or-create-workspace
             tabspaces-open-or-create-project-and-workspace)
  
  :custom
  (tabspaces-use-filtered-buffers-as-default t)
  (tabspaces-default-tab "Home")
  (tabspaces-remove-to-default t)
  (tabspaces-include-buffers '("*scratch*"))
  (tabspaces-initialize-project-with-todo t)
  (tabspaces-todo-file-name "project-todo.org")
  
  ;; sessions
  (tabspaces-session t)
  (tabspaces-session-auto-restore t)
  (tabspaces-session-file (expand-file-name "tabspaces-session.eld" sp-var-dir))
  
  ;; additional options
  (tabspaces-fully-resolve-paths t)  ; Resolve relative project paths to absolute
  (tabspaces-exclude-buffers '("*Messages*" "*Compile-Log*"))  ; Additional buffers to exclude
  (tab-bar-new-tab-choice "*scratch*"))

;; Optional: treat plain directories containing a .project file as
;; projects, so they work with tabspaces without version control.
;; See the "Non-VC Projects" section below.
;; (setq project-vc-extra-root-markers '(".project"))

;; Keybindings for tabspaces
(defvar tabspaces-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C") 'tabspaces-clear-buffers)
    (define-key map (kbd "b") 'tabspaces-switch-to-buffer)
    (define-key map (kbd "d") 'tabspaces-close-workspace)
    (define-key map (kbd "k") 'tabspaces-kill-buffers-close-workspace)
    (define-key map (kbd "n") 'tabspaces-rename-workspace)
    (define-key map (kbd "o") 'tabspaces-open-or-create-project-and-workspace)
    (define-key map (kbd "r") 'tabspaces-remove-current-buffer)
    (define-key map (kbd "R") 'tabspaces-remove-selected-buffer)
    (define-key map (kbd "s") 'tabspaces-switch-or-create-workspace)
    (define-key map (kbd "t") 'tabspaces-switch-buffer-and-tab)
    (define-key map (kbd "w") 'tabspaces-show-workspaces)
    (define-key map (kbd "T") 'tabspaces-toggle-echo-area-display)
    map)
  "Keymap for tabspace/workspace commands after `tabspaces-keymap-prefix'.")

;;;;; Consult Isolated Workspace Buffers
;; Filter Buffers for Consult-Buffer
(defun lem-buff-filter (buffer)
  (let ((blst (cl-remove (buffer-name) (frame-parameter nil 'buffer-list))))
    (memq buffer blst)))

(with-eval-after-load 'consult
  ;; hide full buffer list (still available with "b" prefix)
  ;; Use plist-put instead of consult-customize for internal sources
  ;; Use boundp check to handle package-quickstart timing issues
  (when (boundp 'consult-source-buffer)
    (plist-put consult-source-buffer :hidden t)
    (plist-put consult-source-buffer :default nil))
  ;; set consult-workspace buffer list
  (defvar consult-source-workspace
    (list :name     "Workspace Buffers"
          :narrow   ?w
          :history  'buffer-name-history
          :category 'buffer
          :state    #'consult--buffer-state
          :default  t
          :items    (lambda () (consult--buffer-query
                           :predicate #'tabspaces--local-buffer-p
                           :sort 'visibility
                           :as #'buffer-name)))

    "Set workspace buffer list for consult-buffer."))

;; MY PERSONAL ARCHIVED SETTINGS

;; Tab bar
;; (setq tab-bar-new-tab-choice "*dashboard*")
;; (setq tab-bar-new-tab-to 'right)
;; (setq tab-bar-new-button-show nil) ; I want to only create tabs from the modeline or through a keybinding
;; (setq tab-bar-show nil)

(provide 'sp-tabs)
;; sp-tabs.el ends here.