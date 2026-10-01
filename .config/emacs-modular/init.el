;; -*- lexical-binding: t -*-
;; -*-no-byte-compile: t; -*-

;; IMPORTANT: This will actually enable this configuration
(load "~/.config/emacs-modular/sia-emacs")

;; INFO: Your custom config can be either here or inside /path/to/siapip-emacs-config/custom.el

;; Essential configurations - essential.el

;; snippet management - snippet.el

;; Search packages - search.el

;; minibuffer - minibuffer-packs.el

;; packages

;; embark.el

;; counsel-recoll.el

;; essential-packs.el

;; consult-snapfile.el

;; keys.el

;; dired-conf.el

;; bookmarks.el

;; org-config.el

;; sia-dashboard.el

;; denote.el

;; dgraphs.el

;; org-node-mem.el

;; academic.el

;; reading.el

;; projects.el

;; latex.el

;; help.el

;; browsing.el

;; vc.el

;; icons.el

;; utils/modeline.el

;; rss.el

;; init/gui.el

;; fonts.el

;; taskman.el

;; themes.el

;; utils/minibuffer.el

;; windows.el

;; buffer-man.el

;; multimedia.el

;; terminal.el

;; macos.el

;; http.el

;; ai.el

;; org-db.el

;; vulpea-eco.el

;; ENVIRONMENT VARIABLES - see env.el

;; EXTRACT FUNCTION

(require 'sia-move-region-to-heading)

;; Create dataview-like tables through the vulpea query system
(require 'sia-vulpea-dblock)
(require 'sia-vulpea-vui-table)
(require 'sia-vulpea-table-views)

;; Batch converting properties to plug into vulpea instead

(require 'sia-vulpea-convert-properties)

;; Grouping backlinks based on the property that it's representing

(require 'sia-vulpea-grouped-backlinks)

;; textui.el