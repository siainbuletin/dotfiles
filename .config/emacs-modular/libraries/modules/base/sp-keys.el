;;; sp-keys.el --- Keybindings, leader prefix and which-key -*- lexical-binding: t; -*-

;;; Commentary:

;; An overhauled system for dealing with keybindings.
;; The general convention is that I use the more modern keymap-global-set instead of global-set-key -- the entire config should be scanned to make sure that the information is added in there.

;; There's also the option of using 'bind-key'.
;; 'bind-key' is a poart of use-package

;; Keybindings for 𝛌-Emacs. This has its disadvantages (e.g. separating
;; functions or packages from keybindings) but it also makes it the place to go
;; to deal with all keybindings. I use `bind-key' for setting bindings, which
;; comes with `use-package'. All 𝛌-Emacs keybindings are under the prefix
;; specified by `sp-prefix'.

;;; Code:

(defun sp-bind-commenting ()
  "Comment or uncomment a region by hitting M-;."
  (global-set-key (kbd "M-;")
                  'sp-comment-region-or-line))

;; this should be removed because I can already do C-a and C-e on Linux and MacOS to get
;; to the proper end of line.
(defun sp-bind-home-and-end-keys ()
  "Make <home> and <end> move point to the beginning and end of
the line, respectively."
  (keymap-global-set "<home>" 'move-beginning-of-line)
  (keymap-global-set "<end>" 'move-end-of-line))

(defun sensible-defaults/use-all-keybindings ()
  "Use all of the sensible-defaults keybindings."
  (sp-bind-commenting)
  (sp-bind-home-and-end-keys))

;;;; ironkey setup
;; Protecting keybindings in certain keymaos
(use-package ironkey
  :ensure (:type git :host github :repo "JimDBh/ironkey")
  :demand t
  :hook 
  ((after-init . ironkey-update))
  
  :config
  (setq ironkey-iron-alist `((,(kbd "M-.") . nil) ;; command in global-map
                             (,(kbd "C-x p") . nil))) ;; prefix keymap in global-map
                             
  (ironkey-mode t))

;;;;; Bind Key
;; Note that bind-key comes with use-package
(use-package bind-key
  :ensure nil
  :config
  (setq bind-key-describe-special-forms nil))

