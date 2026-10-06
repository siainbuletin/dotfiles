;; -*- lexical-binding: t -*-
;; -*-no-byte-compile: t; -*-
;; -*- mode: emacs-lisp; coding:utf-8; fill-column: 80 -*-

;; SETTING UP THE LOAD PATH

(defvar siapip/load-path (file-name-directory (or load-file-name buffer-file-name))
  "Path of the siapip emacs config")
(when (not siapip/load-path)
  (error "Cannot determine configuration path of siapip emacs-config: both load-file-name and buffer-file-name are nil"))

(defun siapip/load (paths)
  "Load files relative to this emacs config."
  (when (not (listp paths))
    (setq paths (list paths)))
  (dolist (path paths)
    (condition-case err
        (load (expand-file-name path siapip/load-path))
      (error (message "Failed to load siapip-config sub-library at %S: %S" path err)))))

;;;; Startup

;;;;; Security
;; Properly verify outgoing ssl connections.
;; See https://glyph.twistedmatrix.com/2015/11/editor-malware.html
(use-package gnutls
  :ensure nil
  :defer 1
  :custom
  (gnutls-verify-error t)
  (gnutls-min-prime-bits 3072))

;;;;; Command Line Switches

;; Conditionally load parts of config depending on command line switches.
;; This allows startup with a clean emacs that still recognizes straight.
;; Helpful for testing packages.
;; Use (straight-use-package) command to selectively load packages.
;; See https://emacs.stackexchange.com/a/34909/11934
;; For function switch see https://stackoverflow.com/a/4065412/6277148

;; NOTE: The variable here doesn't really do anything. It is just useful to keep
;; for a record of switches.
(defvar sp-config-switches
  '("basic"
    "clean"
    "core"
    "test")
  "Custom switches for conditional loading from command line.

  - `clean' loads only the `init.el' file w/no personal config;
  - `core'  loads the set of modules set in `lem-core-modules';
  - `test' loads only a `sp-test.el' file for easy testing.")

