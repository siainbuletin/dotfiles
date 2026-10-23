;;; sp-ai.el --- AI and LLM integration -*- lexical-binding: t; -*-

;;; Commentary:

;; This module installs packages for working with large language models and
;; coding agents from inside Emacs. Most of them are only installed; apart from
;; the Anthropic login for `agent-shell' and turning on `vulpea-mcp', none of
;; them get keybindings, backends or API keys here, so their defaults (or
;; settings made elsewhere) apply.

;;; Code:

;;;; Agents that require an API key
;;;; gptel
(use-package gptel
  :ensure (:wait t))

(use-package gptel-agent
  :ensure t)

;;;; claude-code
(use-package claude-code
  :ensure (:type git :host github :repo "stevemolitor/claude-code.el")
  :after (inheritenv vterm eat))

;;;; eca
(use-package eca
  :ensure t)

;;;; agent-shell
(use-package agent-shell
  :ensure t
  :config
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication
         :login t)))

(use-package efrit
  :ensure (:type git :host github :repo "steveyegge/efrit"))

;;;; Working with AI with my knowledge base
;; Claude reaches the two MCP servers below through the stdio wrapper
;; `emacs-mcp-stdio.sh', which talks to a running Emacs with `emacsclient'. That
;; Emacs can be a headless daemon: see "Running the MCP servers without a GUI" in
;; docs/tangles/media/sp-ai.org.

;; The server library goes first, so that Elpaca does not queue it as a
;; dependency of vulpea-mcp and org-mcp. It only answers `emacsclient' requests;
;; it opens no port.
(use-package mcp-server-lib
  :ensure t
  :config
  (mcp-server-lib-start))

;; Making an LLM recognise my vulpea notes
(use-package vulpea-mcp
  :ensure (:type git :repo "https://codeberg.org/nicolas-graves/vulpea-mcp.git")
  :config
  (vulpea-mcp-enable))

;; Editing existing notes and TODO states, which vulpea-mcp cannot do. org-mcp
;; only touches the files in `org-mcp-allowed-files'.
(defun sp-org-mcp-files ()
  "Org files that org-mcp may read and change: those in the agenda directories."
  (cl-loop for dir in (list (sp-path sp-notes-dir "area/")
                            (sp-path sp-notes-dir "inbox/"))
           when (file-directory-p dir)
           append (directory-files dir t "\\.org\\'")))

(use-package org-mcp
  :ensure t
  :config
  (setq org-mcp-allowed-files (sp-org-mcp-files))
  (org-mcp-enable))

;;;; Enhacing the experience of Claude Code
(use-package monet
  :ensure (:type git :host github :repo "stevemolitor/monet"))

;;;; Linking the MCP of DEVONthink

(provide 'sp-ai)
;; sp-ai.el ends here.