;;;;; Personal Keybindings Prefix
(defcustom sp-prefix "C-x C-SPC"
  "Prefix for all personal keybinds."
  :type 'string
  :group 'sia-lambda)

;;;;; Personal Leader Key

(defcustom lem+leader-map (make-sparse-keymap)
  "An overriding keymap for <leader> key, for use with modal keybindings."
  :type 'string
  :group 'sia-lambda)

;; Use sp-prefix as leader namespace
(bind-keys :prefix-map lem+leader-map
           :prefix sp-prefix)

;;;;; Personal Keybindings by Group
;;;;;; Buffer Keys
(bind-keys :prefix-map lem+buffer-keys
           :prefix (concat sp-prefix " b")
           ("a" . ibuffer)
           ("b" . consult-buffer)
           ("c" . sp-copy-whole-buffer-to-clipboard )
           ("d" . kill-buffer-and-window             )
           ("e" . sp-create-new-elisp-buffer        )
           ("E" . erase-buffer                       )
           ("f" . reveal-in-osx-finder               )
           ("i" . consult-imenu                      )
           ("j" . sp-jump-in-buffer                 )
           ("k" . sp-kill-this-buffer               )
           ("K" . crux-kill-other-buffers            )
           ("m" . consult-mark                       )
           ("M" . consult-global-mark                )
           ("n" . sp-create-new-buffer              )
           ("N" . sp-new-buffer-new-frame           )
           ("p" . consult-project-buffer             )
           ("r" . revert-buffer                      )
           ("R" . crux-rename-file-and-buffer        )
           ("s" . consult-buffer-other-window        )
           ("S" . sp-spelling-transient            )
           ("t" . tab-bar-new-tab                    )
           ("[" . sp-previous-user-buffer           )
           ("]" . sp-next-user-buffer               )
           ("{" . tab-bar-switch-to-prev-tab         )
           ("}" . tab-bar-switch-to-next-tab         )
           ("<backtab>" . crux-switch-to-previous-buffer))

;;;;;; Comment Keybindings
(bind-keys :prefix-map lem+comment-wrap-keys
           :prefix (concat sp-prefix " c")
           ("c" . comment-dwim)
           ("d" . crux-duplicate-and-comment-current-line-or-region)
           ("l" . comment-line)
           ("o" . org-block-wrap)
           ("y" . sp-yaml-wrap))

;;;;;; Config Keybindings
;; FIXME: fix goto functions to make them more generic
;; FIXME: fix kill-and-archive so that it creates an archive file
(bind-keys :prefix-map lem+config-keys
           :prefix (concat sp-prefix " C")
           ("a" . sp-kill-and-archive-region           )
           ("c" . sp-goto-custom.el                    )
           ("d" . sp-goto-emacs-dir                    )
           ("e" . sp-goto-early-init.el                )
           ("f" . sp-find-lambda-file                  )
           ("l" . sp-load-config                       )
           ("i" . sp-goto-init.el                      )
           ("I" . sp-load-init-file                    )
           ("o" . sp-goto-org-files                    )
           ("s" . sp-search-lambda-files               ))

;;;;;; Compile Keybindings
;; TODO: remove complile-next-makefile in favor of project compile?
(bind-keys :prefix-map lem+compile-keys
           :prefix (concat sp-prefix " M")
           ("m"  . compile                  )
           ("M"  . multi-compile-run        )
           ("e"  . compile-goto-error       )
           ("k"  . sp-compile-next-makefile)
           ("K"  . kill-compilation         )
           ("r"  . recompile                ))

;;;;;; Eval Keybindings
(bind-keys :prefix-map lem+eval-keys
           :prefix (concat sp-prefix " e")
           ("b"  . eval-buffer )
           ("c"  . sp-eval-current-form)
           ("e"  . eval-last-sexp)
           ("f"  . eval-defun))

;;;;;; File Keybindings
(bind-keys :prefix-map lem+file-keys
           :prefix (concat sp-prefix " f")
           ("b" . consult-bookmark                 )
           ("f" . find-file                        )
           ("l" . consult-locate                   )
           ("o" . crux-open-with                   )
           ("s" . save-buffer                      )
           ("r" . consult-recent-file              )
           ("y" . sp-show-and-copy-buffer-filename))

;;;;;; Linting (Flymake)
(bind-keys :prefix-map lem+flymake-keys
           :prefix (concat sp-prefix " F"        )
           ("b" . flymake-start                   )
           ("c" . consult-flymake                 )
           ("d" . flymake-show-buffer-diagnostic  )
           ("p" . flymake-show-project-diagnostics)
           ("P" . package-lint-current-buffer     )
           ("u" . use-package-lint                ))

;;;;;; Mail Keybindings
(bind-keys :prefix-map lem+mail-keys
           :prefix (concat sp-prefix " m")
           ("c" . mu4e-compose-new           )
           ("i" . cpm-go-to-mail-inbox       )
           ("k" . mu4e-kill-update-mail      )
           ("m" . cpm-open-email-in-workspace)
           ("s" . mu4e-update-mail-and-index )
           ("u" . cpm-go-to-mail-unread      ))

;;;;;; Notes
;; General notes
(bind-keys :prefix-map lem+notes-keys
           :prefix (concat sp-prefix " n")
           ("d"  .  denote)
           ("n"  .  consult-notes)
           ("s"  .  consult-notes-search-in-all-notes)
           ("w"  .  sp-denote-workbook-create-entry))
;; Biblio notes
(bind-keys :prefix-map lem+bib-keys
           :prefix (concat sp-prefix " n b")
           ("a"  .  citar-denote-add-citekey)
           ("c"  .  citar-create-note)
           ("o"  .  citar-open-notes)
           ("O"  .  citar-denote-dwim))

;;;;;; Quit Keybindings
(bind-keys :prefix-map lem+quit-keys
           :prefix (concat sp-prefix " q")
           ("d" . sp-kill-emacs-capture-daemon)
           ("q" . save-buffers-kill-emacs      )
           ("Q" . sp-kill-all-emacsen         )
           ("r" . restart-emacs                ))

;;;;;; Search Keybindings
(bind-keys :prefix-map lem+search-keys
           :prefix (concat sp-prefix " s")
           ("a" . consult-org-agenda           )
           ;; search current buffer's directory
           ("d" . consult-ripgrep              )
           ;; search with directory input
           ("D" . sp-search-in-input-dir      )
           ("b" . multi-occur                  )
           ("f" . consult-line                 )
           ("h" . consult-org-heading          )
           ("j" . sp-forward-or-backward-sexp )
           ("k" . consult-yank-pop             )
           ("l" . vertico-repeat               )
           ("n" . consult-notes-search-in-all-notes)
           ("r" . vr/query-replace             )
           ("s" . consult-line                 )
           ;; search for next spelling error
           ("S" . sp-flyspell-ispell-goto-next-error)
           ("t" . sp-todo-transient           )
           ("." . consult-line-symbol-at-point ))

;;;;;; Toggle Keybindings
(bind-keys :prefix-map lem+toggle-keys
           :prefix (concat sp-prefix " t")
           ("g" . git-gutter-mode             )
           ("d" . dired-sidebar-toggle-sidebar)
           ("e" . toggle-indicate-empty-lines )
           ("E" . eldoc-mode                  )
           ("F" . flymake-mode                )
           ("h" . hl-line-mode                )
           ("H" . hide-mode-line-mode         )
           ("m" . sp-toggle-display-markup   )
           ("n" . display-line-numbers-mode   )
           ("o" . imenu-list-smart-toggle     )
           ("p" . puni-global-mode            )
           ("P" . show-paren-mode             )
           ("r" . rainbow-identifiers-mode    )
           ("s" . flyspell-mode               )
           ("S" . ispell-buffer               )
           ;; ("t" . toggle-dark-light-theme     )
           ("t" . sp-load-theme              )
           ("w" . writeroom-mode              )
           ("z" . zone                        ))

;;;;;; User Keybindings
;; NOTE: This keymap is for user-specific keybindings. Define this in your
;; `config.el' file.
(bind-keys :prefix-map lem+user-keys
           :prefix (concat sp-prefix " u"))

;;;;;; Version Control (Git) Keybindings
;; git-gutter is referenced by several bindings here but is not declared
;; in `sp-packages-alist'. Autoload the commands we bind so the keymap
;; entries are `commandp'-true even on a cold boot before the user
;; installs git-gutter; pressing the key without git-gutter installed
;; raises `file-missing' (not `void-function'), and once git-gutter is
;; on `package-user-dir' the autoload resolves the actual command.
(autoload 'git-gutter:popup-hunk    "git-gutter" "Show diff hunk in popup." t)
(autoload 'git-gutter:next-hunk     "git-gutter" "Move to next hunk."       t)
(autoload 'git-gutter:previous-hunk "git-gutter" "Move to previous hunk."   t)
(autoload 'git-gutter-mode          "git-gutter" "Toggle git-gutter-mode."  t)
;; `sp-merge-pick' loads late, after Emacs is idle; this opens its graph log.
(autoload 'sp-merge-pick-log        "sp-merge-pick" "Graph log for picking two commits." t)
(bind-keys :prefix-map  lem+vc-keys
           :prefix (concat sp-prefix " g")
           ("b" .  magit-blame                 )
           ("c" .  magit-commit                )
           ("d" .  magit-diff                  )
           ("h" .  git-gutter:popup-hunk       )
           ("l" .  magit-log                   )
           ;; show history of selected region
           ("L" .  magit-log-buffer-file       )
           ;; graph log in which to pick two commits to review or merge
           ("m" .  sp-merge-pick-log           )
           ("n" .  git-gutter:next-hunk        )
           ("p" .  git-gutter:previous-hunk    )
           ;; quick commit file
           ("q" .  vc-next-action              )
           ("r" .  magit-reflog                )
           ("s" .  magit-status                ))

;;;;;; Window Keybindings
(bind-keys :prefix-map lem+window-keys
           :prefix (concat sp-prefix " w")
           ("a" .  ace-window                      )
           ("f" .  lem-toggle-window-split        )
           ("c" .  delete-window                   )
           ("d" .  delete-window                   )
           ("h" .  lem-split-window-below-and-focus)
           ("H" .  split-window-below              )
           ("m" .  delete-other-windows            )
           ("o" .  other-window                   )
           ("r" .  lem-rotate-windows            )
           ("R" .  lem-rotate-windows-backward   )
           ("t" .  tear-off-window                 )
           ("u" .  winner-undo                     )
           ("U" .  winner-redo                     )
           ("v" .  lem-split-window-right-and-focus)
           ("V" .  split-window-right              )
           ("w" .  ace-window                      )
           ("x" .  lem-window-exchange-buffer     )
           ("-" .  split-window-below              )
           ("_" .  lem-split-window-below-and-focus))

;;;;;; Workspace Keybindings
(bind-keys :prefix-map lem+workspace-keys
           :prefix (concat sp-prefix " W")
           ("b"  .  tabspaces-switch-to-buffer)
           ("c"  .  tabspaces-clear-buffers)
           ("d"  .  tabspaces-close-workspace)
           ("k"  .  tabspaces-kill-buffers-close-workspace)
           ("o"  .  tabspaces-open-or-create-project-and-workspace)
           ("p"  .  tabspaces-project-switch-project-open-file)
           ("r"  .  tabspaces-remove-current-buffer)
           ("R"  .  tabspaces-remove-selected-buffer)
           ("s"  .  tabspaces-switch-or-create-workspace))

;;;;; Which Key (built-in baseline)
;; EMACS-29+ built-in (which-key was merged into Emacs core in 29,
;; not 28). Raw top-level baseline -- C-6 forbids use-package
;; wrapping of built-in baselines. `which-key-mode' is autoloaded
;; in Emacs 29+, so the bare call resolves without an explicit
;; require.
(setq which-key-show-early-on-C-h t)

;; Delay for which-key
;; The which-key-idle-delay variable controls how long which-key-mode waits after a prefix
;; key is entered before displaying the available bindings.
;;
;; Reducing the delay makes key discovery appear sooner, but it also increases the likelihood
;; that a popup will appear during an ordinary key sequence. (For experienced users with
;; memorized prefixes, a longer delay can reduce visual interruptions.)
;; 
;; source: https://www.jamescherti.com/emacs-user-interface-better-responsiveness-and-latency/

(setq which-key-idle-delay 0.75)
(setq which-key-idle-secondary-delay 0.05)

;; other witch key settings
(setq which-key-popup-type 'side-window)
(setq which-key-side-window-max-height 0.5)
(setq which-key-allow-imprecise-window-fit nil)
(setq which-key-side-window-location 'top)
;; ASCII separator. Was U+2192 RIGHTWARDS ARROW; CLAUDE.md forbids
;; multi-byte Unicode in source files (AC-8 byte-vs-char check).
(setq which-key-separator " -> ")
(which-key-mode 1)

;;;;; Hydras

;;;;; Ediff transient
;; Adapted from the hydra wiki (Emacs#ediff section), ported to
;; transient in Spec 09.
;; Body color was blue (exit on every suffix); :hint nil meant the
;; freeform tabular docstring was the entire UI -- replaced here by
;; transient's standard column groups.

(transient-define-prefix sp-ediff-transient ()
  "Launch an ediff session."
  ["Ediff"
   ["Buffers"
    ("b" "Buffers"          ediff-buffers)
    ("B" "Buffers (3-way)"  ediff-buffers3)
    ("c" "Current file"     ediff-current-file)]
   ["Files"
    ("=" "Files"            ediff-files)
    ("f" "Files"            ediff-files)
    ("F" "Files (3-way)"    ediff-files3)]
   ["VC"
    ("r" "Revisions"        ediff-revision)]
   ["Regions"
    ("l" "Linewise"         ediff-regions-linewise)
    ("w" "Wordwise"         ediff-regions-wordwise)]])

;;;;;; Transpose
;; <leader> . binds `transpose-words' (the most common case).
;; `transpose-chars', `transpose-lines', `transpose-sentences',
;; `transpose-paragraphs', `org-transpose-words',
;; `org-transpose-element', and `org-table-transpose-table-at-point'
;; remain accessible via M-x. Spec 09 dropped a wrapping menu; see git
;; history for the prior dispatch macro.
(bind-key (concat sp-prefix " .") #'transpose-words)

;;;;;; Rectangle transient
;; Suffixes stay on press; "g" exits. Setup/teardown:
;; `rectangle-mark-mode' is enabled on entry, `deactivate-mark' fires
;; on every exit path via a one-shot `transient-exit-hook'. Ported in
;; Spec 09 -- see git history for the prior macro-based dispatch
;; implementation including its ASCII-art docstring.

(defun sp-rectangle-toggle-region ()
  "Toggle `rectangle-mark-mode' based on current region state.
Used by `sp-rectangle-transient' as the \"r\" suffix; replaces
an inline branching lambda from the prior implementation."
  (interactive)
  (if (region-active-p)
      (deactivate-mark)
    (rectangle-mark-mode 1)))

(transient-define-prefix sp-rectangle-transient ()
  "Rectangle editing."
  ["Rectangle"
   ["Move"
    ("k" "Up"    rectangle-previous-line :transient t)
    ("j" "Down"  rectangle-next-line     :transient t)
    ("h" "Left"  rectangle-backward-char :transient t)
    ("l" "Right" rectangle-forward-char  :transient t)]
   ["Edit"
    ("d" "Kill"   kill-rectangle           :transient t)
    ("y" "Yank"   yank-rectangle           :transient t)
    ("w" "Copy"   copy-rectangle-as-kill   :transient t)
    ("o" "Open"   open-rectangle           :transient t)
    ("t" "Type"   string-rectangle         :transient t)
    ("c" "Clear"  clear-rectangle          :transient t)]
   ["Mark"
    ("e" "Exchange"     rectangle-exchange-point-and-mark :transient t)
    ("N" "Number lines" rectangle-number-lines            :transient t)
    ("r" "Toggle region" sp-rectangle-toggle-region      :transient t)]
   [""
    ("u" "Undo" undo                :transient t)
    ("g" "Quit" transient-quit-one)]]
  (interactive)
  (rectangle-mark-mode 1)
  (let (cleanup)
    (setq cleanup
          (lambda ()
            (when (region-active-p)
              (deactivate-mark))
            (remove-hook 'transient-exit-hook cleanup)))
    (add-hook 'transient-exit-hook cleanup))
  (transient-setup 'sp-rectangle-transient))

;; TODO: Add org and markdown keybindings
;;;; End keybindings



(use-package hydra
  :ensure (:wait t))

(use-package use-package-hydra
  :ensure (:wait t))

;; READING MORE ABOUT KEYBINDINGS AND GETTING TO USE THEM

(use-package which-key
    :ensure t
    :demand t

    :config
    (which-key-mode 1)

    :custom
    (which-key-max-description-length 40)
    (which-key-lighter nil)
    ;; (setq which-key-idle-delay 0.3) ;; no delay so I can actually get the previews in the minibuffer
    ;; (which-key-sort-order 'which-key-order-alpha) ;; error. see what are the actual symbols/options
    (which-key-mode +1))

(use-package helm-descbinds
  :ensure (:type git :host github :repo "emacs-helm/helm-descbinds"))

(global-unset-key (kbd "C-z"))

(keymap-global-set "C->" #'indent-rigidly-right-to-tab-stop) ; Indent selection by one tab length
(keymap-global-set "C-<" #'indent-rigidly-left-to-tab-stop)  ; De-indent selection by one tab length

(keymap-global-set "C-x t b" 'transpose-buffers)

;; Main keybindings
(keymap-global-set "C-c s l" 'easysession-switch-to)  ; Load
(keymap-global-set "C-c s s" 'easysession-save-as)  ; Save

;; Other keybindings
(keymap-global-set "C-c s L" 'easysession-switch-to-and-restore-geometry)
(keymap-global-set "C-c s d" 'easysession-delete)
(keymap-global-set "C-c s r" 'easysession-rename)
(keymap-global-set "C-c s R" 'easysession-reset)

(keymap-global-set "C-c e b b" 'eval-buffer)

;; THIS BIT WAS TRIGGERING AN ERROR BUT I DON'T KNOW WHY
;; (keymap-global-set "C-M-<up>") (lambda () (interactive)
;;                                   (set-face-attribute 'default nil :height (+ (face-attribute 'default :height) 5))))
;;(keymap-global-set "C-M-<down>") (lambda () (interactive)
;;                                     (set-face-attribute 'default nil :height (- (face-attribute 'default :height) 5))))

(keymap-global-set "C-+" 'text-scale-increase)
(keymap-global-set "C--" 'text-scale-decrease)
(keymap-global-set "C-M-S-u" 'rename-uniquely)
(keymap-global-set "C-M-z C-e" 'eval-region)
(keymap-global-set "C-M-z C-M-e" 'eval-buffer)
(keymap-global-set "C-M-S-c" 'find-emacs-config)
(keymap-global-set "C-M-S-z" 'cmake-ide-compile)
(defun find-emacs-config ()
  "Open the emacs configuration file"
  (interactive)
  (find-file "~/.emacs.d/siapip/siapip-emacs.el"))

;; See the keys being used in real time
(use-package keycast
  :ensure (:wait t))

(provide 'sp-keys)

;;; sp-keys.el ends here