(defvar sp--emacs-switches-found nil
  "Custom command-line switches found in `command-line-args' at startup.
Populated by a single scan at load time: each known switch
(\"-minimal\", \"-test\", \"-vanilla\", \"-default\") present in
`command-line-args' is recorded here and deleted from
`command-line-args' exactly once, so Emacs's own option processing
does not signal \"Unknown option\" after init.")

(dolist (switch '("-minimal" "-test" "-vanilla" "-default"))
  (when (member switch command-line-args)
    (push switch sp--emacs-switches-found)
    (setq command-line-args (delete switch command-line-args))))

(defun sp--emacs-switches (switch)
  "Non-nil if command line argument SWITCH was passed.
Consults `sp--emacs-switches-found', the snapshot recorded when the
switch was removed from `command-line-args' at load time, so it is
safe to call any number of times per switch."
  (member switch sp--emacs-switches-found))

;;;;; Emacs Build Version
;; When built with https://codeberg.org/mclearc/build-emacs-macos, Emacs has
;; git-version patch to include git sha1 in emacs-version string.
;; Load it only when the running build actually provides it on its load-path.
;; Checking a hardcoded Emacs.app path with `file-exists-p' breaks other builds
;; (e.g. a homebrew daemon) whose load-path omits that site-lisp: the file
;; exists on disk so the guard passes, but `require' cannot find it.
;;
;;
;; this should be worked on later!!

(when (locate-library "emacs-git-version")
  (require 'emacs-git-version))

(defun lem-emacs-version ()
  "A convenience function to print the emacs-version in the echo-area/*messages* buffer and put
emacs-version string on the kill ring."
  (interactive)
  (let ((emacs (emacs-version)))
    (message (emacs-version))
    (kill-new emacs)))

;;;;; Outline Navigation

;; this navigation could be moved to a different module !!

;; Navigate elisp files easily. Outline is a built-in library and we can easily
;; configure it to treat elisp comments as headings.
(use-package outline
  :ensure nil
  :hook (prog-mode . outline-minor-mode)
  :bind (:map outline-minor-mode-map
         ("<tab>"   . outline-cycle)
         ("S-<tab>" . outline-cycle-buffer)
         ("M-j"     . outline-move-subtree-down)
         ("M-k"     . outline-move-subtree-up)
         ("M-h"     . outline-promote)
         ("M-l"     . outline-demote))
  :config
  (add-hook 'emacs-lisp-mode-hook
            (lambda ()
              ;; prevent `outline-level' from being overwritten by `lispy'
              (setq-local outline-level #'outline-level)
              ;; setup heading regexp specific to `emacs-lisp-mode'
              (setq-local outline-regexp ";;;\\(;* \\)")
              ;; heading alist allows for subtree-like folding
              (setq-local outline-heading-alist
                          '((";;; " . 1)
                            (";;;; " . 2)
                            (";;;;; " . 3)
                            (";;;;;; " . 4)
                            (";;;;;;; " . 5))))))

;;;;;;;; LOADING MODULES FOR PACKAGES (with groups)

;; Commentary:
;;
;; Probably this needs to be organised so that the load order
;; makes sense enough. For example, the environment set-up for
;; macOS should come later on in the process, before drawing the
;; graphical interface, as it needs the theme declarations before
;; deciding to use the ns-system-hook.

;; init modules (the most important files that I have to be loading up)

(siapip/load
 '("./libraries/modules/base/speedup"              ;; stuff that should probably be in early-init.el
   "./libraries/modules/base/sp-package"           ;; this is the basic setup for elpaca
   "./libraries/modules/base/sp-encoding"         ;; text encoding
   "./libraries/modules/base/sp-base-libraries"   ;; the very basic processing libraries
   "./libraries/modules/base/sp-gui"              ;; currently handled by early-init from Lambda Emacs
   "./libraries/modules/base/sp-snippets"         ;; snippet management
   "./libraries/modules/base/sp-interaction"      ;; ways to interact with the GUI
   ))

;; UI (modules organised alphabetically -- should be fixed somehow
;; but I don't know how I'm supposed to make it properly readable)

(siapip/load
  '("./libraries/modules/ui/sp-buffers"           ;; Buffer management and general drawing instructions.
    "./libraries/modules/ui/sp-canvas"            ;; For modules developed around the new Canvas feature in Emacs 32.
    "./libraries/modules/ui/sp-colors"            ;; Global color scheme to follow.
    "./libraries/modules/ui/sp-dashboard"
    "./libraries/modules/ui/sp-faces"
    "./libraries/modules/ui/sp-fonts"
    "./libraries/modules/ui/sp-icons"
    "./libraries/modules/ui/sp-tabs"
    "./libraries/modules/ui/sp-textui"
    "./libraries/modules/ui/sp-themes"
    "./libraries/modules/ui/sp-windows"
    "./libraries/modules/ui/sp-writing-appearance"
  ))

;; Environment specific settings

(siapip/load
 '("./libraries/modules/env/sp-env"              ;; Making exec-path work.
   "./libraries/modules/env/sp-macos.el"         ;; MacOS specific settings
   "./libraries/modules/env/sp-win.el"       ;; this should be triggered conditionally with the system type (and required in a different file)
   "./libraries/modules/env/sp-exwm"             ;; see whether you're going to combine this with regular window management
))

;; navigation

(siapip/load
  '("./libraries/modules/navigation/sp-dired"
    "./libraries/modules/navigation/sp-search" ;; this represents full-text search packages
  ))

;; misc modules (utility) --- these should be split apart differently at some point

(siapip/load
 '("./libraries/modules/tooling/sp-backups"             ;; For the backup files that Emacs creates
  "./libraries/modules/tooling/sp-bookmarks"            ;; Bookmark management.
  "./libraries/modules/tooling/sp-choose-modeline"      ;; You can choose between 2 modelines.
  "./libraries/modules/tooling/sp-debug"                ;; If you ever need to do deep debugging for Elisp
  "./libraries/modules/tooling/sp-embark"
  "./libraries/modules/tooling/sp-evil"
  "./libraries/modules/tooling/sp-help"                 ;; Improvements for the help module.
  "./libraries/modules/tooling/sp-indention"
  "./libraries/modules/tooling/sp-keys"                 ;; Keybindings
  ;; "./libraries/modules/tooling/sp-lambda-line"       ;; Separate modeline
  "./libraries/modules/tooling/sp-md"
  "./libraries/modules/tooling/sp-minibuffer"
  "./libraries/modules/tooling/sp-misc-writing"
  "./libraries/modules/tooling/sp-network"
  "./libraries/modules/tooling/sp-scratch"
  "./libraries/modules/tooling/sp-server"
  "./libraries/modules/tooling/sp-spelling"
  "./libraries/modules/tooling/sp-splash"                ;; this is the splash screen from lambda emacs
  "./libraries/modules/tooling/sp-templating"
  "./libraries/modules/tooling/sp-text-manipulation"
  "./libraries/modules/tooling/sp-workspaces"
))

;; Org-related settings
(siapip/load
  '("./libraries/modules/text/sp-org-base" ;; the very basic functions -- the others should be stringed in after this

    "./libraries/modules/text/sp-denote" ;; the file creation subsystem

    ;; it does also depend on how essential i find some features to be

    ;; defined essential org-features
    "./libraries/modules/text/sp-org-appearance"
    "./libraries/modules/text/sp-org-capture"
    "./libraries/modules/text/sp-org-export"
    ;; "./libraries/modules/text/sp-org-refile" ;; having an issue with org refile targets when loading
    "./libraries/modules/text/sp-org-tables"
    "./libraries/modules/text/sp-org-narrow"

    ;; task management
    "./libraries/modules/text/sp-org-agenda"
    "./libraries/modules/text/sp-org-taskman-extra"

    "./libraries/modules/text/sp-org-ext" ;; other extensions
    
    ;; "./libraries/modules/text/sp-org-node-mem"
    "./libraries/modules/text/sp-vulpea-base" ;; (this module) will pull its necessary add-on functions on its own (recursion)
    "./libraries/modules/text/sp-vulpea-ext" ;; needs the functions that I called earlier

    ;; Generating networks with the information
    "./libraries/modules/text/sp-dgraphs"

    ;; other notes-related settings
    "./libraries/modules/text/sp-notes"
    ))

;; ACADEMIC WORK (submodules are found inside)
(siapip/load
  '("./libraries/modules/academic/sp-academic"
    "./libraries/modules/academic/sp-statistics"
  ))

;; MULTIMEDIA WORK + OTHER WORKFLOWS
(siapip/load
  '("./libraries/modules/media/sp-beets"                ;; Managing a beets library
    "./libraries/modules/media/sp-instant-messenger"
    "./libraries/modules/media/sp-mail"
    ;; "./libraries/modules/media/sp-music-play"        ;; I currently don't know how to configure any of these media players.
    "./libraries/modules/media/sp-reading"
    "./libraries/modules/media/sp-browsing"             ;; Setup for different browsers inside of Emacs
    "./libraries/modules/media/sp-rss"                  ;; elfeed and inboxing of new information
   ))

;;;;; OTHER
(siapip/load
  '("./libraries/modules/sp-ai"                         ;; this is for engaging with different models. could be for local models as well, but it has to be set up
    "./libraries/modules/sp-consult-snapfile"
  ))

;;;;; FUNCTIONS I WROTE
(siapip/load
  '("./libraries/modules/funct/sp-helper-functions.el"
    "./libraries/modules/funct/sp-open-externally.el"

    ;; text manipulation
    "./libraries/modules/funct/sp-move-region-to-heading.el"

    ;; vulpea regions - these are all now 'required' in the vulpea-ext file
    ))

;; Programming setup

(siapip/load
 '("./libraries/modules/prog/sp-base-code"
   ;; "./libraries/modules/prog/sp-plantuml"
   ;; "./libraries/modules/prog/sp-lisp"
   ;; "./libraries/modules/prog/sp-go"
   ;; "./libraries/modules/prog/sp-c"
   ;; "./libraries/modules/prog/sp-python"
   ;; "./libraries/modules/prog/sp-rust"
   ;; "./libraries/modules/prog/sp-xml"
   ;; "./libraries/modules/prog/sp-nix"
   ;; "./libraries/modules/prog/sp-misc"                    ;; currently disabled, as there's several packages that conflict with something else that I have on the system
   "./libraries/modules/prog/sp-latex"
   "./libraries/modules/prog/sp-prog-misc"
   "./libraries/modules/prog/sp-terminal"
   "./libraries/modules/prog/sp-vcontrol"
))

;; Cloned modules (can't install with use-package otherwise)
;; set up later

;; re-add here the conditional loading for different modules, which came from Lambda Emacs

;;;; After Startup
;; reset file-name-handler-alist
(add-hook 'emacs-startup-hook (lambda ()
                                (setq file-name-handler-alist lem-file-name-handler-alist)
                                ;; reset garbage collection
                                (setq gc-cons-threshold 800000)
                                ;; Startup time
                                (message (format ";; ======================================================\n;; Emacs ready in %.2f seconds with %d garbage collections.\n;; ======================================================"
                                                 (float-time
                                                  (time-subtract after-init-time before-init-time)) gcs-done))
                                (put 'narrow-to-page 'disabled nil)))

;;; Endnotes:
;; INFO: Your custom config can be either here or inside /path/to/siapip-emacs-config/custom.el

;; Other configurations will be found in the libraries folder.

;; CUSTOM VARIABLES

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(bibtex-aux-opt-alist
   '(("keywords" "Keywords to describe the entry" "")
     ("file" "Relative or absolute path to attachments" "")) nil nil "Customized with use-package bibtex")
 '(custom-safe-themes
   '("acd363510d3e4b638db178783bde3d4492574c0f5c889f845251949f43567d16"
     "f2f42f0b7c53736840fc3ff5751235e3b87cc535b04ddaf3423e2926548bfbb4"
     default))
 '(org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "|" "DONE" "CNCL")) nil nil "Customized with use-package org-gtd")
 '(package-selected-packages '(lambda-themes))
 '(package-vc-selected-packages
   '((lambda-themes :vc-backend Git :url
                    "https://codeberg.org/Lambda-Emacs/lambda-themes.git")))
 '(sia/modeline 'doom-modeline))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-default ((t (:background "#F0B609" :inherit default))))
 '(org-extra-emphasis ((t (:background "#F0B609" :height 1.0 :inherit default :weight bold :width normal))) t)
 '(org-extra-emphasis-01 ((t (:foreground "#003F66" :inherit org-extra-emphasis :underline t))))
 '(org-extra-emphasis-02 ((t (:foreground "#003F66" :inherit org-extra-emphasis :underline t)))))
