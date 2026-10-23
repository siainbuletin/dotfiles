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
;; Making an LLM recognise my vulpea notes
(use-package vulpea-mcp
  :ensure (:type git :repo "https://codeberg.org/nicolas-graves/vulpea-mcp.git"))

(vulpea-mcp-enable)

;;; Enhacing the experience of Claude Code
(use-package monet
  :ensure (:type git :host github :repo "stevemolitor/monet"))

;;; Linking the MCP of DEVONthink

(provide 'sp-ai)
;; sp-ai.el ends here.
