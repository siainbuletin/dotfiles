;;; sp-icons.el --- Nerd icons for files, dired, completion and ibuffer -*- lexical-binding: t; -*-

;;; Commentary:

;; The code for icons that was found in Lambda Emacs ~lem-setup-fonts~ now lives in a
;; separate file.
;;
;; TODO: completely remove all-the-icons from any call on the system and depend
;; on one icons package entirely.
;;
;; The reason for choosing nerd-icons instead is that it uses a SINGLE patched
;; font ("Symbols Nerd Font Mono") rather than the six separate fonts
;; all-the-icons shipped.
;;
;; nerd-icons renders in TTY frames, so -- unlike the old all-the-icons
;; gate -- this omits the (display-graphic-p) condition.

;;; Code:

;; nerd-icons uses 
(defun sp-font--icon-check ()
  "Report whether the Nerd Font for `nerd-icons' glyphs is present.
Deliberately does NOT auto-install the font.  In a terminal the
glyphs are rendered by the terminal emulator's own font (e.g. a
Nerd Font configured in the terminal), not by Emacs. 

A GUI frame needs the font installed at the OS level -- run
`M-x nerd-icons-install-fonts' once, by hand."
  (cond ((sp-font-available-p "Symbols Nerd Font Mono")
         (message "Nerd Font for icons already installed!"))
        ((display-graphic-p)
         (message "GUI frame: run M-x nerd-icons-install-fonts to display icon glyphs."))
        (t
         (message "Terminal frame: icon glyphs render via the terminal font."))))

(defun sp-font--init-nerd-icons-fonts ()
  "Map the single Nerd Font for icon glyphs in GUI frames.
A no-op in a TTY, where the terminal font handles the glyphs."
  (when (and (display-graphic-p) (fboundp 'set-fontset-font))
    (set-fontset-font t 'unicode
                      (font-spec :family "Symbols Nerd Font Mono")
                      nil 'prepend)))

(use-package nerd-icons


  :ensure t
  :commands (nerd-icons-octicon
             nerd-icons-faicon
             nerd-icons-mdicon
             nerd-icons-sucicon
             nerd-icons-wicon
             nerd-icons-codicon
             nerd-icons-devicon
             nerd-icons-flicon
             nerd-icons-icon-for-file
             nerd-icons-icon-for-dir
             nerd-icons-icon-for-mode)

  :init
  (add-hook 'after-setting-font-hook #'sp-font--icon-check)

  :custom
  (nerd-icons-scale-factor 1.0) ;; Adjust this as necessary per user font
  :config
  (add-hook 'after-setting-font-hook #'sp-font--init-nerd-icons-fonts))

;; icons for dired
(use-package nerd-icons-dired
  :ensure t
  :defer t
  :commands nerd-icons-dired-mode
  :init
  (add-hook 'dired-mode-hook 'nerd-icons-dired-mode)
  ;; Dirvish draws its own icons (the `nerd-icons' attribute in
  ;; `dirvish-attributes'); with this mode on as well each entry has two.
  (defun sp-icons--dired-off-in-dirvish ()
    "Turn off `nerd-icons-dired-mode' in Dirvish buffers."
    (nerd-icons-dired-mode -1))
  (dolist (hook '(dirvish-mode-hook dirvish-directory-view-mode-hook))
    (add-hook hook #'sp-icons--dired-off-in-dirvish)))

;; Completion Icons
(use-package nerd-icons-completion
  :ensure t
  ;; On MELPA proper, so it installs through `sp-packages-alist' like
  ;; everything else -- no fork or package-vc-install hack needed.
  :hook (emacs-startup . nerd-icons-completion-mode)
  :config
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package nerd-icons-ibuffer
  :ensure t
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

(provide 'sp-icons)
;; sp-icons.el ends here.
