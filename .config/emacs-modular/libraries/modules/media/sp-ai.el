;; -*- lexical-binding: t; -*-
;; sp-ai.el --- AI implementation

;;; Commentary:

;;; Code:

(use-package gptel
  :ensure (:wait t))

(use-package eca
  :ensure t)

(use-package agent-shell
  :ensure t)

;; Making an LLM recognise my vulpea notes

(use-package vulpea-mcp
  :ensure (:type git :repo "https://codeberg.org/nicolas-graves/vulpea-mcp.git"))

;;; Provide:

(provide 'sp-ai)
;; sp-ai.el ends here.
