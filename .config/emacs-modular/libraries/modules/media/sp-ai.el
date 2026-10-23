;; -*- lexical-binding: t; -*-
;; sp-ai.el --- AI implementation

;;; Commentary:

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
  :ensure (:type git :repo "https://codeberg.org/nicolas-graves/vulpea-mcp.git")
  :config
  (vulpea-mcp-enable))

;;; Enhacing the experience of Claude Code
(use-package monet
  :ensure (:type git :host github :repo "stevemolitor/monet"))

;;; Linking the MCP of DEVONthink

;;; Provide:

(provide 'sp-ai)
;; sp-ai.el ends here.
